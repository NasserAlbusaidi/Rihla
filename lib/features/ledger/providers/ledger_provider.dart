import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/transaction_model.dart';
import 'expense_provider.dart';

/// Unifies Expenses and Settlements into a single chronologically sorted stream.
/// Returns an AsyncValue containing the list of merged transactions.
final tripUnifiedLedgerProvider = Provider.family<AsyncValue<List<Transaction>>, String>((ref, tripId) {
  final expensesAsync = ref.watch(tripExpensesProvider(tripId));
  final settlementsAsync = ref.watch(tripSettlementsProvider(tripId));

  // If either is loading and we don't have data yet, show loading
  if (expensesAsync.isLoading || settlementsAsync.isLoading) {
    if (!expensesAsync.hasValue || !settlementsAsync.hasValue) {
      return const AsyncValue.loading();
    }
  }

  // Handle errors
  if (expensesAsync.hasError) {
    return AsyncValue.error(expensesAsync.error!, expensesAsync.stackTrace!);
  }
  if (settlementsAsync.hasError) {
    return AsyncValue.error(settlementsAsync.error!, settlementsAsync.stackTrace!);
  }

  final expenses = expensesAsync.valueOrNull ?? [];
  final settlements = settlementsAsync.valueOrNull ?? [];
  
  final transactions = <Transaction>[
    ...expenses.map((e) => Transaction.fromExpense(e)),
    ...settlements.map((s) => Transaction.fromSettlement(s)),
  ];

  // Sort by Date Descending (Newest First)
  transactions.sort((a, b) => b.date.compareTo(a.date));

  return AsyncValue.data(transactions);
});