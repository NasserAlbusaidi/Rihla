import {
  DocumentData,
  DocumentReference,
  Firestore,
  Timestamp,
  WriteBatch,
  getFirestore,
} from 'firebase-admin/firestore';
import { logger } from 'firebase-functions/v2';
import { CallableRequest, HttpsError, onCall } from 'firebase-functions/v2/https';
import Decimal from 'decimal.js';
import '../admin';

// #190: server-authoritative group deletion. The callable recomputes per-actor
// net balances EXACTLY as the client BalanceCalculator (per-doc currency decode,
// the percent /1000 split decode, the per-event former-actor universe, strict
// `isDeleted === false`), refuses with FAILED_PRECONDITION on any non-zero net,
// then SOFT-deletes the group + its events (keeping the append-only
// expense/settlement records reachable for the audit trail). The group doc is
// UPDATED (isDeleted:true), never destroyed — the direct client delete path is
// locked in firestore.rules (`allow delete: if false;`).

// Isolated Decimal constructor (clone, NOT the global) so this module's rounding
// config never leaks to any other function that imports decimal.js. ROUND_DOWN =
// truncate toward zero, mirroring Dart's `Rational.truncate()` / `BigInt`
// conversion used throughout MoneySerializer + BalanceCalculator; high precision
// so division never rounds before the explicit subunit quantization.
const Money = Decimal.clone({ precision: 50, rounding: Decimal.ROUND_DOWN });

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
  const total = sumValues(distribution);
  if (total.minus(amount).abs().gt(SPLIT_TOLERANCE)) {
    return allocateEqual(amount, distribution.keys(), currency);
  }
  return new Map(distribution);
}

function allocatePercent(
  amount: Decimal,
  distribution: Map<string, Decimal>,
  currency: string,
): Map<string, Decimal> {
  const total = sumValues(distribution);
  if (total.minus(HUNDRED).abs().gt(SPLIT_TOLERANCE)) {
    return allocateEqual(amount, distribution.keys(), currency);
  }
  return allocateWeighted(amount, distribution, HUNDRED, currency);
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

function stringArray(value: unknown): string[] {
  return Array.isArray(value) ? value.filter((v): v is string => typeof v === 'string') : [];
}

interface RecomputeResult {
  net: Map<string, Decimal>;
  liveEventRefs: DocumentReference[];
}

async function recomputeNet(
  db: Firestore,
  groupRef: DocumentReference,
): Promise<RecomputeResult> {
  // liveMemberIds: a member is live unless explicitly tombstoned.
  const membersSnap = await groupRef.collection('members').get();
  const liveMemberIds = new Set<string>();
  for (const member of membersSnap.docs) {
    const data = member.data();
    if (data.isTombstone !== true && typeof data.userId === 'string') {
      liveMemberIds.add(data.userId);
    }
  }

  const net = new Map<string, Decimal>();
  const addNet = (uid: string, delta: Decimal): void => {
    net.set(uid, (net.get(uid) ?? new Money(0)).plus(delta));
  };

  // Skip soft-deleted events wholesale (the client drops them at
  // event_provider.dart:42 — their live children must NOT enter the balance).
  const eventsSnap = await groupRef.collection('events').get();
  const liveEventDocs = eventsSnap.docs.filter((doc) => isLiveDoc(doc.data()));

  for (const eventDoc of liveEventDocs) {
    const eventData = eventDoc.data();
    const participantIds = stringArray(eventData.participantIds);

    const [expensesSnap, settlementsSnap] = await Promise.all([
      eventDoc.ref.collection('expenses').get(),
      eventDoc.ref.collection('settlements').get(),
    ]);
    const expenses = expensesSnap.docs.map((d) => d.data()).filter(isLiveDoc);
    const settlements = settlementsSnap.docs.map((d) => d.data()).filter(isLiveDoc);

    // Per-event universe = participantIds ∪ former financial actors
    // (payer/settlement uids no longer in liveMemberIds). Mirrors
    // group_balance_provider.dart:225-241.
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
    const universe = new Set<string>(participantIds);
    for (const uid of financial) {
      if (!liveMemberIds.has(uid)) universe.add(uid);
    }
    if (universe.size === 0) continue;

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

    for (const uid of universe) {
      const delta = paid.get(uid)!.plus(settlementAdj.get(uid)!).minus(owed.get(uid)!);
      addNet(uid, delta);
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

  return { net, liveEventRefs: liveEventDocs.map((doc) => doc.ref) };
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
    const groupSnap = await groupRef.get();
    if (!groupSnap.exists) {
      throw new HttpsError('not-found', 'Group not found.');
    }
    const groupData = groupSnap.data() ?? {};

    // Idempotent no-op: re-deleting an already-soft-deleted group is success.
    if (groupData.isDeleted === true) {
      return { groupId, mode: 'softDelete', eventsSoftDeleted: 0, alreadyDeleted: true };
    }

    if (groupData.createdBy !== uid) {
      throw new HttpsError('permission-denied', 'Only the group creator can delete the group.');
    }

    // Throttle before the (potentially large) balance recompute so replays are
    // bounded.
    await enforceDeleteGroupRateLimit(db, uid);

    const { net, liveEventRefs } = await recomputeNet(db, groupRef);
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
    const now = Timestamp.now();
    const writer = new BatchWriter(db);
    for (const eventRef of liveEventRefs) {
      await writer.update(eventRef, { isDeleted: true, deletedAt: now, updatedAt: now });
    }
    await writer.update(groupRef, { isDeleted: true, deletedAt: now, updatedAt: now });
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
  },
);
