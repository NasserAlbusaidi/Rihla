import { FieldValue, Timestamp, getFirestore } from 'firebase-admin/firestore';
import { logger } from 'firebase-functions/v2';
import { CallableRequest, HttpsError, onCall } from 'firebase-functions/v2/https';
import '../admin';
import { recomputeNet } from './groupNetBalance';

// #290: server-authoritative group self-leave. The client guard ("settle before
// leaving") was skipped whenever the balance had not loaded (offline / slow /
// error), so a member could leave while still owing — orphaning debt that nets
// non-zero with a departed party. This callable mirrors deleteGroup's authority:
// it recomputes the LEAVER's net via the shared groupNetBalance oracle (exactly
// as the client BalanceCalculator), refuses with FAILED_PRECONDITION on a
// non-zero net, then atomically removes the uid from memberIds + deletes EVERY
// member doc matching `userId == uid` (creator docs are uuid-keyed, #294) +
// writes the `member_left` activity entry. The direct client self-leave write is
// locked in firestore.rules (`validSelfLeave` dropped from group `allow update`).
//
// Removal is a hard-delete (preserve current client behavior), NOT a tombstone:
// leave never touches event participantIds, so a participant leaver's per-event
// balance universe is unchanged ⇒ other members' balances are preserved, and the
// net==0 gate (same oracle) only passes when the removal is balance-neutral. (The
// non-participant split-recipient / #249 conservation edge is pre-existing and
// out of scope; tombstoning would CHANGE balance semantics on that axis.)
//
// No separate mutation lock and no rate-limit (unlike deleteGroup): leave is a
// single small atomic mutation touching only the leaver's own membership;
// re-entry is bounded upstream by joinGroupByInviteCode's 5/hr throttle. It
// still honors deleteGroup's quiesce marker like every Admin-SDK membership
// writer, because Admin SDK writes bypass firestore.rules. enforceAppCheck is
// the per-actor control (#197).

export interface LeaveGroupInput {
  groupId: string;
}

export interface LeaveGroupOutput {
  groupId: string;
  mode: 'left';
  alreadyLeft: boolean;
}

export const leaveGroup = onCall<LeaveGroupInput, Promise<LeaveGroupOutput>>(
  { enforceAppCheck: true },
  async (request: CallableRequest<LeaveGroupInput>) => {
    if (!request.auth) {
      throw new HttpsError('unauthenticated', 'Sign-in required.');
    }

    const groupId = request.data?.groupId;
    if (typeof groupId !== 'string' || groupId.length === 0 || groupId.includes('/')) {
      throw new HttpsError('invalid-argument', 'groupId must be a valid id.');
    }

    const uid = request.auth.uid;
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
    if (group.isDeleted === true || group.deletingInProgress === true) {
      throw new HttpsError('not-found', 'Group not found.');
    }
    const memberIds: string[] = Array.isArray(group.memberIds)
      ? group.memberIds.filter((v): v is string => typeof v === 'string')
      : [];
    const isMember = memberIds.includes(uid);

    // Match member docs by the `userId` FIELD, never the doc id: joiners key by
    // {uid} but the creator's doc is keyed by a random uuid with `userId:uid`
    // (#294) — a `.doc(uid)` lookup would miss it.
    const memberDocsSnap = await groupRef
      .collection('members')
      .where('userId', '==', uid)
      .get();

    // Idempotent short-circuit ONLY when the leaver is fully absent. If EITHER
    // the uid is still in memberIds OR any member doc exists, proceed and
    // re-assert both writes (a partial prior leave self-heals: arrayRemove of an
    // absent uid is a no-op, delete of an absent doc is skipped).
    if (!isMember && memberDocsSnap.empty) {
      return { groupId, mode: 'left', alreadyLeft: true };
    }

    // Balance gate: the leaver must be square. recomputeNet is the SAME oracle
    // the client ledger + deleteGroup use; a missing entry means the leaver never
    // had a financial position ⇒ owes nothing ⇒ allowed. isZero() is exact (the
    // allocators close residuals, incl. the #223 in-tolerance close-out).
    const { net } = await recomputeNet(db, groupRef);
    // #382 PR-2: net is per-currency buckets (currency -> uid -> net). The
    // leaver may leave only when they net exactly zero in EVERY currency bucket
    // — no FX, so each currency must clear independently. (The old
    // `currencies.size > 1` refusal is gone: a mixed group where the leaver is
    // square per-currency is fine.) A missing entry ⇒ no position in that
    // currency ⇒ zero. isZero() is exact (the allocators close residuals, incl.
    // the #223 in-tolerance close-out).
    const leaverOutstanding = [...net.values()].some((bucket) => {
      const v = bucket.get(uid);
      return v != null && !v.isZero();
    });
    if (leaverOutstanding) {
      throw new HttpsError(
        'failed-precondition',
        'You have an unsettled balance and cannot leave the group.',
      );
    }

    const actorName =
      memberDocsSnap.docs
        .map((d) => d.data().displayName)
        .find((name): name is string => typeof name === 'string' && name.length > 0)
      ?? 'Someone';

    const mutation = await db.runTransaction(async (tx) => {
      const freshGroupSnap = await tx.get(groupRef);
      if (!freshGroupSnap.exists) {
        throw new HttpsError('not-found', 'Group not found.');
      }
      const freshGroup = freshGroupSnap.data() ?? {};
      if (freshGroup.isDeleted === true || freshGroup.deletingInProgress === true) {
        throw new HttpsError('not-found', 'Group not found.');
      }
      const freshMemberIds: string[] = Array.isArray(freshGroup.memberIds)
        ? freshGroup.memberIds.filter((v): v is string => typeof v === 'string')
        : [];
      const freshMemberDocsSnap = await tx.get(
        groupRef.collection('members').where('userId', '==', uid),
      );
      const freshIsMember = freshMemberIds.includes(uid);
      if (!freshIsMember && freshMemberDocsSnap.empty) {
        return { alreadyLeft: true };
      }
      const freshActorName =
        freshMemberDocsSnap.docs
          .map((d) => d.data().displayName)
          .find((name): name is string => typeof name === 'string' && name.length > 0)
        ?? actorName;

      const now = Timestamp.now();
      tx.update(groupRef, {
        memberIds: FieldValue.arrayRemove(uid),
        updatedAt: now,
      });
      for (const memberDoc of freshMemberDocsSnap.docs) {
        tx.delete(memberDoc.ref);
      }
      const activityRef = groupRef.collection('activity').doc();
      tx.set(activityRef, {
        id: activityRef.id,
        type: 'member_left',
        actorId: uid,
        actorName: freshActorName,
        description: 'left the group',
        metadata: {},
        timestamp: new Date().toISOString(),
      });
      return { alreadyLeft: false };
    });

    if (mutation.alreadyLeft) {
      return { groupId, mode: 'left', alreadyLeft: true };
    }

    logger.info('leaveGroup removed member', { uid, groupId });

    return { groupId, mode: 'left', alreadyLeft: false };
  },
);
