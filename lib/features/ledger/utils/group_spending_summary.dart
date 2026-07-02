import 'package:decimal/decimal.dart';

import '../../../core/services/money_serializer.dart';
import '../models/expense_model.dart';

/// One event's spend in one currency (#180). Display-only.
typedef GroupEventTotal = ({String eventId, Decimal total});

/// One category's spend in one currency (#180). Display-only.
typedef GroupCategoryTotal = ({String categoryId, Decimal total});

/// A person + a positive amount: a top-payer / top-consumer row (#180).
typedef GroupPersonAmount = ({String participantId, Decimal amount});

/// Immutable, per-currency spending summary of one GROUP (#180). A pure
/// projection over the inputs `groupBalancesProvider` already streams — it
/// adds no money arithmetic beyond per-currency sum/max. Display-only:
/// nothing here may feed a write path.
///
/// Money invariant: every field is a per-currency map; Decimals are NEVER
/// summed across currencies. Per currency, [eventTotalsByCurrency] and
/// [categoryTotalsByCurrency] each sum to [totalSpentByCurrency] by
/// construction (all three fold the same filtered input in one pass).
///
/// Spec + Gate review: docs/plans/2026-07-02-180-group-spending-summary.md.
class GroupSpendingSummary {
  final int expenseCount;

  /// Keyed by EXPENSE currencies (fence: unsupported → OMR, matching
  /// [BalanceCalculator.calculateTotalExpensesByCurrency]).
  final Map<String, Decimal> totalSpentByCurrency;

  /// Per currency: events with spend in that currency, desc by total, tie
  /// eventId asc. First entry = highest-spending event.
  final Map<String, List<GroupEventTotal>> eventTotalsByCurrency;

  /// Per currency: categoryId (`?? 'other'`) → summed amount, desc, tie
  /// categoryId asc.
  final Map<String, List<GroupCategoryTotal>> categoryTotalsByCurrency;

  /// Max [UserBalance.totalPaid] per EXPENSE currency — gross cash fronted,
  /// settlement-INDEPENDENT (settlements fold into netBalance only). Absent
  /// when nobody paid > 0 in that bucket. Tie: participantId asc.
  final Map<String, GroupPersonAmount> topPayerByCurrency;

  /// Max [UserBalance.totalOwed] per EXPENSE currency — biggest consumed
  /// share. Same absence/tie rules as [topPayerByCurrency].
  final Map<String, GroupPersonAmount> topConsumerByCurrency;

  final bool isEmpty;

  const GroupSpendingSummary({
    required this.expenseCount,
    required this.totalSpentByCurrency,
    required this.eventTotalsByCurrency,
    required this.categoryTotalsByCurrency,
    required this.topPayerByCurrency,
    required this.topConsumerByCurrency,
    required this.isEmpty,
  });
}

/// Pure fold from per-event expense lists + already-bucketed balances to a
/// [GroupSpendingSummary]. No I/O, no Riverpod — callers assemble the inputs.
///
/// [expensesByEvent] is keyed by the event whose stream produced each list
/// (positional, not `expense.tripId` matching), so by-event slices sum to the
/// total by construction. [balances] is `GroupBalances.balances`.
GroupSpendingSummary computeGroupSpendingSummary({
  required Map<String, List<Expense>> expensesByEvent,
  required Map<String, List<UserBalance>> balances,
}) {
  final total = <String, Decimal>{};
  final eventRaw = <String, Map<String, Decimal>>{};
  final categoryRaw = <String, Map<String, Decimal>>{};
  var expenseCount = 0;

  expensesByEvent.forEach((eventId, expenses) {
    for (final expense in expenses) {
      // The Firestore query already filters isDeleted (expense_service.dart);
      // kept here so direct callers of this public pure fn can't count them.
      if (expense.isDeleted) continue;
      final currency = MoneySerializer.isSupported(expense.currency)
          ? expense.currency
          : 'OMR';
      total[currency] = (total[currency] ?? Decimal.zero) + expense.amount;
      (eventRaw[currency] ??= {}).update(
        eventId,
        (v) => v + expense.amount,
        ifAbsent: () => expense.amount,
      );
      final categoryId = expense.categoryId ?? 'other';
      (categoryRaw[currency] ??= {}).update(
        categoryId,
        (v) => v + expense.amount,
        ifAbsent: () => expense.amount,
      );
      expenseCount++;
    }
  });

  final eventTotals = <String, List<GroupEventTotal>>{
    for (final entry in eventRaw.entries)
      entry.key: List.unmodifiable(
        entry.value.entries
            .map((e) => (eventId: e.key, total: e.value))
            .toList()
          ..sort((a, b) {
            final byTotal = b.total.compareTo(a.total);
            return byTotal != 0 ? byTotal : a.eventId.compareTo(b.eventId);
          }),
      ),
  };
  final categoryTotals = <String, List<GroupCategoryTotal>>{
    for (final entry in categoryRaw.entries)
      entry.key: List.unmodifiable(
        entry.value.entries
            .map((e) => (categoryId: e.key, total: e.value))
            .toList()
          ..sort((a, b) {
            final byTotal = b.total.compareTo(a.total);
            return byTotal != 0
                ? byTotal
                : a.categoryId.compareTo(b.categoryId);
          }),
      ),
  };

  // Superlatives keyed by EXPENSE currencies only: totalPaid/totalOwed > 0
  // implies expenses exist in that currency, so a settlement-only balance
  // bucket has no meaningful "top payer" and is skipped.
  final topPayer = <String, GroupPersonAmount>{};
  final topConsumer = <String, GroupPersonAmount>{};
  for (final currency in total.keys) {
    final bucket = balances[currency];
    if (bucket == null) continue;
    final payer = _topBy(bucket, (b) => b.totalPaid);
    final consumer = _topBy(bucket, (b) => b.totalOwed);
    if (payer != null) topPayer[currency] = payer;
    if (consumer != null) topConsumer[currency] = consumer;
  }

  return GroupSpendingSummary(
    expenseCount: expenseCount,
    totalSpentByCurrency: Map.unmodifiable(total),
    eventTotalsByCurrency: Map.unmodifiable(eventTotals),
    categoryTotalsByCurrency: Map.unmodifiable(categoryTotals),
    topPayerByCurrency: Map.unmodifiable(topPayer),
    topConsumerByCurrency: Map.unmodifiable(topConsumer),
    isEmpty: expenseCount == 0,
  );
}

GroupPersonAmount? _topBy(
  List<UserBalance> bucket,
  Decimal Function(UserBalance) amountOf,
) {
  GroupPersonAmount? best;
  for (final balance in bucket) {
    final amount = amountOf(balance);
    if (amount <= Decimal.zero) continue;
    final wins = best == null ||
        amount > best.amount ||
        (amount == best.amount &&
            balance.participantId.compareTo(best.participantId) < 0);
    if (wins) {
      best = (participantId: balance.participantId, amount: amount);
    }
  }
  return best;
}
