import 'dart:io';

import 'package:decimal/decimal.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:safar/core/services/cache/expense_cache_repository.dart';
import 'package:safar/core/services/cache/settlement_cache_repository.dart';
import 'package:safar/core/services/local_database.dart';
import 'package:safar/features/ledger/models/expense_model.dart';
import 'package:safar/features/ledger/providers/expense_provider.dart';
import 'package:safar/features/ledger/services/expense_service.dart';
import 'package:safar/features/ledger/services/settlement_service.dart';
import 'package:safar/features/trip/models/trip_model.dart';

/// Offline scenario integration tests — SQLite side-write verification (D-12).
///
/// These tests verify the side-write pipeline: service writes to
/// FakeFirebaseFirestore, then we manually cache to SQLite (simulating what
/// the asyncMap listener does in production), then verify SQLite has correct
/// data.
///
/// Per D-11: This is SQLite-only verification. No Firestore network simulation.
/// Per D-13: Lives in test/integration/ because it tests interaction between
/// Firestore services and SQLite.
void main() {
  late Directory tempDir;

  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    tempDir = await Directory.systemTemp.createTemp('rihla-offline-scenario-');
    await LocalDatabase.setDatabasePathForTesting(
      '${tempDir.path}/safar_cache.db',
    );
  });

  setUp(() async {
    await LocalDatabase.clearAll();
  });

  tearDownAll(() async {
    await LocalDatabase.close();
    await LocalDatabase.setDatabasePathForTesting(null);
    await tempDir.delete(recursive: true);
  });

  group('Offline scenarios — SQLite side-write verification (D-12)', () {
    // -----------------------------------------------------------------------
    // Helpers
    // -----------------------------------------------------------------------

    const groupId = 'grp-offline';
    const eventId = 'evt-offline';

    // -----------------------------------------------------------------------
    // Scenario 1: expense write -> SQLite side-write verified
    // -----------------------------------------------------------------------

    test(
      'Scenario 1: expense write lands in SQLite with correct Decimal amount',
      () async {
        final fakeDb = FakeFirebaseFirestore();
        final expenseService = ExpenseService.withFirestore(fakeDb);
        final repo = ExpenseCacheRepository();

        // Write an expense via ExpenseService (writes to FakeFirebaseFirestore)
        final expense = await expenseService.addExpense(
          groupId: groupId,
          eventId: eventId,
          payerParticipantId: 'uid-alice',
          amount: Decimal.parse('25.750'),
          currency: 'OMR',
          description: 'Hotel stay',
        );

        // Cache the expense to SQLite — simulating the asyncMap side-write
        await repo.cacheExpenses(eventId, [expense]);

        // Read back from SQLite
        final cached = await repo.getExpenses(eventId);

        // Verify SQLite record has correct Decimal amount matching what was written
        expect(cached.length, equals(1));
        expect(
          cached.first.amount,
          equals(Decimal.parse('25.750')),
          reason:
              'Decimal amount must survive the Firestore->SQLite round-trip',
        );
        expect(cached.first.id, equals(expense.id));
      },
    );

    // -----------------------------------------------------------------------
    // Scenario 2: settlement write + BalanceCalculator reads correct values
    // -----------------------------------------------------------------------

    test(
      'Scenario 2: settlement write + BalanceCalculator reads correct values from cache',
      () async {
        final fakeDb = FakeFirebaseFirestore();
        final expenseService = ExpenseService.withFirestore(fakeDb);
        final settlementService = SettlementService.withFirestore(fakeDb);
        final expenseRepo = ExpenseCacheRepository();
        final settlementRepo = SettlementCacheRepository();

        // Write expense: Alice paid 30.000 OMR for a shared expense
        final expense = await expenseService.addExpense(
          groupId: groupId,
          eventId: eventId,
          payerParticipantId: 'uid-alice',
          amount: Decimal.parse('30.000'),
          currency: 'OMR',
          description: 'Dinner for two',
          scope: ExpenseScope.global,
        );

        // Write settlement: Bob pays Alice 15.000 OMR (his share)
        final settlement = await settlementService.addSettlement(
          groupId: groupId,
          eventId: eventId,
          payerParticipantId: 'uid-bob',
          recipientParticipantId: 'uid-alice',
          amount: Decimal.parse('15.000'),
          currency: 'OMR',
        );

        // Cache both to SQLite — simulating asyncMap side-writes in production
        await expenseRepo.cacheExpenses(eventId, [expense]);
        await settlementRepo.cacheSettlements(eventId, [settlement]);

        // Read from SQLite via the new split cache repositories
        final cachedExpenses = await expenseRepo.getExpenses(eventId);
        final cachedSettlements = await settlementRepo.getSettlements(eventId);

        // Feed cached data to BalanceCalculator
        final participants = [
          Participant(
            id: 'uid-alice',
            tripId: eventId,
            role: ParticipantRole.member,
            joinedAt: DateTime(2026, 1, 1),
            displayName: 'Alice',
          ),
          Participant(
            id: 'uid-bob',
            tripId: eventId,
            role: ParticipantRole.member,
            joinedAt: DateTime(2026, 1, 1),
            displayName: 'Bob',
          ),
        ];
        final balances = BalanceCalculator.calculateBalances(
          expenses: cachedExpenses,
          settlements: cachedSettlements,
          participants: participants,
        );

        // Alice paid 30, expense split 2 ways = 15 each.
        // Bob settled 15 to Alice.
        // Net result: both at zero.
        final aliceBalance = balances.firstWhere(
          (b) => b.participantId == 'uid-alice',
        );
        final bobBalance = balances.firstWhere(
          (b) => b.participantId == 'uid-bob',
        );

        expect(
          aliceBalance.netBalance,
          equals(Decimal.zero),
          reason: 'Alice net balance should be zero after settlement',
        );
        expect(
          bobBalance.netBalance,
          equals(Decimal.zero),
          reason: 'Bob net balance should be zero after settlement',
        );
      },
    );

    // -----------------------------------------------------------------------
    // Scenario 3: multiple writes -> all appear in SQLite in correct order
    // -----------------------------------------------------------------------

    test(
      'Scenario 3: multiple writes all appear in SQLite with correct amounts',
      () async {
        final fakeDb = FakeFirebaseFirestore();
        final expenseService = ExpenseService.withFirestore(fakeDb);
        final repo = ExpenseCacheRepository();

        // Write 3 expenses with different amounts
        final expense1 = await expenseService.addExpense(
          groupId: groupId,
          eventId: eventId,
          payerParticipantId: 'uid-alice',
          amount: Decimal.parse('10.000'),
          currency: 'OMR',
          description: 'Coffee',
        );

        final expense2 = await expenseService.addExpense(
          groupId: groupId,
          eventId: eventId,
          payerParticipantId: 'uid-bob',
          amount: Decimal.parse('20.500'),
          currency: 'OMR',
          description: 'Lunch',
        );

        final expense3 = await expenseService.addExpense(
          groupId: groupId,
          eventId: eventId,
          payerParticipantId: 'uid-alice',
          amount: Decimal.parse('5.250'),
          currency: 'OMR',
          description: 'Snacks',
        );

        // Cache all to SQLite
        await repo.cacheExpenses(eventId, [expense1, expense2, expense3]);

        // Read from SQLite
        final cached = await repo.getExpenses(eventId);

        // Verify all 3 are present with correct amounts
        expect(cached.length, equals(3));

        final ids = cached.map((e) => e.id).toSet();
        expect(
          ids.contains(expense1.id),
          isTrue,
          reason: 'expense1 must be in SQLite cache',
        );
        expect(
          ids.contains(expense2.id),
          isTrue,
          reason: 'expense2 must be in SQLite cache',
        );
        expect(
          ids.contains(expense3.id),
          isTrue,
          reason: 'expense3 must be in SQLite cache',
        );

        // Verify amounts are correct for each expense
        final cachedById = {for (final e in cached) e.id: e};
        expect(
          cachedById[expense1.id]!.amount,
          equals(Decimal.parse('10.000')),
          reason: 'expense1 amount must match',
        );
        expect(
          cachedById[expense2.id]!.amount,
          equals(Decimal.parse('20.500')),
          reason: 'expense2 amount must match',
        );
        expect(
          cachedById[expense3.id]!.amount,
          equals(Decimal.parse('5.250')),
          reason: 'expense3 amount must match',
        );
      },
    );
  });
}
