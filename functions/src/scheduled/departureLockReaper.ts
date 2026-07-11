import { FieldValue, getFirestore } from 'firebase-admin/firestore';
import { logger } from 'firebase-functions/v2';
import { onSchedule } from 'firebase-functions/v2/scheduler';
import '../admin';
import { timestampMillis } from '../callables/groupNetBalance';

// #1144: backstop for "leaveGroup/removeMember killed after acquiring the
// departure lock". A lingering departureInProgress freezes ALL client writes
// via groupAllowsClientWrites (firestore.rules) with no in-band recovery —
// in-band callers never clear a peer's lock (departureLock.ts). Unlike
// deleteGroupLockReaper there is NOTHING to resume: the membership mutation
// releases the lock atomically in the same transaction (leaveGroup.ts /
// removeMember.ts), so a lingering lock proves the mutation never committed
// and clearing is always safe.
const DEFAULT_GRACE_MS = 60 * 60 * 1000; // > 540s function timeout: never race a live invocation
const DEFAULT_BATCH = 50;

const resolveGraceMs = (): number =>
  Number(process.env.DEPARTURE_LOCK_REAPER_GRACE_MS) || DEFAULT_GRACE_MS;
const resolveBatch = (): number =>
  Number(process.env.DEPARTURE_LOCK_REAPER_BATCH) || DEFAULT_BATCH;

async function clearLock(
  groupRef: FirebaseFirestore.DocumentReference,
  lockedBy: string | null,
  lockedAtMs: number | null,
): Promise<boolean> {
  return groupRef.firestore.runTransaction(async (tx) => {
    const cur = (await tx.get(groupRef)).data() ?? {};
    const curLockedBy = typeof cur.departureLockedBy === 'string' ? cur.departureLockedBy : null;
    // Compare-and-clear: never clobber a lock a fresh invocation just took.
    // Freeze-respect: leave the flag alone while another cascade holds the
    // group (mirrors deleteGroupLockReaper).
    if (
      cur.departureInProgress !== true
      || curLockedBy !== lockedBy
      || timestampMillis(cur.departureLockedAt) !== lockedAtMs
      || cur.deletingInProgress === true
      || cur.claimingInProgress === true
      || cur.accountDeletionInProgress === true
    ) {
      return false;
    }
    tx.update(groupRef, {
      departureInProgress: false,
      departureLockedAt: FieldValue.delete(),
      departureLockedBy: FieldValue.delete(),
    });
    return true;
  });
}

export const departureLockReaper = onSchedule(
  { schedule: 'every 1 hours', timeoutSeconds: 540, memory: '256MiB' },
  async () => {
    const db = getFirestore();
    const cutoffMs = Date.now() - resolveGraceMs();
    // departureInProgress==true is rare + short-lived → a tiny set; age-filter
    // in memory to avoid a composite index (same trade as deleteGroupLockReaper).
    const locked = await db
      .collection('groups')
      .where('departureInProgress', '==', true)
      .limit(resolveBatch())
      .get();

    let stale = 0;
    let malformed = 0;
    let cleared = 0;
    for (const doc of locked.docs) {
      const data = doc.data();
      const lockedAtMs = timestampMillis(data.departureLockedAt);
      const lockedBy = typeof data.departureLockedBy === 'string' ? data.departureLockedBy : null;
      if (
        data.deletingInProgress === true
        || data.claimingInProgress === true
        || data.accountDeletionInProgress === true
      ) {
        logger.warn('departureLockReaper left lock during another freeze', { groupId: doc.id });
        continue;
      }
      if (lockedAtMs == null) {
        // Malformed (no timestamp): unreapable by age — clear immediately.
        malformed += 1;
      } else if (lockedAtMs >= cutoffMs) {
        continue; // fresh → a live invocation may hold it
      } else {
        stale += 1;
      }
      if (await clearLock(doc.ref, lockedBy, lockedAtMs)) {
        cleared += 1;
        logger.warn('departureLockReaper cleared lingering departure lock', { groupId: doc.id });
      }
    }

    if (locked.size === resolveBatch()) {
      logger.warn('departureLockReaper batch cap hit — stale locks may remain for next pass', {
        batch: resolveBatch(),
      });
    }
    logger.info('departureLockReaper run', {
      scanned: locked.size, stale, malformed, cleared,
    });
  },
);
