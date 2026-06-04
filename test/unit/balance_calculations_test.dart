import 'package:decimal/decimal.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:safar/core/models/split_mode.dart';
import 'package:safar/features/ledger/models/expense_model.dart';
import 'package:safar/features/ledger/providers/expense_provider.dart';
import 'package:safar/features/trip/models/trip_model.dart';

void main() {
  Participant participant(String id) => Participant(
    id: id,
    tripId: 'event-1',
    role: ParticipantRole.member,
    joinedAt: DateTime(2026),
    displayName: id,
  );

  Expense expense({
    required String amount,
    required SplitMode? splitMode,
    Map<String, Decimal>? splitDistribution,
    String payerId = 'p1',
    ExpenseScope scope = ExpenseScope.global,
    List<String>? customSplitParticipants,
    String currency = 'OMR',
  }) {
    return Expense(
      id: 'expense-$amount-${splitMode?.storageKey ?? 'legacy'}',
      tripId: 'event-1',
      payerParticipantId: payerId,
      amount: Decimal.parse(amount),
      scope: scope,
      customSplitParticipants: customSplitParticipants,
      splitMode: splitMode,
      splitDistribution: splitDistribution,
      createdAt: DateTime(2026),
      currency: currency,
    );
  }

  Decimal owedFor(List<UserBalance> balances, String participantId) {
    return balances
        .singleWhere((balance) => balance.participantId == participantId)
        .totalOwed;
  }

  group('BalanceCalculator splitDistribution', () {
    final participants = [
      participant('p1'),
      participant('p2'),
      participant('p3'),
    ];

    test('legacy null mode keeps existing equal split by scope', () {
      final balances = BalanceCalculator.calculateBalances(
        expenses: [
          expense(
            amount: '9.000',
            splitMode: null,
            scope: ExpenseScope.custom,
            customSplitParticipants: ['p1', 'p3'],
          ),
        ],
        participants: participants,
      );

      expect(owedFor(balances, 'p1'), Decimal.parse('4.500'));
      expect(owedFor(balances, 'p2'), Decimal.zero);
      expect(owedFor(balances, 'p3'), Decimal.parse('4.500'));
    });

    test('shares mode splits by share ratio', () {
      final balances = BalanceCalculator.calculateBalances(
        expenses: [
          expense(
            amount: '12.000',
            splitMode: SplitMode.shares,
            splitDistribution: {
              'p1': Decimal.fromInt(1),
              'p2': Decimal.fromInt(2),
              'p3': Decimal.fromInt(3),
            },
          ),
        ],
        participants: participants,
      );

      expect(owedFor(balances, 'p1'), Decimal.parse('2.000'));
      expect(owedFor(balances, 'p2'), Decimal.parse('4.000'));
      expect(owedFor(balances, 'p3'), Decimal.parse('6.000'));
    });

    test('shares mode assigns rounding remainder to the last sorted pid', () {
      final balances = BalanceCalculator.calculateBalances(
        expenses: [
          expense(
            amount: '1.000',
            splitMode: SplitMode.shares,
            splitDistribution: {
              'p2': Decimal.fromInt(1),
              'p3': Decimal.fromInt(1),
              'p1': Decimal.fromInt(1),
            },
          ),
        ],
        participants: participants,
      );

      expect(owedFor(balances, 'p1'), Decimal.parse('0.333'));
      expect(owedFor(balances, 'p2'), Decimal.parse('0.333'));
      expect(owedFor(balances, 'p3'), Decimal.parse('0.334'));
    });

    test('exact mode uses validated per-pid amounts', () {
      final balances = BalanceCalculator.calculateBalances(
        expenses: [
          expense(
            amount: '10.000',
            splitMode: SplitMode.exact,
            splitDistribution: {
              'p1': Decimal.parse('2.250'),
              'p2': Decimal.parse('3.750'),
              'p3': Decimal.parse('4.000'),
            },
          ),
        ],
        participants: participants,
      );

      expect(owedFor(balances, 'p1'), Decimal.parse('2.250'));
      expect(owedFor(balances, 'p2'), Decimal.parse('3.750'));
      expect(owedFor(balances, 'p3'), Decimal.parse('4.000'));
    });

    test(
      'exact mode falls back to equal split across distribution keys on invalid sum',
      () {
        final balances = BalanceCalculator.calculateBalances(
          expenses: [
            expense(
              amount: '10.000',
              splitMode: SplitMode.exact,
              splitDistribution: {
                'p1': Decimal.parse('3.000'),
                'p2': Decimal.parse('3.000'),
                'p3': Decimal.parse('3.000'),
              },
            ),
          ],
          participants: participants,
        );

        expect(owedFor(balances, 'p1'), Decimal.parse('3.333'));
        expect(owedFor(balances, 'p2'), Decimal.parse('3.333'));
        expect(owedFor(balances, 'p3'), Decimal.parse('3.334'));
      },
    );

    test('percent mode splits by validated percentages', () {
      final balances = BalanceCalculator.calculateBalances(
        expenses: [
          expense(
            amount: '10.000',
            splitMode: SplitMode.percent,
            splitDistribution: {
              'p1': Decimal.parse('25.000'),
              'p2': Decimal.parse('25.000'),
              'p3': Decimal.parse('50.000'),
            },
          ),
        ],
        participants: participants,
      );

      expect(owedFor(balances, 'p1'), Decimal.parse('2.500'));
      expect(owedFor(balances, 'p2'), Decimal.parse('2.500'));
      expect(owedFor(balances, 'p3'), Decimal.parse('5.000'));
    });

    test('percent mode assigns rounding remainder to the last sorted pid', () {
      final balances = BalanceCalculator.calculateBalances(
        expenses: [
          expense(
            amount: '1.000',
            splitMode: SplitMode.percent,
            splitDistribution: {
              'p2': Decimal.parse('33.333'),
              'p3': Decimal.parse('33.334'),
              'p1': Decimal.parse('33.333'),
            },
          ),
        ],
        participants: participants,
      );

      expect(owedFor(balances, 'p1'), Decimal.parse('0.333'));
      expect(owedFor(balances, 'p2'), Decimal.parse('0.333'));
      expect(owedFor(balances, 'p3'), Decimal.parse('0.334'));
    });

    test(
      'percent mode falls back to equal split across distribution keys on invalid sum',
      () {
        final balances = BalanceCalculator.calculateBalances(
          expenses: [
            expense(
              amount: '9.000',
              splitMode: SplitMode.percent,
              splitDistribution: {
                'p1': Decimal.parse('25.000'),
                'p2': Decimal.parse('25.000'),
              },
            ),
          ],
          participants: participants,
        );

        expect(owedFor(balances, 'p1'), Decimal.parse('4.500'));
        expect(owedFor(balances, 'p2'), Decimal.parse('4.500'));
        expect(owedFor(balances, 'p3'), Decimal.zero);
      },
    );
  });

  group('BalanceCalculator negative-entry guard (#192 / #220)', () {
    final participants = [
      participant('p1'),
      participant('p2'),
      participant('p3'),
    ];

    Decimal netFor(List<UserBalance> balances, String id) =>
        balances.singleWhere((b) => b.participantId == id).netBalance;

    void expectNoNegativeOwed(List<UserBalance> balances) {
      for (final b in balances) {
        expect(
          b.totalOwed >= Decimal.zero,
          isTrue,
          reason: '${b.participantId} owed ${b.totalOwed} (< 0)',
        );
      }
    }

    void expectConserved(List<UserBalance> balances) {
      final sumNet = balances.fold(
        Decimal.zero,
        (sum, b) => sum + b.netBalance,
      );
      expect(sumNet, Decimal.zero);
    }

    test(
      'shares mode with a negative entry (positive total) falls back to equal split',
      () {
        // {5, -2, 1} sums to 4 > 0, so the totalShares<=0 guard does NOT fire —
        // only the new per-entry sign guard catches it. Weighted allocation
        // would otherwise hand p2 a negative owed.
        final balances = BalanceCalculator.calculateBalances(
          expenses: [
            expense(
              amount: '9.000',
              splitMode: SplitMode.shares,
              splitDistribution: {
                'p1': Decimal.fromInt(5),
                'p2': Decimal.fromInt(-2),
                'p3': Decimal.fromInt(1),
              },
            ),
          ],
          participants: participants,
        );

        expect(owedFor(balances, 'p1'), Decimal.parse('3.000'));
        expect(owedFor(balances, 'p2'), Decimal.parse('3.000'));
        expect(owedFor(balances, 'p3'), Decimal.parse('3.000'));
        expectNoNegativeOwed(balances);
        expectConserved(balances);
      },
    );

    test('shares mode with a zero entry stays valid (zero is not negative)', () {
      // Regression fence: the new guard rejects < 0, NOT <= 0. A 0 share is a
      // legitimate "owes nothing" and must keep the weighted split.
      final balances = BalanceCalculator.calculateBalances(
        expenses: [
          expense(
            amount: '9.000',
            splitMode: SplitMode.shares,
            splitDistribution: {
              'p1': Decimal.fromInt(2),
              'p2': Decimal.zero,
              'p3': Decimal.fromInt(1),
            },
          ),
        ],
        participants: participants,
      );

      expect(owedFor(balances, 'p1'), Decimal.parse('6.000'));
      expect(owedFor(balances, 'p2'), Decimal.zero);
      expect(owedFor(balances, 'p3'), Decimal.parse('3.000'));
    });

    test(
      'percent mode with a negative entry (summing to 100) falls back to equal split',
      () {
        // {150, -50} sums to 100 so the tolerance guard passes — only the new
        // per-entry sign guard catches it.
        final balances = BalanceCalculator.calculateBalances(
          expenses: [
            expense(
              amount: '10.000',
              splitMode: SplitMode.percent,
              splitDistribution: {
                'p1': Decimal.parse('150.000'),
                'p2': Decimal.parse('-50.000'),
              },
            ),
          ],
          participants: participants,
        );

        expect(owedFor(balances, 'p1'), Decimal.parse('5.000'));
        expect(owedFor(balances, 'p2'), Decimal.parse('5.000'));
        expect(owedFor(balances, 'p3'), Decimal.zero);
        expectNoNegativeOwed(balances);
      },
    );

    test(
      'adversarial (identity axis): payer is also a recipient with a negative share',
      () {
        // Orthogonal-axis check: a negative entry on the PAYER, exercising the
        // settlement-free money flow. Conservation must still hold and no one
        // may carry a negative owed.
        final balances = BalanceCalculator.calculateBalances(
          expenses: [
            expense(
              amount: '6.000',
              payerId: 'p1',
              splitMode: SplitMode.shares,
              splitDistribution: {
                'p1': Decimal.fromInt(-3),
                'p2': Decimal.fromInt(1),
              },
            ),
          ],
          participants: participants,
        );

        expect(owedFor(balances, 'p1'), Decimal.parse('3.000'));
        expect(owedFor(balances, 'p2'), Decimal.parse('3.000'));
        expect(netFor(balances, 'p1'), Decimal.parse('3.000'));
        expect(netFor(balances, 'p2'), Decimal.parse('-3.000'));
        expectNoNegativeOwed(balances);
        expectConserved(balances);
      },
    );
  });

  group('BalanceCalculator currency-aware precision (Issue #47)', () {
    final participants = [
      participant('p1'),
      participant('p2'),
      participant('p3'),
    ];

    test('USD shares 1:1:1 of 10.00 quantizes to USD 2dp (3.33/3.33/3.34)', () {
      final balances = BalanceCalculator.calculateBalances(
        expenses: [
          expense(
            amount: '10.00',
            currency: 'USD',
            splitMode: SplitMode.shares,
            splitDistribution: {
              'p1': Decimal.fromInt(1),
              'p2': Decimal.fromInt(1),
              'p3': Decimal.fromInt(1),
            },
          ),
        ],
        participants: participants,
      );

      expect(owedFor(balances, 'p1'), Decimal.parse('3.33'));
      expect(owedFor(balances, 'p2'), Decimal.parse('3.33'));
      expect(owedFor(balances, 'p3'), Decimal.parse('3.34'));
    });

    test('JPY equal split of 1000 across 3 quantizes to 0dp (333/333/334)', () {
      final balances = BalanceCalculator.calculateBalances(
        expenses: [expense(amount: '1000', currency: 'JPY', splitMode: null)],
        participants: participants,
      );

      expect(owedFor(balances, 'p1'), Decimal.parse('333'));
      expect(owedFor(balances, 'p2'), Decimal.parse('333'));
      expect(owedFor(balances, 'p3'), Decimal.parse('334'));
    });

    test('JPY exact split with invalid sum falls back to equal at 0dp', () {
      // 333+333+333 = 999 != 1000 (> tolerance) → equal-split fallback.
      final balances = BalanceCalculator.calculateBalances(
        expenses: [
          expense(
            amount: '1000',
            currency: 'JPY',
            splitMode: SplitMode.exact,
            splitDistribution: {
              'p1': Decimal.fromInt(333),
              'p2': Decimal.fromInt(333),
              'p3': Decimal.fromInt(333),
            },
          ),
        ],
        participants: participants,
      );

      expect(owedFor(balances, 'p1'), Decimal.parse('333'));
      expect(owedFor(balances, 'p2'), Decimal.parse('333'));
      expect(owedFor(balances, 'p3'), Decimal.parse('334'));
    });

    test('conservation holds for JPY equal split (sum owed == 1000)', () {
      final balances = BalanceCalculator.calculateBalances(
        expenses: [expense(amount: '1000', currency: 'JPY', splitMode: null)],
        participants: participants,
      );

      final totalOwed = balances.fold(
        Decimal.zero,
        (sum, b) => sum + b.totalOwed,
      );
      expect(totalOwed, Decimal.parse('1000'));
    });

    test('unsupported currency falls back to OMR precision without throwing', () {
      late final List<UserBalance> balances;
      expect(() {
        balances = BalanceCalculator.calculateBalances(
          expenses: [
            expense(amount: '1.000', currency: 'XYZ', splitMode: null),
          ],
          participants: participants,
        );
      }, returnsNormally);

      // OMR 3dp behaviour preserved for unknown currency: 1.000 / 3.
      expect(owedFor(balances, 'p1'), Decimal.parse('0.333'));
      expect(owedFor(balances, 'p2'), Decimal.parse('0.333'));
      expect(owedFor(balances, 'p3'), Decimal.parse('0.334'));
    });
  });
}
