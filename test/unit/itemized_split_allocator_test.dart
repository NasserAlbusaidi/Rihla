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

  group('allocateItemizedDistribution + adjustments (#605)', () {
    Decimal sum(Map<String, Decimal> m) =>
        m.values.fold(Decimal.zero, (s, v) => s + v);

    test('approved scenario: service+tax+tip all equal (OMR) → each +1.000', () {
      final dist = BalanceCalculator.allocateItemizedDistribution(
        items: const [
          SplitItem(
            label: 'Mixed grill',
            amountFils: 8000,
            participantIds: ['hessa', 'khalid', 'nasser', 'sara'],
          ),
          SplitItem(label: 'Pasta', amountFils: 4000, participantIds: ['sara']),
          SplitItem(label: 'Steak', amountFils: 6000, participantIds: ['khalid']),
          SplitItem(label: 'Salad', amountFils: 2000, participantIds: ['hessa']),
        ],
        currency: 'OMR',
        adjustments: const [
          SplitAdjustment(type: 'service', amountFils: 2000, allocation: 'equal'),
          SplitAdjustment(type: 'tax', amountFils: 1000, allocation: 'equal'),
          SplitAdjustment(type: 'tip', amountFils: 1000, allocation: 'equal'),
        ],
        participantIds: const ['nasser', 'sara', 'khalid', 'hessa'],
      );
      expect(dist['nasser'], _d('3.000'));
      expect(dist['sara'], _d('7.000'));
      expect(dist['khalid'], _d('9.000'));
      expect(dist['hessa'], _d('5.000'));
      expect(sum(dist), _d('24.000'));
    });

    test('additive proportional: service by item share', () {
      final dist = BalanceCalculator.allocateItemizedDistribution(
        items: const [
          SplitItem(label: 'Cheap', amountFils: 5000, participantIds: ['a']),
          SplitItem(label: 'Pricey', amountFils: 15000, participantIds: ['b']),
        ],
        currency: 'OMR',
        adjustments: const [
          SplitAdjustment(
            type: 'service',
            amountFils: 4000,
            allocation: 'proportional',
          ),
        ],
        participantIds: const ['a', 'b'],
      );
      expect(dist['a'], _d('6.000')); // 5 + 1
      expect(dist['b'], _d('18.000')); // 15 + 3
      expect(sum(dist), _d('24.000'));
    });

    test('equal across whole table incl. zero-item person', () {
      final dist = BalanceCalculator.allocateItemizedDistribution(
        items: const [
          SplitItem(label: 'Solo', amountFils: 10000, participantIds: ['a']),
        ],
        currency: 'OMR',
        adjustments: const [
          SplitAdjustment(type: 'tax', amountFils: 1000, allocation: 'equal'),
        ],
        participantIds: const ['a', 'b'],
      );
      expect(dist['a'], _d('10.500'));
      expect(dist['b'], _d('0.500')); // owes tax despite no item
      expect(sum(dist), _d('11.000'));
    });

    test('discount re-allocates the remaining bill proportionally (non-negative)', () {
      final dist = BalanceCalculator.allocateItemizedDistribution(
        items: const [
          SplitItem(label: 'Cheap', amountFils: 5000, participantIds: ['a']),
          SplitItem(label: 'Pricey', amountFils: 15000, participantIds: ['b']),
        ],
        currency: 'OMR',
        adjustments: const [
          SplitAdjustment(
            type: 'service',
            amountFils: 4000,
            allocation: 'proportional',
          ),
          SplitAdjustment(
            type: 'discount',
            amountFils: 6000,
            allocation: 'proportional',
          ),
        ],
        participantIds: const ['a', 'b'],
      );
      expect(dist['a'], _d('4.500'));
      expect(dist['b'], _d('13.500'));
      expect(sum(dist), _d('18.000'));
    });

    test('negative-edge: {1,1,1} JPY − discount 2 → {0,0,1}, never negative', () {
      final dist = BalanceCalculator.allocateItemizedDistribution(
        items: const [
          SplitItem(label: 'x', amountFils: 1, participantIds: ['a']),
          SplitItem(label: 'y', amountFils: 1, participantIds: ['b']),
          SplitItem(label: 'z', amountFils: 1, participantIds: ['c']),
        ],
        currency: 'JPY',
        adjustments: const [
          SplitAdjustment(
            type: 'discount',
            amountFils: 2,
            allocation: 'proportional',
          ),
        ],
        participantIds: const ['a', 'b', 'c'],
      );
      expect(dist['a'], _d('0'));
      expect(dist['b'], _d('0'));
      expect(dist['c'], _d('1')); // alphabetically-last positive-weight absorbs remainder
      expect(sum(dist), _d('1'));
      for (final v in dist.values) {
        expect(v >= Decimal.zero, isTrue);
      }
    });

    test(
      'discount remainder can exceed pre-discount owed (#1203, pins the '
      'exceeds case — the JPY negative-edge test above only covers the '
      'EQUALS case)',
      () {
        final dist = BalanceCalculator.allocateItemizedDistribution(
          items: const [
            SplitItem(label: 'x', amountFils: 10, participantIds: ['A']),
            SplitItem(label: 'y', amountFils: 10, participantIds: ['B']),
            SplitItem(label: 'z', amountFils: 1, participantIds: ['Z']),
          ],
          currency: 'OMR',
          adjustments: const [
            SplitAdjustment(
              type: 'discount',
              amountFils: 1,
              allocation: 'proportional',
            ),
          ],
          participantIds: const ['A', 'B', 'Z'],
        );
        // preDiscount {A:0.010, B:0.010, Z:0.001}; discount 0.001; remaining
        // 0.020 truncates A/B to 0.009 each and drops the 2-fil remainder on
        // Z (alphabetically-last positive-weight) — Z's owed rises from
        // 0.001 to 0.002, ABOVE its pre-discount owed. Non-negativity and
        // conservation still hold; only the false "never exceeds
        // pre-discount" comment is wrong.
        expect(dist['A'], _d('0.009'));
        expect(dist['B'], _d('0.009'));
        expect(dist['Z'], _d('0.002'));
        expect(sum(dist), _d('0.020'));
        for (final v in dist.values) {
          expect(v >= Decimal.zero, isTrue);
        }
      },
    );

    test('equal additive on a zero-item person, THEN discount (conserves, ≥0)', () {
      final dist = BalanceCalculator.allocateItemizedDistribution(
        items: const [
          SplitItem(label: 'Solo', amountFils: 10000, participantIds: ['a']),
        ],
        currency: 'OMR',
        adjustments: const [
          SplitAdjustment(type: 'service', amountFils: 1000, allocation: 'equal'),
          SplitAdjustment(
            type: 'discount',
            amountFils: 2000,
            allocation: 'proportional',
          ),
        ],
        participantIds: const ['a', 'b'],
      );
      expect(dist['a'], _d('8.590'));
      expect(dist['b'], _d('0.410'));
      expect(sum(dist), _d('9.000'));
    });

    test('JPY ×1 additive equal', () {
      final dist = BalanceCalculator.allocateItemizedDistribution(
        items: const [
          SplitItem(label: 'A', amountFils: 100, participantIds: ['a']),
          SplitItem(label: 'B', amountFils: 300, participantIds: ['b']),
        ],
        currency: 'JPY',
        adjustments: const [
          SplitAdjustment(type: 'tip', amountFils: 100, allocation: 'equal'),
        ],
        participantIds: const ['a', 'b'],
      );
      expect(dist['a'], _d('150'));
      expect(dist['b'], _d('350'));
      expect(sum(dist), _d('500'));
    });

    test('empty adjustments → byte-identical to no-adjustments (participantIds ignored)', () {
      const items = [
        SplitItem(label: 'Shared', amountFils: 1000, participantIds: ['p1', 'p2', 'p3']),
      ];
      final withEmpty = BalanceCalculator.allocateItemizedDistribution(
        items: items,
        currency: 'OMR',
        adjustments: const [],
      );
      final without = BalanceCalculator.allocateItemizedDistribution(
        items: items,
        currency: 'OMR',
      );
      expect(withEmpty, without);
    });

    test('additive proportional with empty items → equal over whole table (amount not dropped)', () {
      final dist = BalanceCalculator.allocateItemizedDistribution(
        items: const [],
        currency: 'OMR',
        adjustments: const [
          SplitAdjustment(
            type: 'service',
            amountFils: 1000,
            allocation: 'proportional',
          ),
        ],
        participantIds: const ['a', 'b'],
      );
      expect(dist['a'], _d('0.500'));
      expect(dist['b'], _d('0.500'));
      expect(sum(dist), _d('1.000'));
    });

    test('throws: discount exceeds pre-discount (remaining < 0)', () {
      expect(
        () => BalanceCalculator.allocateItemizedDistribution(
          items: const [
            SplitItem(label: 'I', amountFils: 1000, participantIds: ['a']),
          ],
          currency: 'OMR',
          adjustments: const [
            SplitAdjustment(
              type: 'discount',
              amountFils: 5000,
              allocation: 'proportional',
            ),
          ],
          participantIds: const ['a', 'b'],
        ),
        throwsArgumentError,
      );
    });

    test('throws: unknown adjustment type', () {
      expect(
        () => BalanceCalculator.allocateItemizedDistribution(
          items: const [
            SplitItem(label: 'I', amountFils: 1000, participantIds: ['a']),
          ],
          currency: 'OMR',
          adjustments: const [
            SplitAdjustment(type: 'gratuity', amountFils: 500, allocation: 'equal'),
          ],
          participantIds: const ['a', 'b'],
        ),
        throwsArgumentError,
      );
    });

    test('throws: negative adjustment amount', () {
      expect(
        () => BalanceCalculator.allocateItemizedDistribution(
          items: const [
            SplitItem(label: 'I', amountFils: 1000, participantIds: ['a']),
          ],
          currency: 'OMR',
          adjustments: const [
            SplitAdjustment(type: 'service', amountFils: -500, allocation: 'equal'),
          ],
          participantIds: const ['a', 'b'],
        ),
        throwsArgumentError,
      );
    });

    test('throws: adjustments present but participantIds empty (whole-table required)', () {
      expect(
        () => BalanceCalculator.allocateItemizedDistribution(
          items: const [
            SplitItem(label: 'I', amountFils: 1000, participantIds: ['a']),
          ],
          currency: 'OMR',
          adjustments: const [
            SplitAdjustment(type: 'service', amountFils: 500, allocation: 'equal'),
          ],
        ),
        throwsArgumentError,
      );
    });

    test('folded dist decodes byte-clean through the exact read-back (zero-item bearer kept)', () {
      final dist = BalanceCalculator.allocateItemizedDistribution(
        items: const [
          SplitItem(label: 'Solo', amountFils: 10000, participantIds: ['a']),
        ],
        currency: 'OMR',
        adjustments: const [
          SplitAdjustment(type: 'tax', amountFils: 1000, allocation: 'equal'),
        ],
        participantIds: const ['a', 'b'],
      );
      final owed = BalanceCalculator.allocateExpenseOwed(
        amount: _d('11.000'),
        splitMode: SplitMode.exact,
        splitDistribution: dist,
        scope: ExpenseScope.custom,
        customSplitParticipants: const ['a', 'b'],
        payerId: 'a',
        participantIds: const ['a', 'b'],
        currency: 'OMR',
      );
      expect(owed, dist); // b (zero-item, tax-bearer) survives the read-back
    });
  });

  // #1206 — _spreadProportional int-multiply overflow guard. The private helper
  // is exercised through the PUBLIC Phase-3 discount reallocation. Pre-fix, the
  // native `amount * weight` overflows int64 (~9.22e18) whenever both factors are
  // ~3.1e9 subunits, silently wrapping to a grossly mis-proportioned share; the
  // remainder line still forces conservation and the values stay non-negative, so
  // ONLY the exact per-key-share assertion catches the wrap (the load-bearing RED).
  group('_spreadProportional int64 overflow (#1206)', () {
    // Each row: description, items, discount fils, expected per-key OMR shares.
    // 'A' < 'B', so the alphabetically-last key ('B') absorbs the +1 remainder.
    final cases = <({
      String name,
      List<SplitItem> items,
      int discountFils,
      Map<String, String> expected,
    })>[
      // OVERFLOW: remaining = 6_199_999_999, weight = 3_100_000_000 →
      // remaining * weight ≈ 1.92e19 wraps int64 pre-fix. Correct floor shares:
      // A = 3_099_999_999 fils, B = 3_100_000_000 fils (B absorbs the +1 residual).
      (
        name: 'two ~3.1e9-fils items + 1-fil discount wraps int64 pre-fix',
        items: const [
          SplitItem(
              label: 'BigA', amountFils: 3100000000, participantIds: ['A']),
          SplitItem(
              label: 'BigB', amountFils: 3100000000, participantIds: ['B']),
        ],
        discountFils: 1,
        expected: {'A': '3099999.999', 'B': '3100000.000'},
      ),
      // BOUNDARY (non-overflow): remaining = 2_000_000_000, max weight
      // 2_000_000_000 → product 4e18 < 2^63, so pre-fix and post-fix are
      // byte-identical. Pins that the BigInt widening leaves safe inputs unchanged.
      (
        name: 'large-but-safe product (4e18 < 2^63) is unchanged',
        items: const [
          SplitItem(
              label: 'A', amountFils: 2000000000, participantIds: ['A']),
          SplitItem(
              label: 'B', amountFils: 1000000000, participantIds: ['B']),
        ],
        discountFils: 1000000000,
        expected: {'A': '1333333.333', 'B': '666666.667'},
      ),
    ];

    for (final c in cases) {
      test(c.name, () {
        final dist = BalanceCalculator.allocateItemizedDistribution(
          items: c.items,
          currency: 'OMR',
          adjustments: [
            SplitAdjustment(type: 'discount', amountFils: c.discountFils),
          ],
          participantIds: const ['A', 'B'],
        );

        // Load-bearing: exact per-key shares. The wrapped pre-fix output still
        // conserves and is non-negative, so these are the ONLY assertions that go
        // red before the fix.
        for (final entry in c.expected.entries) {
          expect(dist[entry.key], _d(entry.value),
              reason: 'share for ${entry.key} in "${c.name}"');
        }

        // Conservation and non-negativity (green pre- AND post-fix; sanity only).
        final sum = dist.values.fold(Decimal.zero, (s, v) => s + v);
        final expectedSum = c.expected.values.fold(
            Decimal.zero, (s, v) => s + _d(v));
        expect(sum, expectedSum, reason: 'conservation for "${c.name}"');
        for (final v in dist.values) {
          expect(v >= Decimal.zero, isTrue,
              reason: 'non-negative for "${c.name}"');
        }
      });
    }
  });
}
