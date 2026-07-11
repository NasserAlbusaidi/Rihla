import { FieldValue, Timestamp, getFirestore } from 'firebase-admin/firestore';
import type { DocumentData } from 'firebase-admin/firestore';
import { logger } from 'firebase-functions/v2';
import { CallableRequest, HttpsError, onCall } from 'firebase-functions/v2/https';
import '../admin';
import {
  computeNetFromSnapshot,
  loadGroupBalanceSnapshot,
  universeOnlyEventIds,
} from './groupNetBalance';
import {
  acquireDepartureLock,
  assertDepartureLockHeld,
  clearDepartureLockForFailure,
  departureLockClearFields,
} from './shared/departureLock';
import { deletedUserSentinel, oldestRealMemberUid } from './shared/membership';

// #290: server-authoritative group self-leave. The client guard ("settle before
// leaving") was skipped whenever the balance had not loaded (offline / slow /
// error), so a member could leave while still owing — orphaning debt that nets
// non-zero with a departed party. This callable mirrors deleteGroup's authority:
// it recomputes the LEAVER's net via the shared groupNetBalance oracle (exactly
// as the client BalanceCalculator), refuses with FAILED_PRECONDITION on a
// non-zero net, then atomically removes the uid from memberIds + deletes EVERY
// member doc matching `userId == uid` (legacy docs may be uuid-keyed, #294) +
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
// #1144: the zero-check runs UNDER a departureInProgress lock (shared/
// departureLock.ts). Without it, any balance-input write committing between
// recomputeNet and the membership transaction departed the leaver at
// non-zero (the zero-check-to-removal race). The lock freezes client writes
// via rules groupAllowsClientWrites and is honored by every oracle-input
// Admin writer inside its own write transaction; the final transaction
// verifies the lock is still OURS and releases it atomically with the
// mutation. Lock contention / a reaped lock throw `aborted` — NEVER
// `failed-precondition`, which the client reserves for the settle-up
// snackbar. Still honors deleteGroup's quiesce marker like every Admin-SDK
// membership writer, because Admin SDK writes bypass firestore.rules.
// enforceAppCheck is the per-actor control (#197). No rate-limit: re-entry is
// bounded upstream by joinGroupByInviteCode's 5/hr throttle.

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
    if (
      group.isDeleted === true
      || group.deletingInProgress === true
      || group.claimingInProgress === true
      || group.accountDeletionInProgress === true
    ) {
      throw new HttpsError('not-found', 'Group not found.');
    }
    const memberIds: string[] = Array.isArray(group.memberIds)
      ? group.memberIds.filter((v): v is string => typeof v === 'string')
      : [];
    const isMember = memberIds.includes(uid);

    // Match member docs by the `userId` FIELD, never the doc id: new client docs
    // key by {uid}, but legacy creator docs may still be uuid-keyed (#294/#524).
    // A `.doc(uid)` lookup would miss those legacy rows.
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

    // #1144: acquire the departure lock BEFORE the balance gate so the
    // recompute basis cannot change under us. Everything after the acquire
    // runs in a try whose catch releases OUR lock (own-invocation-only).
    const lock = await acquireDepartureLock(db, groupRef, uid);

    const actorName =
      memberDocsSnap.docs
        .map((d) => d.data().displayName)
        .find((name): name is string => typeof name === 'string' && name.length > 0)
      ?? 'Someone';

    let mutation: { alreadyLeft: boolean };
    try {
      // Balance gate: the leaver must be square. This is the SAME oracle the
      // client ledger + deleteGroup use (recomputeNet = compute ∘ load); a
      // missing entry means the leaver never had a financial position ⇒ owes
      // nothing ⇒ allowed. The snapshot is loaded once and shared with the
      // #1144 R1 universe-only guard below.
      const snapshot = await loadGroupBalanceSnapshot(db, groupRef);
      const { net } = computeNetFromSnapshot(snapshot);
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

      // #1144 R1: a member with universe-only history (payer or settlement
      // party in an event that no longer rosters them) folds INTO the balance
      // universe the instant they stop being live — gaining paid rows and an
      // equal-split share the zero-gate above cannot see (the live fold DROPS
      // their rows). Refuse; the state is reachable only via a forged write
      // or a D9 roster removal of a current payer (no client UI writes roster
      // removals), and Admin roster repair is the remedy. Runs inside this
      // try so a refusal releases OUR lock like every other exit.
      if (universeOnlyEventIds(snapshot, uid).length > 0) {
        throw new HttpsError(
          'failed-precondition',
          'You have unsettled event history and cannot leave the group.',
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
        const freshMemberIds: string[] = Array.isArray(freshGroup.memberIds)
          ? freshGroup.memberIds.filter((v): v is string => typeof v === 'string')
          : [];
        const freshMemberDocsSnap = await tx.get(
          groupRef.collection('members').where('userId', '==', uid),
        );
        const freshIsMember = freshMemberIds.includes(uid);
        if (!freshIsMember && freshMemberDocsSnap.empty) {
          tx.update(groupRef, departureLockClearFields());
          return { alreadyLeft: true };
        }
        const freshActorName =
          freshMemberDocsSnap.docs
            .map((d) => d.data().displayName)
            .find((name): name is string => typeof name === 'string' && name.length > 0)
          ?? actorName;

        // #1138: creator succession. leaveGroup never reassigned createdBy, so
        // a creator leave produced an admin-less group (#1132 closed the
        // security half and deliberately opened this availability half).
        // Mirror deleteAccount Phase C: hand createdBy to the oldest real
        // remaining member; when none survives, tombstone createdBy and
        // soft-delete the group (a creator leaving an otherwise-empty group).
        // Succession is a PERMANENT handoff — a rejoining ex-creator comes
        // back as a plain MEMBER. The full-roster read runs only on a creator
        // leave, and before any write (Firestore tx ordering).
        const isCreatorLeave = freshGroup.createdBy === uid;
        let successorUid: string | null = null;
        let successorDocIds: string[] = [];
        if (isCreatorLeave) {
          const membersSnap = await tx.get(groupRef.collection('members'));
          const members = membersSnap.docs.map((d) => ({ id: d.id, data: d.data() }));
          successorUid = oldestRealMemberUid(members, uid, freshMemberIds);
          successorDocIds = members
            .filter((m) => m.data.userId === successorUid)
            .map((m) => m.id);
        }

        const now = Timestamp.now();
        const groupUpdate: DocumentData = {
          memberIds: FieldValue.arrayRemove(uid),
          updatedAt: now,
          // #1144: release the lock atomically with the mutation.
          ...departureLockClearFields(),
        };
        if (isCreatorLeave) {
          if (successorUid != null) {
            groupUpdate.createdBy = successorUid;
          } else {
            groupUpdate.createdBy = deletedUserSentinel;
            groupUpdate.isDeleted = true;
            groupUpdate.deletedAt = now;
          }
        }
        tx.update(groupRef, groupUpdate);
        // #1138: the roster badge reads member.role (group_members_section.dart),
        // a derived display surface of createdBy — keep it truthful in the same tx.
        for (const docId of successorDocIds) {
          tx.update(groupRef.collection('members').doc(docId), { role: 'CREATOR' });
        }
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
    } catch (err) {
      await clearDepartureLockForFailure(groupRef, lock);
      throw err;
    }

    if (mutation.alreadyLeft) {
      return { groupId, mode: 'left', alreadyLeft: true };
    }

    logger.info('leaveGroup removed member', { uid, groupId });

    return { groupId, mode: 'left', alreadyLeft: false };
  },
);
