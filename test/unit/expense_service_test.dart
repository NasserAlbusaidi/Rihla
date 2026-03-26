import 'package:decimal/decimal.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:safar/features/ledger/models/expense_model.dart';
import 'package:safar/features/ledger/services/expense_service.dart';

void main() {
  group('ExpenseService (Firestore)', () {
    late FakeFirebaseFirestore fakeDb;
    late ExpenseService service;

    setUp(() {
      fakeDb = FakeFirebaseFirestore();
      service = ExpenseService.withFirestore(fakeDb);
    });

    group('addExpense', () {
      test(
        'writes expense document to groups/{groupId}/events/{eventId}/expenses',
        () async {
          const groupId = 'g1';
          const eventId = 'e1';

          final expense = await service.addExpense(
            groupId: groupId,
            eventId: eventId,
            payerParticipantId: 'p1',
            amount: Decimal.parse('10.500'),
          );

          final snap = await fakeDb
              .collection('groups')
              .doc(groupId)
              .collection('events')
              .doc(eventId)
              .collection('expenses')
              .doc(expense.id)
              .get();

          expect(snap.exists, isTrue);
          expect(snap.data()!['eventId'], equals(eventId));
          expect(snap.data()!['payerParticipantId'], equals('p1'));
          expect(snap.data()!['isDeleted'], isFalse);
        },
      );

      test(
        'uses MoneySerializer.toSubunits to store amountFils',
        () async {
          const groupId = 'g1';
          const eventId = 'e1';

          // OMR 10.500 = 10500 fils (1000 subunits per OMR)
          final expense = await service.addExpense(
            groupId: groupId,
            eventId: eventId,
            payerParticipantId: 'p1',
            amount: Decimal.parse('10.500'),
          );

          final snap = await fakeDb
              .collection('groups')
              .doc(groupId)
              .collection('events')
              .doc(eventId)
              .collection('expenses')
              .doc(expense.id)
              .get();

          expect(snap.data()!['amountFils'], equals(10500));
          expect(snap.data()!['currency'], equals('OMR'));

          // Verify round-trip: amount field on returned Expense
          expect(expense.amount, equals(Decimal.parse('10.500')));
        },
      );
    });

    group('watchExpenses', () {
      test(
        'returns a stream of expenses from Firestore subcollection',
        () async {
          const groupId = 'g1';
          const eventId = 'e1';

          await service.addExpense(
            groupId: groupId,
            eventId: eventId,
            payerParticipantId: 'p1',
            amount: Decimal.parse('5.000'),
            description: 'Lunch',
          );

          final expenses = await service
              .watchExpenses(groupId, eventId)
              .first;

          expect(expenses, hasLength(1));
          expect(expenses.first.description, equals('Lunch'));
          expect(expenses.first.amount, equals(Decimal.parse('5.000')));
        },
      );

      test(
        'filters out soft-deleted expenses (isDeleted=true)',
        () async {
          const groupId = 'g1';
          const eventId = 'e1';

          final expense = await service.addExpense(
            groupId: groupId,
            eventId: eventId,
            payerParticipantId: 'p1',
            amount: Decimal.parse('5.000'),
          );

          await service.deleteExpense(
            groupId: groupId,
            eventId: eventId,
            expenseId: expense.id,
          );

          final expenses = await service
              .watchExpenses(groupId, eventId)
              .first;

          // Soft-deleted expenses filtered by the query (isDeleted=false)
          expect(expenses, isEmpty);
        },
      );
    });

    group('updateExpense', () {
      test(
        'updates expense fields using Firestore update',
        () async {
          const groupId = 'g1';
          const eventId = 'e1';

          final expense = await service.addExpense(
            groupId: groupId,
            eventId: eventId,
            payerParticipantId: 'p1',
            amount: Decimal.parse('5.000'),
            description: 'Old description',
          );

          await service.updateExpense(
            groupId: groupId,
            eventId: eventId,
            expenseId: expense.id,
            description: 'New description',
            amount: Decimal.parse('7.500'),
          );

          final snap = await fakeDb
              .collection('groups')
              .doc(groupId)
              .collection('events')
              .doc(eventId)
              .collection('expenses')
              .doc(expense.id)
              .get();

          expect(snap.data()!['description'], equals('New description'));
          // OMR 7.500 = 7500 fils
          expect(snap.data()!['amountFils'], equals(7500));
        },
      );
    });

    group('deleteExpense', () {
      test(
        'uses soft-delete pattern (sets isDeleted=true, deletedAt timestamp)',
        () async {
          const groupId = 'g1';
          const eventId = 'e1';

          final expense = await service.addExpense(
            groupId: groupId,
            eventId: eventId,
            payerParticipantId: 'p1',
            amount: Decimal.parse('5.000'),
          );

          await service.deleteExpense(
            groupId: groupId,
            eventId: eventId,
            expenseId: expense.id,
          );

          final snap = await fakeDb
              .collection('groups')
              .doc(groupId)
              .collection('events')
              .doc(eventId)
              .collection('expenses')
              .doc(expense.id)
              .get();

          expect(snap.data()!['isDeleted'], isTrue);
          expect(snap.data()!['deletedAt'], isNotNull);
        },
      );
    });

    group('Expense serialization', () {
      test(
        'fromFirestore and toFirestore round-trip produces equivalent Expense',
        () async {
          const groupId = 'g1';
          const eventId = 'e1';

          final original = await service.addExpense(
            groupId: groupId,
            eventId: eventId,
            payerParticipantId: 'p1',
            amount: Decimal.parse('10.500'),
            description: 'Test expense',
            scope: ExpenseScope.global,
          );

          final snap = await fakeDb
              .collection('groups')
              .doc(groupId)
              .collection('events')
              .doc(eventId)
              .collection('expenses')
              .doc(original.id)
              .get();

          final restored = Expense.fromFirestore({
            ...snap.data()!,
            'id': snap.id,
          });

          expect(restored.id, equals(original.id));
          expect(restored.amount, equals(original.amount));
          expect(restored.payerParticipantId, equals(original.payerParticipantId));
          expect(restored.isDeleted, isFalse);
        },
      );
    });
  });
}
