import 'package:decimal/decimal.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:safar/core/services/money_serializer.dart';
import 'package:safar/features/ledger/models/expense_model.dart';
import 'package:safar/features/ledger/providers/expense_provider.dart';

/// #363 — table-driven tests for [BalanceCalculator.calculateDirectSettlements]
/// (the simplify-debts OFF allocator: integer-subunit pro-rata fan-out with
/// per-directed-pair accumulation and a bounded pass-2 sweep).
///
/// Money math ⇒ table-driven clean/edge cases (operating contract). The
/// invariants of spec §3 (docs/plans/2026-07-13-363-simplify-debts-toggle.md)
/// are asserted generically over every case; margin-EXACTNESS assertions apply
/// to conserving buckets only (Σ nets == 0 in subunits — the production case).

UserBalance _balance(String id, String name, String net) {
  return UserBalance(
    participantId: id,
    displayName: name,
    totalPaid: Decimal.zero,
    totalOwed: Decimal.zero,
    netBalance: Decimal.parse(net),
  );
}

typedef _Leg = ({String from, String to, String amount});

class _Case {
  const _Case({
    required this.name,
    required this.currency,
    required this.nets,
    this.conserving = true,
    this.expectedLegs,
  });

  final String name;
  final String currency;

  /// participantId → net balance (display name = capitalized id).
  final Map<String, String> nets;

  /// Whether Σ nets == 0 in subunits (enables the exactness assertions).
  final bool conserving;

  /// Exact expected output (in emission order: debtors alpha-outer,
  /// creditors alpha-inner) when the case pins concrete legs.
  final List<_Leg>? expectedLegs;

  List<UserBalance> get balances => [
    for (final e in nets.entries) _balance(e.key, e.key.toUpperCase(), e.value),
  ];
}

const _cases = <_Case>[
  _Case(
    name: '2x2 pro-rata exactness (OMR)',
    currency: 'OMR',
    nets: {
      'alice': '4.000',
      'bob': '6.000',
      'charlie': '-3.000',
      'dana': '-7.000',
    },
    expectedLegs: [
      (from: 'charlie', to: 'alice', amount: '1.200'),
      (from: 'charlie', to: 'bob', amount: '1.800'),
      (from: 'dana', to: 'alice', amount: '2.800'),
      (from: 'dana', to: 'bob', amount: '4.200'),
    ],
  ),
  _Case(
    name: 'remainder-forcing shares (OMR 3dp)',
    currency: 'OMR',
    nets: {
      'alice': '3.333',
      'bob': '3.333',
      'carol': '3.334',
      'dave': '-5.000',
      'erin': '-5.000',
    },
    expectedLegs: [
      (from: 'dave', to: 'alice', amount: '1.667'),
      (from: 'dave', to: 'bob', amount: '1.666'),
      (from: 'dave', to: 'carol', amount: '1.667'),
      (from: 'erin', to: 'alice', amount: '1.666'),
      (from: 'erin', to: 'bob', amount: '1.667'),
      (from: 'erin', to: 'carol', amount: '1.667'),
    ],
  ),
  // The Gate-R2 P1 RED case: pass 1 floors leave a row residual whose pass-2
  // close-out lands on a creditor pass 1 ALREADY touched. Without per-pair
  // accumulation the allocator emits TWO ali→fahad legs whose identical sd1
  // dedup ids (same scope/pair/currency/amount/epoch) would record ONCE and
  // silently drop a payment.
  _Case(
    name: 'JPY pass-collision — one leg per directed pair',
    currency: 'JPY',
    nets: {
      'ali': '-5',
      'badr': '-5',
      'fahad': '3',
      'ghala': '3',
      'hamed': '4',
    },
    expectedLegs: [
      (from: 'ali', to: 'fahad', amount: '2'),
      (from: 'ali', to: 'ghala', amount: '1'),
      (from: 'ali', to: 'hamed', amount: '2'),
      (from: 'badr', to: 'fahad', amount: '1'),
      (from: 'badr', to: 'ghala', amount: '2'),
      (from: 'badr', to: 'hamed', amount: '2'),
    ],
  ),
  // A 2dp currency where one row's pass-1 floors all to ZERO and the whole
  // row is allocated by the bounded pass-2 sweep.
  _Case(
    name: '2dp pass-2-only row (USD)',
    currency: 'USD',
    nets: {'alice': '0.50', 'bob': '0.50', 'xena': '-0.99', 'yusuf': '-0.01'},
    expectedLegs: [
      (from: 'xena', to: 'alice', amount: '0.50'),
      (from: 'xena', to: 'bob', amount: '0.49'),
      (from: 'yusuf', to: 'bob', amount: '0.01'),
    ],
  ),
  // Documents the nets-based semantic (the load-bearing constraint): the
  // transaction graph A→B 50, B→C 50 nets to A=-50, B=0, C=+50 — the only
  // recordable leg is A→C; B appears in NO leg.
  _Case(
    name: 'triangle — nets-based, no zero-net legs',
    currency: 'OMR',
    nets: {'amal': '-50.000', 'basma': '0.000', 'chami': '50.000'},
    expectedLegs: [(from: 'amal', to: 'chami', amount: '50.000')],
  ),
  _Case(
    name: 'single debtor, multi creditor (JPY exact)',
    currency: 'JPY',
    nets: {'alice': '3', 'bob': '3', 'carol': '4', 'dina': '-10'},
    expectedLegs: [
      (from: 'dina', to: 'alice', amount: '3'),
      (from: 'dina', to: 'bob', amount: '3'),
      (from: 'dina', to: 'carol', amount: '4'),
    ],
  ),
  _Case(
    name: 'multi debtor, single creditor',
    currency: 'OMR',
    nets: {
      'alice': '10.000',
      'bilal': '-3.000',
      'chris': '-3.000',
      'daud': '-4.000',
    },
    expectedLegs: [
      (from: 'bilal', to: 'alice', amount: '3.000'),
      (from: 'chris', to: 'alice', amount: '3.000'),
      (from: 'daud', to: 'alice', amount: '4.000'),
    ],
  ),
  _Case(
    name: 'empty balances',
    currency: 'OMR',
    nets: {},
    expectedLegs: [],
  ),
  _Case(
    name: 'all zero — already settled',
    currency: 'OMR',
    nets: {'alice': '0.000', 'bob': '0.000'},
    expectedLegs: [],
  ),
  // Non-conserving BOTH directions (forged/legacy/Admin data — the #249/
  // #1144-R1 residual class): degrade gracefully, never spin.
  _Case(
    name: 'non-conserving creditor-heavy (rows drain, columns underfill)',
    currency: 'OMR',
    nets: {'alice': '4.000', 'bob': '3.000', 'dara': '-5.000'},
    conserving: false,
    expectedLegs: [
      (from: 'dara', to: 'alice', amount: '2.858'),
      (from: 'dara', to: 'bob', amount: '2.142'),
    ],
  ),
  _Case(
    name: 'non-conserving debtor-heavy (bounded sweep, surplus debt dropped)',
    currency: 'JPY',
    nets: {'ali': '-5', 'badr': '-5', 'cyrus': '4'},
    conserving: false,
    expectedLegs: [(from: 'ali', to: 'cyrus', amount: '4')],
  ),
];

List<Map<String, dynamic>> _run(_Case c) =>
    BalanceCalculator.calculateDirectSettlements(
      balances: c.balances,
      currency: c.currency,
    );

Decimal _netOf(_Case c, String id) => Decimal.parse(c.nets[id]!);

void main() {
  group('calculateDirectSettlements — table cases (exact legs)', () {
    for (final c in _cases) {
      if (c.expectedLegs == null) continue;
      test(c.name, () {
        final legs = _run(c);
        expect(
          [
            for (final l in legs)
              (
                from: l['fromUserId'] as String,
                to: l['toUserId'] as String,
                amount: (l['amount'] as Decimal).toString(),
              ),
          ],
          [
            for (final e in c.expectedLegs!)
              (
                from: e.from,
                to: e.to,
                amount: Decimal.parse(e.amount).toString(),
              ),
          ],
        );
      });
    }
  });

  group('calculateDirectSettlements — generic invariants (all cases)', () {
    for (final c in _cases) {
      test(c.name, () {
        final legs = _run(c);

        // At most ONE leg per directed pair — always (the sd1 dedup contract).
        final pairs = <String>{};
        for (final l in legs) {
          final key = '${l['fromUserId']}→${l['toUserId']}';
          expect(pairs.add(key), isTrue, reason: 'duplicate pair leg $key');
        }

        var totalLegSubunits = 0;
        for (final l in legs) {
          final amount = l['amount'] as Decimal;
          // No zero or negative legs.
          expect(amount > Decimal.zero, isTrue);
          // Whole-subunit at the currency scale (subunit round-trip identity).
          final subunits = MoneySerializer.toSubunits(amount, c.currency);
          expect(MoneySerializer.fromSubunits(subunits, c.currency), amount);
          totalLegSubunits += subunits;
          // Per-leg cap vs FULL fresh nets — the server cap every leg must
          // individually pass (recordSettlement rejects over-outstanding).
          expect(
            amount <=
                BalanceCalculator.outstandingForPair(
                  bucket: c.balances,
                  fromUserId: l['fromUserId'] as String,
                  toUserId: l['toUserId'] as String,
                ),
            isTrue,
            reason: 'leg ${l['fromUserId']}→${l['toUserId']} over pair cap',
          );
        }

        // Σ legs == min(totalDebt, totalCredit) — conserving or not.
        var totalDebt = 0;
        var totalCredit = 0;
        for (final b in c.balances) {
          final sub = MoneySerializer.toSubunits(
            b.netBalance.abs(),
            c.currency,
          );
          if (b.netBalance < Decimal.zero) totalDebt += sub;
          if (b.netBalance > Decimal.zero) totalCredit += sub;
        }
        expect(
          totalLegSubunits,
          totalDebt < totalCredit ? totalDebt : totalCredit,
        );

        if (c.conserving) {
          // Row sums: Σ legs per debtor == toSubunits(|net_d|) exactly.
          // Column sums: Σ legs per creditor == toSubunits(net_c) exactly.
          final rowSums = <String, int>{};
          final colSums = <String, int>{};
          for (final l in legs) {
            final sub = MoneySerializer.toSubunits(
              l['amount'] as Decimal,
              c.currency,
            );
            rowSums.update(
              l['fromUserId'] as String,
              (v) => v + sub,
              ifAbsent: () => sub,
            );
            colSums.update(
              l['toUserId'] as String,
              (v) => v + sub,
              ifAbsent: () => sub,
            );
          }
          for (final b in c.balances) {
            final sub = MoneySerializer.toSubunits(
              b.netBalance.abs(),
              c.currency,
            );
            if (b.netBalance < Decimal.zero) {
              expect(rowSums[b.participantId] ?? 0, sub);
            } else if (b.netBalance > Decimal.zero) {
              expect(colSums[b.participantId] ?? 0, sub);
            } else {
              // Zero-net members never appear in any leg.
              expect(rowSums.containsKey(b.participantId), isFalse);
              expect(colSums.containsKey(b.participantId), isFalse);
            }
          }
        }

        // Determinism: a second run over the same inputs is deep-equal.
        expect(_run(c), legs);
      });
    }
  });

  group('calculateDirectSettlements — sequential recordability', () {
    // Pins the spec §3 any-order claim against the REAL Dart cap function:
    // folding the legs against a live net vector, every leg stays within
    // outstandingForPair of the CURRENT vector — in emission order and
    // reversed. (Row/column totals never exceed either party's net, so this
    // holds on non-conserving buckets too.)
    for (final c in _cases) {
      test(c.name, () {
        final legs = _run(c);
        for (final ordered in [legs, legs.reversed.toList()]) {
          final nets = {
            for (final b in c.balances) b.participantId: b.netBalance,
          };
          for (final l in legs.isEmpty ? <Map<String, dynamic>>[] : ordered) {
            final from = l['fromUserId'] as String;
            final to = l['toUserId'] as String;
            final amount = l['amount'] as Decimal;
            final bucket = [
              for (final e in nets.entries)
                _balance(e.key, e.key.toUpperCase(), e.value.toString()),
            ];
            expect(
              amount <=
                  BalanceCalculator.outstandingForPair(
                    bucket: bucket,
                    fromUserId: from,
                    toUserId: to,
                  ),
              isTrue,
              reason: '$from→$to $amount over live cap (order matters?)',
            );
            nets[from] = nets[from]! + amount;
            nets[to] = nets[to]! - amount;
          }
        }
      });
    }
  });

  group('calculateDirectSettlements — output shape', () {
    test('userNames override displayName; displayName is the fallback', () {
      final legs = BalanceCalculator.calculateDirectSettlements(
        balances: [
          _balance('alice', 'Alice', '5.000'),
          _balance('bob', 'Bob', '-5.000'),
        ],
        currency: 'OMR',
        userNames: {'alice': 'Alice (2)'},
      );
      expect(legs, hasLength(1));
      expect(legs.single['fromUserName'], 'Bob'); // fallback: displayName
      expect(legs.single['toUserName'], 'Alice (2)'); // override wins
      expect(legs.single.keys.toSet(), {
        'fromUserId',
        'toUserId',
        'fromUserName',
        'toUserName',
        'amount',
      });
    });

    test('triangle zero-net member gets NO legs in either direction', () {
      final legs = BalanceCalculator.calculateDirectSettlements(
        balances: [
          _balance('amal', 'Amal', '-50.000'),
          _balance('basma', 'Basma', '0.000'),
          _balance('chami', 'Chami', '50.000'),
        ],
        currency: 'OMR',
      );
      for (final l in legs) {
        expect(l['fromUserId'], isNot('basma'));
        expect(l['toUserId'], isNot('basma'));
      }
    });

    test('exhausted-capacity table case verifies min-sum on both directions', () {
      // Creditor-heavy and debtor-heavy sums asserted explicitly (belt for
      // the generic min(totalDebt,totalCredit) braces above).
      final creditorHeavy = BalanceCalculator.calculateDirectSettlements(
        balances: [
          _balance('alice', 'Alice', '4.000'),
          _balance('bob', 'Bob', '3.000'),
          _balance('dara', 'Dara', '-5.000'),
        ],
        currency: 'OMR',
      );
      final chSum = creditorHeavy.fold<Decimal>(
        Decimal.zero,
        (s, l) => s + (l['amount'] as Decimal),
      );
      expect(chSum, Decimal.parse('5.000'));

      final debtorHeavy = BalanceCalculator.calculateDirectSettlements(
        balances: [
          _balance('ali', 'Ali', '-5'),
          _balance('badr', 'Badr', '-5'),
          _balance('cyrus', 'Cyrus', '4'),
        ],
        currency: 'JPY',
      );
      final dhSum = debtorHeavy.fold<Decimal>(
        Decimal.zero,
        (s, l) => s + (l['amount'] as Decimal),
      );
      expect(dhSum, Decimal.fromInt(4));
    });
  });
}
