import {
  DocumentData,
  DocumentReference,
  Firestore,
  Timestamp,
} from 'firebase-admin/firestore';
import Decimal from 'decimal.js';

// Shared group-balance oracle. Recomputes per-actor net balances EXACTLY as the
// client BalanceCalculator (per-doc currency decode, the percent /1000 split
// decode, the per-event former-actor universe, strict `isDeleted === false`).
// Extracted from deleteGroup.ts (#190) so the server-authoritative deleteGroup
// (#190) and leaveGroup (#290) callables share ONE oracle by construction —
// CLAUDE.md makes byte-for-byte balance parity load-bearing, and a second
// hand-rolled copy would drift. Behavior-preserving move: `deleteGroup.test.ts`
// + `delete_group_balance_parity_test.dart` stay green = the proof.

// Isolated Decimal constructor (clone, NOT the global) so this module's rounding
// config never leaks to any other function that imports decimal.js. ROUND_DOWN =
// truncate toward zero, mirroring Dart's `Rational.truncate()` / `BigInt`
// conversion used throughout MoneySerializer + BalanceCalculator; high precision
// so division never rounds before the explicit subunit quantization.
export const Money = Decimal.clone({ precision: 50, rounding: Decimal.ROUND_DOWN });

// ---------------------------------------------------------------------------
// MoneySerializer port (lib/core/services/money_serializer.dart)
// ---------------------------------------------------------------------------

const CURRENCY_SCALE: Record<string, number> = {
  OMR: 1000,
  USD: 100,
  EUR: 100,
  GBP: 100,
  SAR: 100,
  AED: 100,
  JPY: 1,
  KWD: 1000,
  BHD: 1000,
  QAR: 100,
};

function isSupportedCurrency(currency: string): boolean {
  return Object.prototype.hasOwnProperty.call(CURRENCY_SCALE, currency.toUpperCase());
}

function currencyScale(currency: string): number {
  return CURRENCY_SCALE[currency.toUpperCase()];
}

// Mirror expense_provider.dart:155-157 + the model defaults: unknown/garbage
// currency falls back to OMR so the gate never throws on untrusted Firestore data.
function currencyOf(raw: unknown): string {
  return typeof raw === 'string' && isSupportedCurrency(raw) ? raw : 'OMR';
}

function fromSubunits(subunits: number, currency: string): Decimal {
  return new Money(subunits).div(currencyScale(currency));
}

// Quantize toward zero to [currency]'s subunit precision by the same integer
// round-trip MoneySerializer uses (toSubunits truncates via `.toBigInt()`).
function quantize(value: Decimal, currency: string): Decimal {
  const scale = currencyScale(currency);
  const subunits = value.times(scale).toDecimalPlaces(0, Decimal.ROUND_DOWN);
  return subunits.div(scale);
}

// ---------------------------------------------------------------------------
// Split-value decode by mode (expense_model.dart:341-362 _splitValueFromPersisted)
// ---------------------------------------------------------------------------

type SplitMode = 'equally' | 'shares' | 'exact' | 'percent';

// Mirror Expense._splitModeFromPersisted + splitModeFromStorage: null stays
// null; any other non-null value that is not a known key falls back to 'equally'.
function decodeSplitMode(raw: unknown): SplitMode | null {
  if (raw == null) return null;
  const s = String(raw);
  if (s === 'equally' || s === 'shares' || s === 'exact' || s === 'percent') {
    return s;
  }
  return 'equally';
}

function persistedInt(value: unknown): number {
  if (typeof value === 'number') return Math.trunc(value);
  if (typeof value === 'string') {
    const parsed = Number(value);
    return Number.isFinite(parsed) ? Math.trunc(parsed) : 0;
  }
  return 0;
}

function decodeSplitValue(value: unknown, mode: SplitMode, currency: string): Decimal {
  const persisted = persistedInt(value);
  switch (mode) {
    case 'exact':
      return fromSubunits(persisted, currency);
    case 'percent':
      // value x 1000 was persisted; decode back to 0..100 humanPercent.
      return new Money(persisted).div(1000);
    case 'shares':
    case 'equally':
      return new Money(persisted);
  }
}

// Returns null when raw is absent / not a map / mode is null, or when the
// decoded map is empty (mirror _splitDistributionFromPersisted).
function decodeDistribution(
  raw: unknown,
  mode: SplitMode | null,
  currency: string,
): Map<string, Decimal> | null {
  if (raw == null || mode == null || typeof raw !== 'object' || Array.isArray(raw)) {
    return null;
  }
  const out = new Map<string, Decimal>();
  for (const [key, value] of Object.entries(raw as Record<string, unknown>)) {
    out.set(key, decodeSplitValue(value, mode, currency));
  }
  return out.size === 0 ? null : out;
}

// ---------------------------------------------------------------------------
// Allocation (BalanceCalculator._allocate* in expense_provider.dart)
// ---------------------------------------------------------------------------

const SPLIT_TOLERANCE = new Money('0.001');
const HUNDRED = new Money(100);

function sumValues(map: Map<string, Decimal>): Decimal {
  let total = new Money(0);
  for (const value of map.values()) total = total.plus(value);
  return total;
}

// Equal split: each non-last recipient gets the truncated per-head; the
// alphabetically-LAST recipient absorbs the remainder so sum(slices) == amount.
function allocateEqual(
  amount: Decimal,
  recipientIds: Iterable<string>,
  currency: string,
): Map<string, Decimal> {
  // Dedup: the client's scope-based equal split operates on a Set
  // (customSplitParticipants.toSet() / the participant universe), so a
  // duplicated custom recipient must not inflate the per-head divisor.
  const sorted = [...new Set(recipientIds)].sort();
  const out = new Map<string, Decimal>();
  const count = sorted.length;
  if (count === 0) return out;
  const perHead = quantize(amount.div(count), currency);
  const remainder = amount.minus(perHead.times(count));
  sorted.forEach((id, i) => {
    const isLast = i === count - 1;
    out.set(id, isLast ? perHead.plus(remainder) : perHead);
  });
  return out;
}

// Weighted split (shares / percent): non-remainder recipients quantized; the
// alphabetically-last POSITIVE-weight recipient absorbs the running remainder
// so sum(slices) == amount exactly — never a declared-0-share key (#872).
// Byte-for-byte mirror of the client _allocateWeighted
// (expense_provider.dart); callers guarantee >=1 positive weight, so the
// whole-table-last fallback is defensive only. Parity note: remainder
// selection depends on weight positivity, and both sides decode positivity
// identically (shares are raw ints; percent persists x1000 and decodes /1000
// in decodeSplitValue and the client _splitValueFromPersisted alike) — keep
// those decodes in lockstep or the oracle drifts.
function allocateWeighted(
  amount: Decimal,
  weights: Map<string, Decimal>,
  denominator: Decimal,
  currency: string,
): Map<string, Decimal> {
  const sorted = [...weights.keys()].sort();
  let remainderKey = sorted[sorted.length - 1];
  for (let i = sorted.length - 1; i >= 0; i--) {
    if (weights.get(sorted[i])!.gt(0)) {
      remainderKey = sorted[i];
      break;
    }
  }
  const allocations = new Map<string, Decimal>();
  let allocated = new Money(0);
  for (const id of sorted) {
    if (id === remainderKey) continue;
    const allocation = quantize(amount.times(weights.get(id)!).div(denominator), currency);
    allocations.set(id, allocation);
    allocated = allocated.plus(allocation);
  }
  allocations.set(remainderKey, amount.minus(allocated));
  return new Map(sorted.map((id) => [id, allocations.get(id)!]));
}

function allocateShares(
  amount: Decimal,
  distribution: Map<string, Decimal>,
  currency: string,
): Map<string, Decimal> {
  // #270: a negative share is never a valid weight — without this guard a
  // negative entry with a still-positive total (e.g. {-1, 5}) reaches
  // allocateWeighted and emits a negative owed, diverging from the client
  // _allocateShares (expense_provider.dart:457). New negatives are rules-blocked
  // (firestore.rules:497 splitValuesNonNegative); only a legacy/Admin doc could
  // carry one. Guard FIRST, mirroring the Dart equal-split fallback.
  if ([...distribution.values()].some((value) => value.lt(0))) {
    return allocateEqual(amount, distribution.keys(), currency);
  }
  const totalShares = sumValues(distribution);
  if (totalShares.lte(0)) {
    return allocateEqual(amount, distribution.keys(), currency);
  }
  return allocateWeighted(amount, distribution, totalShares, currency);
}

function allocateExact(
  amount: Decimal,
  distribution: Map<string, Decimal>,
  currency: string,
): Map<string, Decimal> {
  // #270: a negative exact entry is never a valid split — and it can still be
  // IN-tolerance (e.g. {-1.000, 11.000} sums to amount 10.000), so the tolerance
  // check + residual close-out below would keep it verbatim. Guard FIRST,
  // mirroring _allocateExact (expense_provider.dart:492). See allocateShares for
  // the threat model (legacy/Admin docs; new negatives are rules-blocked).
  if ([...distribution.values()].some((value) => value.lt(0))) {
    return allocateEqual(amount, distribution.keys(), currency);
  }
  const total = sumValues(distribution);
  if (total.minus(amount).abs().gt(SPLIT_TOLERANCE)) {
    return allocateEqual(amount, distribution.keys(), currency);
  }
  // In-tolerance (±SPLIT_TOLERANCE) non-zero drift: close the residual onto the
  // alphabetically-LAST recipient that can absorb it without going negative, so
  // sum(owed) == amount EXACTLY. This MUST mirror the client BalanceCalculator
  // ._allocateExact (expense_provider.dart:507-543) byte-for-byte — without it
  // the server net carries the residual the client closed, diverging by up to
  // ±tolerance per expense and (since the deleteGroup gate is an exact
  // !isZero() check) refusing to delete a group the app shows as settled (#223).
  const residual = amount.minus(total);
  if (residual.isZero()) {
    return new Map(distribution);
  }
  const sortedKeys = [...distribution.keys()].sort();
  let target: string | null = null;
  for (let i = sortedKeys.length - 1; i >= 0; i--) {
    if (distribution.get(sortedKeys[i])!.plus(residual).gte(0)) {
      target = sortedKeys[i];
      break;
    }
  }
  if (target === null) {
    // No recipient can absorb the residual non-negatively — unreachable for an
    // in-tolerance drift on a positive amount; mirror the client's defensive
    // equal-split fallback (expense_provider.dart:532-539) rather than emit a
    // negative owed.
    return allocateEqual(amount, distribution.keys(), currency);
  }
  const out = new Map<string, Decimal>();
  for (const key of sortedKeys) {
    out.set(
      key,
      key === target ? distribution.get(key)!.plus(residual) : distribution.get(key)!,
    );
  }
  return out;
}

function allocatePercent(
  amount: Decimal,
  distribution: Map<string, Decimal>,
  currency: string,
): Map<string, Decimal> {
  // #270: a negative percent is never a valid weight — and entries can still sum
  // to 100 (in-tolerance, e.g. {-20, 120}), reaching allocateWeighted. Guard
  // FIRST, mirroring _allocatePercent (expense_provider.dart:554).
  if ([...distribution.values()].some((value) => value.lt(0))) {
    return allocateEqual(amount, distribution.keys(), currency);
  }
  const total = sumValues(distribution);
  if (total.minus(HUNDRED).abs().gt(SPLIT_TOLERANCE)) {
    return allocateEqual(amount, distribution.keys(), currency);
  }
  return allocateWeighted(amount, distribution, HUNDRED, currency);
}

// ---------------------------------------------------------------------------
// Balance recompute (mirror group_balance_provider.dart + BalanceCalculator)
// ---------------------------------------------------------------------------

function amountFilsOf(data: DocumentData): number {
  return typeof data.amountFils === 'number' ? data.amountFils : 0;
}

function isLiveDoc(data: DocumentData): boolean {
  // Strict `isDeleted === false`: a Firestore equality query (the client's
  // `where('isDeleted','==',false)`) excludes absent/null docs. Do NOT use
  // `isDeleted !== true`.
  return data.isDeleted === false;
}

export function timestampMillis(value: unknown): number | null {
  if (value instanceof Timestamp) return value.toMillis();
  if (value instanceof Date) return value.getTime();
  if (
    value != null
    && typeof value === 'object'
    && 'toMillis' in value
    && typeof value.toMillis === 'function'
  ) {
    const millis = value.toMillis();
    return typeof millis === 'number' ? millis : null;
  }
  return null;
}

function isEventInDeleteBalanceScope(
  data: DocumentData,
  includeSoftDeletedSinceMs: number | null,
): boolean {
  if (isLiveDoc(data)) return true;
  if (includeSoftDeletedSinceMs == null || data.isDeleted !== true) return false;
  const deletedAtMs = timestampMillis(data.deletedAt);
  return deletedAtMs != null && deletedAtMs >= includeSoftDeletedSinceMs;
}

function stringArray(value: unknown): string[] {
  return Array.isArray(value) ? value.filter((v): v is string => typeof v === 'string') : [];
}

export interface RecomputeResult {
  // #382 PR-2: per-CURRENCY net buckets. currency -> uid -> net, mirroring the
  // client BalanceCalculator.calculateBalances → Map<currency, List<UserBalance>>
  // (expense_provider.dart:313-484) and computeGroupBalances.balances
  // (group_balance_provider.dart:405-424). Expenses AND settlements (event- and
  // group-scope) bucket by their OWN per-doc currency (raw, case-preserved via
  // currencyOf — NOT uppercased).
  // The gates check zero in EVERY bucket. A no-money group with participants
  // carries a single OMR bucket of universe-zeros (finalizeNet) so the flat v1
  // aggregate doc key-set is preserved.
  net: Map<string, Map<string, Decimal>>;
  liveEventRefs: DocumentReference[];
  // #366/#382: per-event drill-down slice, now also per-currency
  // (eid -> currency -> uid -> net). Universe = event.participantIds ONLY (no
  // former financial actors, no member-gated split-recipient fold) and
  // group-scope settlements are NOT folded — this mirrors the client
  // _buildPerEventBreakdown
  // (lib/features/groups/providers/group_balance_provider.dart:461-513), which
  // is pinned participantIds-only by group_balance_provider_test.dart. A
  // no-money event yields a single OMR bucket of participantIds-zeros
  // (bucketizeDrill), matching the client's explicit zero-rows. Events with
  // empty participantIds are omitted. NON-DECOMPOSITION: net is NOT the sum of
  // these slices (different universes + group settlements + drops) — never
  // reconcile one from the other.
  perEventNet: Map<string, Map<string, Map<string, Decimal>>>;
  // #366: count of events in balance scope (strict isDeleted === false outside
  // a deleteGroup lock window), mirroring GroupBalances.eventCount.
  eventCount: number;
}

// One event's money fold: each universe member's event-scoped net
// (paid + settlementAdj − owed). Extracted (#366, behavior-preserving — the
// existing deleteGroup/leaveGroup/removeMember suites are the proof) so it runs
// twice per event: once with the FULL balance universe (participantIds ∪ former
// financial actors ∪ member-gated split recipients — feeds `net`) and once with
// the participantIds-only drill-down universe (feeds `perEventNet`). The fold
// itself is identical either way: payers/recipients outside the universe are
// dropped (`.has()` gates — the load-bearing drop) and equal-split recipients
// default to the universe.
function foldEventNet(
  expenses: DocumentData[],
  settlements: DocumentData[],
  universe: Set<string>,
): Map<string, Map<string, Decimal>> {
  // currency -> uid -> amount. Each bucket is lazily created and seeded with the
  // universe at zero, mirroring the client calculateBalances `bucketFor`
  // (expense_provider.dart:329-337); the .has() membership gate below keeps
  // dropping keys outside the universe (the #192/#223 drop-guard). Bucket KEY is
  // the raw fenced currency (currencyOf — case-preserved), exactly the client's
  // `MoneySerializer.isSupported(x) ? x : 'OMR'` key, NOT uppercased.
  const paid = new Map<string, Map<string, Decimal>>();
  const owed = new Map<string, Map<string, Decimal>>();
  const adj = new Map<string, Map<string, Decimal>>();

  const bucketFor = (
    maps: Map<string, Map<string, Decimal>>,
    currency: string,
  ): Map<string, Decimal> => {
    let bucket = maps.get(currency);
    if (bucket == null) {
      bucket = new Map<string, Decimal>();
      for (const uid of universe) bucket.set(uid, new Money(0));
      maps.set(currency, bucket);
    }
    return bucket;
  };

  for (const e of expenses) {
    const currency = currencyOf(e.currency);
    const paidBucket = bucketFor(paid, currency);
    const owedBucket = bucketFor(owed, currency); // seed owed alongside paid → owed.keys ⊆ paid.keys
    const amount = fromSubunits(amountFilsOf(e), currency);
    const payerId = e.payerParticipantId;
    if (typeof payerId === 'string' && paidBucket.has(payerId)) {
      paidBucket.set(payerId, paidBucket.get(payerId)!.plus(amount));
    }

    const mode = decodeSplitMode(e.splitMode);
    const distribution = decodeDistribution(e.splitDistribution, mode, currency);

    let allocations: Map<string, Decimal>;
    if (mode != null && mode !== 'equally' && distribution != null && distribution.size > 0) {
      allocations =
        mode === 'shares'
          ? allocateShares(amount, distribution, currency)
          : mode === 'exact'
            ? allocateExact(amount, distribution, currency)
            : allocatePercent(amount, distribution, currency);
    } else {
      // Equal-split branch by scope (expense_provider.dart:186-216). The
      // global / sub_group / custom-empty universe is the FULL universe,
      // NOT participantIds alone (Gate R1 finding #2).
      const scope = typeof e.scope === 'string' ? e.scope : 'global';
      let recipients: string[];
      if (scope === 'personal') {
        recipients = typeof payerId === 'string' ? [payerId] : [];
      } else if (scope === 'custom') {
        const custom = stringArray(e.customSplitParticipants);
        recipients = custom.length > 0 ? custom : [...universe];
      } else {
        recipients = [...universe];
      }
      allocations = allocateEqual(amount, recipients, currency);
    }

    // Fold owed into this expense's currency bucket, dropping any recipient
    // outside the universe (the load-bearing drop: an out-of-universe
    // splitDistribution key never offsets the payer).
    for (const [uid, value] of allocations) {
      if (owedBucket.has(uid)) owedBucket.set(uid, owedBucket.get(uid)!.plus(value));
    }
  }

  for (const s of settlements) {
    const currency = currencyOf(s.currency);
    const adjBucket = bucketFor(adj, currency);
    const amount = fromSubunits(amountFilsOf(s), currency);
    const payerId = s.payerParticipantId;
    const recipientId = s.recipientParticipantId;
    if (typeof payerId === 'string' && adjBucket.has(payerId)) {
      adjBucket.set(payerId, adjBucket.get(payerId)!.plus(amount));
    }
    if (typeof recipientId === 'string' && adjBucket.has(recipientId)) {
      adjBucket.set(recipientId, adjBucket.get(recipientId)!.minus(amount));
    }
  }

  // Net per bucket. Bucket union = paid.keys ∪ adj.keys (owed.keys ⊆ paid.keys
  // since each expense seeds both) — mirrors calculateBalances:460-463. Each
  // bucket lists every universe uid (zeros included), mirroring :467-482.
  const allCurrencies = new Set<string>([...paid.keys(), ...adj.keys()]);
  const net = new Map<string, Map<string, Decimal>>();
  for (const currency of allCurrencies) {
    const paidBucket = paid.get(currency);
    const owedBucket = owed.get(currency);
    const adjBucket = adj.get(currency);
    const bucketNet = new Map<string, Decimal>();
    for (const uid of universe) {
      const p = paidBucket?.get(uid) ?? new Money(0);
      const o = owedBucket?.get(uid) ?? new Money(0);
      const a = adjBucket?.get(uid) ?? new Money(0);
      bucketNet.set(uid, p.plus(a).minus(o));
    }
    net.set(currency, bucketNet);
  }
  return net;
}

// Restore the flat-net key-set + no-money zero-rows the v1 aggregate doc and the
// gates expect (#382 PR-2). A no-money event still surfaces its participants as
// zeros (the pre-bucketing fold seeded the universe), but under bucketing there
// is no real currency to key those zeros — so when NO real currency exists we
// emit a single OMR bucket of seen-uid-zeros, and when real currencies DO exist
// we list every seen uid in each (zeros for the absent), mirroring the client
// `balances` build (group_balance_provider.dart:405-424). The fallback fires
// ONLY when there is no real currency, so it never inflates net.size for a group
// that holds money (which would falsely degrade the aggregate doc).
function finalizeNet(
  netByCurrency: Map<string, Map<string, Decimal>>,
  seenUids: Set<string>,
): Map<string, Map<string, Decimal>> {
  if (netByCurrency.size === 0) {
    if (seenUids.size === 0) return new Map();
    const zeros = new Map<string, Decimal>();
    for (const uid of seenUids) zeros.set(uid, new Money(0));
    return new Map([['OMR', zeros]]);
  }
  const out = new Map<string, Map<string, Decimal>>();
  for (const [currency, bucket] of netByCurrency) {
    const full = new Map<string, Decimal>();
    for (const uid of seenUids) full.set(uid, bucket.get(uid) ?? new Money(0));
    // Defensive: a bucket uid not in seenUids (should not happen — seenUids ⊇
    // every event universe ∪ group-settlement parties) is preserved.
    for (const [uid, value] of bucket) if (!full.has(uid)) full.set(uid, value);
    out.set(currency, full);
  }
  return out;
}

// Per-event drill-down: foldEventNet already seeds the drill universe per real
// bucket; a no-money event returns {} → emit the OMR zero-rows the v1 doc's
// perEventNetMilli expects (mirror _buildPerEventBreakdown's explicit zero rows,
// group_balance_provider.dart:500-505).
function bucketizeDrill(
  slice: Map<string, Map<string, Decimal>>,
  drillUniverse: Set<string>,
): Map<string, Map<string, Decimal>> {
  if (slice.size > 0) return slice;
  const zeros = new Map<string, Decimal>();
  for (const uid of drillUniverse) zeros.set(uid, new Money(0));
  return new Map([['OMR', zeros]]);
}

// Plain-object snapshot of every Firestore doc the oracle reads, so the pure
// computeNetFromSnapshot can run over it with ZERO I/O. This is what lets
// claimShadow SIMULATE a uuid→uid re-key in memory (apply the relabel to deep
// copies of these arrays, recompute the net) and assert it against the
// post-commit recompute (#278 PR7). Behavior-preserving split of recomputeNet —
// the same move that extracted foldEventNet (#366) and this whole module from
// deleteGroup (#190). `ref` is threaded so liveEventRefs survives.
export interface GroupBalanceSnapshot {
  groupExists: boolean;
  groupData: DocumentData;
  members: { docId: string; data: DocumentData }[];
  events: {
    id: string;
    ref: DocumentReference;
    data: DocumentData;
    expenses: DocumentData[];
    settlements: DocumentData[];
  }[];
  groupSettlements: DocumentData[];
}

// All Firestore reads, no compute. Fetches children for EVERY event (the
// soft-deleted / out-of-scope event filter is pure and lives in
// computeNetFromSnapshot), so a resumed #205 deleteGroup lock window never
// misses a child. Returns raw `.data()` — the per-doc isLiveDoc filter is the
// compute's job.
export async function loadGroupBalanceSnapshot(
  db: Firestore,
  groupRef: DocumentReference,
): Promise<GroupBalanceSnapshot> {
  const groupSnap = await groupRef.get();
  const membersSnap = await groupRef.collection('members').get();
  const eventsSnap = await groupRef.collection('events').get();
  const events = await Promise.all(
    eventsSnap.docs.map(async (eventDoc) => {
      const [expensesSnap, settlementsSnap] = await Promise.all([
        eventDoc.ref.collection('expenses').get(),
        eventDoc.ref.collection('settlements').get(),
      ]);
      return {
        id: eventDoc.id,
        ref: eventDoc.ref,
        data: eventDoc.data(),
        expenses: expensesSnap.docs.map((d) => d.data()),
        settlements: settlementsSnap.docs.map((d) => d.data()),
      };
    }),
  );
  const groupSettlementsSnap = await groupRef.collection('settlements').get();
  return {
    groupExists: groupSnap.exists,
    groupData: groupSnap.data() ?? {},
    members: membersSnap.docs.map((doc) => ({ docId: doc.id, data: doc.data() })),
    events,
    groupSettlements: groupSettlementsSnap.docs.map((d) => d.data()),
  };
}

// Pure net recompute over a snapshot — no I/O.
//
// ⚠️ The per-event universe construction below moves in LOCK-STEP with
// claimShadow.ts's Part-2 footprint pre-scan: every identity-bearing input here
// (participantIds, the financial payer/settlement set, the member-gated
// split-recipient keys) is a divisor-driving slot the pre-scan must reject the
// claimer from. Adding a NEW identity-bearing universe input here REQUIRES a new
// pre-scan term there, or the claimShadow divisor-collapse class reopens (#278).
export function computeNetFromSnapshot(snapshot: GroupBalanceSnapshot): RecomputeResult {
  const { groupData, members, events, groupSettlements } = snapshot;
  const includeSoftDeletedSinceMs =
    groupData.deletingInProgress === true ? timestampMillis(groupData.deleteLockedAt) : null;

  // liveMemberIds: a member is live unless explicitly tombstoned.
  // allMemberIds: every member doc (live OR tombstoned) — used to member-gate
  // the #249 split-recipient fold so a forged non-member key is never credited.
  const liveMemberIds = new Set<string>();
  const allMemberIds = new Set<string>();
  for (const member of members) {
    const data = member.data;
    if (typeof data.userId === 'string') {
      allMemberIds.add(data.userId);
      if (data.isTombstone !== true) liveMemberIds.add(data.userId);
    }
  }

  // #382 PR-2: per-currency net buckets. addNet routes a delta into (ccy, uid).
  const netByCurrency = new Map<string, Map<string, Decimal>>();
  const addNet = (currency: string, uid: string, delta: Decimal): void => {
    let bucket = netByCurrency.get(currency);
    if (bucket == null) {
      bucket = new Map<string, Decimal>();
      netByCurrency.set(currency, bucket);
    }
    bucket.set(uid, (bucket.get(uid) ?? new Money(0)).plus(delta));
  };
  // seenUids = the server analog of the client `allUids` (minus bare members):
  // ∪ event universes ∪ group-settlement parties. finalizeNet lists these in
  // each bucket so the flat v1-doc net key-set (incl. no-money zero rows) is
  // preserved (#382 PR-2).
  const seenUids = new Set<string>();
  const perEventNet = new Map<string, Map<string, Map<string, Decimal>>>();

  // Skip soft-deleted events wholesale (the client drops them at
  // event_provider.dart:42 — their live children must NOT enter the balance).
  // Exception: when resuming a #205 deleteGroup lock, include events already
  // soft-deleted after the lock was acquired so a partially flushed cascade can
  // be retried idempotently.
  const liveEvents = events.filter((ev) =>
    isEventInDeleteBalanceScope(ev.data, includeSoftDeletedSinceMs));

  for (const ev of liveEvents) {
    const eventData = ev.data;
    const participantIds = stringArray(eventData.participantIds);

    const expenses = ev.expenses.filter(isLiveDoc);
    const settlements = ev.settlements.filter(isLiveDoc);

    // Per-event universe = participantIds ∪ former financial actors. Mirrors
    // eventBalanceUniverse() in
    // lib/features/ledger/providers/expense_provider.dart (#249) — keep in
    // parity or this delete gate disagrees with the client ledger.
    //
    // Payers + settlement parties: folded whenever no longer live (NOT
    // member-gated — established behavior).
    const financial = new Set<string>();
    for (const e of expenses) {
      if (typeof e.payerParticipantId === 'string') financial.add(e.payerParticipantId);
    }
    for (const s of settlements) {
      if (typeof s.payerParticipantId === 'string') financial.add(s.payerParticipantId);
      if (typeof s.recipientParticipantId === 'string') {
        financial.add(s.recipientParticipantId);
      }
    }
    // Split recipients (splitDistribution keys for non-equally modes,
    // customSplitParticipants for custom scope) — folded ONLY if a known member
    // (live or tombstoned). Member-gating keeps a forged NON-member key out of
    // the universe so its owed is dropped (preserves the #192/#223 backstop and
    // this gate's forged-write rejection).
    const splitRecipientKeys = new Set<string>();
    for (const e of expenses) {
      const mode = decodeSplitMode(e.splitMode);
      if (
        mode != null &&
        mode !== 'equally' &&
        e.splitDistribution != null &&
        typeof e.splitDistribution === 'object'
      ) {
        for (const k of Object.keys(e.splitDistribution as Record<string, unknown>)) {
          splitRecipientKeys.add(k);
        }
      }
      if (e.scope === 'custom') {
        for (const uid of stringArray(e.customSplitParticipants)) {
          splitRecipientKeys.add(uid);
        }
      }
    }
    const universe = new Set<string>(participantIds);
    for (const uid of financial) {
      if (!liveMemberIds.has(uid)) universe.add(uid);
    }
    for (const uid of splitRecipientKeys) {
      if (allMemberIds.has(uid) && !liveMemberIds.has(uid)) universe.add(uid);
    }
    if (universe.size === 0) continue;

    // Record the full universe (incl. a no-money event's participants) so
    // finalizeNet reproduces today's flat-net key-set.
    for (const uid of universe) seenUids.add(uid);
    const eventNet = foldEventNet(expenses, settlements, universe);
    for (const [currency, bucket] of eventNet) {
      for (const [uid, delta] of bucket) addNet(currency, uid, delta);
    }

    // #366/#382: drill-down slice — same fold, participantIds-only universe, now
    // per-currency. Skip empty-participant events (the client skips
    // participants.isEmpty). A no-money event yields the OMR zero-rows
    // (bucketizeDrill), matching the client's explicit zero rows.
    const drillUniverse = new Set<string>(participantIds);
    if (drillUniverse.size > 0) {
      perEventNet.set(
        ev.id,
        bucketizeDrill(
          foldEventNet(expenses, settlements, drillUniverse),
          drillUniverse,
        ),
      );
    }
  }

  // Group-scope settlements fold into net globally (not bounded to any event
  // universe), each into its OWN per-doc currency bucket. Mirror the client
  // groupAdjByCurrency fold (group_balance_provider.dart:353-378).
  for (const s of groupSettlements) {
    if (!isLiveDoc(s)) continue;
    const currency = currencyOf(s.currency);
    const amount = fromSubunits(amountFilsOf(s), currency);
    const payerId = s.payerParticipantId;
    const recipientId = s.recipientParticipantId;
    if (typeof payerId === 'string') {
      seenUids.add(payerId);
      addNet(currency, payerId, amount);
    }
    if (typeof recipientId === 'string') {
      seenUids.add(recipientId);
      addNet(currency, recipientId, amount.negated());
    }
  }

  return {
    net: finalizeNet(netByCurrency, seenUids),
    liveEventRefs: liveEvents.map((ev) => ev.ref),
    perEventNet,
    eventCount: liveEvents.length,
  };
}

// Public entry point — exact HEAD signature preserved (5 callers + the Dart
// parity tests pin it). Loads the snapshot, then runs the pure compute.
export async function recomputeNet(
  db: Firestore,
  groupRef: DocumentReference,
): Promise<RecomputeResult> {
  return computeNetFromSnapshot(await loadGroupBalanceSnapshot(db, groupRef));
}
