import { getFirestore, FieldValue, DocumentData } from 'firebase-admin/firestore';
import { onCall, HttpsError, CallableRequest } from 'firebase-functions/v2/https';
import { logger } from 'firebase-functions/v2';
import { randomUUID } from 'crypto';
import '../admin';
import { normalizeRequiredDisplayName } from './shared/displayName';
import { MAX_FAN_IN_EVENTS, applyEventFanIn, collectEventFanIn } from './shared/eventFanIn';

export interface AddShadowMemberInput {
  groupId: string;
  displayName: string;
}

export interface AddShadowMemberOutput {
  memberId: string;
}

// Generous cap: bounds roster spam + per-write recompute cost. The persona is
// small friend groups; 50 is far above any real Rihla group. This caps ONLY the
// shadow-add path — joinGroupByInviteCode stays uncapped. App Check + the
// creator-only gate are the real controls (#197 — do NOT add per-IP throttling).
const MAX_GROUP_MEMBERS = 50;

function normalizeGroupId(groupId: unknown): string {
  if (typeof groupId !== 'string' || groupId.length === 0 || groupId.includes('/')) {
    throw new HttpsError('invalid-argument', 'groupId must be a valid id.');
  }
  return groupId;
}

function getMemberIds(groupData: DocumentData): string[] {
  const memberIds = groupData.memberIds;
  if (!Array.isArray(memberIds) || memberIds.some((m) => typeof m !== 'string')) {
    throw new HttpsError('failed-precondition', 'Group membership data is malformed.');
  }
  return memberIds;
}

// #278: add a placeholder ("shadow") member by name. A shadow has NO real auth
// uid — its id/userId is a freshly-minted uuid — so a brand-new group is usable
// on the first session (split against it immediately, cash-settle it). Creating
// it requires the Admin SDK because (a) memberIds is server-authoritative
// (firestore.rules:308) and (b) #524 binds a client-created member doc's id to
// the caller's auth.uid (rules:782-783), which a placeholder can never satisfy.
export const addShadowMember = onCall<AddShadowMemberInput, Promise<AddShadowMemberOutput>>(
  { enforceAppCheck: true },
  async (request: CallableRequest<AddShadowMemberInput>) => {
    if (!request.auth) {
      throw new HttpsError('unauthenticated', 'Sign-in required.');
    }
    // A shadow is group-scoped placeholder data; the CREATOR adds it and is
    // always durable (validGroupCreate requires a durable sign-in). Reject anon
    // defensively, mirroring joinGroupByInviteCode:236.
    if (request.auth.token?.firebase?.sign_in_provider === 'anonymous') {
      throw new HttpsError(
        'permission-denied',
        'A linked (non-anonymous) account is required to add members.',
      );
    }

    const uid = request.auth.uid;
    const groupId = normalizeGroupId(request.data?.groupId);
    const displayName = normalizeRequiredDisplayName(request.data?.displayName);
    const db = getFirestore();
    const groupRef = db.doc(`groups/${groupId}`);

    const memberId = await db.runTransaction(async (tx) => {
      const groupSnap = await tx.get(groupRef);
      if (!groupSnap.exists) {
        throw new HttpsError('not-found', 'Group not found.');
      }
      const groupData = groupSnap.data() ?? {};
      // Honor the same write-lock as firestore.rules (the Admin SDK bypasses
      // rules), mirroring joinGroupByInviteCode:286.
      if (
        groupData.isDeleted === true
        || groupData.deletingInProgress === true
        || groupData.claimingInProgress === true
        || groupData.accountDeletionInProgress === true
      ) {
        throw new HttpsError('not-found', 'Group not found.');
      }
      if (groupData.createdBy !== uid) {
        throw new HttpsError(
          'permission-denied',
          'Only the group creator can add members by name.',
        );
      }

      const memberIds = getMemberIds(groupData);
      if (memberIds.length >= MAX_GROUP_MEMBERS) {
        throw new HttpsError(
          'failed-precondition',
          'This group has reached the maximum number of members.',
        );
      }

      // #279 collision: a shadow name must be unique (case-insensitive, trimmed)
      // across ALL member docs (real + shadow) — duplicate names make roster +
      // settle-up attribution ambiguous, and keeping names unique now keeps the
      // future claim picker unambiguous. Compared by the displayName FIELD.
      const membersSnap = await tx.get(groupRef.collection('members'));
      // #245: the shadow is fanned into every live event below (same contract
      // as joinGroupByInviteCode), so the event count bounds this tx's writes.
      const eventsSnap = await tx.get(groupRef.collection('events'));
      if (eventsSnap.size > MAX_FAN_IN_EVENTS) {
        throw new HttpsError(
          'failed-precondition',
          'Group has too many events to add a member safely.',
        );
      }
      const candidate = displayName.toLowerCase();
      const collides = membersSnap.docs.some((doc) => {
        const existing = doc.get('displayName');
        return typeof existing === 'string' && existing.trim().toLowerCase() === candidate;
      });
      if (collides) {
        throw new HttpsError(
          'already-exists',
          'That name is already taken in this group. Please choose a different name.',
        );
      }

      // The placeholder uuid is BOTH the doc id and the userId (the balance
      // oracle keys on userId). Same 6 fields joinGroupByInviteCode writes
      // (:375-384), with isShadow:true. isTombstone is omitted (defaults false in
      // GroupMember.fromDoc), matching the join write.
      const newId = randomUUID();
      tx.set(groupRef.collection('members').doc(newId), {
        id: newId,
        userId: newId,
        displayName,
        role: 'MEMBER',
        joinedAt: FieldValue.serverTimestamp(),
        isShadow: true,
      });
      tx.update(groupRef, {
        memberIds: FieldValue.arrayUnion(newId),
        updatedAt: FieldValue.serverTimestamp(),
      });
      // #245: mirror the join callable — a member absent from an event's
      // participantIds can never be split against there (the expense editor
      // rosters event.participantIds and no client path grows it).
      applyEventFanIn(tx, collectEventFanIn(eventsSnap, newId, displayName), newId);
      return newId;
    });

    logger.info('addShadowMember created', { uid, groupId, memberId });
    return { memberId };
  },
);
