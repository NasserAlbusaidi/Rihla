import 'package:decimal/decimal.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:safar/features/ledger/models/expense_model.dart';
import 'package:safar/features/ledger/providers/expense_currency_default.dart';

/// #382 PR-6 — the smart-default + dominant pure helpers.
///
/// [defaultExpenseCurrency] = last-used-in-event (greatest createdAt,
/// first-encountered wins on a tie, non-deleted only, empty → groupDefault).
/// [dominantEventCurrency] = mode (highest count, GCC-first tie-break,
/// null iff no non-deleted expenses).
void main() {
  Expense expense({
    required String id,
    required String currency,
    required DateTime createdAt,
    bool isDeleted = false,
  }) {
    return Expense(
      id: id,
      tripId: 'event-1',
      payerParticipantId: 'p1',
      amount: Decimal.fromInt(10),
      scope: ExpenseScope.global,
      createdAt: createdAt,
      currency: currency,
      isDeleted: isDeleted,
    );
  }

  group('defaultExpenseCurrency', () {
    test('empty list → groupDefault', () {
      expect(defaultExpenseCurrency(const [], 'OMR'), 'OMR');
    });

    test('single expense → that expense currency', () {
      final expenses = [
        expense(id: 'e1', currency: 'OMR', createdAt: DateTime(2025, 1, 1)),
      ];
      expect(defaultExpenseCurrency(expenses, 'AED'), 'OMR');
    });

    test('most-recent (greatest createdAt) wins, not most-frequent', () {
      final expenses = [
        expense(id: 'e1', currency: 'OMR', createdAt: DateTime(2025, 1, 1)),
        expense(id: 'e2', currency: 'OMR', createdAt: DateTime(2025, 1, 2)),
        expense(id: 'e3', currency: 'AED', createdAt: DateTime(2025, 1, 3)),
      ];
      expect(defaultExpenseCurrency(expenses, 'GBP'), 'AED');
    });

    test('createdAt tie → first-encountered wins (list order)', () {
      final tie = DateTime(2025, 1, 5);
      final expenses = [
        expense(id: 'e1', currency: 'USD', createdAt: tie),
        expense(id: 'e2', currency: 'EUR', createdAt: tie),
      ];
      expect(defaultExpenseCurrency(expenses, 'OMR'), 'USD');
    });

    test('soft-deleted expenses are excluded', () {
      final expenses = [
        expense(id: 'e1', currency: 'OMR', createdAt: DateTime(2025, 1, 1)),
        expense(
          id: 'e2',
          currency: 'AED',
          createdAt: DateTime(2025, 1, 2),
          isDeleted: true,
        ),
      ];
      expect(defaultExpenseCurrency(expenses, 'GBP'), 'OMR');
    });

    test('all-deleted → groupDefault', () {
      final expenses = [
        expense(
          id: 'e1',
          currency: 'AED',
          createdAt: DateTime(2025, 1, 1),
          isDeleted: true,
        ),
      ];
      expect(defaultExpenseCurrency(expenses, 'OMR'), 'OMR');
    });
  });

  group('dominantEventCurrency', () {
    test('empty list → null', () {
      expect(dominantEventCurrency(const []), isNull);
    });

    test('all-deleted → null', () {
      final expenses = [
        expense(
          id: 'e1',
          currency: 'OMR',
          createdAt: DateTime(2025, 1, 1),
          isDeleted: true,
        ),
      ];
      expect(dominantEventCurrency(expenses), isNull);
    });

    test('single expense → that currency', () {
      final expenses = [
        expense(id: 'e1', currency: 'OMR', createdAt: DateTime(2025, 1, 1)),
      ];
      expect(dominantEventCurrency(expenses), 'OMR');
    });

    test('highest count wins (mode), even if not most-recent', () {
      final expenses = [
        expense(id: 'e1', currency: 'OMR', createdAt: DateTime(2025, 1, 1)),
        expense(id: 'e2', currency: 'OMR', createdAt: DateTime(2025, 1, 2)),
        expense(id: 'e3', currency: 'AED', createdAt: DateTime(2025, 1, 3)),
      ];
      expect(dominantEventCurrency(expenses), 'OMR');
    });

    test('count tie → GCC-first (OMR ranks before AED)', () {
      final expenses = [
        expense(id: 'e1', currency: 'AED', createdAt: DateTime(2025, 1, 1)),
        expense(id: 'e2', currency: 'OMR', createdAt: DateTime(2025, 1, 2)),
      ];
      expect(dominantEventCurrency(expenses), 'OMR');
    });

    test('soft-deleted excluded from the count', () {
      final expenses = [
        expense(id: 'e1', currency: 'AED', createdAt: DateTime(2025, 1, 1)),
        expense(
          id: 'e2',
          currency: 'AED',
          createdAt: DateTime(2025, 1, 2),
          isDeleted: true,
        ),
        expense(id: 'e3', currency: 'OMR', createdAt: DateTime(2025, 1, 3)),
      ];
      // Live: AED×1, OMR×1 → tie → GCC-first → OMR (not AED, which would win
      // if the deleted AED were counted).
      expect(dominantEventCurrency(expenses), 'OMR');
    });
  });
}
