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

export interface JoinGroupByInviteCodeInput {
  inviteCode: string;
  displayName?: string;
}

export interface JoinGroupByInviteCodeOutput {
  groupId: string;
}

const JOIN_ATTEMPT_WINDOW_MS = 60 * 60 * 1000;
const JOIN_ATTEMPT_LOCK_MS = 60 * 60 * 1000;
const JOIN_ATTEMPT_LIMIT = 5;
const DISPLAY_NAME_MAX_LENGTH = 32;
// Intentionally matches control characters to REJECT them in display names —
// the server-side counterpart to isValidDisplayName, kept aligned with
// firestore.rules. The control chars are the validation target, not a mistake.
// eslint-disable-next-line no-control-regex
const CONTROL_CHARACTER_PATTERN = /[\x00-\x1F\x7F]/u;

function normalizeInviteCode(inviteCode: unknown): string {
  if (typeof inviteCode !== 'string') {
    throw new HttpsError('invalid-argument', 'inviteCode must be a string.');
  }
  const normalized = inviteCode.trim().toUpperCase();
  if (!/^[A-Z0-9]{6}$/.test(normalized)) {
    throw new HttpsError('invalid-argument', 'Invalid invite code.');
  }
  return normalized;
}

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

    const uid = request.auth.uid;
    const inviteCode = normalizeInviteCode(request.data?.inviteCode);
    const displayName = normalizeDisplayName(request.data?.displayName);
    const db = getFirestore();
    const inviteRef = db.doc(`inviteCodes/${inviteCode}`);

    await assertJoinNotLocked(db, uid);

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
        const eventsQuery = groupRef.collection('events');
        const [memberSnap, eventsSnap] = await Promise.all([
          tx.get(memberRef),
          tx.get(eventsQuery),
        ]);
        if (eventsSnap.size > 400) {
          throw new HttpsError(
            'failed-precondition',
            'Group has too many events to join safely.',
          );
        }
        const memberIds = getMemberIds(groupData);

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
    return { groupId };
  },
);
