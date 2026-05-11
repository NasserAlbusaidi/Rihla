import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/transaction_model.dart';
import 'expense_provider.dart';

/// NEW: Unifies Expenses and Settlements into a single chronologically sorted stream.
///
/// Uses Firestore-backed [eventExpensesProvider] and [eventSettlementsProvider].
final eventUnifiedLedgerProvider =
    Provider.family<AsyncValue<List<Transaction>>, EventRef>((ref, eventRef) {
      final expensesAsync = ref.watch(eventExpensesProvider(eventRef));
      final settlementsAsync = ref.watch(eventSettlementsProvider(eventRef));

      if (expensesAsync.isLoading || settlementsAsync.isLoading) {
        if (!expensesAsync.hasValue || !settlementsAsync.hasValue) {
          return const AsyncValue.loading();
        }
      }

      if (expensesAsync.hasError) {
        return AsyncValue.error(
          expensesAsync.error!,
          expensesAsync.stackTrace!,
        );
      }
      if (settlementsAsync.hasError) {
        return AsyncValue.error(
          settlementsAsync.error!,
          settlementsAsync.stackTrace!,
        );
      }

      final expenses = expensesAsync.valueOrNull ?? [];
      final settlements = settlementsAsync.valueOrNull ?? [];

      final transactions = <Transaction>[
        ...expenses.map(Transaction.fromExpense),
        ...settlements.map(Transaction.fromSettlement),
      ];

      transactions.sort((a, b) => b.date.compareTo(a.date));

      return AsyncValue.data(transactions);
    });
