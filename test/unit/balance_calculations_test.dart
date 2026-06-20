import 'package:decimal/decimal.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:safar/core/models/split_mode.dart';
import 'package:safar/features/ledger/models/expense_model.dart';
import 'package:safar/features/ledger/models/settlement_model.dart';
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
      )['OMR']!;

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
      )['OMR']!;

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
      )['OMR']!;

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
      )['OMR']!;

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
        )['OMR']!;

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
      )['OMR']!;

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
      )['OMR']!;

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
        )['OMR']!;

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
        )['OMR']!;

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
      )['OMR']!;

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
        )['OMR']!;

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
        )['OMR']!;

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
      )['USD']!;

      expect(owedFor(balances, 'p1'), Decimal.parse('3.33'));
      expect(owedFor(balances, 'p2'), Decimal.parse('3.33'));
      expect(owedFor(balances, 'p3'), Decimal.parse('3.34'));
    });

    test('JPY equal split of 1000 across 3 quantizes to 0dp (333/333/334)', () {
      final balances = BalanceCalculator.calculateBalances(
        expenses: [expense(amount: '1000', currency: 'JPY', splitMode: null)],
        participants: participants,
      )['JPY']!;

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
      )['JPY']!;

      expect(owedFor(balances, 'p1'), Decimal.parse('333'));
      expect(owedFor(balances, 'p2'), Decimal.parse('333'));
      expect(owedFor(balances, 'p3'), Decimal.parse('334'));
    });

    test('conservation holds for JPY equal split (sum owed == 1000)', () {
      final balances = BalanceCalculator.calculateBalances(
        expenses: [expense(amount: '1000', currency: 'JPY', splitMode: null)],
        participants: participants,
      )['JPY']!;

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
        )['OMR']!;
      }, returnsNormally);

      // OMR 3dp behaviour preserved for unknown currency: 1.000 / 3.
      expect(owedFor(balances, 'p1'), Decimal.parse('0.333'));
      expect(owedFor(balances, 'p2'), Decimal.parse('0.333'));
      expect(owedFor(balances, 'p3'), Decimal.parse('0.334'));
    });
  });

  group('BalanceCalculator bucketing (#382 PR-1)', () {
    final participants = [
      participant('p1'),
      participant('p2'),
      participant('p3'),
    ];

    Settlement settlement({
      required String amount,
      required String payerId,
      required String recipientId,
      String currency = 'OMR',
    }) {
      return Settlement(
        id: 'settle-$amount-$currency',
        tripId: 'event-1',
        payerParticipantId: payerId,
        recipientParticipantId: recipientId,
        amount: Decimal.parse(amount),
        settledAt: DateTime(2026),
        currency: currency,
      );
    }

    void expectBucketConserved(List<UserBalance> bucket) {
      final sumNet = bucket.fold(Decimal.zero, (sum, b) => sum + b.netBalance);
      expect(sumNet, Decimal.zero, reason: 'bucket must conserve sum(net)==0');
    }

    test('mixed-currency event produces one independent bucket per currency',
        () {
      final buckets = BalanceCalculator.calculateBalances(
        expenses: [
          expense(amount: '30.000', payerId: 'p1', splitMode: null),
          expense(amount: '20.00', currency: 'AED', payerId: 'p2',
              splitMode: null),
        ],
        participants: participants,
      );

      expect(buckets.keys.toSet(), {'OMR', 'AED'});

      // Every participant appears in every bucket, in participants order.
      for (final bucket in buckets.values) {
        expect(
          bucket.map((b) => b.participantId).toList(),
          ['p1', 'p2', 'p3'],
        );
        expectBucketConserved(bucket);
      }

      // OMR bucket: p1 paid 30, all owe 10 each.
      final omr = buckets['OMR']!;
      expect(owedFor(omr, 'p1'), Decimal.parse('10.000'));
      expect(omr.singleWhere((b) => b.participantId == 'p1').netBalance,
          Decimal.parse('20.000'));
      expect(omr.singleWhere((b) => b.participantId == 'p1').totalPaid,
          Decimal.parse('30.000'));

      // AED bucket: p2 paid 20, 6.67/6.67/6.66 split (2dp, remainder to p3).
      final aed = buckets['AED']!;
      expect(aed.singleWhere((b) => b.participantId == 'p2').totalPaid,
          Decimal.parse('20.00'));
      expect(owedFor(aed, 'p1'), Decimal.parse('6.66'));
      expect(owedFor(aed, 'p2'), Decimal.parse('6.66'));
      expect(owedFor(aed, 'p3'), Decimal.parse('6.68'));
      // OMR money never leaks into the AED bucket.
      expect(aed.singleWhere((b) => b.participantId == 'p1').totalPaid,
          Decimal.zero);
    });

    test('per-bucket remainder goes to the alphabetically-last recipient at '
        'that bucket\'s own precision (OMR 3dp vs AED 2dp)', () {
      final buckets = BalanceCalculator.calculateBalances(
        expenses: [
          expense(amount: '1.000', splitMode: null), // OMR 3dp
          expense(amount: '1.00', currency: 'AED', splitMode: null), // 2dp
        ],
        participants: participants,
      );

      final omr = buckets['OMR']!;
      expect(owedFor(omr, 'p1'), Decimal.parse('0.333'));
      expect(owedFor(omr, 'p3'), Decimal.parse('0.334'));

      final aed = buckets['AED']!;
      expect(owedFor(aed, 'p1'), Decimal.parse('0.33'));
      expect(owedFor(aed, 'p3'), Decimal.parse('0.34'));
    });

    test('settlement folds ONLY into its own currency bucket', () {
      final buckets = BalanceCalculator.calculateBalances(
        expenses: [
          expense(amount: '30.000', payerId: 'p1', splitMode: null),
          expense(amount: '20.00', currency: 'AED', payerId: 'p2',
              splitMode: null),
        ],
        settlements: [
          // p3 pays back p2 in AED — must not touch the OMR bucket.
          settlement(
              amount: '6.68', payerId: 'p3', recipientId: 'p2',
              currency: 'AED'),
        ],
        participants: participants,
      );

      final omrP3 = buckets['OMR']!.singleWhere((b) => b.participantId == 'p3');
      expect(omrP3.netBalance, Decimal.parse('-10.000'),
          reason: 'AED settlement must not adjust the OMR bucket');

      final aedP3 = buckets['AED']!.singleWhere((b) => b.participantId == 'p3');
      expect(aedP3.netBalance, Decimal.zero,
          reason: 'p3 settled the AED debt in AED');
      expectBucketConserved(buckets['AED']!);
      expectBucketConserved(buckets['OMR']!);
    });

    test('a settlement in a currency with no expenses creates its own bucket',
        () {
      final buckets = BalanceCalculator.calculateBalances(
        expenses: const [],
        settlements: [
          settlement(
              amount: '5.00', payerId: 'p1', recipientId: 'p2',
              currency: 'USD'),
        ],
        participants: participants,
      );

      expect(buckets.keys.toSet(), {'USD'});
      final usd = buckets['USD']!;
      expect(usd.singleWhere((b) => b.participantId == 'p1').netBalance,
          Decimal.parse('5.00'));
      expect(usd.singleWhere((b) => b.participantId == 'p2').netBalance,
          Decimal.parse('-5.00'));
      expectBucketConserved(usd);
    });

    test('unsupported settlement currency is fenced into the OMR bucket', () {
      final buckets = BalanceCalculator.calculateBalances(
        expenses: [expense(amount: '3.000', payerId: 'p1', splitMode: null)],
        settlements: [
          settlement(
              amount: '1.000', payerId: 'p2', recipientId: 'p1',
              currency: 'XYZ'),
        ],
        participants: participants,
      );

      expect(buckets.keys.toSet(), {'OMR'},
          reason: 'XYZ fences to OMR — no garbage bucket key');
      final p2 = buckets['OMR']!.singleWhere((b) => b.participantId == 'p2');
      // owed 1.000 from the split, paid back 1.000 via the fenced settlement.
      expect(p2.netBalance, Decimal.zero);
    });

    test('no money records → empty map (no buckets)', () {
      final buckets = BalanceCalculator.calculateBalances(
        expenses: const [],
        participants: participants,
      );
      expect(buckets, isEmpty);
    });

    test('single-currency result is element-for-element the pre-flip list', () {
      final buckets = BalanceCalculator.calculateBalances(
        expenses: [
          expense(amount: '9.000', payerId: 'p2', splitMode: null),
        ],
        participants: participants,
      );

      expect(buckets.keys.toList(), ['OMR']);
      final bucket = buckets['OMR']!;
      expect(bucket.map((b) => b.participantId).toList(), ['p1', 'p2', 'p3']);
      expect(bucket[0].totalPaid, Decimal.zero);
      expect(bucket[0].totalOwed, Decimal.parse('3.000'));
      expect(bucket[0].netBalance, Decimal.parse('-3.000'));
      expect(bucket[1].totalPaid, Decimal.parse('9.000'));
      expect(bucket[1].netBalance, Decimal.parse('6.000'));
      expect(bucket[0].displayName, 'p1');
    });

    test('calculateTotalExpensesByCurrency buckets by fenced currency', () {
      final totals = BalanceCalculator.calculateTotalExpensesByCurrency([
        expense(amount: '10.000', splitMode: null),
        expense(amount: '2.500', splitMode: null),
        expense(amount: '7.00', currency: 'AED', splitMode: null),
        expense(amount: '1.000', currency: 'XYZ', splitMode: null), // fenced
      ]);

      expect(totals.keys.toSet(), {'OMR', 'AED'});
      expect(totals['OMR'], Decimal.parse('13.500'));
      expect(totals['AED'], Decimal.parse('7.00'));
    });

    test('calculateTotalExpensesByCurrency returns empty map for no expenses',
        () {
      expect(BalanceCalculator.calculateTotalExpensesByCurrency(const []),
          isEmpty);
    });
  });

  group('BalanceCalculator terminating sub-subunit equal split (#596)', () {
    // 2.900 OMR / 8 = 0.3625 terminates below baisa precision. Pre-#596 the
    // client _allocateEqual kept the raw half-baisa (0.3625) for every head:
    //  - diverged from the server quantize (0.362 ×7, last 0.366), breaking the
    //    cross-impl oracle parity;
    //  - left netBalance non-whole-subunit (e.g. 7.1335), which mis-fired the
    //    settle-up cap and split the home(#366 aggregate) vs settle-up(client)
    //    display. Conservation-only checks pass with half-baisa shares
    //    (0.3625 × 8 == 2.900), which is why this slipped through.
    const eight = ['a', 'b', 'c', 'd', 'e', 'f', 'g', 'h'];

    List<UserBalance> balancesFor() => BalanceCalculator.calculateBalances(
          expenses: [
            expense(amount: '2.900', payerId: 'a', splitMode: SplitMode.equally),
          ],
          participants: [for (final id in eight) participant(id)],
        )['OMR']!;

    test('per-head owed is whole-baisa, matching the server (0.362 ×7, '
        'last 0.366)', () {
      final balances = balancesFor();
      for (final id in const ['a', 'b', 'c', 'd', 'e', 'f', 'g']) {
        expect(owedFor(balances, id), Decimal.parse('0.362'));
      }
      expect(owedFor(balances, 'h'), Decimal.parse('0.366'));
    });

    test('every net is a whole number of baisa (no half-baisa residue)', () {
      for (final b in balancesFor()) {
        final subunits = b.netBalance * Decimal.fromInt(1000);
        expect(
          subunits.isInteger,
          isTrue,
          reason: '${b.participantId} net ${b.netBalance} is not whole-baisa',
        );
      }
    });

    test('conservation holds (sum owed == 2.900, sum net == 0)', () {
      final balances = balancesFor();
      expect(balances.fold(Decimal.zero, (s, b) => s + b.totalOwed),
          Decimal.parse('2.900'));
      expect(balances.fold(Decimal.zero, (s, b) => s + b.netBalance),
          Decimal.zero);
    });
  });
}
