import 'package:decimal/decimal.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:safar/core/services/balance_cache_repository.dart';
import 'package:safar/core/services/local_database.dart';
import 'package:safar/features/ledger/models/expense_model.dart';
import 'package:safar/features/ledger/models/settlement_model.dart';

// BalanceCacheRepository tests.
// Uses sqflite_common_ffi for in-memory SQLite on macOS/Linux/Windows.

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    // Ensure a fresh state for each test by clearing all rows.
    // LocalDatabase opens lazily on first access; clearAll() handles that.
    await LocalDatabase.clearAll();
  });

  tearDownAll(() async {
    // Close the DB once after all tests complete.
    await LocalDatabase.close();
  });

  group('BalanceCacheRepository', () {
    late BalanceCacheRepository repo;

    setUp(() {
      repo = BalanceCacheRepository();
    });

    tearDown(() {
      repo.dispose();
    });

    // Helper: create a minimal Expense with the given id and tripId.
    Expense buildExpense({
      required String id,
      required String tripId,
      String payerId = 'payer-1',
      String amount = '10.000',
    }) {
      return Expense(
        id: id,
        tripId: tripId,
        payerParticipantId: payerId,
        amount: Decimal.parse(amount),
        scope: ExpenseScope.global,
        createdAt: DateTime(2026, 1, 1),
      );
    }

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
    // cacheExpenses / getExpenses
    // -------------------------------------------------------------------------

    group('cacheExpenses', () {
      test('writes expense list to SQLite expenses table', () async {
        final expenses = [
          buildExpense(id: 'e-1', tripId: 'trip-1'),
          buildExpense(id: 'e-2', tripId: 'trip-1', amount: '20.000'),
        ];

        await repo.cacheExpenses('trip-1', expenses);

        final result = await repo.getExpenses('trip-1');
        expect(result.length, equals(2));
      });

      test('stores correct id and amount', () async {
        final expense = buildExpense(
          id: 'e-42',
          tripId: 'trip-1',
          amount: '42.500',
        );

        await repo.cacheExpenses('trip-1', [expense]);

        final result = await repo.getExpenses('trip-1');
        expect(result.first.id, equals('e-42'));
        expect(result.first.amount, equals(Decimal.parse('42.500')));
      });

      test('replaces existing entries on conflict (upsert)', () async {
        final original = buildExpense(
          id: 'e-1',
          tripId: 'trip-1',
          amount: '10.000',
        );
        await repo.cacheExpenses('trip-1', [original]);

        final updated = buildExpense(
          id: 'e-1',
          tripId: 'trip-1',
          amount: '99.000',
        );
        await repo.cacheExpenses('trip-1', [updated]);

        final result = await repo.getExpenses('trip-1');
        expect(result.length, equals(1));
        expect(result.first.amount, equals(Decimal.parse('99.000')));
      });

      test('does not return deleted expenses', () async {
        final active = buildExpense(id: 'e-1', tripId: 'trip-1');
        final deleted = Expense(
          id: 'e-2',
          tripId: 'trip-1',
          payerParticipantId: 'payer-1',
          amount: Decimal.parse('5.000'),
          scope: ExpenseScope.global,
          createdAt: DateTime(2026, 1, 1),
          isDeleted: true,
        );

        await repo.cacheExpenses('trip-1', [active, deleted]);

        final result = await repo.getExpenses('trip-1');
        expect(result.length, equals(1));
        expect(result.first.id, equals('e-1'));
      });
    });

    group('getExpenses', () {
      test('reads expenses from SQLite by eventId', () async {
        await repo.cacheExpenses('trip-A', [
          buildExpense(id: 'e-1', tripId: 'trip-A'),
        ]);
        await repo.cacheExpenses('trip-B', [
          buildExpense(id: 'e-2', tripId: 'trip-B'),
        ]);

        final resultA = await repo.getExpenses('trip-A');
        expect(resultA.length, equals(1));
        expect(resultA.first.id, equals('e-1'));

        final resultB = await repo.getExpenses('trip-B');
        expect(resultB.length, equals(1));
        expect(resultB.first.id, equals('e-2'));
      });

      test('returns empty list when no expenses cached', () async {
        final result = await repo.getExpenses('nonexistent-trip');
        expect(result, isEmpty);
      });
    });

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
    });

    // -------------------------------------------------------------------------
    // watchExpenses stream (deprecated backward-compat)
    // -------------------------------------------------------------------------

    group('watchExpenses', () {
      test('emits initial list when expenses are already cached', () async {
        await repo.cacheExpenses('trip-1', [
          buildExpense(id: 'e-1', tripId: 'trip-1'),
        ]);

        final stream = repo.watchExpenses('trip-1');
        final first = await stream.first;
        expect(first.length, equals(1));
        expect(first.first.id, equals('e-1'));
      });

      test('emits empty list when nothing is cached', () async {
        final stream = repo.watchExpenses('trip-empty');
        final first = await stream.first;
        expect(first, isEmpty);
      });
    });
  });
}
