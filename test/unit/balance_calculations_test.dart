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
    bool isDeleted = false,
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
      isDeleted: isDeleted,
    );
  }

  Decimal owedFor(List<UserBalance> balances, String participantId) {
    return balances
        .singleWhere((balance) => balance.participantId == participantId)
        .totalOwed;
  }

  Decimal paidFor(List<UserBalance> balances, String participantId) {
    return balances
        .singleWhere((balance) => balance.participantId == participantId)
        .totalPaid;
  }

  Decimal netFor(List<UserBalance> balances, String participantId) {
    return balances
        .singleWhere((balance) => balance.participantId == participantId)
        .netBalance;
  }

  Settlement settlement({
    required String amount,
    required String payerId,
    required String recipientId,
  }) {
    return Settlement(
      id: 'settlement-$payerId-$recipientId-$amount',
      tripId: 'event-1',
      payerParticipantId: payerId,
      recipientParticipantId: recipientId,
      amount: Decimal.parse(amount),
      settledAt: DateTime(2026),
    );
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
      'exact mode throws on invalid sum instead of silently rewriting to equal split',
      () {
        // Distribution sums to 9 but expense is 10 -- off by more than the
        // tolerance. The editor validates this upstream; if a persisted
        // expense ever diverges, we surface the discrepancy loudly instead
        // of replacing the user's intent with an equal split.
        expect(
          () => BalanceCalculator.calculateBalances(
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
          ),
          throwsStateError,
        );
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

  group('BalanceCalculator settlements', () {
    final participants = [
      participant('p1'),
      participant('p2'),
      participant('p3'),
    ];

    test(
      'totalPaid includes settlement payments made by the participant',
      () {
        // p1 pays a 9.000 expense, global split (each owes 3.000).
        // p2 then settles 3.000 to p1.
        // After fold: paidFor(p1)=9 (received, not paid); paidFor(p2)=3 (paid
        // the settlement); paidFor(p3)=0. netBalance unchanged.
        final balances = BalanceCalculator.calculateBalances(
          expenses: [
            expense(amount: '9.000', splitMode: null, payerId: 'p1'),
          ],
          settlements: [
            settlement(amount: '3.000', payerId: 'p2', recipientId: 'p1'),
          ],
          participants: participants,
        );

        expect(paidFor(balances, 'p1'), Decimal.parse('9.000'));
        expect(paidFor(balances, 'p2'), Decimal.parse('3.000'));
        expect(paidFor(balances, 'p3'), Decimal.zero);

        expect(netFor(balances, 'p1'), Decimal.parse('3.000'));
        expect(netFor(balances, 'p2'), Decimal.zero);
        expect(netFor(balances, 'p3'), Decimal.parse('-3.000'));
      },
    );
  });

  group('BalanceCalculator.calculateOptimalSettlements', () {
    test(
      'equal-balance debtors are matched in deterministic participantId order',
      () {
        // p1 is a creditor (+15); p3, p2, p4 are debtors all at -5.
        // Input order is intentionally non-alphabetical so the test detects
        // any reliance on insertion order. After the tiebreaker fix the first
        // settlement must come from p2 (alphabetically first among equal-
        // balance debtors), not whoever appeared first in the input.
        final balances = [
          UserBalance(
            participantId: 'p1',
            displayName: 'p1',
            totalPaid: Decimal.parse('15'),
            totalOwed: Decimal.zero,
            netBalance: Decimal.parse('15'),
          ),
          UserBalance(
            participantId: 'p3',
            displayName: 'p3',
            totalPaid: Decimal.zero,
            totalOwed: Decimal.parse('5'),
            netBalance: Decimal.parse('-5'),
          ),
          UserBalance(
            participantId: 'p2',
            displayName: 'p2',
            totalPaid: Decimal.zero,
            totalOwed: Decimal.parse('5'),
            netBalance: Decimal.parse('-5'),
          ),
          UserBalance(
            participantId: 'p4',
            displayName: 'p4',
            totalPaid: Decimal.zero,
            totalOwed: Decimal.parse('5'),
            netBalance: Decimal.parse('-5'),
          ),
        ];

        final settlements = BalanceCalculator.calculateOptimalSettlements(
          balances: balances,
        );

        expect(settlements.length, 3);
        expect(settlements[0]['fromUserId'], 'p2');
        expect(settlements[1]['fromUserId'], 'p3');
        expect(settlements[2]['fromUserId'], 'p4');
      },
    );
  });

  group('BalanceCalculator soft-delete', () {
    final participants = [
      participant('p1'),
      participant('p2'),
      participant('p3'),
    ];

    test(
      'isDeleted expenses do not contribute to totalPaid or totalOwed',
      () {
        // One deleted expense (should be ignored) + one live expense
        // (should split equally three ways at 1.000 each).
        final balances = BalanceCalculator.calculateBalances(
          expenses: [
            expense(
              amount: '9.000',
              splitMode: null,
              payerId: 'p1',
              isDeleted: true,
            ),
            expense(
              amount: '3.000',
              splitMode: null,
              payerId: 'p1',
            ),
          ],
          participants: participants,
        );

        expect(paidFor(balances, 'p1'), Decimal.parse('3.000'));
        expect(owedFor(balances, 'p1'), Decimal.parse('1.000'));
        expect(owedFor(balances, 'p2'), Decimal.parse('1.000'));
        expect(owedFor(balances, 'p3'), Decimal.parse('1.000'));
      },
    );
  });
}
