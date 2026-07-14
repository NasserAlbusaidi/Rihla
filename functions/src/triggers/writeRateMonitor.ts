import { getFirestore, Timestamp, DocumentData } from 'firebase-admin/firestore';
import { onDocumentCreated } from 'firebase-functions/v2/firestore';
import { logger } from 'firebase-functions/v2';
import '../admin';

// #198: DETECTION-ONLY per-UID write-rate monitor.
// Event EXPENSE creates are CLIENT-DIRECT (Firestore offline persistence +
// replay — see CLAUDE.md), so a trigger fires AFTER the write commits and CANNOT
// reject it. This monitor only FLAGS bursts (a `logger.warn` + a `lastFlaggedAt`
// marker) for ops visibility; it never deletes or mutates the financial doc.
// Auto-deleting an over-threshold money write on a false positive would be
// money-wrong. Spec + threat model: docs/plans/2026-06-04-198-write-rate-detection.md.
//
// #1129 superseded the old "settlement creates are client-direct" premise:
// settlement creates are now CALLABLE-ONLY (recordSettlement, Admin SDK; rules
// deny client settlement writes in both scopes), so settlement docs and
// settlement-typed activity rows are UN-FORGEABLE and no longer counted —
// counting them was vestigial for this monitor's client-abuse purpose and a
// single legitimate large decomposed settle-up (up to 400 legs in one tx, the
// old 8-leg client cap is gone) would have false-flagged the 100/60s threshold
// AND pre-consumed the per-uid budget that exists to catch expense abuse.
// Expenses remain client-direct and counted.
//
// #526: the EVENT activity_logs subcollection is NOT counted — post-#248 it is
// written SERVER-SIDE by the expenseAuditLogger trigger (stamped with the expense
// creator's uid), so counting it would double-count the actor on every expense and
// effectively halve the threshold. Only the client-direct event expense path is
// counted here.

const WRITE_RATE_WINDOW_MS = 60_000;
const WINDOW_BUFFER_MS = 60_000;

// Env seam (mirrors deleteAccount's DELETE_ACCOUNT_BATCH_LIMIT) so a test can trip
// the threshold without writing 100 docs. Read at call time, not module load.
function resolveWriteRateLimit(): number {
  return Number(process.env.WRITE_RATE_LIMIT) || 100;
}

// T1's `{module}` wildcard matches ANY direct sub-collection of an event, so filter
// to the client-direct paths we count. activity_logs is intentionally excluded
// (#526 — server-written by expenseAuditLogger, see header); settlements are
// excluded since #1129 (callable-only, un-forgeable, see header). A future
// sub-collection silently won't be monitored.
const COUNTED_EVENT_MODULES = new Set(['expenses']);

// Expenses/settlements stamp `createdBy`; group-level `activity` stamps `actorId`.
// No counted doc carries both, so the order is unambiguous. Rules pin the field ==
// auth.uid on client writes, so it reliably identifies the writer. (The `actorId`
// branch serves T3's group-level activity; event activity_logs are not counted.)
function resolveActorUid(data: DocumentData): string | null {
  const createdBy = data.createdBy;
  if (typeof createdBy === 'string' && createdBy.length > 0) return createdBy;
  const actorId = data.actorId;
  if (typeof actorId === 'string' && actorId.length > 0) return actorId;
  return null;
}

// Counter lives at `groups/{gid}/_writeCounters/{uid}` (server-only; TTL on
// `expiresAt`). NONE of the trigger paths match `_writeCounters`, so this write
// never re-fires a trigger (no loop). Transactional read-modify-write because the
// window reset and the threshold-crossing check must be atomic; the original create
// already committed, so this never blocks the user's write.
async function recordWrite(gid: string, uid: string): Promise<void> {
  const db = getFirestore();
  const limit = resolveWriteRateLimit();
  const ref = db.doc(`groups/${gid}/_writeCounters/${uid}`);

  const { crossed, count } = await db.runTransaction(async (tx) => {
    const now = Timestamp.now();
    const data = (await tx.get(ref)).data() ?? {};
    const windowStart = data.windowStart;
    const inWindow =
      windowStart instanceof Timestamp
      && now.toMillis() - windowStart.toMillis() < WRITE_RATE_WINDOW_MS;
    const prevCount = inWindow && typeof data.count === 'number' ? data.count : 0;
    const effectiveStart = inWindow ? (windowStart as Timestamp) : now;
    const nextCount = prevCount + 1;
    // Flag once, on the first write that EXCEEDS the limit (prev <= limit < next),
    // so a sustained burst logs once per window, not once per write. (`<=` not `<`:
    // the crossing write has prev == limit.)
    const justCrossed = prevCount <= limit && nextCount > limit;
    tx.set(
      ref,
      {
        count: nextCount,
        windowStart: effectiveStart,
        expiresAt: Timestamp.fromMillis(
          effectiveStart.toMillis() + WRITE_RATE_WINDOW_MS + WINDOW_BUFFER_MS,
        ),
        ...(justCrossed ? { lastFlaggedAt: now } : {}),
      },
      { merge: true },
    );
    return { crossed: justCrossed, count: nextCount };
  });

  if (crossed) {
    logger.warn('write-rate burst flagged', {
      gid,
      uid,
      count,
      windowMs: WRITE_RATE_WINDOW_MS,
      limit,
    });
  }
}

async function countCreate(
  gid: string,
  snap: { data(): DocumentData; ref: { path: string } } | undefined,
): Promise<void> {
  if (!snap) return;
  const uid = resolveActorUid(snap.data());
  if (!uid) {
    logger.warn('write-rate monitor: create missing actor uid', { path: snap.ref.path });
    return;
  }
  await recordWrite(gid, uid);
}

// T1 — counted event sub-collections (expenses only since #1129) via the
// `{module}` wildcard-collection segment; activity_logs (#526) and settlements
// (#1129 callable-only — a marked #889 correction reverse was already skipped,
// now the whole module is) are filtered out.
export const eventWriteRateMonitor = onDocumentCreated(
  'groups/{gid}/events/{eid}/{module}/{docId}',
  (event) => {
    if (!COUNTED_EVENT_MODULES.has(event.params.module)) return Promise.resolve();
    return countCreate(event.params.gid, event.data);
  },
);

// T2 (groupSettlementWriteRateMonitor) was DELETED by #1129: group-scope
// settlement docs are callable-only (recordSettlement / correctSettlement /
// correctLogicalSettleUp, all Admin SDK) — nothing client-forgeable remains on
// that path to monitor.

// T3 — group-level activity. Skipped types are the SERVER-authored rows:
// expense_* (expenseAuditLogger fan-in of an expense T1 already counted, #808
// PR1), event_settlement/group_settlement (recordSettlement's co-written
// row, #1129 — also no longer in validGroupActivityCreate's client allow-list),
// and member_resplit (#1059 — the join/addShadowMember post-commit disclosure,
// never client-writable). Keying the skip on `type` is safe ONLY because that
// allow-list makes these types un-forgeable by clients (same rationale as the
// #526 activity_logs filter) — extend BOTH together.
const SKIPPED_ACTIVITY_TYPES = new Set([
  'event_settlement',
  'group_settlement',
  'member_resplit',
]);

export const groupActivityWriteRateMonitor = onDocumentCreated(
  'groups/{gid}/activity/{activityId}',
  (event) => {
    const type = event.data?.data()?.type;
    if (typeof type === 'string' && (type.startsWith('expense_') || SKIPPED_ACTIVITY_TYPES.has(type))) {
      return Promise.resolve();
    }
    return countCreate(event.params.gid, event.data);
  },
);
