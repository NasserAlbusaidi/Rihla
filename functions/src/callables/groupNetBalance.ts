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

// Weighted split (shares / percent): non-last recipients quantized; last
// absorbs the running remainder so sum(slices) == amount exactly.
function allocateWeighted(
  amount: Decimal,
  weights: Map<string, Decimal>,
  denominator: Decimal,
  currency: string,
): Map<string, Decimal> {
  const sorted = [...weights.keys()].sort();
  const out = new Map<string, Decimal>();
  let allocated = new Money(0);
  sorted.forEach((id, i) => {
    const isLast = i === sorted.length - 1;
    const allocation = isLast
      ? amount.minus(allocated)
      : quantize(amount.times(weights.get(id)!).div(denominator), currency);
    out.set(id, allocation);
    allocated = allocated.plus(allocation);
  });
  return out;
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
  net: Map<string, Decimal>;
  liveEventRefs: DocumentReference[];
  // #366: per-event drill-down slice for the balance-aggregate doc. Universe =
  // event.participantIds ONLY (no former financial actors, no member-gated
  // split-recipient fold) and group-scope settlements are NOT folded — this
  // mirrors the client _buildPerEventBreakdown
  // (lib/features/groups/providers/group_balance_provider.dart:432-471), which
  // is pinned participantIds-only by group_balance_provider_test.dart. Events
  // with empty participantIds are omitted. NON-DECOMPOSITION: net is NOT the
  // sum of these slices (different universes + group settlements + drops) —
  // never reconcile one from the other.
  perEventNet: Map<string, Map<string, Decimal>>;
  // #366: count of events in balance scope (strict isDeleted === false outside
  // a deleteGroup lock window), mirroring GroupBalances.eventCount.
  eventCount: number;
  // #261: the distinct set of EXPENSE currencies that actually contributed to
  // `net`. The flat scalar `net` is only a true settled-check when a group holds
  // ONE expense currency (Model A); two different EXPENSE currencies can net to a
  // fake Decimal 0 (+10 OMR / −10 USD), so the balance-zero gates (deleteGroup/
  // leaveGroup/removeMember) refuse when size > 1 rather than act on a
  // meaningless scalar.
  //
  // SCOPE — built from EXPENSES ONLY, NOT settlements. This is deliberate and
  // load-bearing, NOT an oversight: settlements are written OMR-scale even in a
  // non-OMR group by convention (settle_up_screen hardcodes 'OMR'), so a
  // legitimate single-expense-currency group routinely carries an OMR settlement
  // against a non-OMR debt — folding settlement currency would (a) falsely flag
  // that group as mixed (false-nonzero → a STUCK, undeletable group), (b) break
  // deleteGroup test 9, and (c) diverge from the client BalanceCalculator (which
  // has the SAME currency-blindness and shows that group as settled) — a parity
  // break. The residual gap this leaves — a non-OMR expense "settled" by an
  // incomparable OMR settlement — is the DEEPER expense-vs-settlement currency-
  // blindness that Model B (per-currency buckets) owns; it is unreachable for
  // app data under Model A (every write is OMR) and pre-exists this guard. Do
  // NOT "fix" it here by adding settlement currencies.
  currencies: Set<string>;
}

// One event's money fold: each universe member's event-scoped net
// (paid + settlementAdj − owed). Extracted (#366, behavior-preserving — the
// existing deleteGroup/leaveGroup/removeMember suites are the proof) so it runs
// twice per event: once with the FULL balance universe (participantIds ∪ former
// financial actors ∪ member-gated split recipients — feeds `net`) and once with
// the participantIds-only drill-down universe (feeds `perEventNet`). The fold
// itself is identical either way: payers/recipients outside the universe are
// dropped (`.has()` gates — the load-bearing drop), equal-split recipients
// default to the universe, and expense currencies are recorded into the
// function-scoped `currencies` set (Set.add is idempotent, so the double call
// per event cannot double-count).
function foldEventNet(
  expenses: DocumentData[],
  settlements: DocumentData[],
  universe: Set<string>,
  currencies: Set<string>,
): Map<string, Decimal> {
  const paid = new Map<string, Decimal>();
  const owed = new Map<string, Decimal>();
  const settlementAdj = new Map<string, Decimal>();
  for (const uid of universe) {
    paid.set(uid, new Money(0));
    owed.set(uid, new Money(0));
    settlementAdj.set(uid, new Money(0));
  }

  for (const e of expenses) {
    const currency = currencyOf(e.currency);
    // #261: normalize case — currencyOf returns the raw code, but the net math
    // (currencyScale) uppercases internally, so a legacy/Admin group mixing
    // 'omr' and 'OMR' decodes to a TRUE zero. Without toUpperCase the set would
    // be {'omr','OMR'} (size 2) and falsely brick a genuinely-settled group —
    // exactly the legacy/Admin population this guard exists to defend.
    currencies.add(currency.toUpperCase());
    const amount = fromSubunits(amountFilsOf(e), currency);
    const payerId = e.payerParticipantId;
    if (typeof payerId === 'string' && paid.has(payerId)) {
      paid.set(payerId, paid.get(payerId)!.plus(amount));
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

    // Fold owed, dropping any recipient outside the universe (the load-bearing
    // drop: an out-of-universe splitDistribution key never offsets the payer).
    for (const [uid, value] of allocations) {
      if (owed.has(uid)) owed.set(uid, owed.get(uid)!.plus(value));
    }
  }

  for (const s of settlements) {
    const currency = currencyOf(s.currency);
    const amount = fromSubunits(amountFilsOf(s), currency);
    const payerId = s.payerParticipantId;
    const recipientId = s.recipientParticipantId;
    if (typeof payerId === 'string' && settlementAdj.has(payerId)) {
      settlementAdj.set(payerId, settlementAdj.get(payerId)!.plus(amount));
    }
    if (typeof recipientId === 'string' && settlementAdj.has(recipientId)) {
      settlementAdj.set(recipientId, settlementAdj.get(recipientId)!.minus(amount));
    }
  }

  const net = new Map<string, Decimal>();
  for (const uid of universe) {
    net.set(uid, paid.get(uid)!.plus(settlementAdj.get(uid)!).minus(owed.get(uid)!));
  }
  return net;
}

export async function recomputeNet(
  db: Firestore,
  groupRef: DocumentReference,
): Promise<RecomputeResult> {
  const groupSnap = await groupRef.get();
  const groupData = groupSnap.data() ?? {};
  const includeSoftDeletedSinceMs =
    groupData.deletingInProgress === true ? timestampMillis(groupData.deleteLockedAt) : null;

  // liveMemberIds: a member is live unless explicitly tombstoned.
  // allMemberIds: every member doc (live OR tombstoned) — used to member-gate
  // the #249 split-recipient fold so a forged non-member key is never credited.
  const membersSnap = await groupRef.collection('members').get();
  const liveMemberIds = new Set<string>();
  const allMemberIds = new Set<string>();
  for (const member of membersSnap.docs) {
    const data = member.data();
    if (typeof data.userId === 'string') {
      allMemberIds.add(data.userId);
      if (data.isTombstone !== true) liveMemberIds.add(data.userId);
    }
  }

  const net = new Map<string, Decimal>();
  const addNet = (uid: string, delta: Decimal): void => {
    net.set(uid, (net.get(uid) ?? new Money(0)).plus(delta));
  };
  const perEventNet = new Map<string, Map<string, Decimal>>();

  // #261: function scope (NOT per-event) so cross-event currency mixing — an OMR
  // expense in e1 and a USD expense in e2 — is also detected. Expense fold only.
  const currencies = new Set<string>();

  // Skip soft-deleted events wholesale (the client drops them at
  // event_provider.dart:42 — their live children must NOT enter the balance).
  // Exception: when resuming a #205 deleteGroup lock, include events already
  // soft-deleted after the lock was acquired so a partially flushed cascade can
  // be retried idempotently.
  const eventsSnap = await groupRef.collection('events').get();
  const liveEventDocs = eventsSnap.docs.filter((doc) =>
    isEventInDeleteBalanceScope(doc.data(), includeSoftDeletedSinceMs));

  for (const eventDoc of liveEventDocs) {
    const eventData = eventDoc.data();
    const participantIds = stringArray(eventData.participantIds);

    const [expensesSnap, settlementsSnap] = await Promise.all([
      eventDoc.ref.collection('expenses').get(),
      eventDoc.ref.collection('settlements').get(),
    ]);
    const expenses = expensesSnap.docs.map((d) => d.data()).filter(isLiveDoc);
    const settlements = settlementsSnap.docs.map((d) => d.data()).filter(isLiveDoc);

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

    const eventNet = foldEventNet(expenses, settlements, universe, currencies);
    for (const [uid, delta] of eventNet) {
      addNet(uid, delta);
    }

    // #366: drill-down slice — same fold, participantIds-only universe. Skip
    // empty-participant events (the client skips participants.isEmpty).
    const drillUniverse = new Set<string>(participantIds);
    if (drillUniverse.size > 0) {
      perEventNet.set(
        eventDoc.id,
        foldEventNet(expenses, settlements, drillUniverse, currencies),
      );
    }
  }

  // Group-scope settlements fold into net globally (not bounded to any event
  // universe). Mirror group_balance_provider.dart:285-304.
  const groupSettlementsSnap = await groupRef.collection('settlements').get();
  for (const doc of groupSettlementsSnap.docs) {
    const s = doc.data();
    if (!isLiveDoc(s)) continue;
    const currency = currencyOf(s.currency);
    const amount = fromSubunits(amountFilsOf(s), currency);
    const payerId = s.payerParticipantId;
    const recipientId = s.recipientParticipantId;
    if (typeof payerId === 'string') addNet(payerId, amount);
    if (typeof recipientId === 'string') addNet(recipientId, amount.negated());
  }

  return {
    net,
    liveEventRefs: liveEventDocs.map((doc) => doc.ref),
    currencies,
    perEventNet,
    eventCount: liveEventDocs.length,
  };
}
