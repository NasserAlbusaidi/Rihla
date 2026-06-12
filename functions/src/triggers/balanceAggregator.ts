import {
  DocumentData,
  FieldValue,
  Firestore,
  getFirestore,
} from 'firebase-admin/firestore';
import { onDocumentWritten } from 'firebase-functions/v2/firestore';
import { logger } from 'firebase-functions/v2';
import Decimal from 'decimal.js';
import '../admin';

import { recomputeNet } from '../callables/groupNetBalance';

// #366 — server-maintained per-group balance aggregate.
//
// Maintains groups/{gid}/aggregates/balance as a DISPLAY CACHE for the home
// dashboard (hero, group rows, journey tickets). It is never OUTBOUND: no
// write path, settle-up flow, or server gate reads it — deleteGroup/leaveGroup/
// removeMember call recomputeNet fresh per invocation. The blast radius of any
// bug here is a wrong number displayed on home until the next write or the
// daily balanceReconciler sweep.
//
// There is NO balance math in this module. The handler calls the shared
// groupNetBalance oracle (parity with the client BalanceCalculator by
// construction) and only ENCODES the result. Full recompute-on-write — not
// incremental deltas — keeps it idempotent under Eventarc's at-least-once
// delivery and self-healing after any missed event.
//
// Ordering guard (spec §0.5): trigger sourceTimeMs = CloudEvent time ≈ the
// commit time of the triggering write. If t1 < t2, write₁ committed before
// write₂, so the recompute fired by write₂ (whose reads start after write₂'s
// commit) has observed write₁ too — skipping any recompute with a smaller
// source time discards only information the surviving write already contains.
// Equal times (one batch fanning out / a redelivery) overwrite with identical
// data. No retry option on purpose: a transiently lost event heals on the next
// write or the reconciler, while retry on a deterministic bug would storm.

export const AGGREGATE_SCHEMA_VERSION = 1;

const DEFAULT_MAX_BYTES = 900_000;

// Encode a Decimal net as integer milli-units (× 1000). Exact for every
// supported currency: scales {1, 100, 1000} all divide 1000, and every oracle
// output is an integer multiple of 1/scale (allocations are subunit-quantized;
// remainders/residuals are differences of subunit-exact values). The defensive
// branch truncates toward zero, mirroring MoneySerializer's toBigInt.
export function toMilli(value: Decimal): number {
  const milli = value.times(1000);
  if (!milli.isInteger()) {
    logger.error('balanceAggregator: non-integral milli value, truncating', {
      value: value.toString(),
    });
    return milli.toDecimalPlaces(0, Decimal.ROUND_DOWN).toNumber();
  }
  return milli.toNumber();
}

function maxBytes(): number {
  const parsed = parseInt(process.env.BALANCE_AGGREGATE_MAX_BYTES ?? '', 10);
  return Number.isFinite(parsed) && parsed > 0 ? parsed : DEFAULT_MAX_BYTES;
}

// Recompute the group's balance via the shared oracle and write the aggregate
// doc behind the sourceTimeMs guard. Skips groups that are missing, soft-
// deleted, or mid-deleteGroup-cascade (the callable owns that window and
// deletes the aggregate doc itself).
export async function refreshGroupBalanceAggregate(
  db: Firestore,
  groupId: string,
  sourceTimeMs: number,
): Promise<void> {
  const groupRef = db.collection('groups').doc(groupId);
  const groupSnap = await groupRef.get();
  const groupData = groupSnap.data();
  if (
    !groupSnap.exists ||
    groupData == null ||
    groupData.isDeleted === true ||
    groupData.deletingInProgress === true
  ) {
    return;
  }

  const result = await recomputeNet(db, groupRef);

  // Shim #2 (#382 PR-2 — REMOVED in PR-3 when the v2 bucketed doc lands). The
  // oracle now returns per-currency buckets (currency -> uid -> net), but the v1
  // aggregate doc is flat. While the uniformity rules are LIVE (#382 PR-6
  // relaxes them last) every prod group holds exactly one currency, so net has
  // exactly one bucket; collapse it to the flat per-uid map the v1 encode
  // expects — byte-identical to the pre-PR-2 doc. A >1-bucket map is unreachable
  // in prod; if one ever appears (a legacy/Admin mixed-case doc) we mark the doc
  // degraded so the client falls back to the once-path loudly rather than
  // persist a half-currency cache. recomputeNet's finalizeNet guarantees a
  // no-money group still yields a single (OMR) bucket of zeros, so the flat
  // netMilli/perEventNetMilli key-sets are preserved.
  const multiCurrency = result.net.size > 1;
  const flatNet: Map<string, Decimal> = multiCurrency
    ? new Map<string, Decimal>()
    : (result.net.values().next().value ?? new Map<string, Decimal>());
  const flatPerEventNet = new Map<string, Map<string, Decimal>>();
  for (const [eventId, slice] of result.perEventNet) {
    flatPerEventNet.set(
      eventId,
      slice.size > 1
        ? new Map<string, Decimal>()
        : (slice.values().next().value ?? new Map<string, Decimal>()),
    );
  }

  const netMilli: Record<string, number> = {};
  for (const [uid, value] of flatNet) {
    netMilli[uid] = toMilli(value);
  }
  const perEventNetMilli: Record<string, Record<string, number>> = {};
  for (const [eventId, slice] of flatPerEventNet) {
    const encoded: Record<string, number> = {};
    for (const [uid, value] of slice) {
      encoded[uid] = toMilli(value);
    }
    perEventNetMilli[eventId] = encoded;
  }
  const currencies = [...result.currencies].sort();

  // Firestore caps docs at 1 MiB. JSON length over the variable-size parts is
  // a conservative proxy; past the threshold we write a DEGRADED marker doc
  // (no maps) so the client falls back loudly instead of this write failing
  // forever and freezing a stale doc in place. #382 PR-2: a >1-currency group
  // (unreachable under live uniformity rules) also degrades — the flat v1 doc
  // cannot represent multiple buckets.
  const mapsBytes = JSON.stringify({ netMilli, perEventNetMilli, currencies }).length;
  const degraded = multiCurrency || mapsBytes > maxBytes();
  if (degraded) {
    logger.warn('balanceAggregator: degraded aggregate (maps exceed size cap)', {
      groupId,
      mapsBytes,
    });
  }

  const payload: DocumentData = {
    schemaVersion: AGGREGATE_SCHEMA_VERSION,
    currency: typeof groupData.currency === 'string' ? groupData.currency : 'OMR',
    eventCount: result.eventCount,
    degraded,
    sourceTimeMs,
    computedAt: FieldValue.serverTimestamp(),
    ...(degraded ? {} : { currencies, netMilli, perEventNetMilli }),
  };

  const aggRef = groupRef.collection('aggregates').doc('balance');
  await db.runTransaction(async (tx) => {
    const existing = await tx.get(aggRef);
    const existingTime = existing.exists ? existing.data()?.sourceTimeMs : null;
    if (typeof existingTime === 'number' && existingTime > sourceTimeMs) {
      return; // a fresher recompute already landed — this one is stale
    }
    tx.set(aggRef, payload);
  });
}

// ---------------------------------------------------------------------------
// Trigger wrappers — diff-gated so writes that cannot move money never
// recompute (the expenseAuditLogger CONTENT_KEYS precedent).
// ---------------------------------------------------------------------------

const EXPENSE_BALANCE_KEYS = [
  'amountFils',
  'currency',
  'payerParticipantId',
  'scope',
  'subGroupId',
  'splitMode',
  'splitDistribution',
  'customSplitParticipants',
  'isDeleted',
] as const;
// description/note/categoryId/receiptUrl/lastEditedBy edits don't move money.

const SETTLEMENT_BALANCE_KEYS = [
  'amountFils',
  'currency',
  'payerParticipantId',
  'recipientParticipantId',
  'isDeleted',
] as const;

const EVENT_BALANCE_KEYS = ['participantIds', 'isDeleted'] as const;
// participantNames-only updates (renames) don't move money.

const MEMBER_BALANCE_KEYS = ['userId', 'isTombstone'] as const;
// displayName changes don't move money.

const AGGREGATED_EVENT_MODULES = new Set(['expenses', 'settlements']);

function deepEqual(a: unknown, b: unknown): boolean {
  if (a === b) return true;
  if (typeof a !== typeof b) return false;
  if (a == null || b == null) return false;
  if (Array.isArray(a) || Array.isArray(b)) {
    if (!Array.isArray(a) || !Array.isArray(b) || a.length !== b.length) return false;
    return a.every((v, i) => deepEqual(v, b[i]));
  }
  if (typeof a === 'object') {
    const aKeys = Object.keys(a as Record<string, unknown>);
    const bKeys = Object.keys(b as Record<string, unknown>);
    if (aKeys.length !== bKeys.length) return false;
    return aKeys.every((k) =>
      deepEqual((a as Record<string, unknown>)[k], (b as Record<string, unknown>)[k]),
    );
  }
  return false;
}

// True when the write can move money: creates, hard deletes (Admin-only,
// defensive), or an update touching any balance-relevant key.
export function shouldRecompute(
  before: DocumentData | undefined,
  after: DocumentData | undefined,
  keys: readonly string[],
): boolean {
  if (before == null || after == null) return true;
  return keys.some((key) => !deepEqual(before[key], after[key]));
}

type FirestoreWriteEvent = {
  data?: {
    before?: { data(): DocumentData | undefined };
    after?: { data(): DocumentData | undefined };
  };
  time: string;
  params: Record<string, string>;
};

function handleWrite(
  event: FirestoreWriteEvent,
  keys: readonly string[],
): Promise<void> {
  const before = event.data?.before?.data();
  const after = event.data?.after?.data();
  if (!shouldRecompute(before, after, keys)) return Promise.resolve();
  return refreshGroupBalanceAggregate(
    getFirestore(),
    event.params.gid,
    Date.parse(event.time),
  );
}

// T1 — event-scoped money docs (expenses + settlements) in one trigger via the
// `{module}` wildcard segment (the writeRateMonitor precedent). activity_logs
// writes — one per audited expense edit — are skipped by the module gate.
export const eventModuleBalanceAggregator = onDocumentWritten(
  'groups/{gid}/events/{eid}/{module}/{docId}',
  (event) => {
    if (!AGGREGATED_EVENT_MODULES.has(event.params.module)) {
      return Promise.resolve();
    }
    const keys =
      event.params.module === 'expenses'
        ? EXPENSE_BALANCE_KEYS
        : SETTLEMENT_BALANCE_KEYS;
    return handleWrite(event, keys);
  },
);

// T2 — group-scope settlements.
export const groupSettlementBalanceAggregator = onDocumentWritten(
  'groups/{gid}/settlements/{settlementId}',
  (event) => handleWrite(event, SETTLEMENT_BALANCE_KEYS),
);

// T3 — event docs (participantIds changes via the join fan-out, soft-deletes).
export const eventBalanceAggregator = onDocumentWritten(
  'groups/{gid}/events/{eid}',
  (event) => handleWrite(event, EVENT_BALANCE_KEYS),
);

// T4 — member docs (tombstones from deleteAccount, removals from
// leaveGroup/removeMember).
export const memberBalanceAggregator = onDocumentWritten(
  'groups/{gid}/members/{memberId}',
  (event) => handleWrite(event, MEMBER_BALANCE_KEYS),
);
