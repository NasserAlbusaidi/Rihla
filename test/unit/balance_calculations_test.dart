import 'package:decimal/decimal.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:safar/features/ledger/models/expense_model.dart';
import 'package:safar/features/ledger/models/settlement_model.dart';
import 'package:safar/features/ledger/providers/expense_provider.dart';
import 'package:safar/features/trip/models/trip_model.dart';
import 'package:safar/features/logistics/models/sub_group_model.dart';

// ---------------------------------------------------------------------------
// Shared helpers
// ---------------------------------------------------------------------------

Participant _participant(String id, String name) => Participant(
      id: id,
      tripId: 't1',
      role: ParticipantRole.member,
      joinedAt: DateTime(2026),
      displayName: name,
    );

Expense _globalExpense(String id, String payerId, String amount,
    {String tripId = 't1'}) =>
    Expense(
      id: id,
      tripId: tripId,
      payerParticipantId: payerId,
      amount: Decimal.parse(amount),
      scope: ExpenseScope.global,
      createdAt: DateTime(2026),
    );

Expense _personalExpense(String id, String payerId, String amount) => Expense(
      id: id,
      tripId: 't1',
      payerParticipantId: payerId,
      amount: Decimal.parse(amount),
      scope: ExpenseScope.personal,
      createdAt: DateTime(2026),
    );

Expense _subGroupExpense(
        String id, String payerId, String amount, String subGroupId) =>
    Expense(
      id: id,
      tripId: 't1',
      payerParticipantId: payerId,
      amount: Decimal.parse(amount),
      scope: ExpenseScope.subGroup,
      subGroupId: subGroupId,
      createdAt: DateTime(2026),
    );

Expense _customExpense(
        String id, String payerId, String amount, List<String> splitIds) =>
    Expense(
      id: id,
      tripId: 't1',
      payerParticipantId: payerId,
      amount: Decimal.parse(amount),
      scope: ExpenseScope.custom,
      customSplitParticipants: splitIds,
      createdAt: DateTime(2026),
    );

Settlement _settlement(
        String id, String payerId, String recipientId, String amount) =>
    Settlement(
      id: id,
      tripId: 't1',
      payerParticipantId: payerId,
      recipientParticipantId: recipientId,
      amount: Decimal.parse(amount),
      settledAt: DateTime(2026),
    );

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

  // ---------------------------------------------------------------------------
  // Personal scope
  // ---------------------------------------------------------------------------
  group('Personal scope', () {
    final participants = [
      _participant('p1', 'Alice'),
      _participant('p2', 'Bob'),
      _participant('p3', 'Charlie'),
    ];

    test('Personal expense: only payer charged, others unaffected, net = 0 for all',
        () {
      final expenses = [_personalExpense('e1', 'p1', '15.000')];

      final balances = BalanceCalculator.calculateBalances(
        expenses: expenses,
        participants: participants,
      );

      final b1 = balances.firstWhere((b) => b.participantId == 'p1');
      final b2 = balances.firstWhere((b) => b.participantId == 'p2');
      final b3 = balances.firstWhere((b) => b.participantId == 'p3');

      // Personal: only payer owes themselves → net = 0
      expect(b1.netBalance, Decimal.zero,
          reason: 'Payer net = 0 for personal expense');
      expect(b2.netBalance, Decimal.zero,
          reason: 'Non-payer unaffected by personal expense');
      expect(b3.netBalance, Decimal.zero,
          reason: 'Non-payer unaffected by personal expense');
    });

    test('Multiple personal expenses from different payers — each payer net = 0', () {
      final expenses = [
        _personalExpense('e1', 'p1', '20.000'),
        _personalExpense('e2', 'p2', '35.500'),
      ];

      final balances = BalanceCalculator.calculateBalances(
        expenses: expenses,
        participants: participants,
      );

      final b1 = balances.firstWhere((b) => b.participantId == 'p1');
      final b2 = balances.firstWhere((b) => b.participantId == 'p2');
      final b3 = balances.firstWhere((b) => b.participantId == 'p3');

      expect(b1.netBalance, Decimal.zero);
      expect(b2.netBalance, Decimal.zero);
      expect(b3.netBalance, Decimal.zero);
    });

    test('Personal + global mixed: personal does not affect global split', () {
      // p1 pays 30 global (each owes 10) AND 10 personal (only p1 owes themselves)
      // Global: p1 net +20, p2 net -10, p3 net -10
      // Personal: no effect on other participants
      final expenses = [
        _globalExpense('e1', 'p1', '30.000'),
        _personalExpense('e2', 'p1', '10.000'),
      ];

      final balances = BalanceCalculator.calculateBalances(
        expenses: expenses,
        participants: participants,
      );

      final b1 = balances.firstWhere((b) => b.participantId == 'p1');
      final b2 = balances.firstWhere((b) => b.participantId == 'p2');
      final b3 = balances.firstWhere((b) => b.participantId == 'p3');

      // p1: paid 40 (30 global + 10 personal), owed 10 (global share) + 10 (personal) = 20 → net = 20
      expect(b1.netBalance, Decimal.parse('20.000'),
          reason: 'Personal does not change global split for others');
      expect(b2.netBalance, Decimal.parse('-10.000'));
      expect(b3.netBalance, Decimal.parse('-10.000'));
    });

    test('ExpenseScope.personal exists and is handled distinctly', () {
      // Verify ExpenseScope.personal is a valid enum value
      expect(ExpenseScope.personal, isA<ExpenseScope>());
      expect(ExpenseScope.personal.value, equals('personal'));
    });
  });

  // ---------------------------------------------------------------------------
  // SubGroup scope
  // ---------------------------------------------------------------------------
  group('SubGroup scope', () {
    final participants = [
      _participant('p1', 'Alice'),
      _participant('p2', 'Bob'),
      _participant('p3', 'Charlie'),
      _participant('p4', 'Diana'),
    ];

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
      SubGroup(
        id: 'sg2',
        tripId: 't1',
        name: 'Car 2',
        type: SubGroupType.car,
        members: [
          SubGroupMember(id: 'm3', subGroupId: 'sg2', participantId: 'p3'),
          SubGroupMember(id: 'm4', subGroupId: 'sg2', participantId: 'p4'),
        ],
      ),
    ];

    test('SubGroup expense split among subgroup members only — non-members unaffected', () {
      final expenses = [_subGroupExpense('e1', 'p1', '20.000', 'sg1')];

      final balances = BalanceCalculator.calculateBalances(
        expenses: expenses,
        participants: participants,
        subGroups: subGroups,
      );

      final b1 = balances.firstWhere((b) => b.participantId == 'p1');
      final b2 = balances.firstWhere((b) => b.participantId == 'p2');
      final b3 = balances.firstWhere((b) => b.participantId == 'p3');
      final b4 = balances.firstWhere((b) => b.participantId == 'p4');

      // sg1 has p1, p2 — split 20 / 2 = 10 each
      expect(b1.netBalance, Decimal.parse('10.000'));
      expect(b2.netBalance, Decimal.parse('-10.000'));
      // p3, p4 not in sg1 — unaffected
      expect(b3.netBalance, Decimal.zero);
      expect(b4.netBalance, Decimal.zero);
    });

    test('SubGroup with missing subGroups parameter falls through to global', () {
      // When subGroups param is not provided but expense has subGroupId, fallback = global
      final expenses = [_subGroupExpense('e1', 'p1', '40.000', 'sg1')];

      final balances = BalanceCalculator.calculateBalances(
        expenses: expenses,
        participants: participants,
        // intentionally omit subGroups parameter
      );

      // Without subGroups, fallback is global (all 4 participants)
      // p1 paid 40, each owes 10 → p1 net = 30, others = -10
      final b1 = balances.firstWhere((b) => b.participantId == 'p1');
      final b2 = balances.firstWhere((b) => b.participantId == 'p2');
      expect(b1.netBalance, Decimal.parse('30.000'));
      expect(b2.netBalance, Decimal.parse('-10.000'));
    });

    test('SubGroup with mismatched subGroupId — graceful fallback to global', () {
      // subGroupId does not exist in provided subGroups
      final expenses = [_subGroupExpense('e1', 'p1', '40.000', 'sg-nonexistent')];

      final balances = BalanceCalculator.calculateBalances(
        expenses: expenses,
        participants: participants,
        subGroups: subGroups,
      );

      // sg-nonexistent not in map → fallback to global (4 participants)
      // p1 paid 40, each owes 10 → p1 net = 30, others = -10
      final b1 = balances.firstWhere((b) => b.participantId == 'p1');
      final b2 = balances.firstWhere((b) => b.participantId == 'p2');
      expect(b1.netBalance, Decimal.parse('30.000'));
      expect(b2.netBalance, Decimal.parse('-10.000'));
    });

    test('Multiple subgroups in same trip — each expense split correctly', () {
      // sg1: p1 pays 20, sg2: p3 pays 30
      final expenses = [
        _subGroupExpense('e1', 'p1', '20.000', 'sg1'),
        _subGroupExpense('e2', 'p3', '30.000', 'sg2'),
      ];

      final balances = BalanceCalculator.calculateBalances(
        expenses: expenses,
        participants: participants,
        subGroups: subGroups,
      );

      final b1 = balances.firstWhere((b) => b.participantId == 'p1');
      final b2 = balances.firstWhere((b) => b.participantId == 'p2');
      final b3 = balances.firstWhere((b) => b.participantId == 'p3');
      final b4 = balances.firstWhere((b) => b.participantId == 'p4');

      // sg1 (p1, p2): p1 paid 20 → p1 net +10, p2 net -10
      expect(b1.netBalance, Decimal.parse('10.000'));
      expect(b2.netBalance, Decimal.parse('-10.000'));
      // sg2 (p3, p4): p3 paid 30 → p3 net +15, p4 net -15
      expect(b3.netBalance, Decimal.parse('15.000'));
      expect(b4.netBalance, Decimal.parse('-15.000'));
    });
  });

  // ---------------------------------------------------------------------------
  // Custom scope
  // ---------------------------------------------------------------------------
  group('Custom scope', () {
    final participants = [
      _participant('p1', 'Alice'),
      _participant('p2', 'Bob'),
      _participant('p3', 'Charlie'),
    ];

    test('Custom scope with splitParticipantIds — only listed participants share cost', () {
      // p1 pays 20, split only between p1 and p2 (p3 excluded)
      final expenses = [_customExpense('e1', 'p1', '20.000', ['p1', 'p2'])];

      final balances = BalanceCalculator.calculateBalances(
        expenses: expenses,
        participants: participants,
      );

      final b1 = balances.firstWhere((b) => b.participantId == 'p1');
      final b2 = balances.firstWhere((b) => b.participantId == 'p2');
      final b3 = balances.firstWhere((b) => b.participantId == 'p3');

      // 20 / 2 = 10 each for p1, p2
      expect(b1.netBalance, Decimal.parse('10.000'));
      expect(b2.netBalance, Decimal.parse('-10.000'));
      expect(b3.netBalance, Decimal.zero);
    });

    test('Custom scope with empty splitParticipantIds — falls back to global', () {
      // When customSplitParticipants is empty, fallback = global (all participants)
      final expenses = [_customExpense('e1', 'p1', '30.000', [])];

      final balances = BalanceCalculator.calculateBalances(
        expenses: expenses,
        participants: participants,
      );

      // Fallback to global: 30 / 3 = 10 each
      final b1 = balances.firstWhere((b) => b.participantId == 'p1');
      final b2 = balances.firstWhere((b) => b.participantId == 'p2');
      final b3 = balances.firstWhere((b) => b.participantId == 'p3');

      expect(b1.netBalance, Decimal.parse('20.000'));
      expect(b2.netBalance, Decimal.parse('-10.000'));
      expect(b3.netBalance, Decimal.parse('-10.000'));
    });

    test('Custom scope correctly identifies ExpenseScope.custom enum value', () {
      expect(ExpenseScope.custom, isA<ExpenseScope>());
      expect(ExpenseScope.custom.value, equals('custom'));
    });
  });

  // ---------------------------------------------------------------------------
  // Cross-event aggregation
  // ---------------------------------------------------------------------------
  group('Cross-event aggregation', () {
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

  // ---------------------------------------------------------------------------
  // Edge cases
  // ---------------------------------------------------------------------------
  group('Edge cases', () {
    final participants = [
      _participant('p1', 'Alice'),
      _participant('p2', 'Bob'),
      _participant('p3', 'Charlie'),
    ];

    test('Zero amount expense — net balance stays 0 for all participants', () {
      final expenses = [_globalExpense('e1', 'p1', '0.000')];

      final balances = BalanceCalculator.calculateBalances(
        expenses: expenses,
        participants: participants,
      );

      for (final b in balances) {
        expect(b.netBalance, Decimal.zero,
            reason: 'Zero-amount expense should not affect any balance');
      }
    });

    test('Over-settlement: settlement exceeds debt — creditor and debtor roles flip', () {
      // p1 pays 30 (global, 3 people → each owes 10)
      // Initial: p1=+20, p2=-10, p3=-10
      // p2 pays p1 15 (over-settling — owed 10, pays 15)
      final expenses = [_globalExpense('e1', 'p1', '30.000')];
      final settlements = [_settlement('s1', 'p2', 'p1', '15.000')];

      final balances = BalanceCalculator.calculateBalances(
        expenses: expenses,
        participants: participants,
        settlements: settlements,
      );

      final b1 = balances.firstWhere((b) => b.participantId == 'p1');
      final b2 = balances.firstWhere((b) => b.participantId == 'p2');

      // p1: (30 + (-15)) - 10 = 5 (reduced from 20 because p2 over-paid)
      expect(b1.netBalance, Decimal.parse('5.000'),
          reason: 'p1 reduced from +20 after receiving 15 over-settlement');
      // p2: (0 + 15) - 10 = +5 (became a creditor after over-settling)
      expect(b2.netBalance, Decimal.parse('5.000'),
          reason: 'p2 is now owed 5 after over-settling');
    });

    test('Over-settlement negative balance: verify sign is correct', () {
      // p2 owes p1 10, but p2 pays 20 → p2 becomes creditor by 10
      final expenses = [_globalExpense('e1', 'p1', '30.000')];
      final settlements = [_settlement('s1', 'p2', 'p1', '20.000')];

      final balances = BalanceCalculator.calculateBalances(
        expenses: expenses,
        participants: participants,
        settlements: settlements,
      );

      final b1 = balances.firstWhere((b) => b.participantId == 'p1');
      final b2 = balances.firstWhere((b) => b.participantId == 'p2');

      // p1: (30 + (-20)) - 10 = 0
      expect(b1.netBalance, Decimal.zero);
      // p2: (0 + 20) - 10 = +10 (creditor after over-settlement)
      expect(b2.netBalance, Decimal.parse('10.000'));
      expect(b2.isOwedMoney, isTrue);
    });

    test('50+ expenses stress test — Decimal precision maintained', () {
      // 55 global expenses of 1.001 OMR each, all paid by p1, split 3 ways
      final expenses = List.generate(
          55, (i) => _globalExpense('e$i', 'p1', '1.001'));

      final balances = BalanceCalculator.calculateBalances(
        expenses: expenses,
        participants: participants,
      );

      final total = Decimal.parse('1.001') * Decimal.fromInt(55);
      final p1 = balances.firstWhere((b) => b.participantId == 'p1');
      expect(p1.totalPaid, equals(total),
          reason: '55 * 1.001 = 55.055 OMR, no precision loss');
    });

    test('Empty expense list — returns zero balances for all participants', () {
      final balances = BalanceCalculator.calculateBalances(
        expenses: [],
        participants: participants,
      );

      expect(balances, hasLength(3));
      for (final b in balances) {
        expect(b.netBalance, Decimal.zero);
        expect(b.totalPaid, Decimal.zero);
        expect(b.totalOwed, Decimal.zero);
      }
    });

    test('Empty participant list — returns empty list', () {
      final expenses = [_globalExpense('e1', 'p1', '30.000')];

      final balances = BalanceCalculator.calculateBalances(
        expenses: expenses,
        participants: [],
      );

      expect(balances, isEmpty);
    });

    test('Single participant group — payer owes themselves, net = 0', () {
      final singleParticipant = [_participant('p1', 'Solo')];
      final expenses = [_globalExpense('e1', 'p1', '50.000')];

      final balances = BalanceCalculator.calculateBalances(
        expenses: expenses,
        participants: singleParticipant,
      );

      expect(balances, hasLength(1));
      // p1 paid 50, owes 50 (100% of global) → net = 0
      expect(balances.first.netBalance, Decimal.zero);
      expect(balances.first.totalPaid, Decimal.parse('50.000'));
    });

    test('Deleted expenses flag (is_deleted) — verified pre-filtering behavior', () {
      // BalanceCalculator receives pre-filtered expenses.
      // A deleted expense passed in would still be counted (pre-filter is caller responsibility).
      // This test confirms is_deleted field exists and the expense still appears if passed in.
      final deletedExpense = Expense(
        id: 'e1',
        tripId: 't1',
        payerParticipantId: 'p1',
        amount: Decimal.parse('30.000'),
        scope: ExpenseScope.global,
        createdAt: DateTime(2026),
        isDeleted: true,
      );

      // When deleted expense is passed (caller should pre-filter):
      final balances = BalanceCalculator.calculateBalances(
        expenses: [deletedExpense],
        participants: participants,
      );

      // BalanceCalculator does not filter is_deleted — that is the caller's job
      // So the balance is computed as if the expense were active
      final b1 = balances.firstWhere((b) => b.participantId == 'p1');
      expect(b1.totalPaid, Decimal.parse('30.000'),
          reason: 'Caller must pre-filter deleted expenses before passing to BalanceCalculator');
    });
  });

  // ---------------------------------------------------------------------------
  // Settlement integration
  // ---------------------------------------------------------------------------
  group('Settlement integration', () {
    final participants = [
      _participant('p1', 'Alice'),
      _participant('p2', 'Bob'),
      _participant('p3', 'Charlie'),
    ];

    test('Settlement reduces net balance correctly', () {
      // p1 pays 30 (global) → p1=+20, p2=-10, p3=-10
      // p3 settles 10 to p1 → p3 = 0, p1 = 10
      final expenses = [_globalExpense('e1', 'p1', '30.000')];
      final settlements = [_settlement('s1', 'p3', 'p1', '10.000')];

      final balances = BalanceCalculator.calculateBalances(
        expenses: expenses,
        participants: participants,
        settlements: settlements,
      );

      final b1 = balances.firstWhere((b) => b.participantId == 'p1');
      final b3 = balances.firstWhere((b) => b.participantId == 'p3');

      expect(b1.netBalance, Decimal.parse('10.000'));
      expect(b3.netBalance, Decimal.zero);
      expect(b3.isSettled, isTrue);
    });

    test('Multiple settlements — all reduce balances correctly', () {
      // p1 pays 30 → p1=+20, p2=-10, p3=-10
      // Both p2 and p3 settle with p1
      final expenses = [_globalExpense('e1', 'p1', '30.000')];
      final settlements = [
        _settlement('s1', 'p2', 'p1', '10.000'),
        _settlement('s2', 'p3', 'p1', '10.000'),
      ];

      final balances = BalanceCalculator.calculateBalances(
        expenses: expenses,
        participants: participants,
        settlements: settlements,
      );

      final b1 = balances.firstWhere((b) => b.participantId == 'p1');
      final b2 = balances.firstWhere((b) => b.participantId == 'p2');
      final b3 = balances.firstWhere((b) => b.participantId == 'p3');

      // p1 receives 20 total settlements → (30 - 20) - 10 = 0
      expect(b1.netBalance, Decimal.zero);
      expect(b1.isSettled, isTrue);
      expect(b2.isSettled, isTrue);
      expect(b3.isSettled, isTrue);
    });

    test('Partial settlement — balance partially reduced', () {
      // p1 pays 30, p2 owes 10, p2 pays 5 (partial)
      final expenses = [_globalExpense('e1', 'p1', '30.000')];
      final settlements = [_settlement('s1', 'p2', 'p1', '5.000')];

      final balances = BalanceCalculator.calculateBalances(
        expenses: expenses,
        participants: participants,
        settlements: settlements,
      );

      final b2 = balances.firstWhere((b) => b.participantId == 'p2');

      // p2: (0 + 5) - 10 = -5 (still owes 5)
      expect(b2.netBalance, Decimal.parse('-5.000'));
      expect(b2.owesMoney, isTrue);
      expect(b2.isSettled, isFalse);
    });

    test('Zero-amount settlement — has no effect on balances', () {
      final expenses = [_globalExpense('e1', 'p1', '30.000')];
      final settlements = [_settlement('s1', 'p2', 'p1', '0.000')];

      final balances = BalanceCalculator.calculateBalances(
        expenses: expenses,
        participants: participants,
        settlements: settlements,
      );

      final b1 = balances.firstWhere((b) => b.participantId == 'p1');
      final b2 = balances.firstWhere((b) => b.participantId == 'p2');

      // Zero settlement should not change anything
      expect(b1.netBalance, Decimal.parse('20.000'));
      expect(b2.netBalance, Decimal.parse('-10.000'));
    });
  });
}
