import { FieldValue, getFirestore } from 'firebase-admin/firestore';
import { logger } from 'firebase-functions/v2';
import { onSchedule } from 'firebase-functions/v2/scheduler';
import '../admin';
import { finalizeGroupDeletion } from '../callables/deleteGroup';
import { timestampMillis } from '../callables/groupNetBalance';

// #519: backstop for the "deleteGroup killed mid-finalize / creator never
// retries" tail. A hard kill (540s timeout, OOM, infra) after the lock is
// acquired leaves `deletingInProgress:true`, which freezes ALL client writes via
// groupAllowsClientWrites (firestore.rules) — permanently, with no in-band
// recovery once the creator is gone. This job reclaims stale locks: it resumes
// the SHARED idempotent finalize (settled → completes the soft-delete; unsettled
// → clears the lock so the group is usable). Money-safe: it never bumps
// deleteLockedAt, so recomputeNet's resume horizon still re-includes a partially
// flushed cascade. A partial cascade is always settled (the gate passes before
// any mutation), so the unsettled-clear branch never runs on one.
const DEFAULT_GRACE_MS = 60 * 60 * 1000; // > 540s function timeout: never race a live invocation
const DEFAULT_BATCH = 50;

const resolveGraceMs = (): number =>
  Number(process.env.DELETE_GROUP_LOCK_REAPER_GRACE_MS) || DEFAULT_GRACE_MS;
const resolveBatch = (): number =>
  Number(process.env.DELETE_GROUP_LOCK_REAPER_BATCH) || DEFAULT_BATCH;

async function clearStaleLock(
  groupRef: FirebaseFirestore.DocumentReference,
  lockedBy: string | null,
  lockedAtMs: number,
): Promise<void> {
  await groupRef.firestore.runTransaction(async (tx) => {
    const cur = (await tx.get(groupRef)).data() ?? {};
    // Compare-and-clear: never clobber a lock a fresh invocation just refreshed.
    if (
      cur.deletingInProgress !== true
      || cur.deleteLockedBy !== lockedBy
      || timestampMillis(cur.deleteLockedAt) !== lockedAtMs
      || cur.claimingInProgress === true
      || cur.accountDeletionInProgress === true
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

async function clearMalformedLock(
  groupRef: FirebaseFirestore.DocumentReference,
  lockedBy: string | null,
): Promise<boolean> {
  return groupRef.firestore.runTransaction(async (tx) => {
    const cur = (await tx.get(groupRef)).data() ?? {};
    const curLockedBy = typeof cur.deleteLockedBy === 'string' ? cur.deleteLockedBy : null;
    if (
      cur.deletingInProgress !== true
      || curLockedBy !== lockedBy
      || timestampMillis(cur.deleteLockedAt) != null
      || cur.claimingInProgress === true
      || cur.accountDeletionInProgress === true
    ) {
      return false;
    }
    tx.update(groupRef, {
      deletingInProgress: false,
      deleteLockedAt: FieldValue.delete(),
      deleteLockedBy: FieldValue.delete(),
    });
    return true;
  });
}

export const deleteGroupLockReaper = onSchedule(
  { schedule: 'every 1 hours', timeoutSeconds: 540, memory: '1GiB' },
  async () => {
    const db = getFirestore();
    const cutoffMs = Date.now() - resolveGraceMs();
    // `deletingInProgress==true` is rare + short-lived → a tiny set; age-filter
    // in memory to avoid a composite index. Batch-capped; a cap hit is logged
    // (convergence, not immediacy — see below) so it is never silent.
    const locked = await db
      .collection('groups')
      .where('deletingInProgress', '==', true)
      .limit(resolveBatch())
      .get();

    let resumed = 0;
    let cleared = 0;
    let stale = 0;
    let malformed = 0;
    for (const doc of locked.docs) {
      const data = doc.data();
      const lockedAtMs = timestampMillis(data.deleteLockedAt);
      const lockedBy = typeof data.deleteLockedBy === 'string' ? data.deleteLockedBy : null;
      if (data.claimingInProgress === true || data.accountDeletionInProgress === true) {
        logger.warn('deleteGroupLockReaper left lock during claim/account-deletion freeze', {
          groupId: doc.id,
        });
        continue;
      }
      if (lockedAtMs == null) {
        malformed += 1;
        if (await clearMalformedLock(doc.ref, lockedBy)) {
          cleared += 1;
          logger.warn('deleteGroupLockReaper malformed lock cleared', { groupId: doc.id });
        }
        continue;
      }
      if (lockedAtMs >= cutoffMs) continue; // fresh → a live invocation may hold it
      stale += 1;
      try {
        // Resumes via the SAME finalize the callable runs. Idempotent: re-soft-
        // deleting already-soft-deleted events is harmless; the resume horizon
        // (unchanged deleteLockedAt) re-includes a partial cascade's events.
        await finalizeGroupDeletion(db, doc.ref);
        resumed += 1;
      } catch (error) {
        if (
          error != null
          && typeof error === 'object'
          && (error as { code?: unknown }).code === 'failed-precondition'
        ) {
          // Pre-mutation balance gate → the original op died before any soft-
          // delete (a partial cascade is always settled), so there is no torn
          // state to lose. Clear the stale lock so the group is usable again.
          await clearStaleLock(doc.ref, lockedBy, lockedAtMs);
          cleared += 1;
        } else {
          logger.error('deleteGroupLockReaper finalize error', {
            groupId: doc.id,
            error: error instanceof Error ? error.message : String(error),
          });
        }
      }
    }

    if (locked.size === resolveBatch()) {
      // Cap hit with no age-predicate/orderBy on the query → some stale locks may
      // be unscanned this pass. They self-heal on a later pass as slots free up
      // (each resumed/cleared group drops deletingInProgress). Never silent.
      logger.warn('deleteGroupLockReaper batch cap hit — stale locks may remain for next pass', {
        batch: resolveBatch(),
      });
    }
    logger.info('deleteGroupLockReaper run', {
      scanned: locked.size, stale, malformed, resumed, cleared,
    });
  },
);
