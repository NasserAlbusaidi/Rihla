import 'package:decimal/decimal.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:safar/features/events/models/event_recap.dart';
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

  EventRecap build({
    String eventName = 'Trip',
    List<String> participantIds = const ['a', 'b'],
    int expenseCount = 1,
    Map<String, Decimal> total = const {},
    Map<String, List<UserBalance>> balances = const {},
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
}
