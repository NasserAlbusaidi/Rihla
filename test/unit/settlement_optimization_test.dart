import 'package:decimal/decimal.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:safar/features/ledger/models/expense_model.dart';
import 'package:safar/features/trip/models/trip_model.dart';
import 'package:safar/features/ledger/providers/expense_provider.dart';

/// Helper to create a [UserBalance] with minimal boilerplate.
UserBalance _balance(
  String id,
  String name,
  Decimal net, {
  Decimal? paid,
  Decimal? owed,
}) {
  return UserBalance(
    participantId: id,
    displayName: name,
    totalPaid: paid ?? Decimal.zero,
    totalOwed: owed ?? Decimal.zero,
    netBalance: net,
  );
}

void main() {
  group('calculateOptimalSettlements', () {
    // ------------------------------------------------------------------
    // 1. Two people, one paid everything
    // ------------------------------------------------------------------
    test('Two people, one paid everything — single settlement', () {
      // A paid 100 for both → each owes 50
      // Net: A = +50, B = -50
      final balances = [
        _balance('a', 'Alice', Decimal.parse('50')),
        _balance('b', 'Bob', Decimal.parse('-50')),
      ];

      final settlements =
          BalanceCalculator.calculateOptimalSettlements(balances: balances);

      expect(settlements, hasLength(1));
      expect(settlements[0]['fromUserId'], 'b');
      expect(settlements[0]['toUserId'], 'a');
      expect(settlements[0]['amount'], Decimal.parse('50'));
    });

    // ------------------------------------------------------------------
    // 2. Three people, one paid
    // ------------------------------------------------------------------
    test('Three people, one paid — two settlements', () {
      // A paid 90 for all 3 → each owes 30
      // Net: A = +60, B = -30, C = -30
      final balances = [
        _balance('a', 'Alice', Decimal.parse('60')),
        _balance('b', 'Bob', Decimal.parse('-30')),
        _balance('c', 'Charlie', Decimal.parse('-30')),
      ];

      final settlements =
          BalanceCalculator.calculateOptimalSettlements(balances: balances);

      expect(settlements, hasLength(2));

      // Total transferred should equal 60
      final totalTransferred = settlements.fold<Decimal>(
        Decimal.zero,
        (sum, s) => sum + (s['amount'] as Decimal),
      );
      expect(totalTransferred, Decimal.parse('60'));

      // Both settlements should pay Alice
      for (final s in settlements) {
        expect(s['toUserId'], 'a');
        expect(s['amount'], Decimal.parse('30'));
      }
    });

    // ------------------------------------------------------------------
    // 3. Three people, circular debts — ≤ 2 transactions
    // ------------------------------------------------------------------
    test('Three people, circular debts — at most 2 transactions', () {
      // A is owed 20, B is owed 10, C owes 30
      // Net: A = +20, B = +10, C = -30
      final balances = [
        _balance('a', 'Alice', Decimal.parse('20')),
        _balance('b', 'Bob', Decimal.parse('10')),
        _balance('c', 'Charlie', Decimal.parse('-30')),
      ];

      final settlements =
          BalanceCalculator.calculateOptimalSettlements(balances: balances);

      expect(settlements.length, lessThanOrEqualTo(2));

      // Total transferred should equal 30
      final totalTransferred = settlements.fold<Decimal>(
        Decimal.zero,
        (sum, s) => sum + (s['amount'] as Decimal),
      );
      expect(totalTransferred, Decimal.parse('30'));

      // All payments come from Charlie
      for (final s in settlements) {
        expect(s['fromUserId'], 'c');
      }
    });

    // ------------------------------------------------------------------
    // 4. Already settled — all balances zero
    // ------------------------------------------------------------------
    test('Already settled — no settlements needed', () {
      final balances = [
        _balance('a', 'Alice', Decimal.zero),
        _balance('b', 'Bob', Decimal.zero),
        _balance('c', 'Charlie', Decimal.zero),
      ];

      final settlements =
          BalanceCalculator.calculateOptimalSettlements(balances: balances);

      expect(settlements, isEmpty);
    });

    // ------------------------------------------------------------------
    // 5. Single person — no settlements
    // ------------------------------------------------------------------
    test('Single person — no settlements possible', () {
      final balances = [
        _balance('a', 'Alice', Decimal.zero),
      ];

      final settlements =
          BalanceCalculator.calculateOptimalSettlements(balances: balances);

      expect(settlements, isEmpty);
    });

    // ------------------------------------------------------------------
    // 6. Two debtors, one creditor
    // ------------------------------------------------------------------
    test('Two debtors, one creditor — two transactions', () {
      // C is owed 50, A owes 30, B owes 20
      final balances = [
        _balance('a', 'Alice', Decimal.parse('-30')),
        _balance('b', 'Bob', Decimal.parse('-20')),
        _balance('c', 'Charlie', Decimal.parse('50')),
      ];

      final settlements =
          BalanceCalculator.calculateOptimalSettlements(balances: balances);

      expect(settlements, hasLength(2));

      // Both should pay Charlie
      for (final s in settlements) {
        expect(s['toUserId'], 'c');
      }

      // Find each debtor's payment
      final aliceSettlement =
          settlements.firstWhere((s) => s['fromUserId'] == 'a');
      final bobSettlement =
          settlements.firstWhere((s) => s['fromUserId'] == 'b');

      expect(aliceSettlement['amount'], Decimal.parse('30'));
      expect(bobSettlement['amount'], Decimal.parse('20'));
    });

    // ------------------------------------------------------------------
    // 7. Rounding with 3-decimal OMR
    // ------------------------------------------------------------------
    test('OMR 3-decimal precision is maintained', () {
      // Three-way split of 100 → 33.333 each
      // Payer A net: +66.666, B and C net: -33.333 each
      final balances = [
        _balance('a', 'Alice', Decimal.parse('66.666')),
        _balance('b', 'Bob', Decimal.parse('-33.333')),
        _balance('c', 'Charlie', Decimal.parse('-33.333')),
      ];

      final settlements =
          BalanceCalculator.calculateOptimalSettlements(balances: balances);

      expect(settlements, hasLength(2));

      // Each settlement should preserve 3-decimal precision
      for (final s in settlements) {
        final amount = s['amount'] as Decimal;
        expect(amount, Decimal.parse('33.333'));
      }

      // Total transferred should be 66.666
      final totalTransferred = settlements.fold<Decimal>(
        Decimal.zero,
        (sum, s) => sum + (s['amount'] as Decimal),
      );
      expect(totalTransferred, Decimal.parse('66.666'));
    });

    // ------------------------------------------------------------------
    // 8. Large group (5+ people) — verify total transfer amounts
    // ------------------------------------------------------------------
    test('Large group of 6 — correct total transfer amounts', () {
      // 6 people: A is owed 50, B is owed 30, C is owed 20,
      //           D owes 40, E owes 35, F owes 25
      // Total credits: 100, total debts: 100
      final balances = [
        _balance('a', 'Alice', Decimal.parse('50')),
        _balance('b', 'Bob', Decimal.parse('30')),
        _balance('c', 'Charlie', Decimal.parse('20')),
        _balance('d', 'Diana', Decimal.parse('-40')),
        _balance('e', 'Eve', Decimal.parse('-35')),
        _balance('f', 'Frank', Decimal.parse('-25')),
      ];

      final settlements =
          BalanceCalculator.calculateOptimalSettlements(balances: balances);

      // Greedy should produce at most 5 transactions (debtors + creditors - 1)
      expect(settlements.length, lessThanOrEqualTo(5));

      // Total transferred should be 100
      final totalTransferred = settlements.fold<Decimal>(
        Decimal.zero,
        (sum, s) => sum + (s['amount'] as Decimal),
      );
      expect(totalTransferred, Decimal.parse('100'));

      // Every fromUserId should be a debtor
      for (final s in settlements) {
        expect(
          ['d', 'e', 'f'],
          contains(s['fromUserId']),
        );
        expect(
          ['a', 'b', 'c'],
          contains(s['toUserId']),
        );
      }

      // Each debtor's total outflow should match their debt
      final outflows = <String, Decimal>{};
      for (final s in settlements) {
        final from = s['fromUserId'] as String;
        outflows[from] = (outflows[from] ?? Decimal.zero) + (s['amount'] as Decimal);
      }
      expect(outflows['d'], Decimal.parse('40'));
      expect(outflows['e'], Decimal.parse('35'));
      expect(outflows['f'], Decimal.parse('25'));

      // Each creditor's total inflow should match their credit
      final inflows = <String, Decimal>{};
      for (final s in settlements) {
        final to = s['toUserId'] as String;
        inflows[to] = (inflows[to] ?? Decimal.zero) + (s['amount'] as Decimal);
      }
      expect(inflows['a'], Decimal.parse('50'));
      expect(inflows['b'], Decimal.parse('30'));
      expect(inflows['c'], Decimal.parse('20'));
    });

    // ------------------------------------------------------------------
    // 9. One debtor, multiple creditors
    // ------------------------------------------------------------------
    test('One debtor, multiple creditors — correct split', () {
      // A owes 100 total, B is owed 60, C is owed 40
      final balances = [
        _balance('a', 'Alice', Decimal.parse('-100')),
        _balance('b', 'Bob', Decimal.parse('60')),
        _balance('c', 'Charlie', Decimal.parse('40')),
      ];

      final settlements =
          BalanceCalculator.calculateOptimalSettlements(balances: balances);

      expect(settlements, hasLength(2));

      // All payments come from Alice
      for (final s in settlements) {
        expect(s['fromUserId'], 'a');
      }

      // Bob should receive 60, Charlie should receive 40
      final toBob = settlements.firstWhere((s) => s['toUserId'] == 'b');
      final toCharlie = settlements.firstWhere((s) => s['toUserId'] == 'c');

      expect(toBob['amount'], Decimal.parse('60'));
      expect(toCharlie['amount'], Decimal.parse('40'));
    });

    // ------------------------------------------------------------------
    // 10. Equal balances cancel out — zero settlements
    // ------------------------------------------------------------------
    test('Equal balances cancel out — zero settlements', () {
      // Everyone paid their fair share
      final balances = [
        _balance(
          'a',
          'Alice',
          Decimal.zero,
          paid: Decimal.parse('25'),
          owed: Decimal.parse('25'),
        ),
        _balance(
          'b',
          'Bob',
          Decimal.zero,
          paid: Decimal.parse('25'),
          owed: Decimal.parse('25'),
        ),
        _balance(
          'c',
          'Charlie',
          Decimal.zero,
          paid: Decimal.parse('25'),
          owed: Decimal.parse('25'),
        ),
        _balance(
          'd',
          'Diana',
          Decimal.zero,
          paid: Decimal.parse('25'),
          owed: Decimal.parse('25'),
        ),
      ];

      final settlements =
          BalanceCalculator.calculateOptimalSettlements(balances: balances);

      expect(settlements, isEmpty);
    });

    // ------------------------------------------------------------------
    // 11. userNames parameter — names populated in output
    // ------------------------------------------------------------------
    test('userNames parameter populates names in output', () {
      final balances = [
        _balance('a', 'Alice', Decimal.parse('50')),
        _balance('b', 'Bob', Decimal.parse('-30')),
        _balance('c', 'Charlie', Decimal.parse('-20')),
      ];

      final userNames = {
        'a': 'Alice Wonderland',
        'b': 'Bob Builder',
        'c': 'Charlie Chaplin',
      };

      final settlements = BalanceCalculator.calculateOptimalSettlements(
        balances: balances,
        userNames: userNames,
      );

      expect(settlements, hasLength(2));

      // Verify custom names are used instead of displayName
      for (final s in settlements) {
        final fromId = s['fromUserId'] as String;
        final toId = s['toUserId'] as String;
        expect(s['fromUserName'], userNames[fromId]);
        expect(s['toUserName'], userNames[toId]);
      }
    });

    // ------------------------------------------------------------------
    // 11b. Without userNames — displayName is used as fallback
    // ------------------------------------------------------------------
    test('Without userNames — displayName is used as fallback', () {
      final balances = [
        _balance('a', 'Alice', Decimal.parse('50')),
        _balance('b', 'Bob', Decimal.parse('-50')),
      ];

      final settlements =
          BalanceCalculator.calculateOptimalSettlements(balances: balances);

      expect(settlements, hasLength(1));
      expect(settlements[0]['fromUserName'], 'Bob');
      expect(settlements[0]['toUserName'], 'Alice');
    });

    // ------------------------------------------------------------------
    // Edge case: empty balances list
    // ------------------------------------------------------------------
    test('Empty balances list — no settlements', () {
      final settlements =
          BalanceCalculator.calculateOptimalSettlements(balances: []);

      expect(settlements, isEmpty);
    });

    // ------------------------------------------------------------------
    // Edge case: very small amounts near zero are still transferred
    // ------------------------------------------------------------------
    test('Very small amounts near zero are still transferred', () {
      final balances = [
        _balance('a', 'Alice', Decimal.parse('0.001')),
        _balance('b', 'Bob', Decimal.parse('-0.001')),
      ];

      final settlements =
          BalanceCalculator.calculateOptimalSettlements(balances: balances);

      expect(settlements, hasLength(1));
      expect(settlements[0]['amount'], Decimal.parse('0.001'));
    });

    // ------------------------------------------------------------------
    // Edge case: 8+ participants with complex cross-debts
    // ------------------------------------------------------------------
    test('8 participants with complex cross-debts — settlement count <= N-1', () {
      // 4 creditors (a, b, c, d) and 4 debtors (e, f, g, h)
      // Total credits = total debits = 100
      final balances = [
        _balance('a', 'Alice', Decimal.parse('40')),
        _balance('b', 'Bob', Decimal.parse('30')),
        _balance('c', 'Charlie', Decimal.parse('20')),
        _balance('d', 'Diana', Decimal.parse('10')),
        _balance('e', 'Eve', Decimal.parse('-35')),
        _balance('f', 'Frank', Decimal.parse('-30')),
        _balance('g', 'Grace', Decimal.parse('-20')),
        _balance('h', 'Hiro', Decimal.parse('-15')),
      ];

      final settlements =
          BalanceCalculator.calculateOptimalSettlements(balances: balances);

      // Greedy produces at most N-1 = 7 transactions (8 participants - 1)
      expect(settlements.length, lessThanOrEqualTo(7));

      // Total transferred should equal 100
      final totalTransferred = settlements.fold<Decimal>(
        Decimal.zero,
        (sum, s) => sum + (s['amount'] as Decimal),
      );
      expect(totalTransferred, Decimal.parse('100'));

      // Every sender is a debtor
      for (final s in settlements) {
        expect(['e', 'f', 'g', 'h'], contains(s['fromUserId']));
        expect(['a', 'b', 'c', 'd'], contains(s['toUserId']));
      }
    });
  });

  // ---------------------------------------------------------------------------
  // Multi-event settlement
  // ---------------------------------------------------------------------------
  group('Multi-event settlement', () {
    // These tests simulate the groupBalancesProvider scenario where balances
    // are computed from expenses spanning 3+ events (different tripIds) and
    // passed to calculateOptimalSettlements.

    test('Multi-event: balances from 3 events — optimizer produces few transactions (greedy, not provably minimal)', () {
      // After aggregating 3 events, the final net balances are:
      //   uid-1: +50 (paid most across events)
      //   uid-2: +10 (paid a bit extra)
      //   uid-3: -30 (owes from events A and B)
      //   uid-4: -30 (owes from events B and C)
      //
      // Minimum transactions: 2 (both debtors pay uid-1 first, then uid-2)
      final balances = [
        _balance('uid-1', 'Ahmed', Decimal.parse('50')),
        _balance('uid-2', 'Nasser', Decimal.parse('10')),
        _balance('uid-3', 'Sara', Decimal.parse('-30')),
        _balance('uid-4', 'Fatima', Decimal.parse('-30')),
      ];

      final settlements =
          BalanceCalculator.calculateOptimalSettlements(balances: balances);

      expect(settlements.length, lessThanOrEqualTo(3));

      // Total transferred must equal total debt (60)
      final totalTransferred = settlements.fold<Decimal>(
        Decimal.zero,
        (sum, s) => sum + (s['amount'] as Decimal),
      );
      expect(totalTransferred, Decimal.parse('60'));

      // All senders should be debtors
      for (final s in settlements) {
        expect(['uid-3', 'uid-4'], contains(s['fromUserId']));
        expect(['uid-1', 'uid-2'], contains(s['toUserId']));
      }
    });

    test('Multi-event: single remaining creditor after all events — one settlement per debtor', () {
      // After 3 events, only uid-1 is owed money. uid-2, uid-3 each owe uid-1.
      final balances = [
        _balance('uid-1', 'Ahmed', Decimal.parse('60')),
        _balance('uid-2', 'Nasser', Decimal.parse('-25')),
        _balance('uid-3', 'Sara', Decimal.parse('-35')),
      ];

      final settlements =
          BalanceCalculator.calculateOptimalSettlements(balances: balances);

      // Exactly 2 settlements, both to uid-1
      expect(settlements, hasLength(2));
      for (final s in settlements) {
        expect(s['toUserId'], equals('uid-1'));
      }

      final totalTransferred = settlements.fold<Decimal>(
        Decimal.zero,
        (sum, s) => sum + (s['amount'] as Decimal),
      );
      expect(totalTransferred, Decimal.parse('60'));
    });

    test('Multi-event: D-06 confirmed — BalanceCalculator is scope-agnostic (tripId irrelevant)', () {
      // Verify that expenses with different tripIds aggregate correctly.
      // This test encodes the D-06 decision: BalanceCalculator handles
      // combined multi-event expense lists without code changes.
      final participants = [
        Participant(
          id: 'u1',
          tripId: 'eventA',
          role: ParticipantRole.leader,
          joinedAt: DateTime(2026),
          displayName: 'Alice',
        ),
        Participant(
          id: 'u2',
          tripId: 'eventA',
          role: ParticipantRole.member,
          joinedAt: DateTime(2026),
          displayName: 'Bob',
        ),
      ];

      // Three expenses from three different tripIds
      final expenses = [
        Expense(
          id: 'e1',
          tripId: 'event-alpha',
          payerParticipantId: 'u1',
          amount: Decimal.parse('30.000'),
          scope: ExpenseScope.global,
          createdAt: DateTime(2026),
        ),
        Expense(
          id: 'e2',
          tripId: 'event-beta',
          payerParticipantId: 'u1',
          amount: Decimal.parse('20.000'),
          scope: ExpenseScope.global,
          createdAt: DateTime(2026),
        ),
        Expense(
          id: 'e3',
          tripId: 'event-gamma',
          payerParticipantId: 'u2',
          amount: Decimal.parse('10.000'),
          scope: ExpenseScope.global,
          createdAt: DateTime(2026),
        ),
      ];

      final balances = BalanceCalculator.calculateBalances(
        expenses: expenses,
        participants: participants,
      );

      final optimalSettlements =
          BalanceCalculator.calculateOptimalSettlements(balances: balances);

      // u1 paid 50, u2 paid 10 → total 60 split 2 ways = 30 each
      // u1 net = 50 - 30 = +20
      // u2 net = 10 - 30 = -20
      // 1 optimal settlement: u2 → u1 for 20
      expect(optimalSettlements, hasLength(1));
      expect(optimalSettlements.first['fromUserId'], equals('u2'));
      expect(optimalSettlements.first['toUserId'], equals('u1'));
      expect(optimalSettlements.first['amount'], equals(Decimal.parse('20.000')));
    });
  });

  // ---------------------------------------------------------------------------
  // calculateTotalExpenses
  // ---------------------------------------------------------------------------
  group('calculateTotalExpenses', () {
    test('Empty list — returns Decimal.zero', () {
      final total = BalanceCalculator.calculateTotalExpenses([]);
      expect(total, Decimal.zero);
    });

    test('Multiple expenses from different events — correct sum', () {
      final expenses = [
        Expense(
          id: 'e1',
          tripId: 'eventA',
          payerParticipantId: 'p1',
          amount: Decimal.parse('30.000'),
          scope: ExpenseScope.global,
          createdAt: DateTime(2026),
        ),
        Expense(
          id: 'e2',
          tripId: 'eventB',
          payerParticipantId: 'p2',
          amount: Decimal.parse('25.500'),
          scope: ExpenseScope.global,
          createdAt: DateTime(2026),
        ),
        Expense(
          id: 'e3',
          tripId: 'eventC',
          payerParticipantId: 'p1',
          amount: Decimal.parse('14.500'),
          scope: ExpenseScope.global,
          createdAt: DateTime(2026),
        ),
      ];

      final total = BalanceCalculator.calculateTotalExpenses(expenses);
      expect(total, Decimal.parse('70.000'),
          reason: '30 + 25.5 + 14.5 = 70.000');
    });

    test('Mix of scopes — all included in total regardless of scope', () {
      // calculateTotalExpenses sums all expenses regardless of scope
      final expenses = [
        Expense(
          id: 'e1',
          tripId: 't1',
          payerParticipantId: 'p1',
          amount: Decimal.parse('10.000'),
          scope: ExpenseScope.global,
          createdAt: DateTime(2026),
        ),
        Expense(
          id: 'e2',
          tripId: 't1',
          payerParticipantId: 'p1',
          amount: Decimal.parse('5.000'),
          scope: ExpenseScope.personal,
          createdAt: DateTime(2026),
        ),
        Expense(
          id: 'e3',
          tripId: 't1',
          payerParticipantId: 'p2',
          amount: Decimal.parse('15.000'),
          scope: ExpenseScope.custom,
          customSplitParticipants: ['p1', 'p2'],
          createdAt: DateTime(2026),
        ),
        Expense(
          id: 'e4',
          tripId: 't1',
          payerParticipantId: 'p2',
          amount: Decimal.parse('20.000'),
          scope: ExpenseScope.subGroup,
          subGroupId: 'sg1',
          createdAt: DateTime(2026),
        ),
      ];

      final total = BalanceCalculator.calculateTotalExpenses(expenses);
      expect(total, Decimal.parse('50.000'),
          reason: '10 + 5 + 15 + 20 = 50.000 across all 4 scopes');
    });

    test('Single expense — returns exact amount with Decimal precision', () {
      final expenses = [
        Expense(
          id: 'e1',
          tripId: 't1',
          payerParticipantId: 'p1',
          amount: Decimal.parse('33.333'),
          scope: ExpenseScope.global,
          createdAt: DateTime(2026),
        ),
      ];

      final total = BalanceCalculator.calculateTotalExpenses(expenses);
      expect(total, Decimal.parse('33.333'));
    });
  });
}
