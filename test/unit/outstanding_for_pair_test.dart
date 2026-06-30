import 'package:decimal/decimal.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:safar/features/ledger/models/expense_model.dart';
import 'package:safar/features/ledger/providers/expense_provider.dart';

UserBalance _ub(String id, String net) => UserBalance(
  participantId: id,
  totalPaid: Decimal.zero,
  totalOwed: Decimal.zero,
  netBalance: Decimal.parse(net),
);

void main() {
  group('BalanceCalculator.outstandingForPair', () {
    Decimal call(List<UserBalance> bucket, String from, String to) =>
        BalanceCalculator.outstandingForPair(
          bucket: bucket,
          fromUserId: from,
          toUserId: to,
        );

    test('clean: from owes 10, to owed 10 -> cap 10', () {
      expect(
        call([_ub('a', '-10'), _ub('b', '10')], 'a', 'b'),
        Decimal.parse('10'),
      );
    });

    test('capped by debtor: from owes 4, to owed 10 -> 4', () {
      expect(
        call([_ub('a', '-4'), _ub('b', '10')], 'a', 'b'),
        Decimal.parse('4'),
      );
    });

    test('capped by creditor: from owes 10, to owed 3 -> 3', () {
      expect(
        call([_ub('a', '-10'), _ub('b', '3')], 'a', 'b'),
        Decimal.parse('3'),
      );
    });

    test('stale-shrunk: to now owed only 2 -> 2 (was 10)', () {
      expect(
        call([_ub('a', '-10'), _ub('b', '2')], 'a', 'b'),
        Decimal.parse('2'),
      );
    });

    test('settled-by-other: to net 0 -> 0', () {
      expect(call([_ub('a', '-10'), _ub('b', '0')], 'a', 'b'), Decimal.zero);
    });

    test('from is no longer a debtor (net >= 0) -> 0', () {
      expect(call([_ub('a', '5'), _ub('b', '10')], 'a', 'b'), Decimal.zero);
    });

    test('to is not a creditor (net < 0) -> 0', () {
      expect(call([_ub('a', '-10'), _ub('b', '-3')], 'a', 'b'), Decimal.zero);
    });

    test('missing party -> treated as net 0 -> 0', () {
      expect(call([_ub('a', '-10')], 'a', 'b'), Decimal.zero);
      expect(call(const <UserBalance>[], 'a', 'b'), Decimal.zero);
    });

    test('OMR 3dp precision preserved', () {
      expect(
        call([_ub('a', '-2.900'), _ub('b', '2.900')], 'a', 'b'),
        Decimal.parse('2.900'),
      );
    });
  });
}
