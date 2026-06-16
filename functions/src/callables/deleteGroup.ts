import {
  DocumentData,
  DocumentReference,
  FieldValue,
  Firestore,
  Timestamp,
  WriteBatch,
  getFirestore,
} from 'firebase-admin/firestore';
import { logger } from 'firebase-functions/v2';
import { CallableRequest, HttpsError, onCall } from 'firebase-functions/v2/https';
import '../admin';
import { recomputeNet, timestampMillis } from './groupNetBalance';

// #190: server-authoritative group deletion. The callable recomputes per-actor
// net balances via the shared groupNetBalance oracle (EXACTLY as the client
// BalanceCalculator), refuses with FAILED_PRECONDITION on any non-zero net,
// then SOFT-deletes the group + its events (keeping the append-only
// expense/settlement records reachable for the audit trail). The group doc is
// UPDATED (isDeleted:true), never destroyed — the direct client delete path is
// locked in firestore.rules (`allow delete: if false;`).

export interface DeleteGroupInput {
  groupId: string;
}

export interface DeleteGroupOutput {
  groupId: string;
  mode: 'softDelete';
  eventsSoftDeleted: number;
  alreadyDeleted: boolean;
}

// ---------------------------------------------------------------------------
// Batch writer (≤450-op auto-flush). Local to this callable with its OWN test
// seam (DELETE_GROUP_BATCH_LIMIT) so the deleteAccount cascade stays untouched.
// ---------------------------------------------------------------------------

const DEFAULT_BATCH_LIMIT = 450;

function resolveBatchLimit(): number {
  return Number(process.env.DELETE_GROUP_BATCH_LIMIT) || DEFAULT_BATCH_LIMIT;
}

class BatchWriter {
  private batch: WriteBatch;
  private writes = 0;
  private readonly limit: number;

  constructor(private readonly db: Firestore) {
    this.batch = db.batch();
    this.limit = resolveBatchLimit();
  }

  async update(ref: DocumentReference, data: DocumentData): Promise<void> {
    this.batch.update(ref, data);
    this.writes += 1;
    if (this.writes >= this.limit) {
      await this.flush();
    }
  }

  async flush(): Promise<void> {
    if (this.writes === 0) return;
    await this.batch.commit();
    this.batch = this.db.batch();
    this.writes = 0;
  }
}

const DELETE_GROUP_PAUSE_AFTER_LOCK_MS = 'DELETE_GROUP_PAUSE_AFTER_LOCK_MS';

function resolvePauseAfterLockMs(): number {
  return Number(process.env[DELETE_GROUP_PAUSE_AFTER_LOCK_MS]) || 0;
}

async function pauseAfterLockIfRequested(): Promise<void> {
  const pauseMs = resolvePauseAfterLockMs();
  if (pauseMs <= 0) return;
  await new Promise((resolve) => {
    setTimeout(resolve, pauseMs);
  });
}

// ---------------------------------------------------------------------------
// Rate limit (mirror deleteAccount.ts enforceDeletionRateLimit, own counter)
// ---------------------------------------------------------------------------

const DELETE_GROUP_ATTEMPT_LIMIT = 5;
const DELETE_GROUP_ATTEMPT_WINDOW_MS = 60 * 60 * 1000;

async function enforceDeleteGroupRateLimit(db: Firestore, uid: string): Promise<void> {
  const ref = db.doc(`deleteGroupAttempts/${uid}`);
  await db.runTransaction(async (tx) => {
    const now = Timestamp.now();
    const data = (await tx.get(ref)).data() ?? {};
    const windowStart = data.windowStart;
    const inWindow =
      windowStart instanceof Timestamp
      && now.toMillis() - windowStart.toMillis() < DELETE_GROUP_ATTEMPT_WINDOW_MS;
    const count = inWindow && typeof data.count === 'number' ? data.count : 0;
    if (count >= DELETE_GROUP_ATTEMPT_LIMIT) {
      throw new HttpsError('resource-exhausted', 'Too many delete attempts. Try again later.');
    }
    const nextWindowStart = inWindow ? (windowStart as Timestamp) : now;
    tx.set(
      ref,
      {
        count: count + 1,
        windowStart: nextWindowStart,
        expiresAt: Timestamp.fromMillis(
          nextWindowStart.toMillis() + DELETE_GROUP_ATTEMPT_WINDOW_MS,
        ),
      },
      { merge: true },
    );
  });
}

async function acquireDeleteGroupLock(
  db: Firestore,
  groupRef: DocumentReference,
  uid: string,
): Promise<{
  alreadyDeleted: boolean;
  createdLock: boolean;
  lockedAtMs: number | null;
  lockedBy: string | null;
}> {
  return db.runTransaction(async (tx) => {
    const groupSnap = await tx.get(groupRef);
    if (!groupSnap.exists) {
      throw new HttpsError('not-found', 'Group not found.');
    }

    const groupData = groupSnap.data() ?? {};
    if (groupData.isDeleted === true) {
      return {
        alreadyDeleted: true,
        createdLock: false,
        lockedAtMs: null,
        lockedBy: null,
      };
    }
    if (groupData.createdBy !== uid) {
      throw new HttpsError('permission-denied', 'Only the group creator can delete the group.');
    }
    if (groupData.deletingInProgress === true) {
      return {
        alreadyDeleted: false,
        createdLock: false,
        lockedAtMs: timestampMillis(groupData.deleteLockedAt),
        lockedBy: typeof groupData.deleteLockedBy === 'string'
          ? groupData.deleteLockedBy
          : null,
      };
    }

    const now = Timestamp.now();
    tx.update(groupRef, {
      deletingInProgress: true,
      deleteLockedAt: now,
      deleteLockedBy: uid,
      updatedAt: now,
    });
    return {
      alreadyDeleted: false,
      createdLock: true,
      lockedAtMs: now.toMillis(),
      lockedBy: uid,
    };
  });
}

async function clearDeleteGroupLockForFailure(
  groupRef: DocumentReference,
  lock: {
    createdLock: boolean;
    lockedAtMs: number | null;
    lockedBy: string | null;
  },
): Promise<void> {
  // #529: only the invocation that CREATED the lock may clear it on failure. A
  // concurrent observer (createdLock:false) never clears — clearing a peer's
  // live lock re-opens client writes against a group mid-finalize (quiesce
  // violation). Stale locks from a dead/abandoned invocation are reclaimed by
  // deleteGroupLockReaper (#519), not by an in-band observer.
  if (!lock.createdLock || lock.lockedAtMs == null || lock.lockedBy == null) {
    return;
  }
  const lockedAtMs = lock.lockedAtMs;
  const lockedBy = lock.lockedBy;

  await groupRef.firestore.runTransaction(async (tx) => {
    const groupSnap = await tx.get(groupRef);
    const groupData = groupSnap.data() ?? {};
    if (
      groupData.deletingInProgress !== true
      || groupData.deleteLockedBy !== lockedBy
      || timestampMillis(groupData.deleteLockedAt) !== lockedAtMs
    ) {
      return;
    }
    tx.update(groupRef, {
      deletingInProgress: false,
      deleteLockedAt: FieldValue.delete(),
      deleteLockedBy: FieldValue.delete(),
    });
  });
}

// ---------------------------------------------------------------------------
// Shared finalize core
// ---------------------------------------------------------------------------

// Money-safe, idempotent finalize. Reused by the callable AND the #519 reaper so
// there is no second copy to drift (mirrors the shared recomputeNet oracle). NO
// rate-limit, NO pause seam — those are callable-entry concerns.
//
// Throws FAILED_PRECONDITION (pre-mutation) when any per-currency bucket is
// unsettled; otherwise soft-deletes the live events + group doc and clears the
// lock via the finalize batch. Because the group still carries
// `deletingInProgress:true` + the ORIGINAL `deleteLockedAt`, recomputeNet's
// resume horizon (groupNetBalance.ts:518) re-includes events soft-deleted under
// the lock, so a partially flushed cascade re-runs idempotently.
//
// `onMutateStart` fires immediately BEFORE the first mutation (the aggregate
// delete) so the caller can set its `finalizeStarted` guard: any catchable error
// AFTER this point must LEAVE the lock in place for an idempotent resume (reaper
// / owner retry), never clear it — else a partial cascade's soft-deleted events
// drop from scope and balanceReconciler would heal to a wrong balance.
export async function finalizeGroupDeletion(
  db: Firestore,
  groupRef: DocumentReference,
  onMutateStart?: () => void,
): Promise<{ eventsSoftDeleted: number }> {
  const { net, liveEventRefs } = await recomputeNet(db, groupRef);
  // #382 PR-2: per-currency net buckets (currency -> uid -> net). A group is
  // settled only when EVERY actor in EVERY currency bucket nets exactly zero —
  // no FX, so each currency must clear independently. isZero() is exact (the
  // allocators close residuals, incl. the #223 in-tolerance close-out).
  const hasOutstanding = [...net.values()].some(
    (bucket) => [...bucket.values()].some((value) => !value.isZero()),
  );
  if (hasOutstanding) {
    throw new HttpsError(
      'failed-precondition',
      'Group has unsettled balances and cannot be deleted.',
    );
  }

  // #366: drop the balance-aggregate display cache BEFORE the group doc flips
  // isDeleted — a re-run after that flip short-circuits at the alreadyDeleted
  // check and would never retry this delete. Deleting a missing doc is a no-op.
  onMutateStart?.();
  await groupRef.collection('aggregates').doc('balance').delete();

  // Soft-delete the live events + the group doc. Children (expenses /
  // settlements) and the invite code are KEPT (append-only audit trail);
  // memberIds is left intact so group-settlement reads stay authorized and
  // re-runs are idempotent.
  const now = Timestamp.now();
  const writer = new BatchWriter(db);
  for (const eventRef of liveEventRefs) {
    await writer.update(eventRef, { isDeleted: true, deletedAt: now, updatedAt: now });
  }
  await writer.update(groupRef, {
    isDeleted: true,
    deletedAt: now,
    updatedAt: now,
    deletingInProgress: false,
    deleteFinalizedAt: now,
  });
  await writer.flush();

  return { eventsSoftDeleted: liveEventRefs.length };
}

// ---------------------------------------------------------------------------
// Callable
// ---------------------------------------------------------------------------

export const deleteGroup = onCall<DeleteGroupInput, Promise<DeleteGroupOutput>>(
  { enforceAppCheck: true, timeoutSeconds: 540, memory: '1GiB' },
  async (request: CallableRequest<DeleteGroupInput>) => {
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

    const lock = await acquireDeleteGroupLock(db, groupRef, uid);
    if (lock.alreadyDeleted) {
      return { groupId, mode: 'softDelete', eventsSoftDeleted: 0, alreadyDeleted: true };
    }

    let finalizeStarted = false;
    try {
      // Throttle before the (potentially large) balance recompute so replays are
      // bounded. The lock is cleared below if the throttle rejects. Rate-limit
      // stays callable-only (the #519 reaper, a system actor, is not throttled).
      await enforceDeleteGroupRateLimit(db, uid);
      await pauseAfterLockIfRequested();

      const { eventsSoftDeleted } = await finalizeGroupDeletion(
        db,
        groupRef,
        () => { finalizeStarted = true; },
      );

      logger.info('deleteGroup soft-deleted group', { uid, groupId, eventsSoftDeleted });

      return {
        groupId,
        mode: 'softDelete',
        eventsSoftDeleted,
        alreadyDeleted: false,
      };
    } catch (error) {
      if (!finalizeStarted) {
        await clearDeleteGroupLockForFailure(groupRef, lock);
      }
      throw error;
    }
  },
);
