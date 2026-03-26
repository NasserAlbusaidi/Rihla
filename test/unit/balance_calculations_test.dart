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
            amount: Decimal.parse('10'),
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

  group('Cross-event balance scenarios', () {
    // Participants use UID-style IDs (same across events per D-04).
    // tripId on Participant is unused by BalanceCalculator — any value works.
    final participants = [
      Participant(
        id: 'uid-1',
        tripId: 'any',
        role: ParticipantRole.leader,
        joinedAt: DateTime(2026),
        displayName: 'Ahmed',
      ),
      Participant(
        id: 'uid-2',
        tripId: 'any',
        role: ParticipantRole.member,
        joinedAt: DateTime(2026),
        displayName: 'Nasser',
      ),
      Participant(
        id: 'uid-3',
        tripId: 'any',
        role: ParticipantRole.member,
        joinedAt: DateTime(2026),
        displayName: 'Sara',
      ),
    ];

    // Test 1: Two events, same 3 participants. Combined balances should be
    // the sum of each participant's net across both events.
    //
    // Event A: uid-1 pays 30.000 OMR split 3 ways → each owes 10.000.
    // Event B: uid-2 pays 60.000 OMR split 3 ways → each owes 20.000.
    //
    // Combined:
    //   uid-1: paid 30, owed 30 (10+20) → net 0
    //   uid-2: paid 60, owed 30 (10+20) → net +30
    //   uid-3: paid 0,  owed 30 (10+20) → net -30
    test('Test 1: Two events combined — correct net balances per participant', () {
      final expenses = [
        // Event A
        Expense(
          id: 'e1',
          tripId: 'eventA',
          payerParticipantId: 'uid-1',
          amount: Decimal.parse('30.000'),
          scope: ExpenseScope.global,
          createdAt: DateTime(2026),
        ),
        // Event B
        Expense(
          id: 'e2',
          tripId: 'eventB',
          payerParticipantId: 'uid-2',
          amount: Decimal.parse('60.000'),
          scope: ExpenseScope.global,
          createdAt: DateTime(2026),
        ),
      ];

      final balances = BalanceCalculator.calculateBalances(
        expenses: expenses,
        participants: participants,
      );

      final b1 = balances.firstWhere((b) => b.participantId == 'uid-1');
      final b2 = balances.firstWhere((b) => b.participantId == 'uid-2');
      final b3 = balances.firstWhere((b) => b.participantId == 'uid-3');

      expect(b1.netBalance, Decimal.zero,
          reason: 'uid-1 paid 30, owed 30 → net 0');
      expect(b2.netBalance, Decimal.parse('30.000'),
          reason: 'uid-2 paid 60, owed 30 → net +30');
      expect(b3.netBalance, Decimal.parse('-30.000'),
          reason: 'uid-3 paid 0, owed 30 → net -30');
    });

    // Test 2: Three events. uid-3 only participates in events A and B.
    // Event C expenses are split only among uid-1 and uid-2 (custom scope).
    // uid-3's balance should only reflect events A and B.
    test('Test 2: Participant absent from one event — balance limited to their events', () {
      final expenseFromEventA = Expense(
        id: 'e1',
        tripId: 'eventA',
        payerParticipantId: 'uid-1',
        amount: Decimal.parse('30.000'),
        scope: ExpenseScope.global,
        createdAt: DateTime(2026),
      );

      final expenseFromEventB = Expense(
        id: 'e2',
        tripId: 'eventB',
        payerParticipantId: 'uid-2',
        amount: Decimal.parse('30.000'),
        scope: ExpenseScope.global,
        createdAt: DateTime(2026),
      );

      // Event C: custom split between uid-1 and uid-2 only
      final expenseFromEventC = Expense(
        id: 'e3',
        tripId: 'eventC',
        payerParticipantId: 'uid-1',
        amount: Decimal.parse('40.000'),
        scope: ExpenseScope.custom,
        customSplitParticipants: ['uid-1', 'uid-2'],
        createdAt: DateTime(2026),
      );

      final expenses = [expenseFromEventA, expenseFromEventB, expenseFromEventC];

      final balances = BalanceCalculator.calculateBalances(
        expenses: expenses,
        participants: participants,
      );

      final b3 = balances.firstWhere((b) => b.participantId == 'uid-3');

      // uid-3 is excluded from Event C (custom split), so:
      // uid-3 paid 0, owed 10 (from A) + 10 (from B) = 20 → net -20
      expect(b3.netBalance, Decimal.parse('-20.000'),
          reason: 'uid-3 excluded from event C — only owes from events A and B');
      expect(b3.totalPaid, Decimal.zero,
          reason: 'uid-3 paid nothing across all events');
    });

    // Test 3: Combined expenses + group-level settlement.
    // uid-3 owes uid-2 30.000 OMR across two events (from Test 1 scenario).
    // A group settlement of 30.000 from uid-3 to uid-2 zeroes the balance.
    test('Test 3: Group-level settlement zeroes cross-event debt', () {
      final expenses = [
        Expense(
          id: 'e1',
          tripId: 'eventA',
          payerParticipantId: 'uid-1',
          amount: Decimal.parse('30.000'),
          scope: ExpenseScope.global,
          createdAt: DateTime(2026),
        ),
        Expense(
          id: 'e2',
          tripId: 'eventB',
          payerParticipantId: 'uid-2',
          amount: Decimal.parse('60.000'),
          scope: ExpenseScope.global,
          createdAt: DateTime(2026),
        ),
      ];

      // Group-level settlement: uid-3 pays uid-2 the full 30.000 debt.
      // The Settlement tripId is set to a group sentinel — BalanceCalculator
      // only uses payerParticipantId, recipientParticipantId, and amount.
      final settlements = [
        Settlement(
          id: 's-group-1',
          tripId: 'group-g1', // sentinel for group-scoped settlement
          payerParticipantId: 'uid-3',
          recipientParticipantId: 'uid-2',
          amount: Decimal.parse('30.000'),
          settledAt: DateTime(2026),
        ),
      ];

      final balances = BalanceCalculator.calculateBalances(
        expenses: expenses,
        participants: participants,
        settlements: settlements,
      );

      final b2 = balances.firstWhere((b) => b.participantId == 'uid-2');
      final b3 = balances.firstWhere((b) => b.participantId == 'uid-3');

      // After settlement:
      //   uid-2 initial net +30, receives 30 from uid-3 via settlement
      //   Settlement: uid-2 receives 30, so adjustmentMap[uid-2] = -30
      //   uid-2 net: (60 + (-30)) - 30 = 0
      expect(b2.netBalance, Decimal.zero,
          reason: 'uid-2 net zeroed after receiving group settlement');
      expect(b2.isSettled, isTrue);

      // uid-3 initial net -30, pays 30 via settlement
      //   adjustmentMap[uid-3] = +30
      //   uid-3 net: (0 + 30) - 30 = 0
      expect(b3.netBalance, Decimal.zero,
          reason: 'uid-3 debt cleared by group settlement');
      expect(b3.isSettled, isTrue);
    });

    // Test 4: calculateOptimalSettlements on combined multi-event balances.
    // 4 participants, 3 events → greedy min-transactions algorithm.
    // Result count must be <= unique debtor-creditor pair count.
    test('Test 4: Optimal settlements produce minimum transactions for multi-event balances', () {
      final fourParticipants = [
        Participant(
          id: 'uid-1',
          tripId: 'any',
          role: ParticipantRole.leader,
          joinedAt: DateTime(2026),
          displayName: 'Ahmed',
        ),
        Participant(
          id: 'uid-2',
          tripId: 'any',
          role: ParticipantRole.member,
          joinedAt: DateTime(2026),
          displayName: 'Nasser',
        ),
        Participant(
          id: 'uid-3',
          tripId: 'any',
          role: ParticipantRole.member,
          joinedAt: DateTime(2026),
          displayName: 'Sara',
        ),
        Participant(
          id: 'uid-4',
          tripId: 'any',
          role: ParticipantRole.member,
          joinedAt: DateTime(2026),
          displayName: 'Fatima',
        ),
      ];

      // Three events, each with a different payer. Combined expenses produce
      // multiple debtors and creditors that can be optimally settled.
      //
      // Event A: uid-1 pays 40 split 4 ways → each owes 10
      //   uid-1 net: 40 - 10 = +30
      //   uid-2 net: 0 - 10 = -10
      //   uid-3 net: 0 - 10 = -10
      //   uid-4 net: 0 - 10 = -10
      //
      // Event B: uid-2 pays 20 split 4 ways → each owes 5
      //   uid-1 net: +30 - 5 = +25
      //   uid-2 net: -10 + 20 - 5 = +5
      //   uid-3 net: -10 - 5 = -15
      //   uid-4 net: -10 - 5 = -15
      //
      // Event C: uid-3 pays 20 split 4 ways → each owes 5
      //   uid-1 net: +25 - 5 = +20
      //   uid-2 net: +5 - 5 = 0
      //   uid-3 net: -15 + 20 - 5 = 0
      //   uid-4 net: -15 - 5 = -20
      //
      // Final: uid-1 = +20, uid-2 = 0, uid-3 = 0, uid-4 = -20
      // Optimal: 1 settlement (uid-4 → uid-1 for 20)
      final expenses = [
        Expense(
          id: 'e1',
          tripId: 'eventA',
          payerParticipantId: 'uid-1',
          amount: Decimal.parse('40.000'),
          scope: ExpenseScope.global,
          createdAt: DateTime(2026),
        ),
        Expense(
          id: 'e2',
          tripId: 'eventB',
          payerParticipantId: 'uid-2',
          amount: Decimal.parse('20.000'),
          scope: ExpenseScope.global,
          createdAt: DateTime(2026),
        ),
        Expense(
          id: 'e3',
          tripId: 'eventC',
          payerParticipantId: 'uid-3',
          amount: Decimal.parse('20.000'),
          scope: ExpenseScope.global,
          createdAt: DateTime(2026),
        ),
      ];

      final balances = BalanceCalculator.calculateBalances(
        expenses: expenses,
        participants: fourParticipants,
      );

      final optimalSettlements = BalanceCalculator.calculateOptimalSettlements(
        balances: balances,
      );

      // There is exactly 1 debtor (uid-4) and 1 creditor (uid-1) after netting,
      // so the optimal settlement count is 1.
      expect(optimalSettlements.length, equals(1),
          reason: 'Only 1 settlement needed: uid-4 pays uid-1 20.000');
      expect(optimalSettlements.first['fromUserId'], equals('uid-4'));
      expect(optimalSettlements.first['toUserId'], equals('uid-1'));
      expect(optimalSettlements.first['amount'], equals(Decimal.parse('20.000')));
    });

    // Test 5: calculateTotalExpenses correctly sums expenses from multiple
    // events (expenses with different tripId values).
    test('Test 5: calculateTotalExpenses sums across expenses from different events', () {
      final expenses = [
        Expense(
          id: 'e1',
          tripId: 'eventA',
          payerParticipantId: 'uid-1',
          amount: Decimal.parse('30.000'),
          scope: ExpenseScope.global,
          createdAt: DateTime(2026),
        ),
        Expense(
          id: 'e2',
          tripId: 'eventB',
          payerParticipantId: 'uid-2',
          amount: Decimal.parse('45.500'),
          scope: ExpenseScope.global,
          createdAt: DateTime(2026),
        ),
        Expense(
          id: 'e3',
          tripId: 'eventC',
          payerParticipantId: 'uid-3',
          amount: Decimal.parse('24.500'),
          scope: ExpenseScope.global,
          createdAt: DateTime(2026),
        ),
      ];

      final total = BalanceCalculator.calculateTotalExpenses(expenses);

      expect(total, Decimal.parse('100.000'),
          reason: '30 + 45.5 + 24.5 = 100.000 OMR across 3 events');
    });

    // Test 6: Empty expense list from one event combined with non-empty from
    // another still produces correct balances.
    test('Test 6: Empty expenses from one event combined with non-empty from another', () {
      // eventA has no expenses (empty list).
      // eventB has one expense: uid-1 pays 30.000 split 3 ways.
      final expensesEventA = <Expense>[]; // event A contributed nothing
      final expensesEventB = [
        Expense(
          id: 'e1',
          tripId: 'eventB',
          payerParticipantId: 'uid-1',
          amount: Decimal.parse('30.000'),
          scope: ExpenseScope.global,
          createdAt: DateTime(2026),
        ),
      ];

      // Combine both lists (simulating groupBalancesProvider behavior).
      final combined = [...expensesEventA, ...expensesEventB];

      final balances = BalanceCalculator.calculateBalances(
        expenses: combined,
        participants: participants,
      );

      final b1 = balances.firstWhere((b) => b.participantId == 'uid-1');
      final b2 = balances.firstWhere((b) => b.participantId == 'uid-2');
      final b3 = balances.firstWhere((b) => b.participantId == 'uid-3');

      // uid-1 paid 30, each owes 10 → uid-1 net = +20
      expect(b1.netBalance, Decimal.parse('20.000'),
          reason: 'uid-1 is owed 20 from event B');
      expect(b2.netBalance, Decimal.parse('-10.000'),
          reason: 'uid-2 owes 10 from event B');
      expect(b3.netBalance, Decimal.parse('-10.000'),
          reason: 'uid-3 owes 10 from event B');
    });
  });
}
