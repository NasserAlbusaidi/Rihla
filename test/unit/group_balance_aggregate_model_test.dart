import 'package:decimal/decimal.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:safar/features/groups/models/group_balance_aggregate_model.dart';

// RED → GREEN (#366 Task 8): decode contract for the server-maintained
// balance-aggregate doc (groups/{gid}/aggregates/balance, written by the
// balanceAggregator triggers — spec docs/plans/2026-06-10-366-balance-aggregate.md
// §0.3). Boundary validation: anything malformed decodes to null so the home
// facade falls back to the once-path instead of rendering garbage money.

Map<String, dynamic> validDoc({Map<String, dynamic> overrides = const {}}) {
  return <String, dynamic>{
    'schemaVersion': 1,
    'currency': 'OMR',
    'currencies': ['OMR'],
    'netMilli': {'alice': -4000, 'bob': -2000, 'carol': 6000},
    'perEventNetMilli': {
      'e1': {'alice': -3500, 'bob': -5500},
    },
    'eventCount': 1,
    'degraded': false,
    'sourceTimeMs': 1000,
    ...overrides,
  };
}

void main() {
  group('GroupBalanceAggregate.fromDoc (#366)', () {
    test('decodes milli ints into exact Decimals (parity case P1 numbers)', () {
      final agg = GroupBalanceAggregate.fromDoc(validDoc());

      expect(agg, isNotNull);
      expect(agg!.netByUid['alice'], Decimal.parse('-4'));
      expect(agg.netByUid['bob'], Decimal.parse('-2'));
      expect(agg.netByUid['carol'], Decimal.parse('6'));
      expect(agg.perEventNetByUid['e1']!['alice'], Decimal.parse('-3.5'));
      expect(agg.perEventNetByUid['e1']!['bob'], Decimal.parse('-5.5'));
      expect(agg.eventCount, 1);
      expect(agg.currency, 'OMR');
      expect(agg.currencies, ['OMR']);
    });

    test('a uid absent from netMilli means zero — exposed via netFor', () {
      final agg = GroupBalanceAggregate.fromDoc(validDoc())!;
      expect(agg.netFor('nobody'), Decimal.zero);
      expect(agg.perEventNetFor('nobody'), isEmpty);
      expect(agg.perEventNetFor('alice'), {'e1': Decimal.parse('-3.5')});
    });

    test('sub-unit milli precision decodes exactly (0.001 OMR = 1 milli)', () {
      final agg = GroupBalanceAggregate.fromDoc(
        validDoc(overrides: {
          'netMilli': {'alice': 1, 'bob': -1},
          'perEventNetMilli': <String, dynamic>{},
        }),
      )!;
      expect(agg.netByUid['alice'], Decimal.parse('0.001'));
      expect(agg.netByUid['bob'], Decimal.parse('-0.001'));
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

    test('an unknown future schemaVersion decodes to null', () {
      expect(
        GroupBalanceAggregate.fromDoc(validDoc(overrides: {'schemaVersion': 2})),
        isNull,
      );
    });

    test('garbage field shapes decode to null, never throw', () {
      expect(
        GroupBalanceAggregate.fromDoc(validDoc(overrides: {'netMilli': 'oops'})),
        isNull,
      );
      expect(
        GroupBalanceAggregate.fromDoc(
          validDoc(overrides: {'perEventNetMilli': 17}),
        ),
        isNull,
      );
      expect(
        GroupBalanceAggregate.fromDoc(validDoc(overrides: {'eventCount': 'x'})),
        isNull,
      );
    });

    test('a non-int milli entry is dropped; the rest of the map survives', () {
      final agg = GroupBalanceAggregate.fromDoc(
        validDoc(overrides: {
          'netMilli': {'alice': -4000, 'bob': 'garbage'},
        }),
      )!;
      expect(agg.netByUid['alice'], Decimal.parse('-4'));
      expect(agg.netByUid.containsKey('bob'), isFalse);
    });

    test('legacy-mixed currencies (>1) still decodes — the facade decides the fallback', () {
      final agg = GroupBalanceAggregate.fromDoc(
        validDoc(overrides: {
          'currencies': ['OMR', 'USD'],
        }),
      )!;
      expect(agg.currencies, ['OMR', 'USD']);
    });
  });
}
