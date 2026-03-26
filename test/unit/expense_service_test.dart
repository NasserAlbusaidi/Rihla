import 'package:flutter_test/flutter_test.dart';

// Wave 0 stub: Firestore ExpenseService tests.
// Real implementation added in Plan 04-01 (Ledger Migration).

void main() {
  group('ExpenseService (Firestore)', () {
    group('addExpense', () {
      test(
        'writes expense document to groups/{groupId}/events/{eventId}/expenses',
        () {},
        skip: 'Awaiting Plan 04-01: ExpenseService Firestore migration',
      );

      test(
        'uses MoneySerializer.toSubunits to store amountFils',
        () {},
        skip: 'Awaiting Plan 04-01: ExpenseService Firestore migration',
      );
    });

    group('watchExpenses', () {
      test(
        'returns a stream of expenses from Firestore subcollection',
        () {},
        skip: 'Awaiting Plan 04-01: ExpenseService Firestore migration',
      );

      test(
        'filters out soft-deleted expenses (isDeleted=true)',
        () {},
        skip: 'Awaiting Plan 04-01: ExpenseService Firestore migration',
      );
    });

    group('updateExpense', () {
      test(
        'updates expense fields using Firestore update',
        () {},
        skip: 'Awaiting Plan 04-01: ExpenseService Firestore migration',
      );
    });

    group('deleteExpense', () {
      test(
        'uses soft-delete pattern (sets isDeleted=true, deletedAt timestamp)',
        () {},
        skip: 'Awaiting Plan 04-01: ExpenseService Firestore migration',
      );
    });

    group('Expense serialization', () {
      test(
        'fromFirestore and toFirestore round-trip produces equivalent Expense',
        () {},
        skip: 'Awaiting Plan 04-01: ExpenseService Firestore migration',
      );
    });
  });
}
