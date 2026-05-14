import 'package:decimal/decimal.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:safar/features/ledger/models/expense_model.dart';
import 'package:safar/features/ledger/models/settlement_model.dart';

void main() {
  group('Expense model serialization', () {
    test('fromJson reads legacy joined category and payer profile data', () {
      final expense = Expense.fromJson({
        'id': 'exp-1',
        'trip_id': 'event-1',
        'payer_id': 'payer-legacy',
        'amount': '12.345',
        'description': 'Dinner',
        'scope': 'custom',
        'sub_group_id': 'sub-1',
        'custom_split_participants': ['p1', 'p2'],
        'receipt_url': 'receipts/event-1/exp-1/r.png',
        'created_at': '2026-05-01T10:00:00.000Z',
        'category_id': 'cat-food',
        'note': 'Paid by card',
        'expense_categories': {'name': 'Food', 'icon': 'food'},
        'participants': {
          'profiles': {
            'display_name': 'Nasser',
            'avatar_url': 'https://example.test/a.png',
          },
        },
        'is_deleted': true,
        'deleted_at': '2026-05-02T10:00:00.000Z',
      });

      expect(expense.id, 'exp-1');
      expect(expense.tripId, 'event-1');
      expect(expense.payerParticipantId, 'payer-legacy');
      expect(expense.amount, Decimal.parse('12.345'));
      expect(expense.scope, ExpenseScope.custom);
      expect(expense.subGroupId, 'sub-1');
      expect(expense.customSplitParticipants, ['p1', 'p2']);
      expect(expense.receiptPath, 'receipts/event-1/exp-1/r.png');
      expect(expense.categoryName, 'Food');
      expect(expense.categoryIcon, 'food');
      expect(expense.payerName, 'Nasser');
      expect(expense.payerAvatarUrl, 'https://example.test/a.png');
      expect(expense.isDeleted, isTrue);
      expect(expense.deletedAt, DateTime.parse('2026-05-02T10:00:00.000Z'));
    });

    test(
      'fromJson prefers direct payer display name over profile fallback',
      () {
        final expense = Expense.fromJson({
          'id': 'exp-2',
          'trip_id': 'event-1',
          'payer_participant_id': 'payer-1',
          'amount': 3.5,
          'created_at': '2026-05-01T10:00:00.000Z',
          'participants': {
            'display_name': 'Direct Name',
            'profiles': {'display_name': 'Profile Name'},
          },
        });

        expect(expense.scope, ExpenseScope.global);
        expect(expense.payerName, 'Direct Name');
        expect(expense.customSplitParticipants, isNull);
        expect(expense.isDeleted, isFalse);
        expect(expense.deletedAt, isNull);
      },
    );

    test(
      'toJson writes legacy cache fields and excludes joined display data',
      () {
        final expense = Expense(
          id: 'exp-3',
          tripId: 'event-1',
          payerParticipantId: 'payer-1',
          amount: Decimal.parse('9.500'),
          description: 'Taxi',
          scope: ExpenseScope.subGroup,
          subGroupId: 'sub-1',
          customSplitParticipants: const ['p1', 'p2'],
          receiptUrl: 'receipts/r.png',
          createdAt: DateTime.utc(2026, 5, 1),
          categoryId: 'cat-transport',
          note: 'Airport',
          categoryName: 'Transport',
          payerName: 'Joined Name',
        );

        expect(expense.toJson(), {
          'trip_id': 'event-1',
          'payer_participant_id': 'payer-1',
          'amount': '9.5',
          'description': 'Taxi',
          'scope': 'sub_group',
          'sub_group_id': 'sub-1',
          'custom_split_participants': ['p1', 'p2'],
          'receipt_url': 'receipts/r.png',
          'category_id': 'cat-transport',
          'note': 'Airport',
        });
      },
    );

    test('fromFirestore handles defaults, soft delete, and custom splits', () {
      final expense = Expense.fromFirestore({
        'id': 'exp-4',
        'eventId': 'event-1',
        'payerParticipantId': 'payer-1',
        'amountFils': 1500,
        'description': 'Coffee',
        'scope': 'custom',
        'customSplitParticipants': ['p1', 'p2'],
        'createdAt': '2026-05-01T10:00:00.000Z',
        'isDeleted': true,
        'deletedAt': '2026-05-02T10:00:00.000Z',
      });

      expect(expense.currency, 'OMR');
      expect(expense.amount, Decimal.parse('1.500'));
      expect(expense.scope, ExpenseScope.custom);
      expect(expense.customSplitParticipants, ['p1', 'p2']);
      expect(expense.isDeleted, isTrue);
      expect(expense.deletedAt, DateTime.parse('2026-05-02T10:00:00.000Z'));
    });

    test(
      'copyWith updates every mutable field and preserves unspecified values',
      () {
        final original = Expense(
          id: 'exp-5',
          tripId: 'event-1',
          payerParticipantId: 'payer-1',
          amount: Decimal.parse('1.000'),
          scope: ExpenseScope.global,
          createdAt: DateTime.utc(2026, 5, 1),
        );

        final copy = original.copyWith(
          id: 'exp-6',
          tripId: 'event-2',
          payerParticipantId: 'payer-2',
          amount: Decimal.parse('2.000'),
          currency: 'USD',
          description: 'Updated',
          scope: ExpenseScope.personal,
          subGroupId: 'sub-2',
          customSplitParticipants: const ['p3'],
          receiptUrl: 'receipts/new.png',
          createdAt: DateTime.utc(2026, 5, 2),
          categoryId: 'cat-1',
          note: 'note',
          categoryName: 'Category',
          categoryIcon: 'food',
          payerName: 'Payer',
          payerAvatarUrl: 'https://example.test/p.png',
          isDeleted: true,
          deletedAt: DateTime.utc(2026, 5, 3),
        );

        expect(copy.id, 'exp-6');
        expect(copy.tripId, 'event-2');
        expect(copy.payerParticipantId, 'payer-2');
        expect(copy.amount, Decimal.parse('2.000'));
        expect(copy.currency, 'USD');
        expect(copy.description, 'Updated');
        expect(copy.scope, ExpenseScope.personal);
        expect(copy.subGroupId, 'sub-2');
        expect(copy.customSplitParticipants, ['p3']);
        expect(copy.receiptUrl, 'receipts/new.png');
        expect(copy.createdAt, DateTime.utc(2026, 5, 2));
        expect(copy.categoryId, 'cat-1');
        expect(copy.note, 'note');
        expect(copy.categoryName, 'Category');
        expect(copy.categoryIcon, 'food');
        expect(copy.payerName, 'Payer');
        expect(copy.payerAvatarUrl, 'https://example.test/p.png');
        expect(copy.isDeleted, isTrue);
        expect(copy.deletedAt, DateTime.utc(2026, 5, 3));

        expect(original.copyWith().currency, 'OMR');
      },
    );
  });

  group('ExpenseScope and UserBalance', () {
    test(
      'ExpenseScope.fromString maps supported scopes and defaults global',
      () {
        expect(ExpenseScope.fromString('global'), ExpenseScope.global);
        expect(ExpenseScope.fromString('sub_group'), ExpenseScope.subGroup);
        expect(ExpenseScope.fromString('personal'), ExpenseScope.personal);
        expect(ExpenseScope.fromString('custom'), ExpenseScope.custom);
        expect(ExpenseScope.fromString('unknown'), ExpenseScope.global);
      },
    );

    test(
      'UserBalance state helpers classify owed, owing, and settled states',
      () {
        final owed = UserBalance(
          participantId: 'p1',
          displayName: 'Owed',
          totalPaid: Decimal.parse('10'),
          totalOwed: Decimal.parse('4'),
          netBalance: Decimal.parse('6'),
        );
        final owes = UserBalance(
          participantId: 'p2',
          totalPaid: Decimal.parse('2'),
          totalOwed: Decimal.parse('5'),
          netBalance: Decimal.parse('-3'),
        );
        final settled = UserBalance(
          participantId: 'p3',
          totalPaid: Decimal.parse('1.000'),
          totalOwed: Decimal.parse('1.000'),
          netBalance: Decimal.parse('0.0005'),
        );

        expect(owed.isOwedMoney, isTrue);
        expect(owed.owesMoney, isFalse);
        expect(owes.owesMoney, isTrue);
        expect(owes.isOwedMoney, isFalse);
        expect(settled.isSettled, isTrue);
      },
    );
  });

  group('Settlement model serialization', () {
    test('fromJson reads legacy participant joins and soft delete fields', () {
      final settlement = Settlement.fromJson({
        'id': 'settle-1',
        'trip_id': 'event-1',
        'payer_id': 'payer-legacy',
        'recipient_id': 'recipient-legacy',
        'amount': '4.250',
        'note': 'Cash',
        'settled_at': '2026-05-01T11:00:00.000Z',
        'payer_participant': {
          'profiles': {'display_name': 'Payer Profile'},
        },
        'recipient_participant': {
          'display_name': 'Recipient Direct',
          'profiles': {'display_name': 'Recipient Profile'},
        },
        'is_deleted': true,
        'deleted_at': '2026-05-02T11:00:00.000Z',
      });

      expect(settlement.payerParticipantId, 'payer-legacy');
      expect(settlement.recipientParticipantId, 'recipient-legacy');
      expect(settlement.amount, Decimal.parse('4.250'));
      expect(settlement.payerName, 'Payer Profile');
      expect(settlement.recipientName, 'Recipient Direct');
      expect(settlement.isDeleted, isTrue);
      expect(settlement.deletedAt, DateTime.parse('2026-05-02T11:00:00.000Z'));
    });

    test('toJson writes event settlement cache fields', () {
      final settlement = Settlement(
        id: 'settle-2',
        tripId: 'event-1',
        payerParticipantId: 'payer-1',
        recipientParticipantId: 'recipient-1',
        amount: Decimal.parse('3.000'),
        note: 'Bank transfer',
        settledAt: DateTime.utc(2026, 5, 1, 12),
      );

      expect(settlement.toJson(), {
        'trip_id': 'event-1',
        'payer_participant_id': 'payer-1',
        'recipient_participant_id': 'recipient-1',
        'amount': '3',
        'note': 'Bank transfer',
        'settled_at': '2026-05-01T12:00:00.000Z',
      });
    });

    test('fromFirestore falls back to groupId when eventId is absent', () {
      final settlement = Settlement.fromFirestore({
        'id': 'settle-3',
        'groupId': 'group-1',
        'scope': 'group',
        'payerParticipantId': 'payer-1',
        'recipientParticipantId': 'recipient-1',
        'amountFils': 750,
        'currency': 'OMR',
        'note': 'Group settle',
        'settledAt': '2026-05-01T12:00:00.000Z',
        'payerName': 'Payer',
        'recipientName': 'Recipient',
      });

      expect(settlement.tripId, 'group-1');
      expect(settlement.groupId, 'group-1');
      expect(settlement.scope, 'group');
      expect(settlement.amount, Decimal.parse('0.750'));
      expect(settlement.payerName, 'Payer');
      expect(settlement.recipientName, 'Recipient');
      expect(settlement.isDeleted, isFalse);
    });

    test('toFirestore writes OMR subunits and scope fields', () {
      final settlement = Settlement(
        id: 'settle-4',
        tripId: 'event-1',
        payerParticipantId: 'payer-1',
        recipientParticipantId: 'recipient-1',
        amount: Decimal.parse('8.125'),
        note: 'Done',
        settledAt: DateTime.utc(2026, 5, 1, 12),
        isDeleted: true,
        deletedAt: DateTime.utc(2026, 5, 2, 12),
        scope: 'event',
      );

      expect(settlement.toFirestore(), {
        'id': 'settle-4',
        'eventId': 'event-1',
        'payerParticipantId': 'payer-1',
        'recipientParticipantId': 'recipient-1',
        'amountFils': 8125,
        'currency': 'OMR',
        'note': 'Done',
        'settledAt': '2026-05-01T12:00:00.000Z',
        'isDeleted': true,
        'deletedAt': '2026-05-02T12:00:00.000Z',
        'scope': 'event',
        'groupId': null,
        'createdBy': '',
      });
    });
  });
}
