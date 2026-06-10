import { Firestore, getFirestore } from 'firebase-admin/firestore';
import { onSchedule } from 'firebase-functions/v2/scheduler';
import { logger } from 'firebase-functions/v2';
import '../admin';

import { refreshGroupBalanceAggregate } from '../triggers/balanceAggregator';

// #366 — daily reconciliation sweep over the balance-aggregate docs.
//
// Two jobs in one (spec §0.6): BACKFILL — the first run after deploy
// materializes groups/{gid}/aggregates/balance for every live group, so no
// separate migration exists — and DRIFT HEALING — a doc the triggers should
// have kept fresh but didn't (lost event, transient handler failure: the
// triggers deliberately carry no retry) is rewritten, with a logger.warn so
// the loss is visible rather than silent. Reuses refreshGroupBalanceAggregate
// (the deletionReaper reuse-the-core precedent) — there is no second compute
// or encode path to drift.

const DEFAULT_BATCH = 200;

function reconcilerBatch(): number {
  const parsed = parseInt(process.env.BALANCE_RECONCILER_BATCH ?? '', 10);
  return Number.isFinite(parsed) && parsed > 0 ? parsed : DEFAULT_BATCH;
}

export interface ReconciliationSummary {
  scanned: number;
  refreshed: number;
  drift: number;
  failures: number;
}

// Map-content fingerprint for drift detection. Key order is deterministic for
// identical data (both encodes iterate the oracle's insertion-ordered Maps), so
// a same-data compare never false-positives; a false warn on exotic reordering
// would be noise, not harm.
function fingerprint(data: FirebaseFirestore.DocumentData | undefined): string {
  return JSON.stringify({
    n: data?.netMilli ?? null,
    p: data?.perEventNetMilli ?? null,
    e: data?.eventCount ?? null,
    c: data?.currencies ?? null,
  });
}

export async function runBalanceReconciliation(
  db: Firestore,
): Promise<ReconciliationSummary> {
  const batch = reconcilerBatch();
  const groups = await db
    .collection('groups')
    .where('isDeleted', '==', false)
    .limit(batch)
    .get();

  const summary: ReconciliationSummary = {
    scanned: groups.size,
    refreshed: 0,
    drift: 0,
    failures: 0,
  };

  for (const groupDoc of groups.docs) {
    const aggRef = groupDoc.ref.collection('aggregates').doc('balance');
    try {
      // Sweep time captured BEFORE the reads: a write racing this recompute
      // carries a later trigger time and wins the ordering guard afterwards.
      const sweepStartMs = Date.now();
      const before = await aggRef.get();
      await refreshGroupBalanceAggregate(db, groupDoc.id, sweepStartMs);
      const after = await aggRef.get();

      if (
        before.exists &&
        after.exists &&
        before.data()?.degraded !== true &&
        fingerprint(before.data()) !== fingerprint(after.data())
      ) {
        summary.drift += 1;
        logger.warn('balanceReconciler: drift healed', {
          groupId: groupDoc.id,
        });
      }
      summary.refreshed += 1;
    } catch (error) {
      summary.failures += 1;
      logger.error('balanceReconciler: group reconciliation failed', {
        groupId: groupDoc.id,
        error: error instanceof Error ? error.message : String(error),
      });
    }
  }

  if (groups.size >= batch) {
    logger.warn(
      'balanceReconciler: batch cap hit — some groups may not have been reconciled',
      { batch },
    );
  }

  logger.info('balanceReconciler: sweep complete', { ...summary });
  return summary;
}

export const balanceReconciler = onSchedule(
  { schedule: 'every 24 hours', timeoutSeconds: 540, memory: '1GiB' },
  async () => {
    await runBalanceReconciliation(getFirestore());
  },
);
