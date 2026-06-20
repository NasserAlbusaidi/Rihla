import 'package:decimal/decimal.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

import '../../../core/constants/supported_currencies.dart';
import '../../../core/models/split_mode.dart';
import '../../../core/services/money_serializer.dart';
import '../../../core/types/event_ref.dart';
import '../../events/models/event_model.dart';
import '../../groups/providers/group_provider.dart';
import '../../trip/models/trip_model.dart';
import '../models/expense_model.dart';
import '../models/settlement_model.dart';
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

/// Provider for the Firestore-backed [SettlementService].
final settlementServiceProvider = Provider<SettlementService>(
  (ref) => SettlementService(),
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
// NEW: EventRef-based balance provider
// ---------------------------------------------------------------------------

/// Provider for user balances in an event.
///
/// Derives participants directly from [Event.participantIds] and
/// [Event.participantNames] — no SQLite lookup needed. Uses
/// [eventExpensesProvider], [eventSettlementsProvider], and
/// [eventSubGroupsProvider] (all Firestore-backed).
///
/// Takes a record `({EventRef eventRef, Event event})` to carry both
/// the EventRef (for provider lookups) and the Event (for participant data).
final eventBalancesProvider = Provider.family<
    AsyncValue<Map<String, List<UserBalance>>>,
    ({EventRef eventRef, Event event})>((ref, params) {
  final expensesAsync = ref.watch(eventExpensesProvider(params.eventRef));
  final settlementsAsync =
      ref.watch(eventSettlementsProvider(params.eventRef));

  if (expensesAsync.isLoading || settlementsAsync.isLoading) {
    if (!expensesAsync.hasValue || !settlementsAsync.hasValue) {
      return const AsyncValue.loading();
    }
  }

  if (expensesAsync.hasError) {
    return AsyncValue.error(expensesAsync.error!, expensesAsync.stackTrace!);
  }

  final expenses = expensesAsync.valueOrNull ?? [];
  final settlements = settlementsAsync.valueOrNull ?? [];

  // #249: fold departed-member split recipients (and former payers/settlers)
  // into the universe so their owed shares aren't dropped. Members supply the
  // member-gate + former-member display names; before they load we degrade to
  // participantIds-only (the prior behavior).
  final members =
      ref.watch(groupMembersProvider(params.eventRef.groupId)).valueOrNull ??
      const [];
  final allMemberIds = members.map((m) => m.userId).toSet();
  final liveMemberIds =
      members.where((m) => !m.isTombstone).map((m) => m.userId).toSet();
  final memberNameByUid = {for (final m in members) m.userId: m.displayName};

  final universe = eventBalanceUniverse(
    event: params.event,
    expenses: expenses,
    settlements: settlements,
    allMemberIds: allMemberIds,
    liveMemberIds: liveMemberIds,
  );

  final participants = universe.map((id) {
    return Participant(
      id: id,
      tripId: params.event.id,
      role: ParticipantRole.member,
      joinedAt: params.event.createdAt,
      displayName: params.event.participantNames[id] ?? memberNameByUid[id],
    );
  }).toList();

  final balances = BalanceCalculator.calculateBalances(
    expenses: expenses,
    settlements: settlements,
    participants: participants,
  );

  return AsyncValue.data(balances);
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
    for (final e in expenses) e.payerParticipantId,
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
    final allocations = <String, Decimal>{};
    var allocated = Decimal.zero;

    for (int i = 0; i < sortedRecipients.length; i++) {
      final recipientId = sortedRecipients[i];
      final isLast = i == sortedRecipients.length - 1;
      final allocation = isLast
          ? amount - allocated
          : _toCurrencyPrecision(
              ((amount * weights[recipientId]!) / denominator).toDecimal(
                scaleOnInfinitePrecision: 10,
              ),
              currency,
            );
      allocations[recipientId] = allocation;
      allocated += allocation;
    }

    return allocations;
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
