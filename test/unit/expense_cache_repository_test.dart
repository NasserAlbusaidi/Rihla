// Tests for ExpenseCacheRepository — migrated from balance_cache_repository_test.dart
// in Phase 36 Plan 06. Uses sqflite_common_ffi for in-memory SQLite on macOS/Linux/Windows.
import 'dart:io';

import 'package:decimal/decimal.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:safar/core/models/split_mode.dart';
import 'package:safar/core/services/cache/expense_cache_repository.dart';
import 'package:safar/core/services/local_database.dart';
import 'package:safar/features/ledger/models/expense_model.dart';

void main() {
  late Directory tempDir;

  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    tempDir = await Directory.systemTemp.createTemp('rihla-expense-cache-');
    await LocalDatabase.setDatabasePathForTesting(
      '${tempDir.path}/safar_cache.db',
    );
  });

  setUp(() async {
    // Ensure a fresh state for each test by clearing all rows.
    await LocalDatabase.clearAll();
  });

  tearDownAll(() async {
    await LocalDatabase.close();
    await LocalDatabase.setDatabasePathForTesting(null);
    await tempDir.delete(recursive: true);
  });

  group('ExpenseCacheRepository', () {
    late ExpenseCacheRepository repo;

    setUp(() {
      repo = ExpenseCacheRepository();
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

      test(
        'asserts OMR-only currency when expense has a splitDistribution '
        '(cache schema does not persist currency; V1 OMR-only)',
        () async {
          // The cache row stores splitDistribution as integer subunits with
          // no currency column. The decode path hardcodes OMR. Caching a
          // USD expense with a splitDistribution would silently round-trip
          // as OMR fils — half the system writes cents, half reads fils.
          // The encode-side assertion makes the asymmetry loud.
          final usdExpense = Expense(
            id: 'e-usd',
            tripId: 'trip-1',
            payerParticipantId: 'payer-1',
            amount: Decimal.parse('10.00'),
            currency: 'USD',
            scope: ExpenseScope.global,
            splitMode: SplitMode.exact,
            splitDistribution: {
              'payer-1': Decimal.parse('5.00'),
              'p2': Decimal.parse('5.00'),
            },
            createdAt: DateTime(2026, 1, 1),
          );

          expect(
            () => repo.cacheExpenses('trip-1', [usdExpense]),
            throwsA(isA<AssertionError>()),
          );
        },
      );

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

      test(
        'ghost-row prevention: second cacheExpenses replaces full set',
        () async {
          // First write: 2 expenses
          await repo.cacheExpenses('trip-1', [
            buildExpense(id: 'e-1', tripId: 'trip-1'),
            buildExpense(id: 'e-2', tripId: 'trip-1'),
          ]);

          // Second write: only 1 expense (e-2 was server-deleted)
          await repo.cacheExpenses('trip-1', [
            buildExpense(id: 'e-1', tripId: 'trip-1'),
          ]);

          // e-2 must be gone — delete-then-insert prevents ghost row
          final result = await repo.getExpenses('trip-1');
          expect(result.length, equals(1));
          expect(result.first.id, equals('e-1'));
        },
      );
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
  });
}
