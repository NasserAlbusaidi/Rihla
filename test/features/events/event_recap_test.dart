import 'package:decimal/decimal.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:safar/features/events/models/event_recap.dart';
import 'package:safar/features/events/models/spending_snapshot.dart';
import 'package:safar/features/ledger/models/expense_model.dart';

/// Slice 1 of #202 — pure `EventRecap.from` money-projection table.
/// Spec: docs/plans/2026-06-20-202-slice1-recap-core.md (Gate-clean, 0 P1s).
void main() {
  Decimal d(String s) => Decimal.parse(s);

  UserBalance ub(String id, String paid, String owed, String net) => UserBalance(
        participantId: id,
        displayName: id,
        totalPaid: d(paid),
        totalOwed: d(owed),
        netBalance: d(net),
      );

  Expense expense(
    String id, {
    required String payer,
    required String amount,
    String currency = 'OMR',
    String? categoryId,
    String? description,
  }) =>
      Expense(
        id: id,
        tripId: 'event-1',
        payerParticipantId: payer,
        amount: d(amount),
        scope: ExpenseScope.global,
        createdAt: DateTime(2026, 1, 1),
        currency: currency,
        categoryId: categoryId,
        description: description,
      );

  EventRecap build({
    String eventName = 'Trip',
    List<String> participantIds = const ['a', 'b'],
    int expenseCount = 1,
    Map<String, Decimal> total = const {},
    Map<String, List<UserBalance>> balances = const {},
    List<Expense> expenses = const [],
    String? uid = 'a',
  }) =>
      EventRecap.from(
        eventId: 'event-1',
        eventName: eventName,
        startDate: null,
        endDate: null,
        participantIds: participantIds,
        expenseCount: expenseCount,
        totalSpentByCurrency: total,
        balances: balances,
        expenses: expenses,
        uid: uid,
      );

  // Every included currency key must satisfy net == paid - share + settled.
  void expectReconciles(EventRecap r) {
    for (final ccy in r.userNetByCurrency.keys) {
      final paid = r.userPaidByCurrency[ccy] ?? Decimal.zero;
      final share = r.userShareByCurrency[ccy] ?? Decimal.zero;
      final settled = r.userSettledByCurrency[ccy] ?? Decimal.zero;
      expect(r.userNetByCurrency[ccy], paid - share + settled,
          reason: 'reconciliation broke for $ccy');
    }
  }

  group('EventRecap.from', () {
    test('1. empty event → isEmpty, all maps empty', () {
      final r = build(expenseCount: 0);
      expect(r.isEmpty, isTrue);
      expect(r.expenseCount, 0);
      expect(r.participantCount, 2);
      expect(r.totalSpentByCurrency, isEmpty);
      expect(r.userPaidByCurrency, isEmpty);
      expect(r.userShareByCurrency, isEmpty);
      expect(r.userSettledByCurrency, isEmpty);
      expect(r.userNetByCurrency, isEmpty);
    });

    test('2. single currency, unsettled → paid/share/net; settled 0', () {
      final r = build(
        total: {'OMR': d('100')},
        balances: {
          'OMR': [ub('a', '100', '50', '50'), ub('b', '0', '50', '-50')],
        },
      );
      expect(r.isEmpty, isFalse);
      expect(r.totalSpentByCurrency['OMR'], d('100'));
      expect(r.userPaidByCurrency['OMR'], d('100'));
      expect(r.userShareByCurrency['OMR'], d('50'));
      expect(r.userSettledByCurrency['OMR'], d('0'));
      expect(r.userNetByCurrency['OMR'], d('50'));
      expectReconciles(r);
    });

    test('2b. square-but-active (net 0, no settlement) → STILL shown (R2 P1 guard)', () {
      final r = build(
        total: {'OMR': d('200')},
        balances: {
          'OMR': [ub('a', '100', '100', '0'), ub('b', '100', '100', '0')],
        },
      );
      // net 0 must NOT blank out a participant who actually spent.
      expect(r.userPaidByCurrency['OMR'], d('100'));
      expect(r.userShareByCurrency['OMR'], d('100'));
      expect(r.userNetByCurrency.containsKey('OMR'), isTrue);
      expect(r.userNetByCurrency['OMR'], d('0'));
      expect(r.userSettledByCurrency['OMR'], d('0'));
      expectReconciles(r);
    });

    test('3. settled scenario (received settlement) → net 0, settled -50 (R1 P1 trap)', () {
      // a paid 100, share 50, received a 50 settlement → net 0.
      final r = build(
        total: {'OMR': d('100')},
        balances: {
          'OMR': [ub('a', '100', '50', '0'), ub('b', '0', '50', '0')],
        },
      );
      expect(r.userPaidByCurrency['OMR'], d('100'));
      expect(r.userShareByCurrency['OMR'], d('50'));
      expect(r.userSettledByCurrency['OMR'], d('-50'));
      expect(r.userNetByCurrency['OMR'], d('0'));
      expectReconciles(r); // 0 == 100 - 50 + (-50)
    });

    test('4. multi-currency → two keys, never cross-summed', () {
      final r = build(
        total: {'USD': d('100'), 'OMR': d('30')},
        balances: {
          'USD': [ub('a', '100', '50', '50')],
          'OMR': [ub('a', '30', '30', '0')],
        },
      );
      expect(r.totalSpentByCurrency, {'USD': d('100'), 'OMR': d('30')});
      expect(r.userPaidByCurrency, {'USD': d('100'), 'OMR': d('30')});
      expect(r.userShareByCurrency, {'USD': d('50'), 'OMR': d('30')});
      expect(r.userNetByCurrency, {'USD': d('50'), 'OMR': d('0')});
      expectReconciles(r);
    });

    test('5. JPY (×1 scale) → integer yen, no fractional drift', () {
      final r = build(
        total: {'JPY': d('1000')},
        balances: {
          'JPY': [ub('a', '1000', '500', '500')],
        },
      );
      expect(r.totalSpentByCurrency['JPY'], d('1000'));
      expect(r.userPaidByCurrency['JPY'], d('1000'));
      expect(r.userShareByCurrency['JPY'], d('500'));
      expect(r.userNetByCurrency['JPY'], d('500'));
      expectReconciles(r);
    });

    test('6. settlement-only currency → in user maps, absent from totalSpent', () {
      // OMR expense + a EUR settlement a received (no EUR expense).
      final r = build(
        total: {'OMR': d('10')}, // no EUR key
        balances: {
          'OMR': [ub('a', '10', '10', '0')],
          'EUR': [ub('a', '0', '0', '-50'), ub('b', '0', '0', '50')],
        },
      );
      expect(r.totalSpentByCurrency.containsKey('EUR'), isFalse);
      expect(r.userNetByCurrency['EUR'], d('-50'));
      expect(r.userSettledByCurrency['EUR'], d('-50'));
      expect(r.userPaidByCurrency['EUR'], d('0'));
      expect(r.userShareByCurrency['EUR'], d('0'));
      expectReconciles(r);
    });

    test('7. null uid → all user maps empty, totals present', () {
      final r = build(
        uid: null,
        total: {'OMR': d('100')},
        balances: {
          'OMR': [ub('a', '100', '50', '50')],
        },
      );
      expect(r.totalSpentByCurrency['OMR'], d('100'));
      expect(r.userPaidByCurrency, isEmpty);
      expect(r.userNetByCurrency, isEmpty);
    });

    test('7b. non-participant uid (absent from balances) → empty user maps', () {
      final r = build(
        uid: 'z',
        total: {'OMR': d('100')},
        balances: {
          'OMR': [ub('a', '100', '50', '50'), ub('b', '0', '50', '-50')],
        },
      );
      expect(r.userPaidByCurrency, isEmpty);
      expect(r.userNetByCurrency, isEmpty);
    });

    test('8. participantCount = participantIds.length, NOT the inflated universe (R1 P1#3)', () {
      // Departed member "c" appears in balances (universe fold) but NOT in participantIds.
      final r = build(
        participantIds: ['a', 'b'],
        total: {'OMR': d('100')},
        balances: {
          'OMR': [
            ub('a', '100', '50', '50'),
            ub('b', '0', '25', '-25'),
            ub('c', '0', '25', '-25'),
          ],
        },
      );
      expect(r.participantCount, 2); // not 3
    });
  });

  // Slice 2 (#721) — full money summary projection.
  // Spec: docs/plans/2026-06-29-721-recap-full-summary.md (Gate-clean, 0 P1s).
  group('EventRecap.from — Slice 2 full summary', () {
    test('S1. biggest expense = max amount per currency', () {
      final r = build(
        expenseCount: 2,
        total: {'OMR': d('225')},
        balances: {
          'OMR': [ub('a', '225', '112.5', '112.5'), ub('b', '0', '112.5', '-112.5')],
        },
        expenses: [
          expense('e1', payer: 'a', amount: '180', categoryId: 'accommodation'),
          expense('e2', payer: 'a', amount: '45', categoryId: 'activities'),
        ],
      );
      expect(r.biggestExpenseByCurrency['OMR']!.amount, d('180'));
      expect(r.biggestExpenseByCurrency['OMR']!.expenseId, 'e1');
    });

    test('S2. biggest expense tie → lower expenseId wins (determinism)', () {
      final r = build(
        total: {'OMR': d('100')},
        balances: {'OMR': [ub('a', '100', '100', '0')]},
        expenses: [
          expense('e9', payer: 'a', amount: '50'),
          expense('e2', payer: 'a', amount: '50'),
        ],
      );
      expect(r.biggestExpenseByCurrency['OMR']!.expenseId, 'e2');
    });

    test('S3. category totals bucket by categoryId, sorted desc', () {
      final r = build(
        expenseCount: 3,
        total: {'OMR': d('380.5')},
        balances: {'OMR': [ub('a', '380.5', '380.5', '0')]},
        expenses: [
          expense('e1', payer: 'a', amount: '120.5', categoryId: 'food'),
          expense('e2', payer: 'a', amount: '180', categoryId: 'accommodation'),
          expense('e3', payer: 'a', amount: '80', categoryId: 'transport'),
        ],
      );
      final cats = r.categoryTotalsByCurrency['OMR']!;
      expect(cats.map((c) => c.categoryId).toList(),
          ['accommodation', 'food', 'transport']);
      expect(cats.first.total, d('180'));
    });

    test('S4. null categoryId → "other" bucket', () {
      final r = build(
        total: {'OMR': d('30')},
        balances: {'OMR': [ub('a', '30', '30', '0')]},
        expenses: [expense('e1', payer: 'a', amount: '30', categoryId: null)],
      );
      expect(r.categoryTotalsByCurrency['OMR']!.single.categoryId, 'other');
    });

    test('S5. unsupported currency expense → OMR bucket (fence parity)', () {
      final r = build(
        total: {'OMR': d('10')},
        balances: {'OMR': [ub('a', '10', '10', '0')]},
        expenses: [
          expense('e1', payer: 'a', amount: '10', currency: 'XYZ', categoryId: 'food'),
        ],
      );
      expect(r.categoryTotalsByCurrency.containsKey('XYZ'), isFalse);
      expect(r.categoryTotalsByCurrency['OMR']!.single.categoryId, 'food');
      expect(r.biggestExpenseByCurrency.containsKey('XYZ'), isFalse);
      expect(r.biggestExpenseByCurrency['OMR']!.amount, d('10'));
    });

    test('S6. category sum == total spent per currency (decomposition)', () {
      final r = build(
        expenseCount: 3,
        total: {'OMR': d('380.5')},
        balances: {'OMR': [ub('a', '380.5', '380.5', '0')]},
        expenses: [
          expense('e1', payer: 'a', amount: '120.5', categoryId: 'food'),
          expense('e2', payer: 'a', amount: '180', categoryId: 'accommodation'),
          expense('e3', payer: 'a', amount: '80', categoryId: 'transport'),
        ],
      );
      final sum = r.categoryTotalsByCurrency['OMR']!
          .fold(Decimal.zero, (s, c) => s + c.total);
      expect(sum, r.totalSpentByCurrency['OMR']);
    });

    test('S7. payer totals desc, zero-paid excluded', () {
      final r = build(
        total: {'OMR': d('340.5')},
        balances: {
          'OMR': [
            ub('a', '250', '113.5', '136.5'),
            ub('b', '90.5', '113.5', '-23'),
            ub('c', '0', '113.5', '-113.5'),
          ],
        },
        expenses: [expense('e1', payer: 'a', amount: '340.5')],
      );
      final payers = r.payerTotalsByCurrency['OMR']!;
      expect(payers.map((p) => p.participantId).toList(), ['a', 'b']);
      expect(payers.first.amount, d('250'));
    });

    test('S8. participant nets include departed universe member', () {
      final r = build(
        participantIds: ['a', 'b'],
        total: {'OMR': d('100')},
        balances: {
          'OMR': [
            ub('a', '100', '50', '50'),
            ub('b', '0', '25', '-25'),
            ub('c', '0', '25', '-25'), // departed, not in participantIds
          ],
        },
        expenses: [expense('e1', payer: 'a', amount: '100')],
      );
      final ids =
          r.participantNetsByCurrency['OMR']!.map((n) => n.participantId).toSet();
      expect(ids.contains('c'), isTrue);
      expect(r.participantCount, 2); // count still excludes c
    });

    test('S9. participant nets: current user first', () {
      final r = build(
        uid: 'b',
        total: {'OMR': d('100')},
        balances: {'OMR': [ub('a', '100', '50', '50'), ub('b', '0', '50', '-50')]},
        expenses: [expense('e1', payer: 'a', amount: '100')],
      );
      expect(r.participantNetsByCurrency['OMR']!.first.participantId, 'b');
    });

    test('S10. isSettled true iff all nets exactly zero', () {
      final r = build(
        total: {'OMR': d('100')},
        balances: {'OMR': [ub('a', '100', '100', '0'), ub('b', '50', '50', '0')]},
        expenses: [expense('e1', payer: 'a', amount: '100')],
      );
      expect(r.isSettledByCurrency['OMR'], isTrue);
    });

    test('S11. isSettled false on sub-tolerance residual (exact, not 0.001)', () {
      final r = build(
        total: {'OMR': d('100')},
        balances: {
          'OMR': [ub('a', '100', '99.9995', '0.0005'), ub('b', '0', '0.0005', '-0.0005')],
        },
        expenses: [expense('e1', payer: 'a', amount: '100')],
      );
      expect(r.isSettledByCurrency['OMR'], isFalse);
    });

    test('S12. multi-currency: breakdowns isolated, never cross-summed', () {
      final r = build(
        expenseCount: 2,
        total: {'USD': d('100'), 'OMR': d('30')},
        balances: {
          'USD': [ub('a', '100', '50', '50'), ub('b', '0', '50', '-50')],
          'OMR': [ub('a', '30', '30', '0')],
        },
        expenses: [
          expense('e1', payer: 'a', amount: '100', currency: 'USD', categoryId: 'food'),
          expense('e2', payer: 'a', amount: '30', currency: 'OMR', categoryId: 'transport'),
        ],
      );
      expect(r.categoryTotalsByCurrency['USD']!.single.total, d('100'));
      expect(r.categoryTotalsByCurrency['OMR']!.single.total, d('30'));
      expect(r.biggestExpenseByCurrency['USD']!.amount, d('100'));
      expect(r.biggestExpenseByCurrency['OMR']!.amount, d('30'));
    });

    test('S13. JPY (×1): integer-yen category totals', () {
      final r = build(
        total: {'JPY': d('1000')},
        balances: {'JPY': [ub('a', '1000', '500', '500'), ub('b', '0', '500', '-500')]},
        expenses: [
          expense('e1', payer: 'a', amount: '1000', currency: 'JPY', categoryId: 'food'),
        ],
      );
      expect(r.categoryTotalsByCurrency['JPY']!.single.total, d('1000'));
    });

    test('S14. settlement-only currency: balance present, no expense (Gate P1)', () {
      // OMR expense + EUR settlement (a received) — EUR has balances, no expense.
      final r = build(
        total: {'OMR': d('10')},
        balances: {
          'OMR': [ub('a', '10', '10', '0')],
          'EUR': [ub('a', '0', '0', '-50'), ub('b', '0', '0', '50')],
        },
        expenses: [expense('e1', payer: 'a', amount: '10')],
      );
      expect(r.categoryTotalsByCurrency.containsKey('EUR'), isFalse);
      expect(r.biggestExpenseByCurrency.containsKey('EUR'), isFalse);
      expect(r.payerTotalsByCurrency['EUR'], isEmpty); // key present, empty list
      expect(r.participantNetsByCurrency['EUR']!.length, 2);
      expect(r.isSettledByCurrency['EUR'], isFalse);
    });
  });

  group('EventRecap.fromSnapshot (Slice 6 #766)', () {
    // Close-time recap: a paid 100 / owed 50 / net +50; b paid 0 / owed 50 /
    // net -50. Unsettled at close.
    SpendingSnapshot closeSnapshot() {
      final closeBalances = {
        'OMR': [ub('a', '100', '50', '50'), ub('b', '0', '50', '-50')],
      };
      final recap = EventRecap.from(
        eventId: 'event-1',
        eventName: 'Trip',
        startDate: null,
        endDate: null,
        participantIds: const ['a', 'b'],
        expenseCount: 1,
        totalSpentByCurrency: {'OMR': d('100')},
        balances: closeBalances,
        expenses: [expense('e1', payer: 'a', amount: '100', categoryId: 'food')],
        uid: 'a',
      );
      return SpendingSnapshot.from(recap: recap, balances: closeBalances);
    }

    EventRecap fromSnap(
            SpendingSnapshot snap, Map<String, List<UserBalance>> live, String? uid) =>
        EventRecap.fromSnapshot(
          snapshot: snap,
          eventId: 'event-1',
          eventName: 'Trip',
          startDate: null,
          endDate: null,
          balances: live,
          uid: uid,
        );

    test('frozen spending from snapshot + live settlement from balances', () {
      // Post-close: b settled 50 to a → both nets now 0 (live).
      final live = {
        'OMR': [ub('a', '100', '50', '0'), ub('b', '0', '50', '0')],
      };
      final r = fromSnap(closeSnapshot(), live, 'a');
      // Frozen spending:
      expect(r.totalSpentByCurrency['OMR'], d('100'));
      expect(r.participantCount, 2);
      expect(r.expenseCount, 1);
      expect(r.userPaidByCurrency['OMR'], d('100'));
      expect(r.userShareByCurrency['OMR'], d('50'));
      expect(r.payerTotalsByCurrency['OMR']!.first.amount, d('100'));
      expect(r.biggestExpenseByCurrency['OMR']!.expenseId, 'e1');
      // Live settlement:
      expect(r.userNetByCurrency['OMR'], d('0'));
      expect(r.isSettledByCurrency['OMR'], isTrue);
      // a received 50 → settled -50; net == paid - share + settled.
      expect(r.userSettledByCurrency['OMR'], d('-50'));
      expect(r.userNetByCurrency['OMR'],
          r.userPaidByCurrency['OMR']! -
              r.userShareByCurrency['OMR']! +
              r.userSettledByCurrency['OMR']!);
    });

    test('every viewer reconciles (viewer b: not in frozen payers)', () {
      final live = {
        'OMR': [ub('a', '100', '50', '0'), ub('b', '0', '50', '0')],
      };
      final r = fromSnap(closeSnapshot(), live, 'b');
      expect(r.userPaidByCurrency['OMR'], d('0')); // frozen: b paid nothing
      expect(r.userShareByCurrency['OMR'], d('50')); // frozen: b owed 50
      expect(r.userNetByCurrency['OMR'], d('0')); // live: settled
      expect(r.userSettledByCurrency['OMR'], d('50')); // b gave 50 → +50
      expect(r.userNetByCurrency['OMR'],
          r.userPaidByCurrency['OMR']! -
              r.userShareByCurrency['OMR']! +
              r.userSettledByCurrency['OMR']!);
    });

    test('spending FROZEN even when live balances drift (identity axis)', () {
      // Live recomputation drifts a's paid/net (participant churn after close).
      // Frozen spending must NOT follow; live settlement must.
      final drifted = {
        'OMR': [ub('a', '999', '50', '200')],
      };
      final r = fromSnap(closeSnapshot(), drifted, 'a');
      // Frozen — unchanged by the drift:
      expect(r.userPaidByCurrency['OMR'], d('100'));
      expect(r.payerTotalsByCurrency['OMR']!.first.amount, d('100'));
      expect(r.totalSpentByCurrency['OMR'], d('100'));
      expect(r.participantCount, 2);
      // Live — follows the drift:
      expect(r.userNetByCurrency['OMR'], d('200'));
      expect(r.participantNetsByCurrency['OMR']!.length, 1);
    });
  });
}
