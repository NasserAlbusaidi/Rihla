import 'package:decimal/decimal.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:safar/core/models/split_mode.dart';
import 'package:safar/features/ledger/models/expense_model.dart';
import 'package:safar/features/ledger/providers/expense_provider.dart';
import 'package:safar/features/trip/models/trip_model.dart';

/// #242 — the PUBLIC, PURE per-expense allocator extracted from
/// [BalanceCalculator.calculateBalances] so the expense-editor split preview
/// can show the SAME owed amounts that get persisted (true WYSIWYG), without a
/// second copy of the money math.
///
/// These tests pin the public contract directly AND assert byte-for-byte parity
/// with [calculateBalances] (the cross-impl ORACLE). The clean/warning/error
/// table is mandatory for money code.
void main() {
  Decimal d(String s) => Decimal.parse(s);

  Participant participant(String id) => Participant(
        id: id,
        tripId: 'event-1',
        role: ParticipantRole.member,
        joinedAt: DateTime(2026),
        displayName: id,
      );

  Map<String, Decimal> allocate({
    required String amount,
    required SplitMode? splitMode,
    Map<String, Decimal>? splitDistribution,
    ExpenseScope scope = ExpenseScope.global,
    List<String>? customSplitParticipants,
    String payerId = 'p1',
    List<String> participantIds = const ['p1', 'p2', 'p3'],
    String currency = 'OMR',
    void Function(SplitFallbackReason reason)? onFallback,
  }) {
    return BalanceCalculator.allocateExpenseOwed(
      amount: d(amount),
      splitMode: splitMode,
      splitDistribution: splitDistribution,
      scope: scope,
      customSplitParticipants: customSplitParticipants,
      payerId: payerId,
      participantIds: participantIds,
      currency: currency,
      onFallback: onFallback,
    );
  }

  group('allocateExpenseOwed — mode-allocator path (clean)', () {
    test('shares 2:1 on 9.000 → 6.000 / 3.000 (weight, not currency)', () {
      final owed = allocate(
        amount: '9.000',
        splitMode: SplitMode.shares,
        splitDistribution: {'a': d('2'), 'b': d('1')},
      );
      expect(owed, {'a': d('6.000'), 'b': d('3.000')});
      // The raw weight 2 is NEVER rendered as 2.000 currency.
      expect(owed['a'], isNot(d('2.000')));
    });

    test('percent 60/40 on 10.000 → 6.000 / 4.000 (percent number, not currency)',
        () {
      final owed = allocate(
        amount: '10.000',
        splitMode: SplitMode.percent,
        splitDistribution: {'a': d('60'), 'b': d('40')},
      );
      expect(owed, {'a': d('6.000'), 'b': d('4.000')});
      // 60 is a percent, never 60.000 currency.
      expect(owed['a'], isNot(d('60.000')));
    });

    test('exact summing to amount → returned verbatim', () {
      final owed = allocate(
        amount: '4.900',
        splitMode: SplitMode.exact,
        splitDistribution: {'a': d('1.600'), 'b': d('2.100'), 'c': d('1.200')},
      );
      expect(owed, {'a': d('1.600'), 'b': d('2.100'), 'c': d('1.200')});
    });

    test('exact in-tolerance under-allocation → residual onto alphabetically-last',
        () {
      // total 2.000, amount 2.001, residual +0.001 (== tolerance, not drift).
      final owed = allocate(
        amount: '2.001',
        splitMode: SplitMode.exact,
        splitDistribution: {'a': d('1.000'), 'b': d('1.000')},
      );
      expect(owed, {'a': d('1.000'), 'b': d('1.001')});
      expect(owed.values.fold(Decimal.zero, (s, v) => s + v), d('2.001'));
    });

    test('exact over-allocation skips a 0.000 entry to avoid a phantom credit',
        () {
      // total 3.000, amount 2.999, residual -0.001. b=0.000 cannot absorb a
      // negative without going negative → a absorbs it. (non-negative scan)
      final owed = allocate(
        amount: '2.999',
        splitMode: SplitMode.exact,
        splitDistribution: {'a': d('3.000'), 'b': d('0.000')},
      );
      expect(owed, {'a': d('2.999'), 'b': d('0.000')});
      expect(owed.values.every((v) => v >= Decimal.zero), isTrue);
    });
  });

  group('allocateExpenseOwed — scope/equal path (clean)', () {
    test('null mode + global scope → equal per-head over participantIds', () {
      final owed = allocate(amount: '9.000', splitMode: null);
      expect(owed, {'p1': d('3.000'), 'p2': d('3.000'), 'p3': d('3.000')});
    });

    test('equally mode + custom scope → only the custom set', () {
      final owed = allocate(
        amount: '9.000',
        splitMode: SplitMode.equally,
        scope: ExpenseScope.custom,
        customSplitParticipants: ['p1', 'p3'],
      );
      expect(owed, {'p1': d('4.500'), 'p3': d('4.500')});
    });

    test('personal scope → only the payer owes', () {
      final owed = allocate(
        amount: '9.000',
        splitMode: null,
        scope: ExpenseScope.personal,
        payerId: 'p2',
      );
      expect(owed, {'p2': d('9.000')});
    });

    test('equal remainder lands on alphabetically-last id (10.000 / 3)', () {
      final owed = allocate(
        amount: '10.000',
        splitMode: SplitMode.equally,
        participantIds: const ['a', 'b', 'c'],
      );
      expect(owed, {'a': d('3.333'), 'b': d('3.333'), 'c': d('3.334')});
      expect(owed.values.fold(Decimal.zero, (s, v) => s + v), d('10.000'));
    });

    test('JPY (scale 1) equal split rounds to whole units', () {
      final owed = allocate(
        amount: '100',
        splitMode: SplitMode.equally,
        participantIds: const ['a', 'b', 'c'],
        currency: 'JPY',
      );
      // 100 / 3 = 33 each, last absorbs +1.
      expect(owed, {'a': d('33'), 'b': d('33'), 'c': d('34')});
    });

    test(
        'OMR 2.900 / 8 terminating sub-baisa → whole-baisa shares, server '
        'quantize parity (#596)', () {
      // 2.900 / 8 = 0.3625 is a FINITE rational, so toDecimal's
      // scaleOnInfinitePrecision never engages. Pre-#596 the client kept the raw
      // half-baisa (every head 0.3625), diverging from the server allocateEqual
      // (groupNetBalance.ts:152 `quantize` ROUND_DOWN): 7 owe 0.362, the
      // alphabetically-last absorbs the 0.004 remainder → 0.366.
      final owed = allocate(
        amount: '2.900',
        splitMode: SplitMode.equally,
        participantIds: const ['a', 'b', 'c', 'd', 'e', 'f', 'g', 'h'],
      );
      for (final id in const ['a', 'b', 'c', 'd', 'e', 'f', 'g']) {
        expect(owed[id], d('0.362'), reason: '$id owes whole-baisa 0.362');
      }
      expect(owed['h'], d('0.366'), reason: 'last absorbs the 0.004 remainder');
      expect(
        owed.values.every((v) => v != d('0.3625')),
        isTrue,
        reason: 'no half-baisa share may survive quantization',
      );
      expect(owed.values.fold(Decimal.zero, (s, v) => s + v), d('2.900'));
    });

    test(
        'USD 0.10 / 8 terminating sub-cent → whole-cent shares '
        '(currency-general, #596)', () {
      // 0.10 / 8 = 0.0125 terminates below cent precision → quantize to 0.01
      // each (scale 100), last absorbs the 0.02 remainder → 0.03. Proves the fix
      // is not OMR-special.
      final owed = allocate(
        amount: '0.10',
        splitMode: SplitMode.equally,
        participantIds: const ['a', 'b', 'c', 'd', 'e', 'f', 'g', 'h'],
        currency: 'USD',
      );
      for (final id in const ['a', 'b', 'c', 'd', 'e', 'f', 'g']) {
        expect(owed[id], d('0.01'));
      }
      expect(owed['h'], d('0.03'));
      expect(owed.values.fold(Decimal.zero, (s, v) => s + v), d('0.10'));
    });
  });

  group('allocateExpenseOwed — fallback (warning/error) + telemetry decoupling',
      () {
    test('negative share → equal fallback; onFallback spy gets negativeShares',
        () {
      SplitFallbackReason? seen;
      final owed = allocate(
        amount: '9.000',
        splitMode: SplitMode.shares,
        splitDistribution: {'a': d('-1'), 'b': d('2')},
        onFallback: (r) => seen = r,
      );
      expect(seen, SplitFallbackReason.negativeShares);
      expect(owed, {'a': d('4.500'), 'b': d('4.500')});
    });

    test('percent drift → equal fallback (percentDrift)', () {
      SplitFallbackReason? seen;
      final owed = allocate(
        amount: '10.000',
        splitMode: SplitMode.percent,
        splitDistribution: {'a': d('60'), 'b': d('20')}, // sums 80, not 100
        onFallback: (r) => seen = r,
      );
      expect(seen, SplitFallbackReason.percentDrift);
      expect(owed, {'a': d('5.000'), 'b': d('5.000')});
    });

    test(
        'onFallback null → NO throw and the static Sentry hook is NEVER called',
        () {
      final original = BalanceCalculator.onSplitFallback;
      var hookCalls = 0;
      BalanceCalculator.onSplitFallback = (_, _) => hookCalls++;
      addTearDown(() => BalanceCalculator.onSplitFallback = original);

      final owed = allocate(
        amount: '9.000',
        splitMode: SplitMode.shares,
        splitDistribution: {'a': d('-1'), 'b': d('2')},
        onFallback: null, // the preview path
      );

      expect(hookCalls, 0, reason: 'pure preview must not emit Sentry/debugPrint');
      expect(owed, {'a': d('4.500'), 'b': d('4.500')});
    });
  });

  group('allocateExpenseOwed — parity with calculateBalances (ORACLE)', () {
    Map<String, Decimal> owedFromCalc({
      required Expense e,
      required List<String> participantIds,
    }) {
      final balances = BalanceCalculator.calculateBalances(
        expenses: [e],
        participants: [for (final id in participantIds) participant(id)],
      )[e.currency]!;
      return {
        for (final b in balances)
          if (b.totalOwed != Decimal.zero) b.participantId: b.totalOwed,
      };
    }

    test('shares parity: single-expense contribution matches', () {
      final e = Expense(
        id: 'e1',
        tripId: 'event-1',
        payerParticipantId: 'p1',
        amount: d('9.000'),
        scope: ExpenseScope.global,
        splitMode: SplitMode.shares,
        splitDistribution: {'p1': d('2'), 'p2': d('1')},
        createdAt: DateTime(2026),
        currency: 'OMR',
      );
      final viaCalc = owedFromCalc(e: e, participantIds: ['p1', 'p2']);
      final viaPure = allocate(
        amount: '9.000',
        splitMode: SplitMode.shares,
        splitDistribution: {'p1': d('2'), 'p2': d('1')},
        participantIds: const ['p1', 'p2'],
      );
      expect(viaPure, viaCalc);
    });

    test(
        'DUP custom id parity: scope .toSet() dedup preserved (NOT _allocateEqual over a List)',
        () {
      // customSplitParticipants is List<String>? — a dup is type-possible.
      // calculateBalances .toSet()s → {p1,p2}, perHead = 9/2 = 4.500.
      // A naive _allocateEqual over ['p1','p1','p2'] would split 3 ways. Guard.
      final e = Expense(
        id: 'e2',
        tripId: 'event-1',
        payerParticipantId: 'p1',
        amount: d('9.000'),
        scope: ExpenseScope.custom,
        customSplitParticipants: ['p1', 'p1', 'p2'],
        splitMode: null,
        createdAt: DateTime(2026),
        currency: 'OMR',
      );
      final viaCalc = owedFromCalc(e: e, participantIds: ['p1', 'p2', 'p3']);
      final viaPure = allocate(
        amount: '9.000',
        splitMode: null,
        scope: ExpenseScope.custom,
        customSplitParticipants: ['p1', 'p1', 'p2'],
        participantIds: const ['p1', 'p2', 'p3'],
      );
      expect(viaCalc, {'p1': d('4.500'), 'p2': d('4.500')});
      expect(viaPure, viaCalc);
    });
  });
}
