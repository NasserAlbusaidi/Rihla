import 'package:decimal/decimal.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:safar/features/events/models/event_recap.dart';
import 'package:safar/features/events/models/spending_snapshot.dart';
import 'package:safar/features/ledger/models/expense_model.dart';

/// Slice 6 of #202 — the frozen, viewer-independent SPENDING half of an
/// EventRecap, serialized to/from the opaque `spendingSnapshot` event-doc blob.
/// Money/legal → table-driven round-trip across currency scales.
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

  EventRecap recapOf({
    required List<Expense> expenses,
    required Map<String, List<UserBalance>> balances,
    required Map<String, Decimal> total,
    List<String> participantIds = const ['a', 'b'],
  }) =>
      EventRecap.from(
        eventId: 'event-1',
        eventName: 'Trip',
        startDate: null,
        endDate: null,
        participantIds: participantIds,
        expenseCount: expenses.length,
        totalSpentByCurrency: total,
        balances: balances,
        expenses: expenses,
        uid: 'a',
      );

  group('SpendingSnapshot round-trip', () {
    test('OMR (×1000): every frozen field survives toMap → fromMap', () {
      final balances = {
        'OMR': [ub('a', '60', '50', '10'), ub('b', '40', '50', '-10')],
      };
      final recap = recapOf(
        expenses: [
          expense('e1', payer: 'a', amount: '60', categoryId: 'food', description: 'Dinner'),
          expense('e2', payer: 'b', amount: '40', categoryId: 'stay'),
        ],
        balances: balances,
        total: {'OMR': d('100')},
      );

      final r = SpendingSnapshot.fromMap(
          SpendingSnapshot.from(recap: recap, balances: balances).toMap());

      expect(r.participantCount, 2);
      expect(r.expenseCount, 2);
      expect(r.totalSpentByCurrency['OMR'], d('100'));
      expect(r.biggestExpenseByCurrency['OMR']!.expenseId, 'e1');
      expect(r.biggestExpenseByCurrency['OMR']!.amount, d('60'));
      expect(r.biggestExpenseByCurrency['OMR']!.description, 'Dinner');
      expect(r.biggestExpenseByCurrency['OMR']!.categoryId, 'food');
      expect(r.biggestExpenseByCurrency['OMR']!.payerId, 'a');
      expect(r.payerTotalsByCurrency['OMR']!.map((p) => p.participantId).toList(), ['a', 'b']);
      expect(r.payerTotalsByCurrency['OMR']!.first.amount, d('60'));
      expect(r.categoryTotalsByCurrency['OMR']!.map((c) => c.categoryId).toList(), ['food', 'stay']);
      expect(r.categoryTotalsByCurrency['OMR']!.first.total, d('60'));
      expect(r.owedByCurrency['OMR']!['a'], d('50'));
      expect(r.owedByCurrency['OMR']!['b'], d('50'));
    });

    test('USD (×100) and JPY (×1) scales round-trip exactly', () {
      final recap = recapOf(
        expenses: [
          expense('u1', payer: 'a', amount: '9.99', currency: 'USD', categoryId: 'food'),
        ],
        balances: {
          'USD': [ub('a', '9.99', '9.99', '0')],
          'JPY': [ub('a', '500', '500', '0')],
        },
        total: {'USD': d('9.99')},
        participantIds: const ['a'],
      );
      final balances = {
        'USD': [ub('a', '9.99', '9.99', '0')],
        'JPY': [ub('a', '500', '500', '0')],
      };
      final r = SpendingSnapshot.fromMap(
          SpendingSnapshot.from(recap: recap, balances: balances).toMap());

      expect(r.totalSpentByCurrency['USD'], d('9.99'));
      expect(r.owedByCurrency['USD']!['a'], d('9.99'));
      expect(r.owedByCurrency['JPY']!['a'], d('500'));
    });

    test('biggest desc/cat omitted in the map when null, round-trips to null', () {
      final recap = recapOf(
        expenses: [expense('e1', payer: 'a', amount: '10')],
        balances: {
          'OMR': [ub('a', '10', '10', '0')],
        },
        total: {'OMR': d('10')},
        participantIds: const ['a'],
      );
      final balances = {
        'OMR': [ub('a', '10', '10', '0')],
      };
      final map = SpendingSnapshot.from(recap: recap, balances: balances).toMap();
      final biggest = (map['biggest'] as Map)['OMR'] as Map;
      expect(biggest.containsKey('desc'), isFalse);
      expect(biggest.containsKey('cat'), isFalse);

      final r = SpendingSnapshot.fromMap(map);
      expect(r.biggestExpenseByCurrency['OMR']!.description, isNull);
      expect(r.biggestExpenseByCurrency['OMR']!.categoryId, isNull);
    });

    test('fromMap drops an unsupported currency bucket (never throws)', () {
      final map = {
        'v': 1,
        'participantCount': 2,
        'expenseCount': 1,
        'totals': {'OMR': 100000, 'XYZ': 5000},
        'biggest': {
          'OMR': {'id': 'e1', 'amt': 100000, 'payer': 'a'},
          'XYZ': {'id': 'e2', 'amt': 5000, 'payer': 'b'},
        },
        'payers': {
          'OMR': [
            {'id': 'a', 'amt': 100000}
          ]
        },
        'categories': {
          'OMR': [
            {'cat': 'food', 'amt': 100000}
          ]
        },
        'owed': {
          'OMR': {'a': 50000},
          'XYZ': {'b': 5000},
        },
      };
      final r = SpendingSnapshot.fromMap(map);
      expect(r.totalSpentByCurrency.containsKey('OMR'), isTrue);
      expect(r.totalSpentByCurrency.containsKey('XYZ'), isFalse);
      expect(r.owedByCurrency.containsKey('XYZ'), isFalse);
    });

    test('fromMap tolerates garbage / missing keys → empty maps, no throw', () {
      expect(() => SpendingSnapshot.fromMap(const {}), returnsNormally);
      final r = SpendingSnapshot.fromMap(const {
        'participantCount': 'not-an-int',
        'totals': 'garbage',
        'biggest': 42,
        'payers': null,
        'owed': {'OMR': 'nope'},
      });
      expect(r.participantCount, 0);
      expect(r.totalSpentByCurrency, isEmpty);
      expect(r.biggestExpenseByCurrency, isEmpty);
      expect(r.payerTotalsByCurrency, isEmpty);
      expect(r.owedByCurrency, isEmpty);
    });
  });
}
