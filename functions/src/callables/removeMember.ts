import { FieldValue, Timestamp, getFirestore } from 'firebase-admin/firestore';
import { logger } from 'firebase-functions/v2';
import { CallableRequest, HttpsError, onCall } from 'firebase-functions/v2/https';
import '../admin';
import { recomputeNet } from './groupNetBalance';

// #318: server-authoritative creator-remove. The client guard ("settle before
// removing") was skipped whenever the balance had not loaded (offline / slow /
// error), so the creator could remove a member who still owed — orphaning debt
// that nets non-zero with a departed party. This callable mirrors leaveGroup's
// authority (#290): it recomputes the TARGET's net via the shared
// groupNetBalance oracle (exactly as the client BalanceCalculator), refuses with
// FAILED_PRECONDITION on a non-zero TARGET net, then atomically removes the
// target uid from memberIds + deletes EVERY member doc matching
// `userId == targetUserId` (creator docs are uuid-keyed, #294) + writes the
// `member_left` activity entry with metadata{memberAction:removed,memberName}.
// The direct client creator-remove write is locked in firestore.rules
// (`validCreatorRemoveMember` dropped from group `allow update`).
//
// Authz: only the group creator may remove another member (permission-denied
// otherwise — the axis leaveGroup has no analog). Self-removal is rejected
// (invalid-argument): the creator must use leaveGroup, which is the only path a
// creator's own debt could leak past the target-keyed gate.
//
// Activity type is `member_left` (NOT `member_removed`): activity_display.dart,
// the group/cross-group Members filter, and the user_minus icon all key on
// `member_left` and disambiguate the removal via metadata.memberAction.
//
// Removal is a hard-delete (preserve current client behavior), NOT a tombstone:
// remove never touches event participantIds, so the target's per-event balance
// universe is unchanged ⇒ other members' balances are preserved, and the net==0
// gate (same oracle) only passes when the removal is balance-neutral.
//
// No lock and no rate-limit (unlike deleteGroup): remove is a single small
// atomic batch. enforceAppCheck is the per-actor control (#197).

export interface RemoveMemberInput {
  groupId: string;
  targetUserId: string;
}

export interface RemoveMemberOutput {
  groupId: string;
  mode: 'removed';
  alreadyRemoved: boolean;
}

export const removeMember = onCall<RemoveMemberInput, Promise<RemoveMemberOutput>>(
  { enforceAppCheck: true },
  async (request: CallableRequest<RemoveMemberInput>) => {
    if (!request.auth) {
      throw new HttpsError('unauthenticated', 'Sign-in required.');
    }

    const groupId = request.data?.groupId;
    if (typeof groupId !== 'string' || groupId.length === 0 || groupId.includes('/')) {
      throw new HttpsError('invalid-argument', 'groupId must be a valid id.');
    }

    const targetUserId = request.data?.targetUserId;
    if (
      typeof targetUserId !== 'string' ||
      targetUserId.length === 0 ||
      targetUserId.includes('/')
    ) {
      throw new HttpsError('invalid-argument', 'targetUserId must be a valid id.');
    }

    const uid = request.auth.uid;
    // The creator cannot self-remove — they must use leaveGroup (the only path a
    // creator's own debt could leak past the target-keyed gate). Reject before
    // any read: it is an input-shape error.
    if (targetUserId === uid) {
      throw new HttpsError(
        'invalid-argument',
        'Use leaveGroup to remove yourself from the group.',
      );
    }

    const db = getFirestore();
    const groupRef = db.doc(`groups/${groupId}`);

    const groupSnap = await groupRef.get();
    if (!groupSnap.exists) {
      throw new HttpsError('not-found', 'Group not found.');
    }
    const group = groupSnap.data() ?? {};

    // Only the group creator may remove another member (deleteGroup.ts:145).
    if (group.createdBy !== uid) {
      throw new HttpsError(
        'permission-denied',
        'Only the group creator can remove a member.',
      );
    }

    const memberIds: string[] = Array.isArray(group.memberIds)
      ? group.memberIds.filter((v): v is string => typeof v === 'string')
      : [];
    const targetIsMember = memberIds.includes(targetUserId);

    // Match member docs by the `userId` FIELD, never the doc id: joiners key by
    // {uid} but the creator's doc is keyed by a random uuid with `userId:uid`
    // (#294) — a `.doc(targetUserId)` lookup would miss it.
    const targetDocsSnap = await groupRef
      .collection('members')
      .where('userId', '==', targetUserId)
      .get();

    // Idempotent short-circuit ONLY when the target is fully absent. If EITHER
    // the uid is still in memberIds OR any member doc exists, proceed and
    // re-assert both writes (a partial prior remove self-heals: arrayRemove of
    // an absent uid is a no-op, delete of an absent doc is skipped).
    if (!targetIsMember && targetDocsSnap.empty) {
      return { groupId, mode: 'removed', alreadyRemoved: true };
    }

    // Balance gate: the TARGET must be square. recomputeNet is the SAME oracle
    // the client ledger + deleteGroup + leaveGroup use; a missing entry means
    // the target never had a financial position ⇒ owes nothing ⇒ allowed.
    // isZero() is exact (the allocators close residuals, incl. the #223
    // in-tolerance close-out).
    const { net } = await recomputeNet(db, groupRef);
    // #382 PR-2: net is per-currency buckets (currency -> uid -> net). The
    // target may be removed only when they net exactly zero in EVERY currency
    // bucket — no FX, so each currency must clear independently. (The old
    // `currencies.size > 1` refusal is gone: a mixed group where the target is
    // square per-currency is fine.) A missing entry ⇒ no position in that
    // currency ⇒ zero. isZero() is exact (the allocators close residuals, incl.
    // the #223 in-tolerance close-out).
    const targetOutstanding = [...net.values()].some((bucket) => {
      const v = bucket.get(targetUserId);
      return v != null && !v.isZero();
    });
    if (targetOutstanding) {
      throw new HttpsError(
        'failed-precondition',
        'This member has an unsettled balance and cannot be removed.',
      );
    }

    const targetName =
      targetDocsSnap.docs
        .map((d) => d.data().displayName)
        .find((name): name is string => typeof name === 'string' && name.length > 0)
      ?? 'Someone';

    // actorName = the creator's own display name (matches the old client log,
    // group_settings_screen used the device name → creator's member doc name).
    const actorDocsSnap = await groupRef
      .collection('members')
      .where('userId', '==', uid)
      .get();
    const actorName =
      actorDocsSnap.docs
        .map((d) => d.data().displayName)
        .find((name): name is string => typeof name === 'string' && name.length > 0)
      ?? 'Someone';

    const now = Timestamp.now();
    const batch = db.batch();
    batch.update(groupRef, {
      memberIds: FieldValue.arrayRemove(targetUserId),
      updatedAt: now,
    });
    for (const memberDoc of targetDocsSnap.docs) {
      batch.delete(memberDoc.ref);
    }
    const activityRef = groupRef.collection('activity').doc();
    batch.set(activityRef, {
      id: activityRef.id,
      type: 'member_left',
      actorId: uid,
      actorName,
      description: `${targetName} was removed from the group`,
      metadata: { memberAction: 'removed', memberName: targetName },
      timestamp: new Date().toISOString(),
    });
    await batch.commit();

    logger.info('removeMember removed member', { uid, targetUserId, groupId });

    return { groupId, mode: 'removed', alreadyRemoved: false };
  },
);
