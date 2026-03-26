import 'package:flutter_test/flutter_test.dart';

// Wave 0 stub: BalanceCacheRepository tests (SQLite-backed).
// Real implementation added in Plan 04-01 (Ledger Migration).

void main() {
  group('BalanceCacheRepository', () {
    group('cacheExpenses', () {
      test(
        'writes expense list to SQLite expenses table',
        () {},
        skip: 'Awaiting Plan 04-01: BalanceCacheRepository implementation',
      );
    });

    group('cacheSettlements', () {
      test(
        'writes settlement list to SQLite settlements table',
        () {},
        skip: 'Awaiting Plan 04-01: BalanceCacheRepository implementation',
      );
    });

    group('getExpenses', () {
      test(
        'reads expenses from SQLite by eventId',
        () {},
        skip: 'Awaiting Plan 04-01: BalanceCacheRepository implementation',
      );
    });
  });
}
