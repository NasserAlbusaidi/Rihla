import 'package:decimal/decimal.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:safar/features/ledger/models/expense_model.dart';
import 'package:safar/features/ledger/providers/expense_provider.dart';

/// #382 PR-5 — pure per-currency display helpers replacing the interim
/// single-bucket selectors. The zero predicate is EXACT `Decimal.zero` (L13):
/// no tolerance, so sub-0.001 residuals stay visible instead of silently
/// reading as settled.
void main() {
  UserBalance balance(String id, String net) => UserBalance(
    participantId: id,
    displayName: id,
    totalPaid: Decimal.zero,
    totalOwed: Decimal.zero,
    netBalance: Decimal.parse(net),
  );

  group('nonZeroNetsGccFirst', () {
    test('orders mixed-sign buckets GCC-first (OMR before USD)', () {
      final lines = nonZeroNetsGccFirst({
        'USD': Decimal.parse('-3'),
        'OMR': Decimal.parse('1.4'),
      });

      expect(lines, [
        (currency: 'OMR', net: Decimal.parse('1.4')),
        (currency: 'USD', net: Decimal.parse('-3')),
      ]);
    });

    test('all-zero map is empty (settled everywhere)', () {
      expect(
        nonZeroNetsGccFirst({'OMR': Decimal.zero, 'USD': Decimal.zero}),
        isEmpty,
      );
      expect(nonZeroNetsGccFirst(const {}), isEmpty);
    });

    test('sub-0.001 residual is NON-zero — exact predicate, no tolerance', () {
      final lines = nonZeroNetsGccFirst({'OMR': Decimal.parse('0.0001')});

      expect(lines, [(currency: 'OMR', net: Decimal.parse('0.0001'))]);
    });
  });

  group('myNetByCurrency', () {
    test('returns my net per currency, exactly-zero buckets dropped', () {
      final nets = myNetByCurrency({
        'OMR': [balance('me', '0'), balance('other', '5')],
        'USD': [balance('me', '-3'), balance('other', '3')],
      }, 'me');

      expect(nets, {'USD': Decimal.parse('-3')});
    });

    test('null uid yields empty', () {
      expect(
        myNetByCurrency({
          'OMR': [balance('me', '5')],
        }, null),
        isEmpty,
      );
    });

    test('uid absent from a bucket drops that bucket', () {
      final nets = myNetByCurrency({
        'OMR': [balance('other', '5')],
        'USD': [balance('me', '2')],
      }, 'me');

      expect(nets, {'USD': Decimal.parse('2')});
    });

    test('sub-0.001 residual survives — exact zero predicate here too', () {
      final nets = myNetByCurrency({
        'OMR': [balance('me', '0.0001')],
      }, 'me');

      expect(nets, {'OMR': Decimal.parse('0.0001')});
    });
  });
}
