import {
  Firestore,
  getFirestore,
  FieldPath,
  QueryDocumentSnapshot,
} from 'firebase-admin/firestore';
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
//
// #525 — the sweep CURSOR-PAGINATES the whole groups collection (ordered by
// document id) instead of reading one fixed `.limit()` page. Two reasons:
//   1. The page filter cannot be `where('isDeleted','==',false)` — a Firestore
//      equality query silently excludes docs where the field is ABSENT, so
//      pre-#190 legacy groups would never be backfilled/drift-healed. We fetch
//      every group and skip ONLY explicit soft-deletes in the loop (mirrors
//      balanceAggregator.ts + group_provider.dart).
//   2. Soft-deleted group docs are retained forever (deleteGroup soft-deletes,
//      never purges). A single fixed page would let accumulated dead docs
//      consume slots and permanently starve live groups sorting behind them out
//      of the SOLE full-collection drift-healer. Paginating reaches every live
//      group; MAX_GROUPS only bounds cost, with a LOUD warn (never a silent cap).

const DEFAULT_PAGE = 200;
const DEFAULT_MAX_GROUPS = 10_000;

// Page size for the cursor sweep (NOT a total cap — the sweep pages past it).
function reconcilerPageSize(): number {
  const parsed = parseInt(process.env.BALANCE_RECONCILER_BATCH ?? '', 10);
  return Number.isFinite(parsed) && parsed > 0 ? parsed : DEFAULT_PAGE;
}

// Hard ceiling on live groups reconciled per run — a cost backstop, far above
// realistic scale; hitting it logs a loud warn so coverage loss is never silent.
function reconcilerMaxGroups(): number {
  const parsed = parseInt(process.env.BALANCE_RECONCILER_MAX ?? '', 10);
  return Number.isFinite(parsed) && parsed > 0 ? parsed : DEFAULT_MAX_GROUPS;
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
    n: data?.netMilliByCurrency ?? null,
    p: data?.perEventNetMilliByCurrency ?? null,
    e: data?.eventCount ?? null,
  });
}

// Recompute one group's aggregate; warn if the existing doc had drifted.
async function reconcileGroup(
  db: Firestore,
  groupDoc: QueryDocumentSnapshot,
  summary: ReconciliationSummary,
): Promise<void> {
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
      logger.warn('balanceReconciler: drift healed', { groupId: groupDoc.id });
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

export async function runBalanceReconciliation(
  db: Firestore,
): Promise<ReconciliationSummary> {
  const pageSize = reconcilerPageSize();
  const maxGroups = reconcilerMaxGroups();
  const summary: ReconciliationSummary = {
    scanned: 0,
    refreshed: 0,
    drift: 0,
    failures: 0,
  };

  // Order by document id: every doc has one (an orderBy on a possibly-absent
  // field would re-introduce the legacy-exclusion bug), so this paginates
  // deterministically AND never drops a field-absent legacy group.
  let cursor: QueryDocumentSnapshot | null = null;
  let truncated = false;

  while (true) {
    let query = db
      .collection('groups')
      .orderBy(FieldPath.documentId())
      .limit(pageSize);
    if (cursor) query = query.startAfter(cursor);
    const page = await query.get();
    if (page.empty) break;

    let capped = false;
    for (const groupDoc of page.docs) {
      cursor = groupDoc;
      if (groupDoc.data()?.isDeleted === true) continue;
      if (summary.scanned >= maxGroups) {
        truncated = true;
        capped = true;
        break;
      }
      summary.scanned += 1;
      await reconcileGroup(db, groupDoc, summary);
    }

    if (capped || page.size < pageSize) break;
  }

  if (truncated) {
    logger.warn(
      'balanceReconciler: max-groups cap hit — some live groups were not reconciled this run',
      { maxGroups },
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
