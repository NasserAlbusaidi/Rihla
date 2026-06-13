import '../../../core/constants/supported_currencies.dart';
import '../models/expense_model.dart';

/// #382 PR-6 — pure currency-defaulting helpers for the add-expense editor.
///
/// Two distinct signals derived from an event's expense history:
/// - [defaultExpenseCurrency]: recency ("last-used") → the new expense's
///   default currency.
/// - [dominantEventCurrency]: frequency (mode) → drives the soft fat-finger
///   warning when a pick diverges from what the event mostly uses.

/// The currency to pre-select for a new expense: the currency of the
/// most-recently-created non-deleted expense in [eventExpenses]; on a
/// `createdAt` tie the first-encountered (list order) wins; empty or
/// all-deleted falls back to [groupDefault].
///
/// Single-pass max-fold — does NOT sort (Dart's sort is not stable, which
/// would break the first-wins tie rule).
String defaultExpenseCurrency(
  List<Expense> eventExpenses,
  String groupDefault,
) {
  String? bestCurrency;
  DateTime? bestCreatedAt;
  for (final expense in eventExpenses) {
    if (expense.isDeleted) continue;
    if (bestCreatedAt == null || expense.createdAt.isAfter(bestCreatedAt)) {
      bestCreatedAt = expense.createdAt;
      bestCurrency = expense.currency;
    }
  }
  return bestCurrency ?? groupDefault;
}

/// The currency used most often among non-deleted expenses in [eventExpenses]
/// (the mode); ties broken GCC-first ([currencyGccRank]). Returns `null` iff
/// there are no non-deleted expenses.
String? dominantEventCurrency(List<Expense> eventExpenses) {
  final counts = <String, int>{};
  for (final expense in eventExpenses) {
    if (expense.isDeleted) continue;
    counts[expense.currency] = (counts[expense.currency] ?? 0) + 1;
  }
  if (counts.isEmpty) return null;

  String? best;
  int bestCount = 0;
  for (final entry in counts.entries) {
    final isHigherCount = entry.value > bestCount;
    final isTieEarlierRank = entry.value == bestCount &&
        best != null &&
        currencyGccRank(entry.key) < currencyGccRank(best);
    if (isHigherCount || isTieEarlierRank) {
      best = entry.key;
      bestCount = entry.value;
    }
  }
  return best;
}
