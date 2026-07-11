import { FieldValue, Timestamp, getFirestore } from 'firebase-admin/firestore';
import { logger } from 'firebase-functions/v2';
import { CallableRequest, HttpsError, onCall } from 'firebase-functions/v2/https';
import '../admin';
import {
  computeNetFromSnapshot,
  loadGroupBalanceSnapshot,
  universeOnlyEventIds,
} from './groupNetBalance';
import { isCurrentMember } from './shared/membership';
import {
  acquireDepartureLock,
  assertDepartureLockHeld,
  clearDepartureLockForFailure,
  departureLockClearFields,
} from './shared/departureLock';

// #318: server-authoritative creator-remove. The client guard ("settle before
// removing") was skipped whenever the balance had not loaded (offline / slow /
// error), so the creator could remove a member who still owed — orphaning debt
// that nets non-zero with a departed party. This callable mirrors leaveGroup's
// authority (#290): it recomputes the TARGET's net via the shared
// groupNetBalance oracle (exactly as the client BalanceCalculator), refuses with
// FAILED_PRECONDITION on a non-zero TARGET net, then atomically removes the
// target uid from memberIds + deletes EVERY member doc matching
// `userId == targetUserId` (legacy docs may be uuid-keyed, #294) + writes the
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
// #1144: the zero-check runs UNDER a departureInProgress lock (shared/
// departureLock.ts) — same fence as leaveGroup; see that file's header for
// the race, the error-code contract (`aborted` for contention/lost lock,
// `failed-precondition` reserved for the unsettled-balance snackbar), and the
// release discipline. Still honors deleteGroup's quiesce marker like every
// Admin-SDK membership writer, because Admin SDK writes bypass
// firestore.rules. enforceAppCheck is the per-actor control (#197).

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
    // Honor the same write-lock as firestore.rules (Admin SDK bypasses rules),
    // mirroring joinGroupByInviteCode/addShadowMember: soft-deleted or
    // delete-quiesced groups are indistinguishable from missing groups.
    if (
      group.isDeleted === true
      || group.deletingInProgress === true
      || group.claimingInProgress === true
      || group.accountDeletionInProgress === true
    ) {
      throw new HttpsError('not-found', 'Group not found.');
    }

    // Only the CURRENT-member group creator may remove another member
    // (deleteGroup.ts:145). #1132: createdBy alone is membership-blind — a
    // departed creator must not retain removal authority.
    if (group.createdBy !== uid || !isCurrentMember(group, uid)) {
      throw new HttpsError(
        'permission-denied',
        'Only the group creator can remove a member.',
      );
    }

    const memberIds: string[] = Array.isArray(group.memberIds)
      ? group.memberIds.filter((v): v is string => typeof v === 'string')
      : [];
    const targetIsMember = memberIds.includes(targetUserId);

    // Match member docs by the `userId` FIELD, never the doc id: new client docs
    // key by {uid}, but legacy creator docs may still be uuid-keyed (#294/#524).
    // A `.doc(targetUserId)` lookup would miss those legacy rows.
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

    // #1144: acquire the departure lock BEFORE the balance gate so the
    // recompute basis cannot change under us. Everything after the acquire
    // runs in a try whose catch releases OUR lock (own-invocation-only).
    const lock = await acquireDepartureLock(db, groupRef, uid);

    const targetName =
      targetDocsSnap.docs
        .map((d) => d.data().displayName)
        .find((name): name is string => typeof name === 'string' && name.length > 0)
      ?? 'Someone';

    let mutation: { alreadyRemoved: boolean };
    try {
      // Balance gate: the TARGET must be square. This is the SAME oracle the
      // client ledger + deleteGroup + leaveGroup use (recomputeNet =
      // compute ∘ load); a missing entry means the target never had a
      // financial position ⇒ owes nothing ⇒ allowed. The snapshot is loaded
      // once and shared with the #1144 R1 universe-only guard below.
      const snapshot = await loadGroupBalanceSnapshot(db, groupRef);
      const { net } = computeNetFromSnapshot(snapshot);
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

      // #1144 R1: a target with universe-only history (payer or settlement
      // party in an event that no longer rosters them) folds INTO the balance
      // universe the instant they stop being live — gaining paid rows and an
      // equal-split share the zero-gate above cannot see (the live fold DROPS
      // their rows). Refuse; the state is reachable only via a forged write
      // or a D9 roster removal of a current payer (no client UI writes roster
      // removals), and Admin roster repair is the remedy. Runs inside this
      // try so a refusal releases OUR lock like every other exit.
      if (universeOnlyEventIds(snapshot, targetUserId).length > 0) {
        throw new HttpsError(
          'failed-precondition',
          'This member has unsettled event history and cannot be removed.',
        );
      }

      mutation = await db.runTransaction(async (tx) => {
        const freshGroupSnap = await tx.get(groupRef);
        if (!freshGroupSnap.exists) {
          throw new HttpsError('not-found', 'Group not found.');
        }
        const freshGroup = freshGroupSnap.data() ?? {};
        if (
          freshGroup.isDeleted === true
          || freshGroup.deletingInProgress === true
          || freshGroup.claimingInProgress === true
          || freshGroup.accountDeletionInProgress === true
        ) {
          throw new HttpsError('not-found', 'Group not found.');
        }
        // #1144: the recompute basis is only trustworthy while the lock we
        // acquired is still in place — a reaper reclaim mid-flight voids it.
        assertDepartureLockHeld(freshGroup, lock);
        // #1132: re-check membership in the tx too — a leave can commit between
        // the first check and here.
        if (freshGroup.createdBy !== uid || !isCurrentMember(freshGroup, uid)) {
          throw new HttpsError(
            'permission-denied',
            'Only the group creator can remove a member.',
          );
        }
        const freshMemberIds: string[] = Array.isArray(freshGroup.memberIds)
          ? freshGroup.memberIds.filter((v): v is string => typeof v === 'string')
          : [];
        const freshTargetDocsSnap = await tx.get(
          groupRef.collection('members').where('userId', '==', targetUserId),
        );
        const freshActorDocsSnap = await tx.get(
          groupRef.collection('members').where('userId', '==', uid),
        );
        const freshTargetIsMember = freshMemberIds.includes(targetUserId);
        if (!freshTargetIsMember && freshTargetDocsSnap.empty) {
          tx.update(groupRef, departureLockClearFields());
          return { alreadyRemoved: true };
        }
        const freshTargetName =
          freshTargetDocsSnap.docs
            .map((d) => d.data().displayName)
            .find((name): name is string => typeof name === 'string' && name.length > 0)
          ?? targetName;
        const freshActorName =
          freshActorDocsSnap.docs
            .map((d) => d.data().displayName)
            .find((name): name is string => typeof name === 'string' && name.length > 0)
          ?? 'Someone';

        const now = Timestamp.now();
        tx.update(groupRef, {
          memberIds: FieldValue.arrayRemove(targetUserId),
          updatedAt: now,
          // #1144: release the lock atomically with the mutation.
          ...departureLockClearFields(),
        });
        for (const memberDoc of freshTargetDocsSnap.docs) {
          tx.delete(memberDoc.ref);
        }
        const activityRef = groupRef.collection('activity').doc();
        tx.set(activityRef, {
          id: activityRef.id,
          type: 'member_left',
          actorId: uid,
          actorName: freshActorName,
          description: `${freshTargetName} was removed from the group`,
          metadata: { memberAction: 'removed', memberName: freshTargetName },
          timestamp: new Date().toISOString(),
        });
        return { alreadyRemoved: false };
      });
    } catch (err) {
      await clearDepartureLockForFailure(groupRef, lock);
      throw err;
    }

    if (mutation.alreadyRemoved) {
      return { groupId, mode: 'removed', alreadyRemoved: true };
    }

    logger.info('removeMember removed member', { uid, targetUserId, groupId });

    return { groupId, mode: 'removed', alreadyRemoved: false };
  },
);
