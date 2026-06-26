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

  group('pivotNetsByParticipant', () {
    // #630: one single pass replaces the per-row O(C×M²) myNetByCurrency loops.
    // Contract: pivot[uid] == myNetByCurrency(buckets, uid) for every uid.
    final buckets = <String, List<UserBalance>>{
      'OMR': [balance('a', '5'), balance('b', '0'), balance('c', '-5')],
      'USD': [balance('a', '0'), balance('b', '-3'), balance('c', '3')],
      'EUR': [balance('a', '2')], // b, c absent from this bucket
    };

    test('one pass equals myNetByCurrency per uid (mixed currency/sign/presence)',
        () {
      for (final uid in ['a', 'b', 'c']) {
        final pivot = pivotNetsByParticipant(buckets);
        expect(
          pivot[uid] ?? const <String, Decimal>{},
          myNetByCurrency(buckets, uid),
          reason: 'pivot[$uid] must equal myNetByCurrency for $uid',
        );
      }
    });

    test('exactly-zero entries are dropped (member absent from pivot/bucket)',
        () {
      final pivot = pivotNetsByParticipant(buckets);
      // a: OMR+5, EUR+2 (USD 0 dropped). b: USD-3 (OMR 0 dropped, EUR absent).
      expect(pivot['a'], {'OMR': Decimal.parse('5'), 'EUR': Decimal.parse('2')});
      expect(pivot['b'], {'USD': Decimal.parse('-3')});
      expect(pivot['c'], {'OMR': Decimal.parse('-5'), 'USD': Decimal.parse('3')});
    });

    test('member zero in every bucket is absent entirely', () {
      final pivot = pivotNetsByParticipant({
        'OMR': [balance('z', '0')],
        'USD': [balance('z', '0')],
      });
      expect(pivot['z'], isNull);
      expect(pivot['z'] ?? const <String, Decimal>{}, myNetByCurrency({
        'OMR': [balance('z', '0')],
        'USD': [balance('z', '0')],
      }, 'z'));
    });

    test('sub-0.001 residual survives the pivot — exact zero predicate', () {
      final pivot = pivotNetsByParticipant({
        'OMR': [balance('me', '0.0001')],
      });
      expect(pivot['me'], {'OMR': Decimal.parse('0.0001')});
    });

    test('empty buckets yield empty pivot', () {
      expect(pivotNetsByParticipant(const {}), isEmpty);
    });
  });
}
