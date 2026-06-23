import {
  getFirestore,
  FieldValue,
  Firestore,
  Timestamp,
  Transaction,
  DocumentData,
  DocumentReference,
} from 'firebase-admin/firestore';
import { onCall, HttpsError, CallableRequest } from 'firebase-functions/v2/https';
import { logger } from 'firebase-functions/v2';
import '../admin';
import { notifyMemberJoin } from '../notifications/memberJoinNotifier';
import { normalizeInviteCode } from './shared/inviteCode';

export interface JoinGroupByInviteCodeInput {
  inviteCode: string;
  displayName?: string;
}

export interface JoinGroupByInviteCodeOutput {
  groupId: string;
}

// #197 / #648: rate-limit threat model + residual — READ before adding "more" limits.
// The per-UID counter below (`joinAttempts/{uid}`) is the only per-actor throttle.
// It is bypassable by anon-UID rotation (anon sign-in is free, so a scripted
// `signOut → signInAnonymously` loop mints a fresh counter per rotation). #441
// USED to close that loop for THIS callable by refusing anon providers outright,
// but #648 ("gate creation, not participation") REMOVED that reject so anonymous
// users can join. The rotation bypass is therefore re-opened — and stays
// contained the same way enumeration is: `enforceAppCheck: true` (below) requires
// a genuine attested app instance to place the call at all, and the invite-code
// space is large (Random.secure(), 32-symbol alphabet, 6 chars ≈ 32⁶ ≈ 1.07 B).
// Do NOT "re-harden" by re-adding the anonymous reject (it would re-gate
// participation, the exact thing #648 un-gated). Rotating durable Google accounts
// is the residual (expensive, attested). Two "obvious" hardenings were
// evaluated for #197 and INTENTIONALLY NOT added:
//   • per-IP — the only signal that would survive UID rotation, BUT these callables
//     run on direct Cloud Run ingress (no external ALB; see index.ts), where the
//     client IP is unavailable in any trustworthy form: `X-Forwarded-For` is fully
//     client-spoofable (`rawRequest.ip` merely reads it), and the socket address is
//     Google's internal front-end proxy, not the caller. Keying a limit on a
//     spoofable IP is security theater AND would false-positive-lock real users
//     behind carrier-grade NAT (common in our market). A trustworthy client IP
//     would require fronting callables with a Global external Application Load
//     Balancer + serverless NEG — disproportionate infra for a P2.
//   • per-code (`joinAttemptsByCode/{code}`) — harmless (a valid join SUCCEEDS and
//     deletes its counter, so only invalid codes ever accumulate → no legit-user
//     lockout) but marginal: invite-code enumeration tries a DIFFERENT code each
//     guess, so a per-code counter essentially never fills.
// The real control is `enforceAppCheck: true` (below): scripted enumeration needs a
// genuine attested app instance to place the call at all. That is why #197 is P2,
// not P1. Do not "fix" the per-UID bypass with per-IP/per-code — neither closes the
// gap on this infra, and per-IP actively harms.
const JOIN_ATTEMPT_WINDOW_MS = 60 * 60 * 1000;
const JOIN_ATTEMPT_LOCK_MS = 60 * 60 * 1000;
const JOIN_ATTEMPT_LIMIT = 5;
const DISPLAY_NAME_MAX_LENGTH = 32;
// Intentionally matches control characters to REJECT them in display names —
// the server-side counterpart to isValidDisplayName, kept aligned with
// firestore.rules. The control chars are the validation target, not a mistake.
// eslint-disable-next-line no-control-regex
const CONTROL_CHARACTER_PATTERN = /[\x00-\x1F\x7F]/u;

function normalizeDisplayName(displayName: unknown): string {
  if (displayName == null) return 'Anonymous';
  if (typeof displayName !== 'string') {
    throw new HttpsError('invalid-argument', 'displayName must be a string.');
  }

  const trimmed = displayName.trim();
  if (trimmed.length < 1 || trimmed.length > DISPLAY_NAME_MAX_LENGTH) {
    throw new HttpsError(
      'invalid-argument',
      `displayName must be between 1 and ${DISPLAY_NAME_MAX_LENGTH} characters.`,
    );
  }
  if (CONTROL_CHARACTER_PATTERN.test(displayName)) {
    throw new HttpsError('invalid-argument', 'displayName contains invalid characters.');
  }
  return trimmed;
}

function getMemberIds(groupData: DocumentData): string[] {
  const memberIds = groupData.memberIds;
  if (
    !Array.isArray(memberIds)
    || memberIds.some((memberId) => typeof memberId !== 'string')
  ) {
    throw new HttpsError('failed-precondition', 'Group membership data is malformed.');
  }
  return memberIds;
}

function getParticipantIds(eventData: DocumentData, eventId: string): string[] {
  const participantIds = eventData.participantIds;
  if (
    !Array.isArray(participantIds)
    || participantIds.some((participantId) => typeof participantId !== 'string')
  ) {
    throw new HttpsError(
      'failed-precondition',
      `Event ${eventId} participantIds data is malformed.`,
    );
  }
  return participantIds;
}

function getParticipantNames(
  eventData: DocumentData,
  eventId: string,
): Record<string, string> {
  const participantNames = eventData.participantNames;
  if (
    participantNames == null
    || typeof participantNames !== 'object'
    || Array.isArray(participantNames)
  ) {
    throw new HttpsError(
      'failed-precondition',
      `Event ${eventId} participantNames data is malformed.`,
    );
  }

  const normalized: Record<string, string> = {};
  for (const [participantId, displayName] of Object.entries(participantNames)) {
    if (typeof displayName !== 'string') {
      throw new HttpsError(
        'failed-precondition',
        `Event ${eventId} participantNames data is malformed.`,
      );
    }
    normalized[participantId] = displayName;
  }
  return normalized;
}

function isTimestamp(value: unknown): value is Timestamp {
  return value instanceof Timestamp;
}

function isLookupFailure(error: unknown): boolean {
  const code = (error as { code?: unknown }).code;
  return code === 'not-found' || code === 'failed-precondition';
}

function tooManyAttemptsError(): HttpsError {
  return new HttpsError('resource-exhausted', 'Too many attempts. Try again later.');
}

interface EventFanoutUpdate {
  ref: DocumentReference;
  addParticipantId: boolean;
  participantNames: Record<string, string>;
}

async function assertJoinNotLocked(db: Firestore, uid: string): Promise<void> {
  const attemptRef = db.doc(`joinAttempts/${uid}`);

  await db.runTransaction(async (tx) => {
    const attemptSnap = await tx.get(attemptRef);
    const lockedUntil = attemptSnap.get('lockedUntil');
    if (
      isTimestamp(lockedUntil)
      && lockedUntil.toMillis() > Timestamp.now().toMillis()
    ) {
      throw tooManyAttemptsError();
    }
  });
}

async function recordFailedJoinAttempt(db: Firestore, uid: string): Promise<boolean> {
  const attemptRef = db.doc(`joinAttempts/${uid}`);

  return db.runTransaction(async (tx: Transaction) => {
    const now = Timestamp.now();
    const attemptSnap = await tx.get(attemptRef);
    const data = attemptSnap.data() ?? {};
    const firstFailAt = data.firstFailAt;
    const insideWindow =
      isTimestamp(firstFailAt)
      && now.toMillis() - firstFailAt.toMillis() < JOIN_ATTEMPT_WINDOW_MS;
    const currentFailCount =
      insideWindow && typeof data.failCount === 'number' ? data.failCount : 0;
    const effectiveFirstFailAt = insideWindow ? firstFailAt : now;

    if (currentFailCount >= JOIN_ATTEMPT_LIMIT) {
      tx.set(
        attemptRef,
        {
          failCount: currentFailCount,
          firstFailAt: effectiveFirstFailAt,
          lockedUntil: Timestamp.fromMillis(now.toMillis() + JOIN_ATTEMPT_LOCK_MS),
        },
        { merge: true },
      );
      return true;
    }

    const nextFailCount = currentFailCount + 1;
    tx.set(
      attemptRef,
      {
        failCount: nextFailCount,
        firstFailAt: effectiveFirstFailAt,
        lockedUntil:
          nextFailCount >= JOIN_ATTEMPT_LIMIT
            ? Timestamp.fromMillis(now.toMillis() + JOIN_ATTEMPT_LOCK_MS)
            : null,
      },
      { merge: true },
    );
    return false;
  });
}

export const joinGroupByInviteCode = onCall<
  JoinGroupByInviteCodeInput,
  Promise<JoinGroupByInviteCodeOutput>
>(
  { enforceAppCheck: true },
  async (request: CallableRequest<JoinGroupByInviteCodeInput>) => {
    if (!request.auth) {
      throw new HttpsError('unauthenticated', 'Sign-in required.');
    }

    // #648: NO anonymous-provider reject here — "gate creation, not
    // participation." Anonymous users may join and participate; only group /
    // invite-code CREATE stays durable-gated (firestore.rules + GroupService).
    // The re-opened anon-rotation throttle bypass is contained by App Check +
    // invite-code entropy (see the #197/#648 note above). Do not re-add it.
    const uid = request.auth.uid;
    const inviteCode = normalizeInviteCode(request.data?.inviteCode);
    const displayName = normalizeDisplayName(request.data?.displayName);
    const db = getFirestore();
    const inviteRef = db.doc(`inviteCodes/${inviteCode}`);

    await assertJoinNotLocked(db, uid);

    // #53 — captured INSIDE the tx (last-run-wins on retry) so a committed join
    // can notify pre-join members. `didJoin` (G1) gates the notification on an
    // ACTUAL member-doc create — an idempotent re-join must not re-announce.
    let didJoin = false;
    let existingMemberIds: string[] = [];
    let groupName = '';

    let groupId: string;
    try {
      groupId = await db.runTransaction(async (tx) => {
        const inviteSnap = await tx.get(inviteRef);
        if (!inviteSnap.exists) {
          throw new HttpsError('not-found', 'Invalid invite code.');
        }

        const inviteData = inviteSnap.data() ?? {};
        const resolvedGroupId = inviteData.groupId;
        if (typeof resolvedGroupId !== 'string' || resolvedGroupId.length === 0) {
          throw new HttpsError('failed-precondition', 'Invite code is malformed.');
        }

        const groupRef = db.doc(`groups/${resolvedGroupId}`);
        const groupSnap = await tx.get(groupRef);

        if (!groupSnap.exists) {
          throw new HttpsError('not-found', 'Group not found.');
        }

        const groupData = groupSnap.data() ?? {};
        // #78/#205: reject joins into a soft-deleted group or a group currently
        // quiesced by deleteGroup. This callable uses Admin SDK writes, so it
        // must honor the same write lock as firestore.rules instead of relying
        // on rules evaluation. 'not-found' mirrors the missing-group throw above
        // (no deleted-vs-never-existed leak) and is intentionally counted as a
        // lookup failure toward the join rate limit, exactly like an invalid code.
        if (groupData.isDeleted === true || groupData.deletingInProgress === true) {
          throw new HttpsError('not-found', 'Group not found.');
        }

        const memberRef = groupRef.collection('members').doc(uid);
        const membersQuery = groupRef.collection('members');
        const eventsQuery = groupRef.collection('events');
        const [memberSnap, membersSnap, eventsSnap] = await Promise.all([
          tx.get(memberRef),
          tx.get(membersQuery),
          tx.get(eventsQuery),
        ]);
        if (eventsSnap.size > 400) {
          throw new HttpsError(
            'failed-precondition',
            'Group has too many events to join safely.',
          );
        }
        const memberIds = getMemberIds(groupData);

        // #53 G1: notify only on a BRAND-NEW member — BOTH the member-doc create
        // (!memberSnap.exists) AND the memberIds arrayUnion (!includes) must
        // fire. Requiring both means a heal-path re-join (uid already in
        // memberIds but member-doc missing) does NOT re-announce, and neither
        // does the inverse. The member-array snapshot is captured PRE-arrayUnion
        // so the joiner is never in `existingMemberIds`.
        didJoin = !memberSnap.exists && !memberIds.includes(uid);
        existingMemberIds = memberIds;
        groupName = typeof groupData.name === 'string' ? groupData.name : '';

        // #279: reject a brand-new join whose display name collides
        // (case-insensitive, trimmed) with an existing member — duplicate names
        // make roster + settle-up attribution ambiguous. Gated on `didJoin`
        // (== `!memberSnap.exists && !memberIds.includes(uid)`) so ONLY a
        // genuinely new member is uniqueness-checked: an idempotent re-join AND
        // the #53 heal path (uid already in memberIds, member-doc missing) both
        // restore their existing name without being self-rejected. Normalization
        // matches MemberNameResolver.disambiguate's collision key
        // (`trim().toLowerCase()`) so prevention and the display disambiguator
        // (#196/#289) agree. Compared across ALL member docs by the
        // `userId`/`displayName` FIELDS (not doc id) so the creator's uuid-keyed
        // doc is included. Throws `already-exists`, which is NOT in
        // `isLookupFailure`, so a collision never burns the 5/hr join throttle —
        // it is a legitimate user error, not enumeration.
        if (didJoin) {
          const candidate = displayName.trim().toLowerCase();
          const collides = membersSnap.docs.some((doc) => {
            if (doc.get('userId') === uid) return false;
            const existing = doc.get('displayName');
            return typeof existing === 'string'
              && existing.trim().toLowerCase() === candidate;
          });
          if (collides) {
            throw new HttpsError(
              'already-exists',
              'That name is already taken in this group. Please choose a different name.',
            );
          }
        }

        const eventFanoutUpdates: EventFanoutUpdate[] = [];
        for (const eventSnap of eventsSnap.docs) {
          const eventData = eventSnap.data() ?? {};
          if (eventData.isDeleted === true) {
            continue;
          }
          const participantIds = getParticipantIds(eventData, eventSnap.id);
          const participantNames = getParticipantNames(eventData, eventSnap.id);
          const addParticipantId = !participantIds.includes(uid);
          const nameChanged = participantNames[uid] !== displayName;
          if (addParticipantId || nameChanged) {
            eventFanoutUpdates.push({
              ref: eventSnap.ref,
              addParticipantId,
              participantNames: {
                ...participantNames,
                [uid]: displayName,
              },
            });
          }
        }

        if (!memberIds.includes(uid)) {
          tx.update(groupRef, {
            memberIds: FieldValue.arrayUnion(uid),
            updatedAt: FieldValue.serverTimestamp(),
          });
        }

        if (!memberSnap.exists) {
          tx.set(memberRef, {
            id: uid,
            userId: uid,
            displayName,
            role: 'MEMBER',
            joinedAt: FieldValue.serverTimestamp(),
            isShadow: false,
          });
        }

        for (const eventUpdate of eventFanoutUpdates) {
          const updateData: Record<string, unknown> = {
            participantNames: eventUpdate.participantNames,
            updatedAt: FieldValue.serverTimestamp(),
          };
          if (eventUpdate.addParticipantId) {
            updateData.participantIds = FieldValue.arrayUnion(uid);
          }
          tx.update(eventUpdate.ref, updateData);
        }

        return resolvedGroupId;
      });
    } catch (error) {
      if (isLookupFailure(error)) {
        const throttled = await recordFailedJoinAttempt(db, uid);
        if (throttled) {
          throw tooManyAttemptsError();
        }
      }
      throw error;
    }

    await db.doc(`joinAttempts/${uid}`).delete();
    logger.info('group-join succeeded', { uid, groupId });

    // #53 — fire-and-forget member-join push, ONLY on an actual join (G1).
    // MUST NOT throw: the join is already committed; a notification failure
    // must never surface as a join failure.
    if (didJoin) {
      try {
        await notifyMemberJoin(groupId, uid, displayName, groupName, existingMemberIds);
      } catch (error) {
        logger.warn('member-join notify failed', { groupId, uid, error: String(error) });
      }
    }

    return { groupId };
  },
);
