import 'package:decimal/decimal.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:safar/features/ledger/models/expense_model.dart';
import 'package:safar/features/ledger/models/settlement_model.dart';
import 'package:safar/features/ledger/providers/expense_provider.dart';
import 'package:safar/features/trip/models/trip_model.dart';
import 'package:safar/features/logistics/models/sub_group_model.dart';

void main() {
  group('BalanceCalculator Tests', () {
    final participants = [
      Participant(
        id: 'p1',
        tripId: 't1',
        role: ParticipantRole.leader,
        joinedAt: DateTime.now(),
        displayName: 'User 1',
      ),
      Participant(
        id: 'p2',
        tripId: 't1',
        role: ParticipantRole.member,
        joinedAt: DateTime.now(),
        displayName: 'User 2',
      ),
      Participant(
        id: 'p3',
        tripId: 't1',
        role: ParticipantRole.member,
        joinedAt: DateTime.now(),
        displayName: 'User 3',
      ),
    ];

    test('Global Split: 3 people share 30 OMR equally', () {
      final expenses = [
        Expense(
          id: 'e1',
          tripId: 't1',
          payerParticipantId: 'p1',
          amount: Decimal.parse('30.0'),
          scope: ExpenseScope.global,
          createdAt: DateTime.now(),
        ),
      ];

      final balances = BalanceCalculator.calculateBalances(
        expenses: expenses,
        participants: participants,
      );

      final b1 = balances.firstWhere((b) => b.participantId == 'p1');
      final b2 = balances.firstWhere((b) => b.participantId == 'p2');
      final b3 = balances.firstWhere((b) => b.participantId == 'p3');

      // Total paid: p1=30, p2=0, p3=0
      // Total owed: p1=10, p2=10, p3=10
      // Net: p1=+20, p2=-10, p3=-10
      expect(b1.totalPaid, Decimal.parse('30.0'));
      expect(b1.totalOwed, Decimal.parse('10.0'));
      expect(b1.netBalance, Decimal.parse('20.0'));

      expect(b2.totalPaid, Decimal.zero);
      expect(b2.totalOwed, Decimal.parse('10.0'));
      expect(b2.netBalance, Decimal.parse('-10.0'));

      expect(b3.netBalance, Decimal.parse('-10.0'));
    });

    test('Sub-Group Split: Only members of the sub-group share the cost', () {
      final subGroups = [
        SubGroup(
          id: 'sg1',
          tripId: 't1',
          name: 'Car 1',
          type: SubGroupType.car,
          members: [
            SubGroupMember(id: 'm1', subGroupId: 'sg1', participantId: 'p1'),
            SubGroupMember(id: 'm2', subGroupId: 'sg1', participantId: 'p2'),
          ],
        ),
      ];

      final expenses = [
        Expense(
          id: 'e1',
          tripId: 't1',
          payerParticipantId: 'p1',
          amount: Decimal.parse('20.0'),
          scope: ExpenseScope.subGroup,
          subGroupId: 'sg1',
          createdAt: DateTime.now(),
        ),
      ];

      final balances = BalanceCalculator.calculateBalances(
        expenses: expenses,
        participants: participants,
        subGroups: subGroups,
      );

      final b1 = balances.firstWhere((b) => b.participantId == 'p1');
      final b2 = balances.firstWhere((b) => b.participantId == 'p2');
      final b3 = balances.firstWhere((b) => b.participantId == 'p3');

      // p1 paid 20. Split between p1 and p2 (10 each).
      // p3 owes nothing.
      expect(b1.netBalance, Decimal.parse('10.0'));
      expect(b2.netBalance, Decimal.parse('-10.0'));
      expect(b3.netBalance, Decimal.zero);
    });

    test(
      'Settlements: Verify balances after adjusting for recorded payments',
      () {
        final expenses = [
          Expense(
            id: 'e1',
            tripId: 't1',
            payerParticipantId: 'p1',
            amount: Decimal.parse('30.0'),
            scope: ExpenseScope.global,
            createdAt: DateTime.now(),
          ),
        ];

        // p2 pays p1 10 OMR (settling p2's debt)
        final settlements = [
          Settlement(
            id: 's1',
            tripId: 't1',
            payerParticipantId: 'p2',
            recipientParticipantId: 'p1',
            amount: 10.0,
            settledAt: DateTime.now(),
          ),
        ];

        final balances = BalanceCalculator.calculateBalances(
          expenses: expenses,
          participants: participants,
          settlements: settlements,
        );

        final b1 = balances.firstWhere((b) => b.participantId == 'p1');
        final b2 = balances.firstWhere((b) => b.participantId == 'p2');
        final b3 = balances.firstWhere((b) => b.participantId == 'p3');

        // Initial net: p1=+20, p2=-10, p3=-10
        // After settlement: p1 gets 10 (total +10 now relative to expenses), wait.
        // Calculation: (Paid + SettlementGiven) - Owed
        // p1: (30 + (-10)) - 10 = 10. (Because p1 "gave" -10 i.e. received 10)
        // p2: (0 + 10) - 10 = 0.
        // p3: (0 + 0) - 10 = -10.

        expect(b1.netBalance, Decimal.parse('10.0'));
        expect(b2.netBalance, Decimal.zero);
        expect(b2.isSettled, isTrue);
        expect(b3.netBalance, Decimal.parse('-10.0'));
      },
    );

    test('Edge Case: Empty participants or expenses', () {
      expect(
        BalanceCalculator.calculateBalances(expenses: [], participants: []),
        isEmpty,
      );

      final balances = BalanceCalculator.calculateBalances(
        expenses: [],
        participants: [participants[0]],
      );
      expect(balances[0].netBalance, Decimal.zero);
    });
  });
}
