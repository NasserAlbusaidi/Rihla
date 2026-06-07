import 'package:decimal/decimal.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:safar/core/models/split_mode.dart';
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
            createdBy: 'test-uid',
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

      test('uses MoneySerializer.toSubunits to store amountFils', () async {
        const groupId = 'g1';
        const eventId = 'e1';

        // OMR 10.500 = 10500 fils (1000 subunits per OMR)
        final expense = await service.addExpense(
          createdBy: 'test-uid',
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
      });

      test('writes a MONEY activity log when an expense is created', () async {
        const groupId = 'g1';
        const eventId = 'e1';

        final expense = await service.addExpense(
          createdBy: 'test-uid',
          groupId: groupId,
          eventId: eventId,
          payerParticipantId: 'p1',
          actorId: 'user1',
          actorName: 'Alice',
          amount: Decimal.parse('12.345'),
          description: 'Dinner',
        );

        final snap = await fakeDb
            .collection('groups')
            .doc(groupId)
            .collection('events')
            .doc(eventId)
            .collection('activity_logs')
            .get();

        expect(snap.docs, hasLength(1));

        final data = snap.docs.first.data();
        final metadata = data['metadata'] as Map<String, dynamic>;

        expect(data['category'], equals('MONEY'));
        expect(data['eventType'], equals('CREATE'));
        expect(data['actorId'], equals('user1'));
        expect(data['actorName'], equals('Alice'));
        expect(data['eventId'], equals(eventId));
        expect(data['logText'], contains('Alice'));
        expect(data['logText'], contains('Dinner'));
        expect(data['logText'], contains('12.345 OMR'));
        expect(metadata, containsPair('expenseId', expense.id));
        expect(metadata, containsPair('amount', '12.345'));
        expect(metadata, containsPair('currency', 'OMR'));
        expect(metadata, containsPair('payerParticipantId', 'p1'));
      });

      test('rejects an empty createdBy uid before writing', () async {
        await expectLater(
          service.addExpense(
            createdBy: '',
            groupId: 'g1',
            eventId: 'e1',
            payerParticipantId: 'p1',
            amount: Decimal.parse('5.000'),
          ),
          throwsA(isA<ArgumentError>()),
        );

        final snap = await fakeDb
            .collection('groups')
            .doc('g1')
            .collection('events')
            .doc('e1')
            .collection('expenses')
            .get();
        expect(snap.docs, isEmpty);
      });

      test('stamps lastEditedBy = createdBy on create (#248)', () async {
        final expense = await service.addExpense(
          createdBy: 'uidA',
          groupId: 'g1',
          eventId: 'e1',
          payerParticipantId: 'p1',
          amount: Decimal.parse('5.000'),
        );

        final snap = await fakeDb
            .collection('groups')
            .doc('g1')
            .collection('events')
            .doc('e1')
            .collection('expenses')
            .doc(expense.id)
            .get();
        expect(snap.data()!['lastEditedBy'], equals('uidA'));
      });
    });

    group('watchExpenses', () {
      test(
        'returns a stream of expenses from Firestore subcollection',
        () async {
          const groupId = 'g1';
          const eventId = 'e1';

          await service.addExpense(
            createdBy: 'test-uid',
            groupId: groupId,
            eventId: eventId,
            payerParticipantId: 'p1',
            amount: Decimal.parse('5.000'),
            description: 'Lunch',
          );

          final expenses = await service.watchExpenses(groupId, eventId).first;

          expect(expenses, hasLength(1));
          expect(expenses.first.description, equals('Lunch'));
          expect(expenses.first.amount, equals(Decimal.parse('5.000')));
        },
      );

      test('filters out soft-deleted expenses (isDeleted=true)', () async {
        const groupId = 'g1';
        const eventId = 'e1';

        final expense = await service.addExpense(
          createdBy: 'test-uid',
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

        final expenses = await service.watchExpenses(groupId, eventId).first;

        // Soft-deleted expenses filtered by the query (isDeleted=false)
        expect(expenses, isEmpty);
      });
    });

    group('updateExpense', () {
      test('updates expense fields using Firestore update', () async {
        const groupId = 'g1';
        const eventId = 'e1';

        final expense = await service.addExpense(
          createdBy: 'test-uid',
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
      });

      test('updates scope, split, note, category, and payer fields', () async {
        final expense = await service.addExpense(
          createdBy: 'test-uid',
          groupId: 'g1',
          eventId: 'e1',
          payerParticipantId: 'p1',
          amount: Decimal.parse('20.000'),
        );

        await service.updateExpense(
          groupId: 'g1',
          eventId: 'e1',
          expenseId: expense.id,
          scope: ExpenseScope.custom,
          customSplitParticipants: ['p2', 'p3'],
          splitMode: SplitMode.shares,
          splitDistribution: {
            'p2': Decimal.fromInt(2),
            'p3': Decimal.fromInt(1),
          },
          note: 'Paid from shared cash',
          categoryId: 'food',
          payerParticipantId: 'p2',
        );

        final snap = await fakeDb
            .collection('groups')
            .doc('g1')
            .collection('events')
            .doc('e1')
            .collection('expenses')
            .doc(expense.id)
            .get();
        final data = snap.data()!;

        expect(data['scope'], 'custom');
        expect(data['customSplitParticipants'], ['p2', 'p3']);
        expect(data['splitMode'], 'shares');
        expect(data['splitDistribution'], {'p2': 2, 'p3': 1});
        expect(data['note'], 'Paid from shared cash');
        expect(data['categoryId'], 'food');
        expect(data['payerParticipantId'], 'p2');
      });

      test('stamps lastEditedBy when a field changes (#248)', () async {
        final expense = await service.addExpense(
          createdBy: 'uidA',
          groupId: 'g1',
          eventId: 'e1',
          payerParticipantId: 'p1',
          amount: Decimal.parse('5.000'),
        );

        await service.updateExpense(
          groupId: 'g1',
          eventId: 'e1',
          expenseId: expense.id,
          amount: Decimal.parse('9.000'),
          lastEditedBy: 'editorX',
        );

        final snap = await fakeDb
            .collection('groups')
            .doc('g1')
            .collection('events')
            .doc('e1')
            .collection('expenses')
            .doc(expense.id)
            .get();
        expect(snap.data()!['lastEditedBy'], equals('editorX'));
      });

      test(
        'no-op update (no field changes) writes nothing — no lastEditedBy-only write (#248)',
        () async {
          final expense = await service.addExpense(
            createdBy: 'uidA',
            groupId: 'g1',
            eventId: 'e1',
            payerParticipantId: 'p1',
            amount: Decimal.parse('5.000'),
          );
          final ref = fakeDb
              .collection('groups')
              .doc('g1')
              .collection('events')
              .doc('e1')
              .collection('expenses')
              .doc(expense.id);
          final before = (await ref.get()).data();

          await service.updateExpense(
            groupId: 'g1',
            eventId: 'e1',
            expenseId: expense.id,
            lastEditedBy: 'editorX', // all content args null
          );

          final after = (await ref.get()).data();
          expect(after, equals(before)); // unchanged — lastEditedBy stays 'uidA'
          expect(after!['lastEditedBy'], equals('uidA'));
        },
      );

      test('throws when updating a missing expense', () async {
        await expectLater(
          service.updateExpense(
            groupId: 'g1',
            eventId: 'e1',
            expenseId: 'missing-expense',
            description: 'Will fail',
          ),
          throwsA(isA<FirebaseException>()),
        );
      });
    });

    group('deleteExpense', () {
      test(
        'uses soft-delete pattern (sets isDeleted=true, deletedAt timestamp)',
        () async {
          const groupId = 'g1';
          const eventId = 'e1';

          final expense = await service.addExpense(
            createdBy: 'test-uid',
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

      test('stamps lastEditedBy on the soft-delete write (#248)', () async {
        final expense = await service.addExpense(
          createdBy: 'uidA',
          groupId: 'g1',
          eventId: 'e1',
          payerParticipantId: 'p1',
          amount: Decimal.parse('5.000'),
        );

        await service.deleteExpense(
          groupId: 'g1',
          eventId: 'e1',
          expenseId: expense.id,
          lastEditedBy: 'editorX',
        );

        final snap = await fakeDb
            .collection('groups')
            .doc('g1')
            .collection('events')
            .doc('e1')
            .collection('expenses')
            .doc(expense.id)
            .get();
        expect(snap.data()!['isDeleted'], isTrue);
        expect(snap.data()!['lastEditedBy'], equals('editorX'));
      });

      test('throws when deleting a missing expense', () async {
        await expectLater(
          service.deleteExpense(
            groupId: 'g1',
            eventId: 'e1',
            expenseId: 'missing-expense',
          ),
          throwsA(isA<FirebaseException>()),
        );
      });
    });

    // -------------------------------------------------------------------------
    // ARCH-03: server-side range query
    // -------------------------------------------------------------------------

    group('watchExpensesInRange', () {
      test(
        'watchExpensesInRange filters server-side by createdAt: includes expenses in range, excludes before and after',
        () async {
          const groupId = 'g1';
          const eventId = 'e1';

          // Three expenses at different times
          // Past: 2025-01-05 (before start)
          // In-range: 2025-01-08 (within week Mon 6 – Sun 12)
          // Future: 2025-01-15 (after endExclusive)
          final pastTime = DateTime.utc(2025, 1, 5);
          final inRangeTime = DateTime.utc(2025, 1, 8);
          final futureTime = DateTime.utc(2025, 1, 15);

          // Directly insert with custom createdAt to avoid DateTime.now() in addExpense
          Future<void> insertWithTime(String id, DateTime time) async {
            await fakeDb
                .collection('groups')
                .doc(groupId)
                .collection('events')
                .doc(eventId)
                .collection('expenses')
                .doc(id)
                .set({
                  'id': id,
                  'eventId': eventId,
                  'payerParticipantId': 'p1',
                  'amountFils': 5000,
                  'currency': 'OMR',
                  'scope': 'global',
                  'customSplitParticipants': [],
                  'isDeleted': false,
                  'deletedAt': null,
                  'createdAt': time.toIso8601String(),
                });
          }

          await insertWithTime('exp-past', pastTime);
          await insertWithTime('exp-in-range', inRangeTime);
          await insertWithTime('exp-future', futureTime);

          final startUtc = DateTime.utc(2025, 1, 6); // Monday
          final endExclusiveUtc = DateTime.utc(2025, 1, 13); // next Monday

          final results = await service
              .watchExpensesInRange(
                groupId: groupId,
                eventId: eventId,
                startUtc: startUtc,
                endExclusiveUtc: endExclusiveUtc,
              )
              .first;

          expect(results, hasLength(1));
          expect(results.first.id, equals('exp-in-range'));
        },
      );

      test('watchExpensesInRange excludes soft-deleted expenses', () async {
        const groupId = 'g2';
        const eventId = 'e2';

        final inRangeTime = DateTime.utc(2025, 1, 8);

        await fakeDb
            .collection('groups')
            .doc(groupId)
            .collection('events')
            .doc(eventId)
            .collection('expenses')
            .doc('exp-deleted')
            .set({
              'id': 'exp-deleted',
              'eventId': eventId,
              'payerParticipantId': 'p1',
              'amountFils': 3000,
              'currency': 'OMR',
              'scope': 'global',
              'customSplitParticipants': [],
              'isDeleted': true,
              'deletedAt': DateTime.utc(2025, 1, 9).toIso8601String(),
              'createdAt': inRangeTime.toIso8601String(),
            });

        final startUtc = DateTime.utc(2025, 1, 6);
        final endExclusiveUtc = DateTime.utc(2025, 1, 13);

        final results = await service
            .watchExpensesInRange(
              groupId: groupId,
              eventId: eventId,
              startUtc: startUtc,
              endExclusiveUtc: endExclusiveUtc,
            )
            .first;

        expect(results, isEmpty);
      });
    });

    // -------------------------------------------------------------------------

    group('Expense serialization', () {
      test(
        'fromFirestore and toFirestore round-trip produces equivalent Expense',
        () async {
          const groupId = 'g1';
          const eventId = 'e1';

          final original = await service.addExpense(
            createdBy: 'test-uid',
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
          expect(
            restored.payerParticipantId,
            equals(original.payerParticipantId),
          );
          expect(restored.isDeleted, isFalse);
        },
      );

      test('lastEditedBy round-trips through Firestore serialization', () {
        final original = Expense(
          id: 'x1',
          tripId: 'e1',
          payerParticipantId: 'p1',
          amount: Decimal.parse('10.500'),
          scope: ExpenseScope.global,
          createdAt: DateTime.parse('2026-06-07T00:00:00.000Z'),
          createdBy: 'uidA',
          lastEditedBy: 'uidB',
        );
        final map = original.toFirestore();
        expect(map['lastEditedBy'], equals('uidB'));
        final restored = Expense.fromFirestore({...map});
        expect(restored.lastEditedBy, equals('uidB'));
      });

      test('lastEditedBy defaults to empty string for legacy docs', () {
        final restored = Expense.fromFirestore({
          'id': 'x1',
          'eventId': 'e1',
          'payerParticipantId': 'p1',
          'amountFils': 10500,
          'currency': 'OMR',
          'scope': 'global',
          'customSplitParticipants': <String>[],
          'isDeleted': false,
          'createdAt': '2026-06-07T00:00:00.000Z',
          'createdBy': 'uidA',
          // no lastEditedBy — legacy doc
        });
        expect(restored.lastEditedBy, equals(''));
      });
    });

    // -------------------------------------------------------------------------
    // T4.N — split mode + per-participant distribution persistence
    // -------------------------------------------------------------------------

    group('split mode persistence', () {
      Future<Map<String, dynamic>> readDoc(
        String gid,
        String eid,
        String xid,
      ) async {
        final snap = await fakeDb
            .collection('groups')
            .doc(gid)
            .collection('events')
            .doc(eid)
            .collection('expenses')
            .doc(xid)
            .get();
        return snap.data()!;
      }

      test(
        'addExpense writes splitMode + shares distribution for non-equal splits',
        () async {
          const groupId = 'g1';
          const eventId = 'e1';

          final expense = await service.addExpense(
            createdBy: 'test-uid',
            groupId: groupId,
            eventId: eventId,
            payerParticipantId: 'p1',
            amount: Decimal.parse('30.000'),
            splitMode: SplitMode.shares,
            splitDistribution: {
              'p1': Decimal.fromInt(2),
              'p2': Decimal.fromInt(1),
              'p3': Decimal.fromInt(1),
            },
          );

          final data = await readDoc(groupId, eventId, expense.id);
          expect(data['splitMode'], equals('shares'));
          expect(
            data['splitDistribution'],
            equals({'p1': 2, 'p2': 1, 'p3': 1}),
          );
        },
      );

      test('addExpense encodes exact amounts as currency subunits', () async {
        final expense = await service.addExpense(
          createdBy: 'test-uid',
          groupId: 'g1',
          eventId: 'e1',
          payerParticipantId: 'p1',
          amount: Decimal.parse('30.000'),
          splitMode: SplitMode.exact,
          splitDistribution: {
            'p1': Decimal.parse('15.000'),
            'p2': Decimal.parse('10.000'),
            'p3': Decimal.parse('5.000'),
          },
        );

        final data = await readDoc('g1', 'e1', expense.id);
        expect(data['splitMode'], equals('exact'));
        // OMR has 3 decimals so 15.000 → 15000 fils.
        expect(
          data['splitDistribution'],
          equals({'p1': 15000, 'p2': 10000, 'p3': 5000}),
        );
      });

      test('addExpense scales percent values by 1000 for storage', () async {
        final expense = await service.addExpense(
          createdBy: 'test-uid',
          groupId: 'g1',
          eventId: 'e1',
          payerParticipantId: 'p1',
          amount: Decimal.parse('30.000'),
          splitMode: SplitMode.percent,
          splitDistribution: {
            'p1': Decimal.parse('33.333'),
            'p2': Decimal.parse('33.333'),
            'p3': Decimal.parse('33.334'),
          },
        );

        final data = await readDoc('g1', 'e1', expense.id);
        expect(data['splitMode'], equals('percent'));
        expect(
          data['splitDistribution'],
          equals({'p1': 33333, 'p2': 33333, 'p3': 33334}),
        );
      });

      test(
        'addExpense omits splitMode/splitDistribution for equally',
        () async {
          final expense = await service.addExpense(
            createdBy: 'test-uid',
            groupId: 'g1',
            eventId: 'e1',
            payerParticipantId: 'p1',
            amount: Decimal.parse('10.000'),
            splitMode: SplitMode.equally,
          );

          final data = await readDoc('g1', 'e1', expense.id);
          expect(data.containsKey('splitMode'), isFalse);
          expect(data.containsKey('splitDistribution'), isFalse);
        },
      );

      test('updateExpense clearSplit removes both fields', () async {
        final expense = await service.addExpense(
          createdBy: 'test-uid',
          groupId: 'g1',
          eventId: 'e1',
          payerParticipantId: 'p1',
          amount: Decimal.parse('30.000'),
          splitMode: SplitMode.shares,
          splitDistribution: {
            'p1': Decimal.fromInt(2),
            'p2': Decimal.fromInt(1),
          },
        );
        var data = await readDoc('g1', 'e1', expense.id);
        expect(data['splitMode'], equals('shares'));

        await service.updateExpense(
          groupId: 'g1',
          eventId: 'e1',
          expenseId: expense.id,
          clearSplit: true,
        );

        data = await readDoc('g1', 'e1', expense.id);
        expect(data.containsKey('splitMode'), isFalse);
        expect(data.containsKey('splitDistribution'), isFalse);
      });

      test(
        'round-trip: addExpense → fromFirestore restores distribution',
        () async {
          final expense = await service.addExpense(
            createdBy: 'test-uid',
            groupId: 'g1',
            eventId: 'e1',
            payerParticipantId: 'p1',
            amount: Decimal.parse('30.000'),
            splitMode: SplitMode.exact,
            splitDistribution: {
              'p1': Decimal.parse('20.000'),
              'p2': Decimal.parse('10.000'),
            },
          );

          final data = await readDoc('g1', 'e1', expense.id);
          final restored = Expense.fromFirestore({...data, 'id': expense.id});
          expect(restored.splitMode, equals(SplitMode.exact));
          expect(
            restored.splitDistribution!['p1'],
            equals(Decimal.parse('20.000')),
          );
          expect(
            restored.splitDistribution!['p2'],
            equals(Decimal.parse('10.000')),
          );
        },
      );
    });
  });
}
