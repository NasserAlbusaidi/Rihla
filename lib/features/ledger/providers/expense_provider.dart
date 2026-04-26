import 'package:decimal/decimal.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/services/cache/expense_cache_repository.dart';
import '../../../core/services/cache/settlement_cache_repository.dart';
import '../../../core/types/event_ref.dart';
import '../../events/models/event_model.dart';
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

/// Error state for expense operations
final expenseErrorProvider = StateProvider<String?>((ref) => null);

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
/// Includes an [asyncMap] SQLite side-write so [BalanceCalculator] data is
/// always fresh after each Firestore snapshot (D-15). The side-write uses
/// [ExpenseCacheRepository.cacheExpenses] (migrated from BalanceCacheRepository
/// in Plan 36-06).
///
/// **Why asyncMap over listen:** `asyncMap` keeps the stream pipeline intact
/// and ensures SQLite writes complete before downstream subscribers receive
/// the data. A separate `listen()` would create a dangling subscription
/// outside Riverpod's lifecycle management.
final eventExpensesProvider = StreamProvider.family<List<Expense>, EventRef>((
  ref,
  eventRef,
) {
  final service = ref.read(expenseServiceProvider);
  final cache = ref.read(expenseCacheRepositoryProvider);
  return service.watchExpenses(eventRef.groupId, eventRef.eventId).asyncMap(
    (expenses) async {
      // Side effect: write to SQLite for BalanceCalculator (D-15)
      // Catch errors — SQLite FK constraints may fail for Firestore-only events
      // that have no corresponding row in the legacy trips table.
      try {
        await cache.cacheExpenses(eventRef.eventId, expenses);
      } catch (_) {
        // SQLite cache is non-critical; Firestore is the source of truth
      }
      return expenses; // pass through unchanged
    },
  );
});

/// Firestore-backed settlement stream using [EventRef] as the family parameter.
///
/// Includes an [asyncMap] SQLite side-write for BalanceCalculator (D-15).
final eventSettlementsProvider =
    StreamProvider.family<List<Settlement>, EventRef>((
  ref,
  eventRef,
) {
  final service = ref.read(settlementServiceProvider);
  final cache = ref.read(settlementCacheRepositoryProvider);
  return service
      .watchSettlements(eventRef.groupId, eventRef.eventId)
      .asyncMap(
    (settlements) async {
      // Side effect: write to SQLite for BalanceCalculator (D-15)
      // Catch errors — SQLite FK constraints may fail for Firestore-only events
      try {
        await cache.cacheSettlements(eventRef.eventId, settlements);
      } catch (_) {
        // SQLite cache is non-critical; Firestore is the source of truth
      }
      return settlements; // pass through unchanged
    },
  );
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
    AsyncValue<List<UserBalance>>,
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

  // Derive participants from event data (no SQLite needed)
  final participants = params.event.participantIds.map((id) {
    return Participant(
      id: id,
      tripId: params.event.id,
      role: ParticipantRole.member,
      joinedAt: params.event.createdAt,
      displayName: params.event.participantNames[id],
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
// Balance calculation engine (pure function -- in-memory)
// ---------------------------------------------------------------------------

/// Balance calculation engine
class BalanceCalculator {
  /// Calculate balances with proper scope handling
  ///
  /// - Global: Split among all participants
  /// - Personal: Only the payer is responsible (no split)
  /// - Custom: Split among the listed participants
  ///
  /// Legacy `subGroup` scope (logistics feature, removed in Phase 39) falls
  /// back to global behaviour for back-compat with persisted Firestore docs.
  static List<UserBalance> calculateBalances({
    required List<Expense> expenses,
    required List<Participant> participants,
    List<Settlement> settlements = const [],
  }) {
    if (participants.isEmpty) return [];

    // Maps: participantId -> amounts
    final Map<String, Decimal> paidMap = {
      for (var p in participants) p.id: Decimal.zero,
    };
    final Map<String, Decimal> owedMap = {
      for (var p in participants) p.id: Decimal.zero,
    };

    // Process each expense
    for (final expense in expenses) {
      final payerId = expense.payerParticipantId;

      // Track what payer paid
      if (paidMap.containsKey(payerId)) {
        paidMap[payerId] = paidMap[payerId]! + expense.amount;
      }

      // Determine who shares this expense based on scope
      Set<String> splitRecipients;

      switch (expense.scope) {
        case ExpenseScope.personal:
          // Personal: only the payer owes themselves (no redistribution)
          splitRecipients = {payerId};
          break;

        case ExpenseScope.subGroup:
          // Legacy sub-group scope (logistics removed in Phase 39):
          // back-compat fallback to global so existing expenses still split.
          splitRecipients = participants.map((p) => p.id).toSet();
          break;

        case ExpenseScope.custom:
          // Custom: only the selected participants
          if (expense.customSplitParticipants != null &&
              expense.customSplitParticipants!.isNotEmpty) {
            splitRecipients = expense.customSplitParticipants!.toSet();
          } else {
            // Fallback to global if no participants specified
            splitRecipients = participants.map((p) => p.id).toSet();
          }
          break;

        case ExpenseScope.global:
          // Global: everyone shares
          splitRecipients = participants.map((p) => p.id).toSet();
          break;
      }

      // Calculate per-head cost for this expense
      final splitCount = splitRecipients.length;
      if (splitCount == 0) continue;

      final perHead = (expense.amount / Decimal.fromInt(splitCount)).toDecimal(
        scaleOnInfinitePrecision: 3,
      );

      // Remainder-safe distribution: assign truncated perHead to all
      // recipients except the last (sorted for determinism), who absorbs
      // the rounding remainder so sum(shares) == expense.amount exactly.
      final remainder =
          expense.amount - (perHead * Decimal.fromInt(splitCount));
      final sortedRecipients = splitRecipients.toList()..sort();
      for (int i = 0; i < sortedRecipients.length; i++) {
        final recipientId = sortedRecipients[i];
        if (owedMap.containsKey(recipientId)) {
          final isLast = i == sortedRecipients.length - 1;
          owedMap[recipientId] =
              owedMap[recipientId]! + perHead + (isLast ? remainder : Decimal.zero);
        }
      }
    }

    // Apply settlement adjustments
    final Map<String, Decimal> settlementAdjustmentMap = {
      for (var p in participants) p.id: Decimal.zero,
    };

    for (final s in settlements) {
      if (s.payerParticipantId != null &&
          settlementAdjustmentMap.containsKey(s.payerParticipantId)) {
        settlementAdjustmentMap[s.payerParticipantId!] =
            settlementAdjustmentMap[s.payerParticipantId!]! +
            s.amount;
      }
      if (s.recipientParticipantId != null &&
          settlementAdjustmentMap.containsKey(s.recipientParticipantId)) {
        settlementAdjustmentMap[s.recipientParticipantId!] =
            settlementAdjustmentMap[s.recipientParticipantId!]! -
            s.amount;
      }
    }

    // Build final balances
    return participants.map((p) {
      final totalPaid = paidMap[p.id] ?? Decimal.zero;
      final totalOwed = owedMap[p.id] ?? Decimal.zero;
      final settlementAdj = settlementAdjustmentMap[p.id] ?? Decimal.zero;

      // Net = (what they paid + settlements given) - what they owe
      final netBalance = (totalPaid + settlementAdj) - totalOwed;

      return UserBalance(
        participantId: p.id,
        displayName: p.displayName ?? 'Unknown',
        totalPaid: totalPaid,
        totalOwed: totalOwed,
        netBalance: netBalance,
      );
    }).toList();
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

  static Decimal calculateTotalExpenses(List<Expense> expenses) {
    return expenses.fold(Decimal.zero, (sum, e) => sum + e.amount);
  }
}
