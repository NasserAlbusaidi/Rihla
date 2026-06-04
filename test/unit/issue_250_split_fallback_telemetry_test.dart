import 'package:decimal/decimal.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:safar/core/models/split_mode.dart';
import 'package:safar/features/ledger/models/expense_model.dart';
import 'package:safar/features/ledger/providers/expense_provider.dart';
import 'package:safar/features/trip/models/trip_model.dart';

// Regression suite — issue #250 (remainder box). PR #253 shipped the add/edit
// write-boundary guard that blocks the only UI-reachable silent re-split. This
// pins the issue's other named box: when a malformed `splitDistribution` reaches
// `BalanceCalculator` anyway (a forged / legacy / Admin-SDK write that bypassed
// the UI), the equal-split fallback must emit a NON-debug telemetry signal — not
// just a `debugPrint` that no one ever sees. There is no user to warn on these
// paths, so the contract is observability: every fallback notifies the
// overridable `BalanceCalculator.onSplitFallback` sink with the right reason.
//
// The seam also keeps the pure money oracle decoupled from the Sentry SDK: the
// default sink is the only SDK touchpoint; tests swap it for a capture closure.
void main() {
  Participant participant(String id) => Participant(
    id: id,
    tripId: 'event-1',
    role: ParticipantRole.member,
    joinedAt: DateTime(2026),
    displayName: id,
  );

  Expense expense({
    required String id,
    required String amount,
    required SplitMode splitMode,
    required Map<String, Decimal> splitDistribution,
    String currency = 'OMR',
  }) {
    return Expense(
      id: id,
      tripId: 'event-1',
      payerParticipantId: 'p1',
      amount: Decimal.parse(amount),
      scope: ExpenseScope.global,
      splitMode: splitMode,
      splitDistribution: splitDistribution,
      createdAt: DateTime(2026),
      currency: currency,
    );
  }

  final participants = [participant('p1'), participant('p2'), participant('p3')];

  // Capture every fallback the calculator reports during a test.
  late List<({SplitFallbackReason reason, String expenseId})> captured;
  late void Function(SplitFallbackReason, Expense) original;

  setUp(() {
    captured = [];
    original = BalanceCalculator.onSplitFallback;
    BalanceCalculator.onSplitFallback = (reason, expense) {
      captured.add((reason: reason, expenseId: expense.id));
    };
  });

  tearDown(() {
    BalanceCalculator.onSplitFallback = original;
  });

  group('BalanceCalculator emits telemetry on every split fallback (#250)', () {
    final cases = <({
      String name,
      String id,
      String amount,
      SplitMode mode,
      Map<String, Decimal> distribution,
      SplitFallbackReason expected,
    })>[
      (
        name: 'negative shares entry',
        id: 'exp-neg-shares',
        amount: '10.000',
        mode: SplitMode.shares,
        distribution: {'p1': Decimal.parse('2'), 'p2': Decimal.parse('-1')},
        expected: SplitFallbackReason.negativeShares,
      ),
      (
        name: 'shares sum to zero',
        id: 'exp-zero-shares',
        amount: '10.000',
        mode: SplitMode.shares,
        distribution: {'p1': Decimal.zero, 'p2': Decimal.zero},
        expected: SplitFallbackReason.invalidShares,
      ),
      (
        name: 'negative exact entry',
        id: 'exp-neg-exact',
        amount: '10.000',
        mode: SplitMode.exact,
        distribution: {
          'p1': Decimal.parse('-1.000'),
          'p2': Decimal.parse('11.000'),
        },
        expected: SplitFallbackReason.negativeExact,
      ),
      (
        name: 'exact sum drifts past tolerance',
        id: 'exp-exact-drift',
        amount: '10.000',
        mode: SplitMode.exact,
        distribution: {
          'p1': Decimal.parse('3.000'),
          'p2': Decimal.parse('3.000'),
          'p3': Decimal.parse('3.000'),
        },
        expected: SplitFallbackReason.exactAmountDrift,
      ),
      (
        // Forged sub-precision write: in-tolerance drift whose residual cannot
        // be absorbed by any recipient without going negative. amount 0.0005,
        // {p1: 0.0006, p2: 0.0006} → sum 0.0012 (drift 0.0007 <= 0.001),
        // residual -0.0007; neither 0.0006 entry can absorb it → no target.
        name: 'exact residual unabsorbable (forged sub-precision)',
        id: 'exp-exact-residual',
        amount: '0.0005',
        mode: SplitMode.exact,
        distribution: {
          'p1': Decimal.parse('0.0006'),
          'p2': Decimal.parse('0.0006'),
        },
        expected: SplitFallbackReason.exactResidualUnabsorbable,
      ),
      (
        name: 'negative percent entry',
        id: 'exp-neg-percent',
        amount: '10.000',
        mode: SplitMode.percent,
        distribution: {
          'p1': Decimal.parse('-10'),
          'p2': Decimal.parse('110'),
        },
        expected: SplitFallbackReason.negativePercent,
      ),
      (
        name: 'percent off 100',
        id: 'exp-percent-drift',
        amount: '10.000',
        mode: SplitMode.percent,
        distribution: {'p1': Decimal.parse('40'), 'p2': Decimal.parse('40')},
        expected: SplitFallbackReason.percentDrift,
      ),
    ];

    for (final c in cases) {
      test('${c.name} → ${c.expected.name}', () {
        BalanceCalculator.calculateBalances(
          expenses: [
            expense(
              id: c.id,
              amount: c.amount,
              splitMode: c.mode,
              splitDistribution: c.distribution,
            ),
          ],
          participants: participants,
        );

        expect(captured, hasLength(1));
        expect(captured.single.reason, c.expected);
        expect(captured.single.expenseId, c.id);
      });
    }

    test('negative-shares fallback still equal-splits (math unchanged)', () {
      // The telemetry seam must not alter the fallback's money output.
      final balances = BalanceCalculator.calculateBalances(
        expenses: [
          expense(
            id: 'exp-neg-shares',
            amount: '10.000',
            splitMode: SplitMode.shares,
            splitDistribution: {
              'p1': Decimal.parse('2'),
              'p2': Decimal.parse('-1'),
            },
          ),
        ],
        participants: participants,
      );
      Decimal owed(String id) =>
          balances.singleWhere((b) => b.participantId == id).totalOwed;
      // Equal split over the distribution's keys {p1, p2}.
      expect(owed('p1'), Decimal.parse('5.000'));
      expect(owed('p2'), Decimal.parse('5.000'));
      expect(captured, hasLength(1));
    });
  });

  group('clean splits never report a fallback (#250)', () {
    test('valid exact split is silent', () {
      BalanceCalculator.calculateBalances(
        expenses: [
          expense(
            id: 'exp-clean-exact',
            amount: '10.000',
            splitMode: SplitMode.exact,
            splitDistribution: {
              'p1': Decimal.parse('5.000'),
              'p2': Decimal.parse('5.000'),
            },
          ),
        ],
        participants: participants,
      );
      expect(captured, isEmpty);
    });

    test('valid shares split is silent', () {
      BalanceCalculator.calculateBalances(
        expenses: [
          expense(
            id: 'exp-clean-shares',
            amount: '10.000',
            splitMode: SplitMode.shares,
            splitDistribution: {
              'p1': Decimal.parse('1'),
              'p2': Decimal.parse('1'),
            },
          ),
        ],
        participants: participants,
      );
      expect(captured, isEmpty);
    });

    test('valid percent split is silent', () {
      BalanceCalculator.calculateBalances(
        expenses: [
          expense(
            id: 'exp-clean-percent',
            amount: '10.000',
            splitMode: SplitMode.percent,
            splitDistribution: {
              'p1': Decimal.parse('50'),
              'p2': Decimal.parse('50'),
            },
          ),
        ],
        participants: participants,
      );
      expect(captured, isEmpty);
    });
  });
}
