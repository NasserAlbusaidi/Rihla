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
  error: unknown,
): Promise<void> {
  const canClearObservedLock = isHttpsErrorCode(error, 'failed-precondition');
  if (
    (!lock.createdLock && !canClearObservedLock)
    || lock.lockedAtMs == null
    || lock.lockedBy == null
  ) {
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

function isHttpsErrorCode(error: unknown, code: string): boolean {
  return (
    error != null
    && typeof error === 'object'
    && 'code' in error
    && (error as { code?: unknown }).code === code
  );
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
      // bounded. The lock is cleared below if the throttle rejects.
      await enforceDeleteGroupRateLimit(db, uid);
      await pauseAfterLockIfRequested();

      const { net, liveEventRefs, currencies } = await recomputeNet(db, groupRef);
      // #261: a mixed-currency group nets to a meaningless flat scalar (a
      // +10 OMR / −10 USD group fakes Decimal 0), so the balance-zero check
      // below cannot be trusted. Refuse rather than risk deleting a group with
      // real per-currency debt. Under Model A (one currency per group) this is
      // unreachable for app data; it defends legacy/Admin-written docs.
      if (currencies.size > 1) {
        throw new HttpsError(
          'failed-precondition',
          'Group holds more than one currency and cannot be deleted.',
        );
      }
      const outstanding = [...net.entries()].filter(([, value]) => !value.isZero());
      if (outstanding.length > 0) {
        throw new HttpsError(
          'failed-precondition',
          'Group has unsettled balances and cannot be deleted.',
        );
      }

      // Soft-delete the live events + the group doc. Children (expenses /
      // settlements) and the invite code are KEPT: the records are the
      // append-only audit trail; a stale invite code is rejected at join time
      // (joinGroupByInviteCode.ts:255). memberIds is left intact so group
      // settlement reads stay authorized and re-runs are idempotent.
      // #366: drop the balance-aggregate display cache BEFORE the group doc
      // flips isDeleted — a re-run after that flip short-circuits at the
      // alreadyDeleted check and would never retry this delete. Deleting a
      // missing doc is a no-op, and if a crash lands between this delete and
      // the finalize batch, the next money write (or the deleteGroup retry)
      // simply recreates/redeletes it. The event soft-deletes below cannot
      // resurrect it: their triggers read the group doc post-commit, see
      // isDeleted:true, and skip.
      await groupRef.collection('aggregates').doc('balance').delete();

      const now = Timestamp.now();
      const writer = new BatchWriter(db);
      finalizeStarted = true;
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

      logger.info('deleteGroup soft-deleted group', {
        uid,
        groupId,
        eventsSoftDeleted: liveEventRefs.length,
      });

      return {
        groupId,
        mode: 'softDelete',
        eventsSoftDeleted: liveEventRefs.length,
        alreadyDeleted: false,
      };
    } catch (error) {
      if (!finalizeStarted) {
        await clearDeleteGroupLockForFailure(groupRef, lock, error);
      }
      throw error;
    }
  },
);
