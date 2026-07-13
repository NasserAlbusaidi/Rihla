import 'package:decimal/decimal.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

import '../../../core/constants/supported_currencies.dart';
import '../../../core/models/split_mode.dart';
import '../../../core/services/firebase_functions_service.dart';
import '../../../core/services/money_serializer.dart';
import '../../../core/types/event_ref.dart';
import '../../events/models/event_model.dart';
import '../../trip/models/trip_model.dart';
import '../models/expense_model.dart';
import '../models/settlement_model.dart';
import '../models/split_explanation.dart';
import '../services/expense_service.dart';
import '../services/settlement_service.dart';

export '../../../core/types/event_ref.dart'; // re-export so existing importers still work

// ---------------------------------------------------------------------------
// Loading / error state providers (kept for backward compat with screens)
// ---------------------------------------------------------------------------

/// Loading state for expense operations
final expenseLoadingProvider = StateProvider<bool>((ref) => false);

/// Liveness lever for the one-shot home balance aggregation (#104).
///
/// The home dashboard reads per-event expenses/settlements ONE-SHOT (no live
/// listener), so an event-level money write is invisible to the home aggregate
/// (`groupBalancesOnceProvider`) until this revision bumps. The four event-level
/// write callsites bump it after a successful write: add / update / soft-delete
/// expense, and add event settlement.
///
/// Group-level settlements need NO bump — `groupBalancesOnceProvider` watches the
/// LIVE `groupSettlementsProvider`, which surfaces them itself.
///
/// ⚠️ Any NEW event-level expense/settlement write path must bump this, or the
/// home balance silently goes stale (money-wrong for the settle-up screen).
/// See docs/plans/perf-home-balance-104/spec.md §5 Phase 3.
final ledgerRevisionProvider = StateProvider<int>((ref) => 0);

// ---------------------------------------------------------------------------
// Service providers (NEW Firestore-backed services)
// ---------------------------------------------------------------------------

/// Provider for the Firestore-backed [ExpenseService].
final expenseServiceProvider = Provider<ExpenseService>(
  (ref) => ExpenseService(),
);

/// Provider for [SettlementService] — Firestore-backed reads; the CREATE
/// routes through the injected `recordSettlement` callable (#1129).
final settlementServiceProvider = Provider<SettlementService>(
  (ref) => SettlementService(
    functionsService: ref.read(firebaseFunctionsServiceProvider),
  ),
);

// ---------------------------------------------------------------------------
// NEW: Firestore-backed stream providers using EventRef (D-15, RESEARCH.md Pattern 4)
// ---------------------------------------------------------------------------

/// Firestore-backed expense stream using [EventRef] as the family parameter.
///
/// Reads come straight from the Firestore `.snapshots()` stream; the Firestore
/// SDK serves them from its own offline cache with no network (persistence is
/// enabled in `firebase_config.dart`). [BalanceCalculator] consumes this stream
/// directly — the local SQLite cache was removed in issue #50.
final eventExpensesProvider =
    StreamProvider.family<List<Expense>, EventRef>((ref, eventRef) {
  final service = ref.read(expenseServiceProvider);
  return service.watchExpenses(eventRef.groupId, eventRef.eventId);
});

/// Firestore-backed settlement stream using [EventRef] as the family parameter.
///
/// Same Firestore-offline-backed read path as [eventExpensesProvider] (#50).
final eventSettlementsProvider =
    StreamProvider.family<List<Settlement>, EventRef>((ref, eventRef) {
  final service = ref.read(settlementServiceProvider);
  return service.watchSettlements(eventRef.groupId, eventRef.eventId);
});

// ---------------------------------------------------------------------------
// Per-event balance universe (#249)
// ---------------------------------------------------------------------------

/// The set of UIDs that must be passed as `participants` to
/// [BalanceCalculator.calculateBalances] for ONE event so that no owed share is
/// silently dropped: the current `event.participantIds` plus any FORMER GROUP
/// MEMBER (∉ [liveMemberIds]) who appears in this event's money records.
///
/// - **Payers and settlement parties** are folded whenever they are no longer
///   live (NOT member-gated — established behavior; mirrors
///   `deleteGroup.ts` `recomputeNet` and the former-payer regression test).
/// - **Split recipients** (`splitDistribution` keys for shares/exact/percent,
///   `customSplitParticipants` for `custom` scope) are folded ONLY when the key
///   is a known group member (live or tombstoned — i.e. in [allMemberIds]).
///   This member-gate keeps a forged / rules-bypassing NON-member key OUT of
///   the universe so [BalanceCalculator]'s drop-guard still fires on it,
///   preserving the #192/#223 server backstop and the `deleteGroup` forged-
///   write rejection (test 12). A rules-compliant write can only reference a
///   key that was a participant at write time, so a real orphan is always a
///   departed (tombstoned) member.
///
/// Pure: no `ref`/provider reads. Callers supply [allMemberIds] (every member
/// doc, live or tombstoned) and [liveMemberIds] (members where `!isTombstone`).
Set<String> eventBalanceUniverse({
  required Event event,
  required List<Expense> expenses,
  required List<Settlement> settlements,
  required Set<String> allMemberIds,
  required Set<String> liveMemberIds,
}) {
  final payersAndSettlers = <String>{
    // #928: the total-parse factory salvages a non-string expense payer to ''.
    // The oracle gates the payer with `typeof === 'string'` before the universe
    // fold (groupNetBalance.ts:651), so guard the '' sentinel out here too — an
    // ungated '' would seed a phantom row and inflate the equal-split divisor,
    // diverging from the server. Settlement parties are nullable (salvaged to
    // null) and already null-gated below, matching the oracle's typeof gates.
    for (final e in expenses)
      if (e.payerParticipantId.isNotEmpty) e.payerParticipantId,
    for (final s in settlements) ...[
      if (s.payerParticipantId != null) s.payerParticipantId!,
      if (s.recipientParticipantId != null) s.recipientParticipantId!,
    ],
  };

  final splitRecipientKeys = <String>{};
  for (final e in expenses) {
    final mode = e.splitMode;
    final dist = e.splitDistribution;
    if (mode != null &&
        mode != SplitMode.equally &&
        dist != null &&
        dist.isNotEmpty) {
      splitRecipientKeys.addAll(dist.keys);
    }
    if (e.scope == ExpenseScope.custom &&
        e.customSplitParticipants != null &&
        e.customSplitParticipants!.isNotEmpty) {
      splitRecipientKeys.addAll(e.customSplitParticipants!);
    }
  }

  final formerActors = <String>{
    ...payersAndSettlers.difference(liveMemberIds),
    ...splitRecipientKeys.intersection(allMemberIds).difference(liveMemberIds),
  };

  return <String>{...event.participantIds, ...formerActors};
}

// ---------------------------------------------------------------------------
// Balance calculation engine (pure function -- in-memory)
// ---------------------------------------------------------------------------

/// Balance calculation engine
/// Why a non-equal split allocation fell back to an equal split. Each value maps
/// to exactly one guard in [BalanceCalculator]'s allocators. Reported through
/// [BalanceCalculator.onSplitFallback] (#250) so a malformed `splitDistribution`
/// that reaches the calculator anyway — a forged / legacy / Admin-SDK write that
/// bypassed the add/edit UI guard (PR #253) — is observable. There is no user to
/// warn on those paths; server-side value validation (#192) is the complement.
enum SplitFallbackReason {
  /// `shares`: a negative weight (would emit a negative owed via _allocateWeighted).
  negativeShares,

  /// `shares`: total of all weights is <= 0 (cannot normalize).
  invalidShares,

  /// `exact`: a negative absolute amount (cannot owe a negative share).
  negativeExact,

  /// `exact`: the entries' sum drifts past the tolerance from the expense amount.
  exactAmountDrift,

  /// `exact`: an in-tolerance residual no recipient can absorb without going
  /// negative (reachable only via a forged sub-precision write).
  exactResidualUnabsorbable,

  /// `percent`: a negative percentage.
  negativePercent,

  /// `percent`: the percentages' sum drifts past the tolerance from 100.
  percentDrift,
}

class BalanceCalculator {
  static final Decimal _splitTolerance = Decimal.parse('0.001');
  static final Decimal _hundred = Decimal.fromInt(100);

  /// Test-only invocation counter (#106). Lets a widget test prove a category
  /// chip tap no longer re-enters [calculateBalances] — the filter-independent
  /// balance work is now memoized in `ledgerViewProvider`. Reset it in test
  /// setUp; production never reads it. Same library, so the `@visibleForTesting`
  /// write below is legal.
  @visibleForTesting
  static int debugCalculateBalancesCount = 0;

  /// Test-only invocation counter (#629). Lets a widget test prove a category
  /// chip tap (or a scroll) no longer re-runs [allocateExpenseOwed] per visible
  /// non-equal-split row — the per-expense owed allocation is now memoized once
  /// in `ledgerViewProvider` and the row is a map lookup. Reset it in test setUp;
  /// production never reads it.
  @visibleForTesting
  static int debugAllocateExpenseOwedCount = 0;

  /// Telemetry sink for split-allocation fallbacks (#250). Defaults to a
  /// PII-free Sentry warning ([_reportSplitFallbackToSentry]); overridable in
  /// tests to assert the calculator never silently swallows a malformed split.
  /// Keeping the SDK call behind this seam leaves the pure money oracle (mirrored
  /// byte-for-byte by the TS `deleteGroup` gate) decoupled from `sentry_flutter`.
  static void Function(SplitFallbackReason reason, Expense expense)
  onSplitFallback = _reportSplitFallbackToSentry;

  static void _reportSplitFallbackToSentry(
    SplitFallbackReason reason,
    Expense expense,
  ) {
    // Local dev console (unchanged from the pre-#250 debugPrint behaviour).
    debugPrint(
      'Split fallback (${reason.name}) for expense ${expense.id}; '
      'falling back to equal split.',
    );
    // Production telemetry. PII-free: only the doc id, the reason, and the split
    // mode — never names or amounts.
    Sentry.captureMessage(
      'ledger.split_fallback',
      level: SentryLevel.warning,
      withScope: (scope) {
        scope.setContexts('split_fallback', <String, dynamic>{
          'reason': reason.name,
          'expenseId': expense.id,
          'splitMode': expense.splitMode?.name ?? 'unknown',
        });
      },
    );
  }

  /// Calculate balances with proper scope handling, bucketed per currency
  /// (#382 PR-1 — amounts in different currencies are NEVER summed; there is
  /// no FX).
  ///
  /// - Global: Split among all participants
  /// - Personal: Only the payer is responsible (no split)
  /// - Custom: Split among the listed participants
  ///
  /// Legacy `subGroup` scope (logistics feature, removed in Phase 39) falls
  /// back to global behaviour for back-compat with persisted Firestore docs.
  ///
  /// Bucket keys are the fence-validated currencies appearing in the money
  /// records (unsupported → OMR, the #47 fence — the same value that drives
  /// allocation precision, so a bucket's key can never disagree with its
  /// scale). Every bucket lists EVERY participant in [participants] order,
  /// zeros included, so a single-currency input's sole bucket is
  /// element-for-element the pre-#382 flat result. No money records → `{}`.
  static Map<String, List<UserBalance>> calculateBalances({
    required List<Expense> expenses,
    required List<Participant> participants,
    List<Settlement> settlements = const [],
  }) {
    debugCalculateBalancesCount++;
    if (participants.isEmpty) return {};

    // currency -> participantId -> amount. Each bucket is pre-seeded with
    // every participant at zero so the containsKey membership gate below
    // keeps dropping keys outside the universe (the #192/#223 drop-guard —
    // the parity contract with the TS oracle).
    final paidByCurrency = <String, Map<String, Decimal>>{};
    final owedByCurrency = <String, Map<String, Decimal>>{};
    final adjByCurrency = <String, Map<String, Decimal>>{};

    Map<String, Decimal> bucketFor(
      Map<String, Map<String, Decimal>> maps,
      String currency,
    ) {
      return maps.putIfAbsent(
        currency,
        () => {for (var p in participants) p.id: Decimal.zero},
      );
    }

    // Process each expense
    for (final expense in expenses) {
      final payerId = expense.payerParticipantId;

      // Quantize allocations to this expense's own currency precision.
      // Unknown/garbage currency (untrusted Firestore data) falls back to OMR
      // so calculateBalances never throws (Issue #47).
      final currency = MoneySerializer.isSupported(expense.currency)
          ? expense.currency
          : 'OMR';
      final paidMap = bucketFor(paidByCurrency, currency);
      final owedMap = bucketFor(owedByCurrency, currency);

      // Track what payer paid
      if (paidMap.containsKey(payerId)) {
        paidMap[payerId] = paidMap[payerId]! + expense.amount;
      }

      // Per-expense owed allocation. The pure, side-effect-free
      // [allocateExpenseOwed] is the single source of this math — the expense
      // editor's split preview (#242) calls the SAME function so the displayed
      // per-person amounts are byte-for-byte what gets accumulated here (true
      // WYSIWYG). The static [onSplitFallback] telemetry hook is re-attached
      // via the closure below; the preview passes `onFallback: null` to stay
      // silent on transient/edit states.
      final owed = allocateExpenseOwed(
        amount: expense.amount,
        splitMode: expense.splitMode,
        splitDistribution: expense.splitDistribution,
        scope: expense.scope,
        customSplitParticipants: expense.customSplitParticipants,
        payerId: payerId,
        participantIds: participants.map((p) => p.id),
        currency: currency,
        onFallback: (reason) => onSplitFallback(reason, expense),
      );

      // Accumulate, dropping owed for any key outside the seeded participant
      // universe (the #192/#223 parity drop-guard — unchanged).
      for (final entry in owed.entries) {
        if (owedMap.containsKey(entry.key)) {
          owedMap[entry.key] = owedMap[entry.key]! + entry.value;
        }
      }
    }

    // Apply settlement adjustments — each settlement adjusts ONLY its own
    // currency's bucket (per-doc currency, fenced like expenses; #382 PR-1).
    // A settlement in a currency with no expense activity still creates that
    // bucket: it is real money flow.
    for (final s in settlements) {
      final currency = MoneySerializer.isSupported(s.currency)
          ? s.currency
          : 'OMR';
      final adjMap = bucketFor(adjByCurrency, currency);
      if (s.payerParticipantId != null &&
          adjMap.containsKey(s.payerParticipantId)) {
        adjMap[s.payerParticipantId!] =
            adjMap[s.payerParticipantId!]! + s.amount;
      }
      if (s.recipientParticipantId != null &&
          adjMap.containsKey(s.recipientParticipantId)) {
        adjMap[s.recipientParticipantId!] =
            adjMap[s.recipientParticipantId!]! - s.amount;
      }
    }

    // Build final balances per bucket. Expense processing seeds paid+owed
    // buckets together, so the union below is paid ∪ adj keys.
    final allCurrencies = <String>{
      ...paidByCurrency.keys,
      ...adjByCurrency.keys,
    };

    return {
      for (final currency in allCurrencies)
        currency: participants.map((p) {
          final totalPaid = paidByCurrency[currency]?[p.id] ?? Decimal.zero;
          final totalOwed = owedByCurrency[currency]?[p.id] ?? Decimal.zero;
          final settlementAdj = adjByCurrency[currency]?[p.id] ?? Decimal.zero;

          // Net = (what they paid + settlements given) - what they owe
          final netBalance = (totalPaid + settlementAdj) - totalOwed;

          return UserBalance(
            participantId: p.id,
            displayName: p.displayName ?? 'Unknown',
            totalPaid: totalPaid,
            totalOwed: totalOwed,
            netBalance: netBalance,
          );
        }).toList(),
    };
  }

  /// Pure, side-effect-free owed allocation for ONE expense (#242). Returns
  /// owed-by-participantId, byte-for-byte identical to what [calculateBalances]
  /// accumulates for this expense BEFORE the participant-universe drop-guard.
  /// The expense-editor split preview calls this so the displayed per-person
  /// amounts are exactly what gets persisted.
  ///
  /// Two paths, mirroring [calculateBalances]:
  ///  - **mode-allocator**: a non-equal [splitMode] with a non-empty
  ///    [splitDistribution] allocates over the distribution keys (scope ignored).
  ///  - **scope/equal**: otherwise (null/equally) — an equal per-head split over
  ///    the scope-derived recipient SET (remainder → alphabetically-last id).
  ///
  /// [currency] is fenced internally (isSupported ? : 'OMR') so a caller can
  /// never throw [MoneySerializer] on an unsupported code (the preview passes a
  /// user-picked currency; [calculateBalances] already fences upstream — keep
  /// that outer fence, it also selects the per-currency bucket). [onFallback] is
  /// invoked when a malformed split falls back to equal — pass `null` (the
  /// preview path) to suppress the Sentry telemetry the [calculateBalances]
  /// closure `(r) => onSplitFallback(r, expense)` would otherwise emit.
  static Map<String, Decimal> allocateExpenseOwed({
    required Decimal amount,
    required SplitMode? splitMode,
    required Map<String, Decimal>? splitDistribution,
    required ExpenseScope scope,
    required List<String>? customSplitParticipants,
    required String payerId,
    required Iterable<String> participantIds,
    required String currency,
    void Function(SplitFallbackReason reason)? onFallback,
  }) {
    debugAllocateExpenseOwedCount++;
    final fenced = MoneySerializer.isSupported(currency) ? currency : 'OMR';

    if (splitMode != null &&
        splitMode != SplitMode.equally &&
        splitDistribution != null &&
        splitDistribution.isNotEmpty) {
      return switch (splitMode) {
        SplitMode.shares =>
          _allocateShares(amount, splitDistribution, fenced, onFallback),
        SplitMode.exact =>
          _allocateExact(amount, splitDistribution, fenced, onFallback),
        SplitMode.percent =>
          _allocatePercent(amount, splitDistribution, fenced, onFallback),
        SplitMode.equally => const <String, Decimal>{}, // gated out above
      };
    }

    // Scope/equal path. Build the recipient SET (deduped) per scope, then run
    // the shared equal split. The `.toSet()` is load-bearing: a duplicate id in
    // the customSplitParticipants `List` must NOT over-divide the per-head cost
    // (parity with calculateBalances, which also `.toSet()`s — #242 Gate P2a).
    final Set<String> recipients;
    switch (scope) {
      case ExpenseScope.personal:
        recipients = {payerId};
      case ExpenseScope.subGroup:
        // Legacy logistics scope (Phase 39) — back-compat fallback to global.
        recipients = participantIds.toSet();
      case ExpenseScope.custom:
        recipients =
            (customSplitParticipants != null &&
                customSplitParticipants.isNotEmpty)
            ? customSplitParticipants.toSet()
            : participantIds.toSet();
      case ExpenseScope.global:
        recipients = participantIds.toSet();
    }
    return _allocateEqual(amount, recipients, fenced);
  }

  /// Pure itemized → exact-distribution producer (#203 Slice 1). Each
  /// [SplitItem.amountFils] (integer-subunit LINE TOTAL) is split equally among
  /// its [SplitItem.participantIds]; the per-item integer remainder lands on the
  /// alphabetically-last assignee (the project-wide remainder contract). Owed
  /// accumulates across items.
  ///
  /// Returns the `SplitMode.exact` splitDistribution to persist:
  ///  - Σ(values) == Σ(item amountFils) exactly (conservation), and
  ///  - every value is a whole number of subunits (#596 — keeps netBalance
  ///    whole-subunit so client↔server oracle parity + the settle-up cap hold).
  ///
  /// This is a WRITE-TIME producer, NOT part of the read-time oracle surface:
  /// the persisted artifact is a standard exact split that `recomputeNet` /
  /// [_allocateExact] already decode, so there is no server mirror to keep in
  /// lockstep (itemized reduces to `exact` at persistence).
  ///
  /// Preconditions — ENFORCED here (throws [ArgumentError]), so this producer
  /// can never emit a negative owed or a non-conserving distribution:
  ///  - non-negative [SplitItem.amountFils] (a negative price is invalid input;
  ///    the Slice 2 editor validates pre-call, `firestore.rules`
  ///    `splitValuesNonNegative` is the write backstop, [_allocateExact] guards
  ///    forged docs on read).
  ///  - ≥1 assignee per item — every item's cost must land somewhere, else
  ///    `Σ distribution < Σ items` and the exact read-back would drift into the
  ///    tolerance fallback and silently discard the itemization.
  static Map<String, Decimal> allocateItemizedDistribution({
    required List<SplitItem> items,
    required String currency,
    List<SplitAdjustment> adjustments = const [],
    List<String> participantIds = const [],
  }) {
    final fenced = MoneySerializer.isSupported(currency) ? currency : 'OMR';
    final owedSubunits = <String, int>{};

    // ── Phase 1 — items: each item's cost split equally among its assignees ──
    for (final item in items) {
      if (item.amountFils < 0) {
        throw ArgumentError.value(
          item.amountFils,
          'amountFils',
          'itemized item "${item.label}" is negative',
        );
      }
      final assignees = item.participantIds.toSet().toList()..sort();
      if (assignees.isEmpty) {
        throw ArgumentError.value(
          item.participantIds,
          'participantIds',
          'itemized item "${item.label}" has no assignees',
        );
      }
      final n = assignees.length;
      final base = item.amountFils ~/ n;
      final remainder = item.amountFils - base * n;
      for (var i = 0; i < n; i++) {
        final share = base + (i == n - 1 ? remainder : 0);
        owedSubunits[assignees[i]] = (owedSubunits[assignees[i]] ?? 0) + share;
      }
    }

    // No adjustments ⇒ byte-identical to #203 (participantIds untouched).
    if (adjustments.isEmpty) {
      return {
        for (final entry in owedSubunits.entries)
          entry.key: MoneySerializer.fromSubunits(entry.value, fenced),
      };
    }

    // #605 — bill-level adjustments fold into the same exact distribution.
    // 'equal' adjustments (and the empty-weight proportional fallback) spread
    // over the WHOLE table, so the caller MUST pass it (reuse-safety).
    final equalBase = participantIds.toSet().toList()..sort();
    if (equalBase.isEmpty) {
      throw ArgumentError.value(
        participantIds,
        'participantIds',
        'itemized adjustments require the full participant list',
      );
    }

    // Per-person item subtotal — the weights for a 'proportional' additive.
    final itemSubtotal = Map<String, int>.from(owedSubunits);

    // ── Phase 2 — additive adjustments (service / tax / tip): each ADDS ──
    for (final adj in adjustments) {
      if (adj.type == 'discount') continue;
      _validateAdjustment(adj);
      final shares = adj.allocation == 'proportional'
          ? _spreadProportional(adj.amountFils, itemSubtotal, equalBase)
          : _spreadEqual(adj.amountFils, equalBase);
      shares.forEach((k, v) => owedSubunits[k] = (owedSubunits[k] ?? 0) + v);
    }

    // ── Phase 3 — discounts: SUBTRACT by re-allocating the REMAINING bill
    // proportional to each person's pre-discount owed. A discount's own
    // `allocation` is intentionally ignored — proportional-to-pre-discount is
    // what provably keeps every owed ≥ 0. It does NOT bound owed at
    // pre-discount: `_spreadProportional` truncates each non-last share and
    // dumps the lost subunits (up to n-1) onto the alphabetically-last
    // positive-weight key, which can land up to n-1 subunits ABOVE its
    // pre-discount owed (#1203). Accepted — a bounded, conservation-safe
    // consequence of the remainder contract, not a bug. ──
    var totalDiscount = 0;
    for (final adj in adjustments) {
      if (adj.type != 'discount') continue;
      _validateAdjustment(adj);
      totalDiscount += adj.amountFils;
    }
    if (totalDiscount > 0) {
      final preDiscount = Map<String, int>.from(owedSubunits);
      final preTotal = preDiscount.values.fold(0, (s, v) => s + v);
      final remaining = preTotal - totalDiscount;
      if (remaining < 0) {
        throw ArgumentError.value(
          totalDiscount,
          'discount',
          'discount $totalDiscount exceeds pre-discount owed $preTotal',
        );
      }
      final reallocated = _spreadProportional(remaining, preDiscount, equalBase);
      owedSubunits
        ..clear()
        ..addAll(reallocated);
    }

    return {
      for (final entry in owedSubunits.entries)
        entry.key: MoneySerializer.fromSubunits(entry.value, fenced),
    };
  }

  /// Strict validation for a #605 adjustment fed to the producer: known [type]
  /// and non-negative [SplitAdjustment.amountFils]. Mirrors the item guards so a
  /// forged/legacy doc displays (lenient `fromMap`) but cannot resave a bad fold.
  static void _validateAdjustment(SplitAdjustment adj) {
    if (!kAdjustmentTypes.contains(adj.type)) {
      throw ArgumentError.value(adj.type, 'type', 'unknown adjustment type');
    }
    if (adj.amountFils < 0) {
      throw ArgumentError.value(
        adj.amountFils,
        'amountFils',
        'adjustment "${adj.type}" is negative',
      );
    }
  }

  /// Spread [amount] subunits equally across [baseSorted]; the integer remainder
  /// lands on the alphabetically-last key (the project remainder contract).
  static Map<String, int> _spreadEqual(int amount, List<String> baseSorted) {
    final n = baseSorted.length;
    if (n == 0) return {};
    final base = amount ~/ n;
    final remainder = amount - base * n;
    return {
      for (var i = 0; i < n; i++)
        baseSorted[i]: base + (i == n - 1 ? remainder : 0),
    };
  }

  /// Spread [amount] subunits proportional to [weights]; the remainder lands on
  /// the alphabetically-last POSITIVE-weight key (distinct from, but compatible
  /// with, the whole-table-last contract — never a zero-weight key). When NO key
  /// has positive weight, fall back to an equal spread over [fallbackBase] (the
  /// whole table) so the amount is never silently dropped (conservation).
  ///
  /// The per-key `amount * weight` product is computed via a [BigInt] intermediate
  /// (#1206): both factors can reach ~3.1e9 subunits, whose native int64 product
  /// (~1.9e19) overflows and silently wraps to a mis-proportioned share; `weight ≤
  /// total` keeps the quotient `≤ amount < 2^63`, so `.toInt()` is exact.
  static Map<String, int> _spreadProportional(
    int amount,
    Map<String, int> weights,
    List<String> fallbackBase,
  ) {
    final keys = [
      for (final e in weights.entries)
        if (e.value > 0) e.key,
    ]..sort();
    if (keys.isEmpty) return _spreadEqual(amount, fallbackBase);
    final total = keys.fold(0, (s, k) => s + weights[k]!);
    if (total == 0) return _spreadEqual(amount, fallbackBase);
    final out = <String, int>{};
    var used = 0;
    for (final k in keys) {
      final share =
          ((BigInt.from(amount) * BigInt.from(weights[k]!)) ~/ BigInt.from(total))
              .toInt();
      out[k] = share;
      used += share;
    }
    out[keys.last] = out[keys.last]! + (amount - used);
    return out;
  }

  static Map<String, Decimal> _allocateShares(
    Decimal amount,
    Map<String, Decimal> distribution,
    String currency,
    void Function(SplitFallbackReason reason)? onFallback,
  ) {
    // A negative share is never a valid weight — it would hand that recipient a
    // negative owed via _allocateWeighted, breaking the non-negative-owed
    // invariant. The custom split sheet strips minus signs, but firestore.rules
    // only checks `splitDistribution is map`, so a forged/legacy write can
    // persist one. Mirror the _allocateExact guard. Server-side value
    // validation is the complementary fix (#192).
    if (distribution.values.any((value) => value < Decimal.zero)) {
      onFallback?.call(SplitFallbackReason.negativeShares);
      return _allocateEqual(amount, distribution.keys, currency);
    }

    final totalShares = distribution.values.fold(
      Decimal.zero,
      (sum, value) => sum + value,
    );

    if (totalShares <= Decimal.zero) {
      onFallback?.call(SplitFallbackReason.invalidShares);
      return _allocateEqual(amount, distribution.keys, currency);
    }

    return _allocateWeighted(
      amount,
      distribution,
      totalShares,
      currency,
    );
  }

  static Map<String, Decimal> _allocateExact(
    Decimal amount,
    Map<String, Decimal> distribution,
    String currency,
    void Function(SplitFallbackReason reason)? onFallback,
  ) {
    // A negative exact entry is never a valid split — you cannot owe a negative
    // share. The custom split sheet strips minus signs, but firestore.rules
    // only checks `splitDistribution is map` (not its sign) and the service
    // encodes values verbatim, so a forged/unvalidated write can persist one.
    // Treat it as an invalid exact split (equal-split fallback) rather than let
    // it (or the residual close-out below) emit a negative owed. Server-side
    // value validation is the complementary fix tracked in #192.
    if (distribution.values.any((value) => value < Decimal.zero)) {
      onFallback?.call(SplitFallbackReason.negativeExact);
      return _allocateEqual(amount, distribution.keys, currency);
    }

    final total = distribution.values.fold(
      Decimal.zero,
      (sum, value) => sum + value,
    );

    if ((total - amount).abs() > _splitTolerance) {
      onFallback?.call(SplitFallbackReason.exactAmountDrift);
      return _allocateEqual(amount, distribution.keys, currency);
    }

    final residual = amount - total;
    if (residual == Decimal.zero) {
      return Map<String, Decimal>.from(distribution);
    }
    // An in-tolerance (±_splitTolerance) sum drift is closed onto the
    // alphabetically-last recipient so sum(owed) == amount exactly — the same
    // remainder contract _allocateEqual/_allocateWeighted use. Without this the
    // residual escapes and conservation (sum(netBalance) == 0) breaks.
    //
    // For an OVER-allocation (residual < 0) the alphabetically-last recipient
    // can be a 0.000 entry — the custom split sheet emits one for any blank
    // participant (custom_split_sheet.dart:241-246) — and subtracting the
    // residual there would persist a negative owed (a non-payer turned phantom
    // creditor). So close the residual onto the alphabetically-last recipient
    // that can absorb it without going negative. For an under-allocation
    // (residual > 0) every recipient qualifies, so this is the last key —
    // identical to the prior contract.
    final sortedKeys = distribution.keys.toList()..sort();
    String? target;
    for (var i = sortedKeys.length - 1; i >= 0; i--) {
      if (distribution[sortedKeys[i]]! + residual >= Decimal.zero) {
        target = sortedKeys[i];
        break;
      }
    }
    if (target == null) {
      // No recipient can absorb the residual non-negatively — the distribution
      // cannot represent `amount` with non-negative owed. Unreachable for an
      // in-tolerance drift on a positive amount, but treat as invalid with the
      // same posture as the out-of-tolerance guard rather than emit a negative.
      onFallback?.call(SplitFallbackReason.exactResidualUnabsorbable);
      return _allocateEqual(amount, distribution.keys, currency);
    }
    return {
      for (final key in sortedKeys)
        key: key == target ? distribution[key]! + residual : distribution[key]!,
    };
  }

  static Map<String, Decimal> _allocatePercent(
    Decimal amount,
    Map<String, Decimal> distribution,
    String currency,
    void Function(SplitFallbackReason reason)? onFallback,
  ) {
    // A negative percent is never a valid weight (see _allocateShares) — it
    // would emit a negative owed even when the entries still sum to 100. Mirror
    // the _allocateExact guard; complementary to server-side validation (#192).
    if (distribution.values.any((value) => value < Decimal.zero)) {
      onFallback?.call(SplitFallbackReason.negativePercent);
      return _allocateEqual(amount, distribution.keys, currency);
    }

    final totalPercent = distribution.values.fold(
      Decimal.zero,
      (sum, value) => sum + value,
    );

    if ((totalPercent - _hundred).abs() > _splitTolerance) {
      onFallback?.call(SplitFallbackReason.percentDrift);
      return _allocateEqual(amount, distribution.keys, currency);
    }

    return _allocateWeighted(amount, distribution, _hundred, currency);
  }

  static Map<String, Decimal> _allocateWeighted(
    Decimal amount,
    Map<String, Decimal> weights,
    Decimal denominator,
    String currency,
  ) {
    final sortedRecipients = weights.keys.toList()..sort();
    // The rounding remainder lands on the alphabetically-last POSITIVE-weight
    // recipient — never a declared-0-share key (#872), mirroring
    // _spreadProportional. Callers guarantee at least one positive weight
    // (negatives → equal fallback, total > 0), so orElse is defensive only.
    // Parity note: remainder selection now depends on weight positivity, and
    // both sides decode positivity identically (shares are raw ints; percent
    // persists ×1000 and decodes ÷1000 in _splitValueFromPersisted and the
    // server decodeSplitValue alike) — keep those decodes in lockstep or the
    // oracle drifts.
    final remainderKey = sortedRecipients.lastWhere(
      (id) => weights[id]! > Decimal.zero,
      orElse: () => sortedRecipients.last,
    );
    final allocations = <String, Decimal>{};
    var allocated = Decimal.zero;

    for (final recipientId in sortedRecipients) {
      if (recipientId == remainderKey) continue;
      final allocation = _toCurrencyPrecision(
        ((amount * weights[recipientId]!) / denominator).toDecimal(
          scaleOnInfinitePrecision: 10,
        ),
        currency,
      );
      allocations[recipientId] = allocation;
      allocated += allocation;
    }
    allocations[remainderKey] = amount - allocated;

    return {for (final id in sortedRecipients) id: allocations[id]!};
  }

  /// Quantize [value] to [currency]'s subunit precision by round-tripping
  /// through integer subunits (OMR→3dp, USD→2dp, JPY→0dp). (Issue #47)
  static Decimal _toCurrencyPrecision(Decimal value, String currency) {
    return MoneySerializer.fromSubunits(
      MoneySerializer.toSubunits(value, currency),
      currency,
    );
  }

  static Map<String, Decimal> _allocateEqual(
    Decimal amount,
    Iterable<String> recipientIds,
    String currency,
  ) {
    final sortedRecipients = recipientIds.toList()..sort();
    final splitCount = sortedRecipients.length;
    if (splitCount == 0) return {};

    // Quantize the per-head share to whole subunits, mirroring _allocateWeighted
    // and the server allocateEqual (groupNetBalance.ts:152 `quantize`). The bare
    // `scaleOnInfinitePrecision` only rounds NON-terminating divisions; a
    // terminating sub-subunit quotient (e.g. OMR 2.900 / 8 = 0.3625) would
    // otherwise pass through as a half-baisa share, breaking client↔server
    // oracle parity and leaving netBalance non-whole-subunit (#596).
    final perHead = _toCurrencyPrecision(
      (amount / Decimal.fromInt(splitCount)).toDecimal(
        scaleOnInfinitePrecision: 10,
      ),
      currency,
    );
    final remainder = amount - (perHead * Decimal.fromInt(splitCount));

    return {
      for (int i = 0; i < sortedRecipients.length; i++)
        sortedRecipients[i]:
            perHead +
            (i == sortedRecipients.length - 1 ? remainder : Decimal.zero),
    };
  }

  /// Pure decomposition of a group transfer [amount] (payer→recipient, in
  /// [currency]) into per-event attributions + a cross-event [residual] — the
  /// SINGLE source of truth for BOTH the displayed breakdown and the written
  /// settlements (#752, #242 WYSIWYG). Computed in integer subunits so
  /// `Σ(perEvent) + residual == toSubunits(amount)` EXACTLY (whole-subunit,
  /// [MoneySerializer]-quantized).
  ///
  /// Invariants (pinned by `decompose_group_settlement_test.dart`):
  ///  - `residual >= 0` ALWAYS (never a negative/reverse settlement).
  ///  - `perEvent[e] <= min(|payerNet_e|, recipientNet_e)` (never more than the
  ///    event "earned") AND `Σ perEvent <= toSubunits(amount)`.
  ///  - `Σ perEvent + residual == toSubunits(amount)`, exactly.
  ///  - Deterministic given [eventOrder]; events absent from a party's
  ///    breakdown contribute zero (skipped).
  ///  - `amount <= 0` → `({}, 0)`.
  ///
  /// An event is attributable only where the payer OWES (`payerNet_e < 0`) and
  /// the recipient is OWED (`recipientNet_e > 0`); the slice is capped at the
  /// overlap `min(|payerNet_e|, recipientNet_e)` and at the unallocated
  /// [remaining]. Cross-event debt (payer owes in E1, is owed in E2) and partial
  /// settlements (`amount` < full suggested) both fall into [residual] by
  /// construction — so the naive `Σ min(|fromNet|, toNet)` over-count (and its
  /// negative residual) can never occur.
  ///
  /// [currency] MUST be the same bucket key used in [payerPerEventNet] /
  /// [recipientPerEventNet] (both derive from the one balance computation, which
  /// fences with `isSupported(c) ? c : 'OMR'`, preserving case). The map lookups
  /// use it verbatim — do NOT `.toUpperCase()` it (the internal `isSupported`
  /// fence only keeps the [MoneySerializer] calls from throwing).
  static ({Map<String, Decimal> perEvent, Decimal residual})
      decomposeGroupSettlement({
    required Map<String, Map<String, Decimal>> payerPerEventNet,
    required Map<String, Map<String, Decimal>> recipientPerEventNet,
    required String currency,
    required Decimal amount,
    required List<String> eventOrder,
  }) {
    final cur = MoneySerializer.isSupported(currency) ? currency : 'OMR';
    final perEvent = <String, Decimal>{};
    var remaining = MoneySerializer.toSubunits(amount, cur);
    if (remaining <= 0) {
      return (perEvent: perEvent, residual: Decimal.zero);
    }

    for (final eventId in eventOrder) {
      if (remaining <= 0) break;
      final payerNet = MoneySerializer.toSubunits(
        payerPerEventNet[eventId]?[cur] ?? Decimal.zero,
        cur,
      );
      final recipientNet = MoneySerializer.toSubunits(
        recipientPerEventNet[eventId]?[cur] ?? Decimal.zero,
        cur,
      );
      if (payerNet < 0 && recipientNet > 0) {
        final cap = (-payerNet) < recipientNet ? (-payerNet) : recipientNet;
        final take = cap < remaining ? cap : remaining;
        if (take > 0) {
          perEvent[eventId] = MoneySerializer.fromSubunits(take, cur);
          remaining -= take;
        }
      }
    }
    return (
      perEvent: perEvent,
      residual: MoneySerializer.fromSubunits(remaining, cur),
    );
  }

  static List<Map<String, dynamic>> calculateOptimalSettlements({
    required List<UserBalance> balances,
    Map<String, String>? userNames,
  }) {
    final debtors = balances.where((b) => b.netBalance < Decimal.zero).toList();
    final creditors = balances
        .where((b) => b.netBalance > Decimal.zero)
        .toList();

    debtors.sort((a, b) => a.netBalance.compareTo(b.netBalance));
    creditors.sort((a, b) => b.netBalance.compareTo(a.netBalance));

    final List<Map<String, dynamic>> settlements = [];
    int i = 0, j = 0;

    final List<Decimal> debtorBalances = debtors
        .map((d) => d.netBalance.abs())
        .toList();
    final List<Decimal> creditorBalances = creditors
        .map((c) => c.netBalance)
        .toList();

    while (i < debtorBalances.length && j < creditorBalances.length) {
      final amount = debtorBalances[i] < creditorBalances[j]
          ? debtorBalances[i]
          : creditorBalances[j];

      if (amount > Decimal.zero) {
        settlements.add({
          'fromUserId': debtors[i].participantId,
          'toUserId': creditors[j].participantId,
          'fromUserName':
              userNames?[debtors[i].participantId] ?? debtors[i].displayName,
          'toUserName':
              userNames?[creditors[j].participantId] ??
              creditors[j].displayName,
          'amount': amount,
        });
      }

      debtorBalances[i] -= amount;
      creditorBalances[j] -= amount;

      if (debtorBalances[i] <= Decimal.zero) i++;
      if (creditorBalances[j] <= Decimal.zero) j++;
    }

    return settlements;
  }

  /// #363 OFF-mode allocator: direct pro-rata fan-out over the same net
  /// balances the optimizer consumes — each debtor pays EVERY creditor a
  /// proportional share instead of the fewest-transfers concentration. Still
  /// BALANCE-based, never expense-graph-based: the deployed recordSettlement
  /// cap (`min(|fromNet|, toNet)` on full fresh nets) makes transaction-graph
  /// pairwise legs unrecordable, so every leg here is `<=` that cap BY
  /// CONSTRUCTION. Same map shape as [calculateOptimalSettlements] (exact keys
  /// fromUserId/toUserId/fromUserName/toUserName/amount) so every downstream
  /// consumer is shape-unchanged. [currency] is the bucket's — unlike the
  /// min-only optimizer this allocator DIVIDES, so it needs the subunit scale.
  ///
  /// All arithmetic is plain-int subunits ([MoneySerializer.toSubunits]/
  /// [fromSubunits]); pro-rata shares floor via integer division — no Decimal
  /// division anywhere, so the #596 sub-subunit quantization trap cannot arise
  /// in integer space. Deterministic: both sides sort alphabetically by
  /// participantId (house-style tiebreak) and a repeat run is deep-equal.
  static List<Map<String, dynamic>> calculateDirectSettlements({
    required List<UserBalance> balances,
    required String currency,
    Map<String, String>? userNames,
  }) {
    // Same fence as [decomposeGroupSettlement]: keep the MoneySerializer
    // calls from throwing on an untrusted bucket key.
    final cur = MoneySerializer.isSupported(currency) ? currency : 'OMR';

    final debtors = balances.where((b) => b.netBalance < Decimal.zero).toList()
      ..sort((a, b) => a.participantId.compareTo(b.participantId));
    final creditors = balances
        .where((b) => b.netBalance > Decimal.zero)
        .toList()
      ..sort((a, b) => a.participantId.compareTo(b.participantId));

    // Guard ORDER matters: this runs BEFORE any division, so the `~/ totalCap`
    // below can never divide by zero on whole-subunit production nets (a
    // nonempty creditor side has totalCap >= 1).
    if (debtors.isEmpty || creditors.isEmpty) return const [];

    final origCap = [
      for (final c in creditors) MoneySerializer.toSubunits(c.netBalance, cur),
    ];
    final capRemaining = [...origCap];
    var totalCap = 0;
    for (final cap in origCap) {
      totalCap += cap;
    }
    // Forged/legacy sub-subunit nets can truncate every cap to 0; treat that
    // like the empty-creditor guard above (still before any division).
    if (totalCap <= 0) return const [];

    final legs = <Map<String, dynamic>>[];
    for (final d in debtors) {
      final rowTotal = MoneySerializer.toSubunits(d.netBalance.abs(), cur);
      var remainingRow = rowTotal;
      // Per-directed-pair accumulation (creditor index → subunits): pass 2 may
      // top up a creditor pass 1 already touched, and TWO same-pair legs would
      // collide on the deterministic sd1 settlement ids downstream
      // (recordSettlement's idempotency probe records one and silently DROPS
      // the other) — so legs are emitted ONCE per pair, after both passes.
      final pairSubunits = <int, int>{};

      // Pass 1: pro-rata by ORIGINAL creditor capacity, floored (integer
      // division), bounded by the creditor's remaining capacity and the row.
      for (var j = 0; j < creditors.length && remainingRow > 0; j++) {
        var take = (rowTotal * origCap[j]) ~/ totalCap;
        if (take > capRemaining[j]) take = capRemaining[j];
        if (take > remainingRow) take = remainingRow;
        if (take <= 0) continue;
        pairSubunits[j] = (pairSubunits[j] ?? 0) + take;
        capRemaining[j] -= take;
        remainingRow -= take;
      }

      // Pass 2 (row residual close-out): ONE BOUNDED sweep over the same
      // fixed creditor list — never a `while (remainingRow > 0)` loop, which
      // would spin when a non-conserving bucket exhausts capacity. Leftover
      // remainingRow after the sweep is DROPPED, mirroring how the two-pointer
      // optimizer leaves surplus unpaired when the other side exhausts.
      // NOTE: alpha-FIRST close-out is a DELIBERATE deviation from the house
      // "remainder → alphabetically-last" rule of the split allocators — here
      // the binding constraint is per-leg cap compliance (each pair total must
      // stay within the creditor's capacity draw-down), not share-remainder
      // placement.
      for (var j = 0; j < creditors.length && remainingRow > 0; j++) {
        final take = remainingRow < capRemaining[j]
            ? remainingRow
            : capRemaining[j];
        if (take <= 0) continue;
        pairSubunits[j] = (pairSubunits[j] ?? 0) + take;
        capRemaining[j] -= take;
        remainingRow -= take;
      }

      // Emit exactly ONE leg per directed pair, creditors in alpha order.
      for (var j = 0; j < creditors.length; j++) {
        final subunits = pairSubunits[j];
        if (subunits == null || subunits <= 0) continue;
        legs.add({
          'fromUserId': d.participantId,
          'toUserId': creditors[j].participantId,
          'fromUserName': userNames?[d.participantId] ?? d.displayName,
          'toUserName':
              userNames?[creditors[j].participantId] ??
              creditors[j].displayName,
          'amount': MoneySerializer.fromSubunits(subunits, cur),
        });
      }
    }

    return legs;
  }

  /// #719: the current directed-pair outstanding in one currency [bucket] — how
  /// much [fromUserId] can pay [toUserId] without overpaying either side =
  /// `min(|fromNet|, toNet)`, clamped to `>= 0`. Conservative mirror of the
  /// per-pair cap in [calculateOptimalSettlements]: that optimizer suggests at
  /// most `min(remaining_debtor, remaining_creditor)` for a pair, and both
  /// remainders only ever shrink from the full nets — so the suggestion is always
  /// `<=` this value. Revalidating an edited amount against it therefore never
  /// false-blocks an unchanged balance; it fires only when the live net actually
  /// dropped below the amount being recorded. A party absent from the bucket is
  /// treated as net 0 (settled). Single-currency by construction — never sum
  /// across buckets. Pure.
  static Decimal outstandingForPair({
    required List<UserBalance> bucket,
    required String fromUserId,
    required String toUserId,
  }) {
    Decimal netFor(String uid) {
      for (final b in bucket) {
        if (b.participantId == uid) return b.netBalance;
      }
      return Decimal.zero;
    }

    final fromNet = netFor(fromUserId); // debtor when negative
    final toNet = netFor(toUserId); // creditor when positive
    final payable = fromNet < Decimal.zero ? fromNet.abs() : Decimal.zero;
    final receivable = toNet > Decimal.zero ? toNet : Decimal.zero;
    return payable < receivable ? payable : receivable;
  }

  /// Per-currency expense totals (#382 PR-1). Keys are fence-validated like
  /// [calculateBalances] bucket keys (unsupported → OMR). Empty input → `{}`.
  static Map<String, Decimal> calculateTotalExpensesByCurrency(
    List<Expense> expenses,
  ) {
    final totals = <String, Decimal>{};
    for (final e in expenses) {
      final currency = MoneySerializer.isSupported(e.currency)
          ? e.currency
          : 'OMR';
      totals[currency] = (totals[currency] ?? Decimal.zero) + e.amount;
    }
    return totals;
  }
}

/// Non-zero buckets, GCC-first ([sortedGccFirst]) — the canonical line list
/// for per-currency display surfaces (#382 PR-5). Empty result ⇔ settled
/// everywhere. "Non-zero" is EXACT `!= Decimal.zero` — no tolerance, so a
/// sub-tolerance residual renders instead of silently reading as settled.
List<({String currency, Decimal net})> nonZeroNetsGccFirst(
  Map<String, Decimal> nets,
) {
  return [
    for (final c in sortedGccFirst(nets.keys))
      if (nets[c] != Decimal.zero) (currency: c, net: nets[c]!),
  ];
}

/// [uid]'s net per currency from a bucketed balance map (#382 PR-5). Buckets
/// where [uid] is absent or nets exactly zero are dropped; null [uid] → `{}`.
///
/// Single-uid reads only. For a list/roster that needs every participant's
/// nets, build [pivotNetsByParticipant] ONCE and index it per row — calling
/// this per row is the O(C×M²) trap #630 fixed.
Map<String, Decimal> myNetByCurrency(
  Map<String, List<UserBalance>> buckets,
  String? uid,
) {
  if (uid == null) return const {};
  return {
    for (final entry in buckets.entries)
      for (final balance in entry.value)
        if (balance.participantId == uid && balance.netBalance != Decimal.zero)
          entry.key: balance.netBalance,
  };
}

/// One single pass pivot of [buckets] → `participantId → {currency: net}`, each
/// inner map zero-filtered exactly like [myNetByCurrency] (#630). For member /
/// roster lists: build ONCE before the loop, then `pivot[uid] ?? const {}` per
/// row is O(1) — collapsing the former O(C×M²) per-row [myNetByCurrency] pivots
/// to O(C×M) for the whole list.
///
/// Equivalence contract: `pivot[uid] ?? const {}` == `myNetByCurrency(buckets,
/// uid)` for every uid (zero predicate is the same EXACT `!= Decimal.zero`, so a
/// member who nets exactly zero in every bucket is absent from the pivot).
Map<String, Map<String, Decimal>> pivotNetsByParticipant(
  Map<String, List<UserBalance>> buckets,
) {
  final pivot = <String, Map<String, Decimal>>{};
  for (final entry in buckets.entries) {
    for (final balance in entry.value) {
      if (balance.netBalance != Decimal.zero) {
        (pivot[balance.participantId] ??= <String, Decimal>{})[entry.key] =
            balance.netBalance;
      }
    }
  }
  return pivot;
}
