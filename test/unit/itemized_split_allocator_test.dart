import 'package:decimal/decimal.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:safar/core/models/split_mode.dart';
import 'package:safar/features/ledger/models/expense_model.dart';
import 'package:safar/features/ledger/models/split_explanation.dart';
import 'package:safar/features/ledger/providers/expense_provider.dart';

Decimal _d(String s) => Decimal.parse(s);

void main() {
  group('allocateItemizedDistribution', () {
    test('coffee case: each item solo-assigned; a non-buyer is absent (owes 0)', () {
      final dist = BalanceCalculator.allocateItemizedDistribution(
        items: const [
          SplitItem(label: 'Latte', amountFils: 1500, participantIds: ['p1']),
          SplitItem(label: 'Mocha', amountFils: 2000, participantIds: ['p2']),
        ],
        currency: 'OMR',
      );
      expect(dist['p1'], _d('1.500'));
      expect(dist['p2'], _d('2.000'));
      expect(dist.containsKey('p3'), isFalse); // non-buyer absent → owes 0.000
      expect(dist.values.fold(Decimal.zero, (s, v) => s + v), _d('3.500'));
    });

    test('shared item OMR 3dp: 1.000/3 → remainder on alphabetically-last', () {
      final dist = BalanceCalculator.allocateItemizedDistribution(
        items: const [
          // deliberately out-of-order ids to prove sort-by-id, not insertion order
          SplitItem(label: 'Pizza', amountFils: 1000, participantIds: ['p3', 'p1', 'p2']),
        ],
        currency: 'OMR',
      );
      expect(dist['p1'], _d('0.333'));
      expect(dist['p2'], _d('0.333'));
      expect(dist['p3'], _d('0.334')); // alphabetically-last absorbs +1 baisa
      expect(dist.values.fold(Decimal.zero, (s, v) => s + v), _d('1.000'));
      for (final v in dist.values) {
        expect((v * Decimal.fromInt(1000)).isInteger, isTrue); // whole-subunit (#596)
      }
    });

    test('multi-item accumulation across items', () {
      final dist = BalanceCalculator.allocateItemizedDistribution(
        items: const [
          SplitItem(label: 'Starter', amountFils: 500, participantIds: ['p1']),
          SplitItem(label: 'Shared', amountFils: 1000, participantIds: ['p1', 'p2']),
        ],
        currency: 'OMR',
      );
      expect(dist['p1'], _d('1.000')); // 0.500 solo + 0.500 share
      expect(dist['p2'], _d('0.500'));
      expect(dist.values.fold(Decimal.zero, (s, v) => s + v), _d('1.500'));
    });

    test('USD 2dp scale: 10.00/3 shared → 3.33/3.33/3.34', () {
      final dist = BalanceCalculator.allocateItemizedDistribution(
        items: const [
          SplitItem(label: 'Tab', amountFils: 1000, participantIds: ['a', 'b', 'c']),
        ],
        currency: 'USD',
      );
      expect(dist['a'], _d('3.33'));
      expect(dist['c'], _d('3.34'));
      expect(dist.values.fold(Decimal.zero, (s, v) => s + v), _d('10.00'));
    });

    test('JPY ×1 scale: 1000/3 shared → 333/333/334', () {
      final dist = BalanceCalculator.allocateItemizedDistribution(
        items: const [
          SplitItem(label: 'Set', amountFils: 1000, participantIds: ['a', 'b', 'c']),
        ],
        currency: 'JPY',
      );
      expect(dist['a'], _d('333'));
      expect(dist['c'], _d('334'));
      expect(dist.values.fold(Decimal.zero, (s, v) => s + v), _d('1000'));
    });

    test('duplicate assignees dedupe (no over-division)', () {
      final dist = BalanceCalculator.allocateItemizedDistribution(
        items: const [
          SplitItem(label: 'Dup', amountFils: 1000, participantIds: ['p1', 'p1', 'p2']),
        ],
        currency: 'OMR',
      );
      expect(dist['p1'], _d('0.500'));
      expect(dist['p2'], _d('0.500'));
    });

    test('throws on a zero-assignee item (its cost must land somewhere)', () {
      expect(
        () => BalanceCalculator.allocateItemizedDistribution(
          items: const [SplitItem(label: 'Orphan', amountFils: 900, participantIds: [])],
          currency: 'OMR',
        ),
        throwsArgumentError,
      );
    });

    test('throws on negative amountFils (producer never emits a negative owed)', () {
      expect(
        () => BalanceCalculator.allocateItemizedDistribution(
          items: const [SplitItem(label: 'Bad', amountFils: -300, participantIds: ['p1', 'p2'])],
          currency: 'OMR',
        ),
        throwsArgumentError,
      );
    });

    test('empty items → empty distribution (conservation trivial)', () {
      final dist = BalanceCalculator.allocateItemizedDistribution(
        items: const [],
        currency: 'OMR',
      );
      expect(dist, isEmpty);
    });

    test('conservation contract: Σ distribution == Σ item amountFils (the persisted amount)', () {
      const items = [
        SplitItem(label: 'A', amountFils: 1500, participantIds: ['p1']),
        SplitItem(label: 'B', amountFils: 1000, participantIds: ['p1', 'p2', 'p3']),
        SplitItem(label: 'C', amountFils: 333, participantIds: ['p2', 'p3']),
      ];
      final dist = BalanceCalculator.allocateItemizedDistribution(items: items, currency: 'OMR');
      final sumItemsFils = items.fold<int>(0, (s, i) => s + i.amountFils);
      expect(sumItemsFils, 2833);
      expect(dist.values.fold(Decimal.zero, (s, v) => s + v), _d('2.833'));
    });

    test('round-trips byte-clean through the persisted exact read-back path', () {
      final dist = BalanceCalculator.allocateItemizedDistribution(
        items: const [
          SplitItem(label: 'X', amountFils: 1000, participantIds: ['p1', 'p2', 'p3']),
        ],
        currency: 'OMR',
      );
      final owed = BalanceCalculator.allocateExpenseOwed(
        amount: _d('1.000'),
        splitMode: SplitMode.exact,
        splitDistribution: dist,
        scope: ExpenseScope.global,
        customSplitParticipants: null,
        payerId: 'p1',
        participantIds: const ['p1', 'p2', 'p3'],
        currency: 'OMR',
      );
      expect(owed, dist); // exact read-back, residual 0, no mutation
    });
  });
}
