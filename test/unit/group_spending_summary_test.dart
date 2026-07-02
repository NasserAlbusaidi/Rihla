import 'package:decimal/decimal.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:safar/features/ledger/models/expense_model.dart';
import 'package:safar/features/ledger/utils/group_spending_summary.dart';

Expense _expense({
  required String id,
  required String tripId,
  required String amount,
  String currency = 'OMR',
  String? categoryId,
  String payer = 'user-a',
  bool isDeleted = false,
}) {
  return Expense(
    id: id,
    tripId: tripId,
    payerParticipantId: payer,
    amount: Decimal.parse(amount),
    scope: ExpenseScope.global,
    createdAt: DateTime(2026, 1, 1),
    categoryId: categoryId,
    currency: currency,
    isDeleted: isDeleted,
  );
}

UserBalance _balance(
  String id, {
  String paid = '0',
  String owed = '0',
  String? net,
}) {
  final paidD = Decimal.parse(paid);
  final owedD = Decimal.parse(owed);
  return UserBalance(
    participantId: id,
    totalPaid: paidD,
    totalOwed: owedD,
    netBalance: net != null ? Decimal.parse(net) : paidD - owedD,
  );
}

Decimal _d(String v) => Decimal.parse(v);

void main() {
  group('computeGroupSpendingSummary', () {
    test('empty input -> isEmpty, every map empty', () {
      final summary = computeGroupSpendingSummary(
        expensesByEvent: const {},
        balances: const {},
      );

      expect(summary.isEmpty, isTrue);
      expect(summary.expenseCount, 0);
      expect(summary.totalSpentByCurrency, isEmpty);
      expect(summary.eventTotalsByCurrency, isEmpty);
      expect(summary.categoryTotalsByCurrency, isEmpty);
      expect(summary.topPayerByCurrency, isEmpty);
      expect(summary.topConsumerByCurrency, isEmpty);
    });

    test('events with empty expense lists -> still isEmpty', () {
      final summary = computeGroupSpendingSummary(
        expensesByEvent: const {'event-1': [], 'event-2': []},
        balances: const {},
      );

      expect(summary.isEmpty, isTrue);
      expect(summary.eventTotalsByCurrency, isEmpty);
    });

    test('single expense -> all slices + superlative tie broken by id asc', () {
      final summary = computeGroupSpendingSummary(
        expensesByEvent: {
          'event-1': [
            _expense(
              id: 'x1',
              tripId: 'event-1',
              amount: '10',
              categoryId: 'food',
            ),
          ],
        },
        balances: {
          'OMR': [
            _balance('user-a', paid: '10', owed: '5'),
            _balance('user-b', owed: '5'),
          ],
        },
      );

      expect(summary.isEmpty, isFalse);
      expect(summary.expenseCount, 1);
      expect(summary.totalSpentByCurrency, {'OMR': _d('10')});
      expect(summary.eventTotalsByCurrency['OMR'], [
        (eventId: 'event-1', total: _d('10')),
      ]);
      expect(summary.categoryTotalsByCurrency['OMR'], [
        (categoryId: 'food', total: _d('10')),
      ]);
      expect(
        summary.topPayerByCurrency['OMR'],
        (participantId: 'user-a', amount: _d('10')),
      );
      // user-a and user-b tie at owed 5 -> participantId asc wins.
      expect(
        summary.topConsumerByCurrency['OMR'],
        (participantId: 'user-a', amount: _d('5')),
      );
    });

    test('worked example: two events, category tie, decomposition invariant',
        () {
      // Issue #180 fixture, category ids adapted to kCategoryIds ("gear" is
      // not a catalog id). Jabal Shams 40 + Wahiba Sands 60 = 100.
      final jabal = [
        _expense(id: 'j1', tripId: 'jabal', amount: '10', categoryId: 'fuel'),
        _expense(id: 'j2', tripId: 'jabal', amount: '10', categoryId: 'food'),
        _expense(
          id: 'j3',
          tripId: 'jabal',
          amount: '10',
          categoryId: 'activities',
        ),
        _expense(
          id: 'j4',
          tripId: 'jabal',
          amount: '10',
          categoryId: 'groceries',
        ),
      ];
      final wahiba = [
        _expense(id: 'w1', tripId: 'wahiba', amount: '20', categoryId: 'fuel'),
        _expense(id: 'w2', tripId: 'wahiba', amount: '15', categoryId: 'food'),
        _expense(
          id: 'w3',
          tripId: 'wahiba',
          amount: '15',
          categoryId: 'groceries',
        ),
        _expense(
          id: 'w4',
          tripId: 'wahiba',
          amount: '10',
          categoryId: 'activities',
        ),
      ];
      final summary = computeGroupSpendingSummary(
        expensesByEvent: {'jabal': jabal, 'wahiba': wahiba},
        balances: {
          'OMR': [
            _balance('abdullah', paid: '70', owed: '50'),
            _balance('nasser', paid: '30', owed: '50'),
          ],
        },
      );

      expect(summary.expenseCount, 8);
      expect(summary.totalSpentByCurrency, {'OMR': _d('100')});

      // Highest-spending event first; desc by total.
      expect(summary.eventTotalsByCurrency['OMR'], [
        (eventId: 'wahiba', total: _d('60')),
        (eventId: 'jabal', total: _d('40')),
      ]);

      // fuel 30 > food 25 == groceries 25 (tie -> categoryId asc) > activities.
      expect(summary.categoryTotalsByCurrency['OMR'], [
        (categoryId: 'fuel', total: _d('30')),
        (categoryId: 'food', total: _d('25')),
        (categoryId: 'groceries', total: _d('25')),
        (categoryId: 'activities', total: _d('20')),
      ]);

      expect(
        summary.topPayerByCurrency['OMR'],
        (participantId: 'abdullah', amount: _d('70')),
      );
      expect(
        summary.topConsumerByCurrency['OMR'],
        (participantId: 'abdullah', amount: _d('50')),
      );

      // Decomposition: byEvent and byCategory each sum to the total.
      final eventSum = summary.eventTotalsByCurrency['OMR']!
          .fold(Decimal.zero, (acc, s) => acc + s.total);
      final categorySum = summary.categoryTotalsByCurrency['OMR']!
          .fold(Decimal.zero, (acc, s) => acc + s.total);
      expect(eventSum, summary.totalSpentByCurrency['OMR']);
      expect(categorySum, summary.totalSpentByCurrency['OMR']);
    });

    test('event total tie -> eventId asc', () {
      final summary = computeGroupSpendingSummary(
        expensesByEvent: {
          'event-b': [_expense(id: 'x1', tripId: 'event-b', amount: '10')],
          'event-a': [_expense(id: 'x2', tripId: 'event-a', amount: '10')],
        },
        balances: const {},
      );

      expect(summary.eventTotalsByCurrency['OMR'], [
        (eventId: 'event-a', total: _d('10')),
        (eventId: 'event-b', total: _d('10')),
      ]);
    });

    test('null categoryId folds to other', () {
      final summary = computeGroupSpendingSummary(
        expensesByEvent: {
          'event-1': [_expense(id: 'x1', tripId: 'event-1', amount: '3')],
        },
        balances: const {},
      );

      expect(summary.categoryTotalsByCurrency['OMR'], [
        (categoryId: 'other', total: _d('3')),
      ]);
    });

    test('soft-deleted expense excluded from every slice', () {
      final summary = computeGroupSpendingSummary(
        expensesByEvent: {
          'event-1': [
            _expense(
              id: 'x1',
              tripId: 'event-1',
              amount: '10',
              categoryId: 'food',
            ),
            _expense(
              id: 'x2',
              tripId: 'event-1',
              amount: '99',
              categoryId: 'fuel',
              isDeleted: true,
            ),
          ],
        },
        balances: const {},
      );

      expect(summary.expenseCount, 1);
      expect(summary.totalSpentByCurrency, {'OMR': _d('10')});
      expect(summary.eventTotalsByCurrency['OMR'], [
        (eventId: 'event-1', total: _d('10')),
      ]);
      expect(summary.categoryTotalsByCurrency['OMR'], [
        (categoryId: 'food', total: _d('10')),
      ]);
    });

    test('multi-currency: separate buckets, nothing summed across', () {
      final summary = computeGroupSpendingSummary(
        expensesByEvent: {
          'event-1': [
            _expense(id: 'x1', tripId: 'event-1', amount: '10'),
            _expense(
              id: 'x2',
              tripId: 'event-1',
              amount: '7',
              currency: 'USD',
            ),
          ],
        },
        balances: {
          'OMR': [_balance('user-a', paid: '10', owed: '10')],
          'USD': [_balance('user-b', paid: '7', owed: '7')],
        },
      );

      expect(summary.totalSpentByCurrency, {'OMR': _d('10'), 'USD': _d('7')});
      expect(summary.topPayerByCurrency['OMR']?.participantId, 'user-a');
      expect(summary.topPayerByCurrency['USD']?.participantId, 'user-b');
    });

    test('unsupported currency folds into OMR bucket (fence parity)', () {
      final summary = computeGroupSpendingSummary(
        expensesByEvent: {
          'event-1': [
            _expense(id: 'x1', tripId: 'event-1', amount: '5'),
            _expense(
              id: 'x2',
              tripId: 'event-1',
              amount: '5',
              currency: 'XXX',
            ),
          ],
        },
        balances: const {},
      );

      expect(summary.totalSpentByCurrency, {'OMR': _d('10')});
    });

    test('superlatives read totalPaid/totalOwed, never netBalance', () {
      // Settlement axis: nets are settlement-folded and deliberately point the
      // OTHER way — user-b has the bigger net but user-a fronted more cash.
      final summary = computeGroupSpendingSummary(
        expensesByEvent: {
          'event-1': [_expense(id: 'x1', tripId: 'event-1', amount: '30')],
        },
        balances: {
          'OMR': [
            _balance('user-a', paid: '20', owed: '15', net: '-10'),
            _balance('user-b', paid: '10', owed: '16', net: '25'),
          ],
        },
      );

      expect(summary.topPayerByCurrency['OMR']?.participantId, 'user-a');
      expect(summary.topConsumerByCurrency['OMR']?.participantId, 'user-b');
    });

    test('departed member with max totalPaid is top payer (identity-blind)',
        () {
      final summary = computeGroupSpendingSummary(
        expensesByEvent: {
          'event-1': [_expense(id: 'x1', tripId: 'event-1', amount: '30')],
        },
        balances: {
          'OMR': [
            _balance('departed-1', paid: '25', owed: '5'),
            _balance('user-a', paid: '5', owed: '25'),
          ],
        },
      );

      expect(summary.topPayerByCurrency['OMR']?.participantId, 'departed-1');
    });

    test('zero-paid bucket -> no top payer, consumer still present', () {
      final summary = computeGroupSpendingSummary(
        expensesByEvent: {
          'event-1': [_expense(id: 'x1', tripId: 'event-1', amount: '10')],
        },
        balances: {
          'OMR': [
            _balance('user-a', owed: '6'),
            _balance('user-b', owed: '4'),
          ],
        },
      );

      expect(summary.topPayerByCurrency, isEmpty);
      expect(
        summary.topConsumerByCurrency['OMR'],
        (participantId: 'user-a', amount: _d('6')),
      );
    });

    test('settlement-only balance bucket gets no superlative entry', () {
      // EUR bucket exists in balances (settlement-only) but has no expenses ->
      // it must not appear anywhere in the summary.
      final summary = computeGroupSpendingSummary(
        expensesByEvent: {
          'event-1': [_expense(id: 'x1', tripId: 'event-1', amount: '10')],
        },
        balances: {
          'OMR': [_balance('user-a', paid: '10', owed: '10')],
          'EUR': [_balance('user-a', net: '5'), _balance('user-b', net: '-5')],
        },
      );

      expect(summary.totalSpentByCurrency.keys, ['OMR']);
      expect(summary.topPayerByCurrency.keys, ['OMR']);
      expect(summary.topConsumerByCurrency.keys, ['OMR']);
    });
  });
}
