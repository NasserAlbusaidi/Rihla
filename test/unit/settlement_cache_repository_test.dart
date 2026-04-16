// Tests for SettlementCacheRepository — migrated from balance_cache_repository_test.dart
// in Phase 36 Plan 06. Uses sqflite_common_ffi for in-memory SQLite on macOS/Linux/Windows.
import 'package:decimal/decimal.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:safar/core/services/cache/settlement_cache_repository.dart';
import 'package:safar/core/services/local_database.dart';
import 'package:safar/features/ledger/models/settlement_model.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    // Ensure a fresh state for each test by clearing all rows.
    await LocalDatabase.clearAll();
  });

  tearDownAll(() async {
    await LocalDatabase.close();
  });

  group('SettlementCacheRepository', () {
    late SettlementCacheRepository repo;

    setUp(() {
      repo = SettlementCacheRepository();
    });

    // Helper: create a minimal Settlement with the given id and tripId.
    Settlement buildSettlement({
      required String id,
      required String tripId,
      String payerId = 'payer-1',
      String recipientId = 'recipient-1',
      String amount = '5.000',
    }) {
      return Settlement(
        id: id,
        tripId: tripId,
        payerParticipantId: payerId,
        recipientParticipantId: recipientId,
        amount: Decimal.parse(amount),
        settledAt: DateTime(2026, 1, 1),
      );
    }

    // -------------------------------------------------------------------------
    // cacheSettlements / getSettlements
    // -------------------------------------------------------------------------

    group('cacheSettlements', () {
      test('writes settlement list to SQLite settlements table', () async {
        final settlements = [
          buildSettlement(id: 's-1', tripId: 'trip-1'),
          buildSettlement(id: 's-2', tripId: 'trip-1', amount: '3.000'),
        ];

        await repo.cacheSettlements('trip-1', settlements);

        final result = await repo.getSettlements('trip-1');
        expect(result.length, equals(2));
      });

      test('stores correct id and amount', () async {
        final settlement = buildSettlement(
          id: 's-99',
          tripId: 'trip-1',
          amount: '7.750',
        );

        await repo.cacheSettlements('trip-1', [settlement]);

        final result = await repo.getSettlements('trip-1');
        expect(result.first.id, equals('s-99'));
        expect(result.first.amount, equals(Decimal.parse('7.750')));
      });

      test('does not return deleted settlements', () async {
        final active = buildSettlement(id: 's-1', tripId: 'trip-1');
        final deleted = Settlement(
          id: 's-2',
          tripId: 'trip-1',
          payerParticipantId: 'payer-1',
          recipientParticipantId: 'recipient-1',
          amount: Decimal.parse('5.000'),
          settledAt: DateTime(2026, 1, 1),
          isDeleted: true,
        );

        await repo.cacheSettlements('trip-1', [active, deleted]);

        final result = await repo.getSettlements('trip-1');
        expect(result.length, equals(1));
        expect(result.first.id, equals('s-1'));
      });

      test('ghost-row prevention: second cacheSettlements replaces full set',
          () async {
        // First write: 2 settlements
        await repo.cacheSettlements('trip-1', [
          buildSettlement(id: 's-1', tripId: 'trip-1'),
          buildSettlement(id: 's-2', tripId: 'trip-1'),
        ]);

        // Second write: only 1 settlement (s-2 was server-deleted)
        await repo.cacheSettlements('trip-1', [
          buildSettlement(id: 's-1', tripId: 'trip-1'),
        ]);

        // s-2 must be gone — delete-then-insert prevents ghost row
        final result = await repo.getSettlements('trip-1');
        expect(result.length, equals(1));
        expect(result.first.id, equals('s-1'));
      });
    });

    group('getSettlements', () {
      test('reads settlements from SQLite by eventId', () async {
        await repo.cacheSettlements('trip-A', [
          buildSettlement(id: 's-a1', tripId: 'trip-A'),
        ]);
        await repo.cacheSettlements('trip-B', [
          buildSettlement(id: 's-b1', tripId: 'trip-B'),
        ]);

        final resultA = await repo.getSettlements('trip-A');
        expect(resultA.length, equals(1));
        expect(resultA.first.id, equals('s-a1'));

        final resultB = await repo.getSettlements('trip-B');
        expect(resultB.length, equals(1));
        expect(resultB.first.id, equals('s-b1'));
      });

      test('returns empty list when no settlements cached', () async {
        final result = await repo.getSettlements('nonexistent-trip');
        expect(result, isEmpty);
      });
    });
  });
}
