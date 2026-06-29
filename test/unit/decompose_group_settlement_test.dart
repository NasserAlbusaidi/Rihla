import 'package:decimal/decimal.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:safar/core/services/money_serializer.dart';
import 'package:safar/features/ledger/providers/expense_provider.dart';

Decimal _d(String s) => Decimal.parse(s);

/// eventId -> currency -> net, the shape of `perEventBreakdown[participantId]`.
Map<String, Map<String, Decimal>> _net(Map<String, Map<String, String>> raw) =>
    raw.map((eventId, byCur) => MapEntry(
          eventId,
          byCur.map((cur, v) => MapEntry(cur, _d(v))),
        ));

void main() {
  group('BalanceCalculator.decomposeGroupSettlement', () {
    test('case 1 — single event, full amount: {E1:10}, residual 0', () {
      final r = BalanceCalculator.decomposeGroupSettlement(
        payerPerEventNet: _net({
          'E1': {'OMR': '-10'}
        }),
        recipientPerEventNet: _net({
          'E1': {'OMR': '10'}
        }),
        currency: 'OMR',
        amount: _d('10'),
        eventOrder: const ['E1'],
      );
      expect(r.perEvent, {'E1': _d('10.000')});
      expect(r.residual, _d('0'));
    });

    test('case 2 — NEGATIVE-RESIDUAL GUARD: cross-event nets cancel; '
        'payer -10/E1 +4/E2, recipient +10/E1 -4/E2, A=6 → {E1:6}, residual 0',
        () {
      // The naive Σ min(|fromNet|, toNet) would over-count and yield a NEGATIVE
      // residual; the capped subunit allocator must give residual 0.
      final r = BalanceCalculator.decomposeGroupSettlement(
        payerPerEventNet: _net({
          'E1': {'OMR': '-10'},
          'E2': {'OMR': '4'},
        }),
        recipientPerEventNet: _net({
          'E1': {'OMR': '10'},
          'E2': {'OMR': '-4'},
        }),
        currency: 'OMR',
        amount: _d('6'),
        eventOrder: const ['E1', 'E2'],
      );
      expect(r.perEvent, {'E1': _d('6.000')});
      expect(r.residual, _d('0'));
    });

    test('case 3 — cross-event residual, no shared event: {}, residual 5', () {
      final r = BalanceCalculator.decomposeGroupSettlement(
        payerPerEventNet: _net({
          'E1': {'OMR': '-5'}
        }),
        recipientPerEventNet: _net({
          'E2': {'OMR': '5'}
        }),
        currency: 'OMR',
        amount: _d('5'),
        eventOrder: const ['E1', 'E2'],
      );
      expect(r.perEvent, isEmpty);
      expect(r.residual, _d('5.000'));
    });

    test('case 4 — partial edit A=4 caps below the earned 10: {E1:4}, residual 0',
        () {
      final r = BalanceCalculator.decomposeGroupSettlement(
        payerPerEventNet: _net({
          'E1': {'OMR': '-10'}
        }),
        recipientPerEventNet: _net({
          'E1': {'OMR': '10'}
        }),
        currency: 'OMR',
        amount: _d('4'),
        eventOrder: const ['E1'],
      );
      expect(r.perEvent, {'E1': _d('4.000')});
      expect(r.residual, _d('0'));
    });

    test('case 5 — multi-event cap exhaustion is ORDER-dependent; '
        'totals/residual are order-INVARIANT', () {
      final payer = _net({
        'E1': {'OMR': '-3'},
        'E2': {'OMR': '-5'},
      });
      final recipient = _net({
        'E1': {'OMR': '10'},
        'E2': {'OMR': '10'},
      });

      final fwd = BalanceCalculator.decomposeGroupSettlement(
        payerPerEventNet: payer,
        recipientPerEventNet: recipient,
        currency: 'OMR',
        amount: _d('6'),
        eventOrder: const ['E1', 'E2'],
      );
      expect(fwd.perEvent, {'E1': _d('3.000'), 'E2': _d('3.000')});
      expect(fwd.residual, _d('0'));

      final rev = BalanceCalculator.decomposeGroupSettlement(
        payerPerEventNet: payer,
        recipientPerEventNet: recipient,
        currency: 'OMR',
        amount: _d('6'),
        eventOrder: const ['E2', 'E1'],
      );
      // Different per-event split…
      expect(rev.perEvent, {'E2': _d('5.000'), 'E1': _d('1.000')});
      // …but identical total + residual (money is never order-wrong).
      expect(rev.residual, _d('0'));
      final fwdTotal =
          fwd.perEvent.values.fold(Decimal.zero, (s, v) => s + v) + fwd.residual;
      final revTotal =
          rev.perEvent.values.fold(Decimal.zero, (s, v) => s + v) + rev.residual;
      expect(fwdTotal, _d('6'));
      expect(revTotal, _d('6'));
    });

    test('case 6 — multi-currency isolation: USD decompose ignores OMR nets', () {
      final r = BalanceCalculator.decomposeGroupSettlement(
        payerPerEventNet: _net({
          'E1': {'OMR': '-10', 'USD': '-7'}
        }),
        recipientPerEventNet: _net({
          'E1': {'OMR': '10', 'USD': '7'}
        }),
        currency: 'USD',
        amount: _d('7'),
        eventOrder: const ['E1'],
      );
      expect(r.perEvent, {'E1': _d('7.00')});
      expect(r.residual, _d('0'));
    });

    test('case 7 — conservation: Σ subunits(perEvent) + subunits(residual) == '
        'subunits(amount) AND residual >= 0, over assorted inputs', () {
      final scenarios = <Map<String, dynamic>>[
        {
          'payer': _net({
            'E1': {'OMR': '-10'},
            'E2': {'OMR': '4'},
          }),
          'recipient': _net({
            'E1': {'OMR': '10'},
            'E2': {'OMR': '-4'},
          }),
          'cur': 'OMR',
          'amount': _d('6'),
          'order': const ['E1', 'E2'],
        },
        {
          'payer': _net({
            'E1': {'OMR': '-3.250'},
            'E2': {'OMR': '-5.125'},
          }),
          'recipient': _net({
            'E1': {'OMR': '3.250'},
            'E2': {'OMR': '5.125'},
          }),
          'cur': 'OMR',
          'amount': _d('8.375'),
          'order': const ['E1', 'E2'],
        },
        {
          'payer': _net({
            'E1': {'USD': '-9.99'},
          }),
          'recipient': _net({
            'E2': {'USD': '9.99'},
          }),
          'cur': 'USD',
          'amount': _d('9.99'),
          'order': const ['E1', 'E2'],
        },
        {
          'payer': _net({
            'E1': {'OMR': '-2'},
          }),
          'recipient': _net({
            'E1': {'OMR': '2'},
          }),
          'cur': 'OMR',
          'amount': _d('5'), // amount exceeds the single event cap → residual 3
          'order': const ['E1'],
        },
      ];

      for (final s in scenarios) {
        final cur = s['cur'] as String;
        final amount = s['amount'] as Decimal;
        final r = BalanceCalculator.decomposeGroupSettlement(
          payerPerEventNet: s['payer'] as Map<String, Map<String, Decimal>>,
          recipientPerEventNet:
              s['recipient'] as Map<String, Map<String, Decimal>>,
          currency: cur,
          amount: amount,
          eventOrder: s['order'] as List<String>,
        );
        final sumPerEvent = r.perEvent.values
            .fold(0, (acc, v) => acc + MoneySerializer.toSubunits(v, cur));
        expect(
          sumPerEvent + MoneySerializer.toSubunits(r.residual, cur),
          MoneySerializer.toSubunits(amount, cur),
          reason: 'conservation failed for $s',
        );
        expect(r.residual >= Decimal.zero, isTrue,
            reason: 'negative residual for $s');
        for (final v in r.perEvent.values) {
          expect(v >= Decimal.zero, isTrue, reason: 'negative per-event for $s');
        }
      }
    });

    test('case 8 — JPY (scale 1) exact + every output is whole-subunit', () {
      final r = BalanceCalculator.decomposeGroupSettlement(
        payerPerEventNet: _net({
          'E1': {'JPY': '-500'},
          'E2': {'JPY': '-300'},
        }),
        recipientPerEventNet: _net({
          'E1': {'JPY': '900'},
          'E2': {'JPY': '900'},
        }),
        currency: 'JPY',
        amount: _d('800'),
        eventOrder: const ['E1', 'E2'],
      );
      expect(r.perEvent, {'E1': _d('500'), 'E2': _d('300')});
      expect(r.residual, _d('0'));
      for (final v in r.perEvent.values) {
        expect(MoneySerializer.toSubunits(v, 'JPY').toString(),
            isNot(contains('.')));
      }
    });

    test('amount <= 0 → ({}, 0)', () {
      final r = BalanceCalculator.decomposeGroupSettlement(
        payerPerEventNet: _net({
          'E1': {'OMR': '-10'}
        }),
        recipientPerEventNet: _net({
          'E1': {'OMR': '10'}
        }),
        currency: 'OMR',
        amount: Decimal.zero,
        eventOrder: const ['E1'],
      );
      expect(r.perEvent, isEmpty);
      expect(r.residual, _d('0'));
    });
  });
}
