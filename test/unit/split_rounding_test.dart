import 'package:decimal/decimal.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:safar/features/ledger/models/expense_model.dart';
import 'package:safar/features/ledger/providers/expense_provider.dart';
import 'package:safar/features/trip/models/trip_model.dart';

/// Tests for remainder-safe split rounding in BalanceCalculator.
///
/// The invariant: sum(shares) == expense.amount for all splits.
/// Without remainder correction, OMR 3-decimal truncation creates money loss.
void main() {
  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

  Participant participant(String id) => Participant(
    id: id,
    tripId: 'trip-1',
    role: ParticipantRole.member,
    joinedAt: DateTime(2026),
  );

  Expense globalExpense(String amount, List<String> allParticipantIds) =>
      Expense(
        id: 'e-${amount.replaceAll('.', '')}',
        tripId: 'trip-1',
        payerParticipantId: allParticipantIds.first,
        amount: Decimal.parse(amount),
        scope: ExpenseScope.global,
        createdAt: DateTime(2026),
      );

  Expense customExpense(String amount, String payerId, List<String> splitIds) =>
      Expense(
        id: 'e-custom',
        tripId: 'trip-1',
        payerParticipantId: payerId,
        amount: Decimal.parse(amount),
        scope: ExpenseScope.custom,
        customSplitParticipants: splitIds,
        createdAt: DateTime(2026),
      );

  // ---------------------------------------------------------------------------
  // Split rounding invariant tests
  // ---------------------------------------------------------------------------

  group('BalanceCalculator — split rounding invariant', () {
    test('10.000 OMR split 3 ways: sum of owedMap equals 10.000', () {
      final participants = [
        participant('p1'),
        participant('p2'),
        participant('p3'),
      ];
      final expense = globalExpense('10.000', ['p1', 'p2', 'p3']);

      final balances = BalanceCalculator.calculateBalances(
        expenses: [expense],
        participants: participants,
      )['OMR']!;

      // Payer paid 10.000; everyone owes some share
      final totalOwed = balances.fold(
        Decimal.zero,
        (sum, b) => sum + b.totalOwed,
      );
      expect(
        totalOwed,
        Decimal.parse('10.000'),
        reason: '10.000 / 3 = 3.333 repeated — sum must still be 10.000',
      );
    });

    test('1.000 OMR split 3 ways: sum of owedMap equals 1.000', () {
      final participants = [
        participant('p1'),
        participant('p2'),
        participant('p3'),
      ];
      final expense = globalExpense('1.000', ['p1', 'p2', 'p3']);

      final balances = BalanceCalculator.calculateBalances(
        expenses: [expense],
        participants: participants,
      )['OMR']!;

      final totalOwed = balances.fold(
        Decimal.zero,
        (sum, b) => sum + b.totalOwed,
      );
      expect(
        totalOwed,
        Decimal.parse('1.000'),
        reason:
            '1.000 / 3 = 0.333 truncated × 3 = 0.999 — remainder 0.001 lost without fix',
      );
    });

    test(
      '9.000 OMR split 2 ways: sum of owedMap equals 9.000 (even split)',
      () {
        final participants = [participant('p1'), participant('p2')];
        final expense = globalExpense('9.000', ['p1', 'p2']);

        final balances = BalanceCalculator.calculateBalances(
          expenses: [expense],
          participants: participants,
        )['OMR']!;

        final totalOwed = balances.fold(
          Decimal.zero,
          (sum, b) => sum + b.totalOwed,
        );
        expect(
          totalOwed,
          Decimal.parse('9.000'),
          reason: 'Even split should have zero remainder',
        );
      },
    );

    test('7.001 OMR split 3 ways: sum of owedMap equals 7.001', () {
      final participants = [
        participant('p1'),
        participant('p2'),
        participant('p3'),
      ];
      final expense = globalExpense('7.001', ['p1', 'p2', 'p3']);

      final balances = BalanceCalculator.calculateBalances(
        expenses: [expense],
        participants: participants,
      )['OMR']!;

      final totalOwed = balances.fold(
        Decimal.zero,
        (sum, b) => sum + b.totalOwed,
      );
      expect(
        totalOwed,
        Decimal.parse('7.001'),
        reason:
            '7.001 / 3 = 2.333 truncated × 3 = 6.999 — remainder 0.002 must be assigned',
      );
    });

    test('Custom scope: 5.000 split 3 ways sums to 5.000', () {
      final participants = [
        participant('p1'),
        participant('p2'),
        participant('p3'),
      ];
      // p1 pays, p1+p2+p3 split (custom)
      final expense = customExpense('5.000', 'p1', ['p1', 'p2', 'p3']);

      final balances = BalanceCalculator.calculateBalances(
        expenses: [expense],
        participants: participants,
      )['OMR']!;

      final totalOwed = balances.fold(
        Decimal.zero,
        (sum, b) => sum + b.totalOwed,
      );
      expect(totalOwed, Decimal.parse('5.000'));
    });
  });

  // ---------------------------------------------------------------------------
  // Expense.currency field tests
  // ---------------------------------------------------------------------------

  group('Expense.currency — reads from Firestore data', () {
    test('fromFirestore: currency field is preserved from data', () {
      final data = {
        'id': 'exp-1',
        'eventId': 'event-1',
        'payerParticipantId': 'p1',
        'amountFils': 10000,
        'currency': 'USD',
        'scope': 'global',
        'customSplitParticipants': [],
        'isDeleted': false,
        'createdAt': '2026-01-01T00:00:00.000Z',
      };
      final expense = Expense.fromFirestore(data);
      expect(expense.currency, 'USD');
    });

    test('fromFirestore: defaults to OMR when currency absent', () {
      final data = {
        'id': 'exp-2',
        'eventId': 'event-1',
        'payerParticipantId': 'p1',
        'amountFils': 5000,
        'scope': 'global',
        'customSplitParticipants': [],
        'isDeleted': false,
        'createdAt': '2026-01-01T00:00:00.000Z',
      };
      final expense = Expense.fromFirestore(data);
      expect(expense.currency, 'OMR');
    });

    test('copyWith: currency is preserved after copy', () {
      final data = {
        'id': 'exp-3',
        'eventId': 'event-1',
        'payerParticipantId': 'p1',
        'amountFils': 10000,
        'currency': 'EUR',
        'scope': 'global',
        'customSplitParticipants': [],
        'isDeleted': false,
        'createdAt': '2026-01-01T00:00:00.000Z',
      };
      final original = Expense.fromFirestore(data);
      final copy = original.copyWith(description: 'Updated');
      expect(
        copy.currency,
        'EUR',
        reason: 'copyWith must not lose the currency field',
      );
    });

    test('toFirestore: currency round-trips correctly', () {
      final data = {
        'id': 'exp-4',
        'eventId': 'event-1',
        'payerParticipantId': 'p1',
        'amountFils': 10000,
        'currency': 'SAR',
        'scope': 'global',
        'customSplitParticipants': [],
        'isDeleted': false,
        'createdAt': '2026-01-01T00:00:00.000Z',
      };
      final expense = Expense.fromFirestore(data);
      final serialized = expense.toFirestore();
      expect(serialized['currency'], 'SAR');
    });
  });
}
