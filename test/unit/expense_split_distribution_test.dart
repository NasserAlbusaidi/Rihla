import 'package:decimal/decimal.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:safar/core/models/split_mode.dart';
import 'package:safar/features/ledger/models/expense_model.dart';

void main() {
  Expense buildExpense({
    required SplitMode splitMode,
    required Map<String, Decimal> splitDistribution,
  }) {
    return Expense(
      id: 'expense-${splitMode.storageKey}',
      tripId: 'event-1',
      payerParticipantId: 'p1',
      amount: Decimal.parse('10.000'),
      scope: ExpenseScope.global,
      splitMode: splitMode,
      splitDistribution: splitDistribution,
      createdAt: DateTime.utc(2026, 5, 13, 10),
    );
  }

  Map<String, Decimal> distributionFor(SplitMode mode) => switch (mode) {
    SplitMode.shares => {
      'p1': Decimal.fromInt(1),
      'p2': Decimal.fromInt(2),
      'p3': Decimal.fromInt(3),
    },
    SplitMode.exact => {
      'p1': Decimal.parse('2.250'),
      'p2': Decimal.parse('3.750'),
      'p3': Decimal.parse('4.000'),
    },
    SplitMode.percent => {
      'p1': Decimal.parse('25.000'),
      'p2': Decimal.parse('25.000'),
      'p3': Decimal.parse('50.000'),
    },
    SplitMode.equally => {'p1': Decimal.fromInt(1), 'p2': Decimal.fromInt(1)},
  };

  Map<String, int> persistedDistributionFor(SplitMode mode) => switch (mode) {
    SplitMode.shares => {'p1': 1, 'p2': 2, 'p3': 3},
    SplitMode.exact => {'p1': 2250, 'p2': 3750, 'p3': 4000},
    SplitMode.percent => {'p1': 25000, 'p2': 25000, 'p3': 50000},
    SplitMode.equally => {'p1': 1, 'p2': 1},
  };

  group('Expense split distribution persistence', () {
    for (final mode in [SplitMode.shares, SplitMode.exact, SplitMode.percent]) {
      test('toFirestore/fromFirestore round-trips ${mode.storageKey}', () {
        final expense = buildExpense(
          splitMode: mode,
          splitDistribution: distributionFor(mode),
        );

        final firestore = expense.toFirestore();

        expect(firestore['splitMode'], mode.storageKey);
        expect(firestore['splitDistribution'], persistedDistributionFor(mode));

        final roundTrip = Expense.fromFirestore(firestore);
        expect(roundTrip.splitMode, mode);
        expect(roundTrip.splitDistribution, distributionFor(mode));
      });

      test('toJson/fromJson round-trips ${mode.storageKey}', () {
        final expense = buildExpense(
          splitMode: mode,
          splitDistribution: distributionFor(mode),
        );

        final json = expense.toJson();

        expect(json['split_mode'], mode.storageKey);
        expect(json['split_distribution'], persistedDistributionFor(mode));

        final roundTrip = Expense.fromJson({
          'id': expense.id,
          'created_at': expense.createdAt.toIso8601String(),
          ...json,
        });
        expect(roundTrip.splitMode, mode);
        expect(roundTrip.splitDistribution, distributionFor(mode));
      });
    }

    test('copyWith preserves, updates, and clears split fields', () {
      final original = buildExpense(
        splitMode: SplitMode.shares,
        splitDistribution: distributionFor(SplitMode.shares),
      );

      final preserved = original.copyWith(description: 'Taxi');
      expect(preserved.splitMode, SplitMode.shares);
      expect(preserved.splitDistribution, distributionFor(SplitMode.shares));

      final updated = original.copyWith(
        splitMode: SplitMode.exact,
        splitDistribution: distributionFor(SplitMode.exact),
      );
      expect(updated.splitMode, SplitMode.exact);
      expect(updated.splitDistribution, distributionFor(SplitMode.exact));

      final cleared = updated.copyWith(clearSplit: true);
      expect(cleared.splitMode, isNull);
      expect(cleared.splitDistribution, isNull);
    });
  });
}
