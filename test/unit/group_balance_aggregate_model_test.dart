import 'package:decimal/decimal.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:safar/features/groups/models/group_balance_aggregate_model.dart';

// RED → GREEN (#382 PR-3 Task 6): decode contract for the v2 per-currency
// balance-aggregate doc (groups/{gid}/aggregates/balance, written by the
// balanceAggregator triggers — spec docs/plans/2026-06-12-382-pr3-aggregate-v2.md
// D1/D2). Boundary validation: anything malformed decodes to null so the home
// facade falls back to the once-path instead of rendering garbage money.

Map<String, dynamic> validDoc({Map<String, dynamic> overrides = const {}}) {
  return <String, dynamic>{
    'schemaVersion': 2,
    'currency': 'OMR',
    'netMilliByCurrency': {
      'OMR': {'alice': -4000, 'bob': -2000, 'carol': 6000},
      'AED': {'alice': 10500, 'bob': -10500},
    },
    'perEventNetMilliByCurrency': {
      'e1': {
        'OMR': {'alice': -3500, 'bob': -5500},
        'AED': {'alice': 10500},
      },
    },
    'eventCount': 1,
    'degraded': false,
    'sourceTimeMs': 1000,
    ...overrides,
  };
}

void main() {
  group('GroupBalanceAggregate.fromDoc (#382 PR-3 v2)', () {
    test('decodes per-currency milli ints into exact Decimals', () {
      final agg = GroupBalanceAggregate.fromDoc(validDoc());

      expect(agg, isNotNull);
      expect(agg!.netByCurrency['OMR']!['alice'], Decimal.parse('-4'));
      expect(agg.netByCurrency['OMR']!['bob'], Decimal.parse('-2'));
      expect(agg.netByCurrency['OMR']!['carol'], Decimal.parse('6'));
      expect(agg.netByCurrency['AED']!['alice'], Decimal.parse('10.5'));
      expect(agg.netByCurrency['AED']!['bob'], Decimal.parse('-10.5'));
      expect(
        agg.perEventNetByCurrency['e1']!['OMR']!['alice'],
        Decimal.parse('-3.5'),
      );
      expect(
        agg.perEventNetByCurrency['e1']!['OMR']!['bob'],
        Decimal.parse('-5.5'),
      );
      expect(
        agg.perEventNetByCurrency['e1']!['AED']!['alice'],
        Decimal.parse('10.5'),
      );
      expect(agg.eventCount, 1);
      expect(agg.currency, 'OMR');
    });

    test('netFor mirrors the bucket key-set — zero when uid absent from a '
        'bucket', () {
      final agg = GroupBalanceAggregate.fromDoc(validDoc())!;
      expect(
        agg.netFor('carol'),
        {'OMR': Decimal.parse('6'), 'AED': Decimal.zero},
      );
      expect(agg.netFor('nobody'), {'OMR': Decimal.zero, 'AED': Decimal.zero});
    });

    test('perEventNetFor OMITS a ccy entry when uid is absent from that '
        'bucket, and omits events with no remaining entries', () {
      final agg = GroupBalanceAggregate.fromDoc(validDoc())!;
      expect(agg.perEventNetFor('alice'), {
        'e1': {'OMR': Decimal.parse('-3.5'), 'AED': Decimal.parse('10.5')},
      });
      expect(agg.perEventNetFor('bob'), {
        'e1': {'OMR': Decimal.parse('-5.5')},
      });
      expect(agg.perEventNetFor('carol'), isEmpty);
      expect(agg.perEventNetFor('nobody'), isEmpty);
    });

    test('sub-unit milli precision decodes exactly (0.001 OMR = 1 milli)', () {
      final agg = GroupBalanceAggregate.fromDoc(
        validDoc(overrides: {
          'netMilliByCurrency': {
            'OMR': {'alice': 1, 'bob': -1},
          },
          'perEventNetMilliByCurrency': <String, dynamic>{},
        }),
      )!;
      expect(agg.netByCurrency['OMR']!['alice'], Decimal.parse('0.001'));
      expect(agg.netByCurrency['OMR']!['bob'], Decimal.parse('-0.001'));
    });

    test('null / missing data decodes to null', () {
      expect(GroupBalanceAggregate.fromDoc(null), isNull);
      expect(GroupBalanceAggregate.fromDoc(<String, dynamic>{}), isNull);
    });

    test('a degraded doc decodes to null (client must fall back)', () {
      expect(
        GroupBalanceAggregate.fromDoc(validDoc(overrides: {
          'degraded': true,
        })),
        isNull,
      );
    });

    test('a v1 doc decodes to null (client falls back to the once-path)', () {
      expect(
        GroupBalanceAggregate.fromDoc(validDoc(overrides: {'schemaVersion': 1})),
        isNull,
      );
    });

    test('an unknown future schemaVersion decodes to null', () {
      expect(
        GroupBalanceAggregate.fromDoc(validDoc(overrides: {'schemaVersion': 3})),
        isNull,
      );
    });

    test('garbage field shapes decode to null, never throw', () {
      expect(
        GroupBalanceAggregate.fromDoc(
          validDoc(overrides: {'netMilliByCurrency': 'oops'}),
        ),
        isNull,
      );
      expect(
        GroupBalanceAggregate.fromDoc(
          validDoc(overrides: {
            'netMilliByCurrency': {'OMR': 'oops'},
          }),
        ),
        isNull,
      );
      expect(
        GroupBalanceAggregate.fromDoc(
          validDoc(overrides: {'perEventNetMilliByCurrency': 17}),
        ),
        isNull,
      );
      expect(
        GroupBalanceAggregate.fromDoc(
          validDoc(overrides: {
            'perEventNetMilliByCurrency': {'e1': 17},
          }),
        ),
        isNull,
      );
      expect(
        GroupBalanceAggregate.fromDoc(
          validDoc(overrides: {
            'perEventNetMilliByCurrency': {
              'e1': {'OMR': 'oops'},
            },
          }),
        ),
        isNull,
      );
      expect(
        GroupBalanceAggregate.fromDoc(validDoc(overrides: {'eventCount': 'x'})),
        isNull,
      );
    });

    test('a non-int milli entry is dropped per-bucket; the rest of the bucket '
        'survives', () {
      final agg = GroupBalanceAggregate.fromDoc(
        validDoc(overrides: {
          'netMilliByCurrency': {
            'OMR': {'alice': -4000, 'bob': 'garbage'},
            'AED': {'alice': 10500},
          },
        }),
      )!;
      expect(agg.netByCurrency['OMR']!['alice'], Decimal.parse('-4'));
      expect(agg.netByCurrency['OMR']!.containsKey('bob'), isFalse);
      expect(agg.netByCurrency['AED']!['alice'], Decimal.parse('10.5'));
    });
  });
}
