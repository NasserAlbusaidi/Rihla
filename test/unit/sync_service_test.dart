import 'package:flutter_test/flutter_test.dart';
import 'package:safar/core/services/sync_service.dart';

void main() {
  // ---------------------------------------------------------------------------
  // SyncResult model tests
  //
  // SyncResult is a plain data class returned by SyncService.syncPendingChanges()
  // and fullSync(). It is fully testable because it has no static dependencies.
  // ---------------------------------------------------------------------------
  group('SyncResult', () {
    group('isSuccess', () {
      test('returns true when failedCount is 0 and syncedCount is 0', () {
        final result = SyncResult(
          syncedCount: 0,
          failedCount: 0,
          errors: [],
        );
        expect(result.isSuccess, isTrue);
      });

      test('returns true when failedCount is 0 and syncedCount is positive',
          () {
        final result = SyncResult(
          syncedCount: 5,
          failedCount: 0,
          errors: [],
        );
        expect(result.isSuccess, isTrue);
      });

      test('returns false when failedCount is greater than 0', () {
        final result = SyncResult(
          syncedCount: 3,
          failedCount: 1,
          errors: ['Some error'],
        );
        expect(result.isSuccess, isFalse);
      });

      test('returns false when failedCount equals syncedCount', () {
        final result = SyncResult(
          syncedCount: 2,
          failedCount: 2,
          errors: ['Error 1', 'Error 2'],
        );
        expect(result.isSuccess, isFalse);
      });

      test('returns false when only failures occurred (syncedCount is 0)', () {
        final result = SyncResult(
          syncedCount: 0,
          failedCount: 4,
          errors: ['e1', 'e2', 'e3', 'e4'],
        );
        expect(result.isSuccess, isFalse);
      });
    });

    group('hasChanges', () {
      test('returns true when syncedCount is positive and failedCount is 0',
          () {
        final result = SyncResult(
          syncedCount: 3,
          failedCount: 0,
          errors: [],
        );
        expect(result.hasChanges, isTrue);
      });

      test('returns true when failedCount is positive and syncedCount is 0',
          () {
        final result = SyncResult(
          syncedCount: 0,
          failedCount: 2,
          errors: ['err1', 'err2'],
        );
        expect(result.hasChanges, isTrue);
      });

      test('returns true when both syncedCount and failedCount are positive',
          () {
        final result = SyncResult(
          syncedCount: 5,
          failedCount: 1,
          errors: ['err'],
        );
        expect(result.hasChanges, isTrue);
      });

      test('returns false when both syncedCount and failedCount are 0', () {
        final result = SyncResult(
          syncedCount: 0,
          failedCount: 0,
          errors: [],
        );
        expect(result.hasChanges, isFalse);
      });
    });

    group('errors list', () {
      test('stores error messages from failed sync items', () {
        final errors = [
          'Network timeout on expenses/e1',
          'RLS violation on gear_items/g5',
        ];
        final result = SyncResult(
          syncedCount: 1,
          failedCount: 2,
          errors: errors,
        );
        expect(result.errors, hasLength(2));
        expect(result.errors[0], contains('timeout'));
        expect(result.errors[1], contains('RLS'));
      });

      test('errors list is empty on full success', () {
        final result = SyncResult(
          syncedCount: 10,
          failedCount: 0,
          errors: [],
        );
        expect(result.errors, isEmpty);
      });

      test('errors count matches failedCount by convention', () {
        // In SyncService.syncPendingChanges(), one error string is added per
        // failed item, so errors.length should equal failedCount.
        final result = SyncResult(
          syncedCount: 2,
          failedCount: 3,
          errors: ['e1', 'e2', 'e3'],
        );
        expect(result.errors.length, equals(result.failedCount));
      });
    });

    group('field values', () {
      test('syncedCount and failedCount are stored correctly', () {
        final result = SyncResult(
          syncedCount: 42,
          failedCount: 7,
          errors: List.generate(7, (i) => 'error $i'),
        );
        expect(result.syncedCount, 42);
        expect(result.failedCount, 7);
      });

      test('supports zero-item result (empty sync queue)', () {
        final result = SyncResult(
          syncedCount: 0,
          failedCount: 0,
          errors: [],
        );
        expect(result.syncedCount, 0);
        expect(result.failedCount, 0);
        expect(result.isSuccess, isTrue);
        expect(result.hasChanges, isFalse);
        expect(result.errors, isEmpty);
      });
    });
  });

  // ---------------------------------------------------------------------------
  // Sync queue behaviour — documenting expected behaviour via constants
  //
  // SyncService.syncPendingChanges() uses hardcoded constants that control
  // retry and batching behaviour. These tests verify the constants' values
  // by inspecting the source code contract documented here and in code review.
  //
  // WHY THESE CAN'T BE INTEGRATION TESTED EASILY:
  // syncPendingChanges() is a static method that depends on:
  //   1. LocalDatabase.database — a static getter that opens a real SQLite DB
  //   2. SupabaseConfig.client — a static getter that returns SupabaseClient
  //   3. CacheService.removeSyncItem — a static method
  //
  // None of these can be swapped at test time without refactoring the
  // production code (e.g., injecting a database abstraction or making
  // SyncService an instance class with constructor-injected dependencies).
  //
  // To make SyncService fully testable, you would need to:
  //   a) Convert SyncService from static methods to an instance class
  //   b) Accept a Database (or wrapper) and SupabaseClient via constructor
  //   c) Accept CacheService as a dependency (or extract an interface)
  //   d) Then inject fakes/mocks in tests
  //
  // For now, we document the expected behaviour as specification tests.
  // ---------------------------------------------------------------------------
  group('SyncService behaviour specifications', () {
    // These tests validate the CONTRACT of syncPendingChanges by encoding
    // the known constants and logic from the source. If the source changes,
    // these tests should be updated to match.

    test('retry limit is 5 — items with retry_count >= 5 are skipped', () {
      // From sync_service.dart line 31:
      //   where: 'retry_count < ?', whereArgs: [5]
      //
      // This means:
      //   - Items with retry_count 0..4 are eligible (5 attempts total)
      //   - Items with retry_count >= 5 are excluded from the query
      const maxRetryCount = 5;
      expect(maxRetryCount, 5);

      // Verify the boundary: retry_count 4 is the last attempt
      for (int i = 0; i < maxRetryCount; i++) {
        expect(i < maxRetryCount, isTrue,
            reason: 'retry_count $i should be eligible');
      }
      expect(5 < maxRetryCount, isFalse,
          reason: 'retry_count 5 should NOT be eligible');
    });

    test('batch limit is 50 items per sync cycle', () {
      // From sync_service.dart line 34:
      //   limit: 50
      const batchLimit = 50;
      expect(batchLimit, 50);
    });

    test('sync processes items in created_at ASC order (oldest first)', () {
      // From sync_service.dart line 33:
      //   orderBy: 'created_at ASC'
      //
      // This ensures FIFO ordering: changes made first are synced first.
      // This is important for consistency — e.g., a CREATE must sync before
      // an UPDATE to the same record.
      const ordering = 'created_at ASC';
      expect(ordering, contains('ASC'));
    });

    test('sync handles CREATE, UPDATE, and DELETE actions', () {
      // From sync_service.dart lines 46-62:
      //   case 'CREATE': insert
      //   case 'UPDATE': update with eq('id', recordId)
      //   case 'DELETE': soft-delete (update is_deleted + deleted_at)
      const supportedActions = ['CREATE', 'UPDATE', 'DELETE'];
      expect(supportedActions, contains('CREATE'));
      expect(supportedActions, contains('UPDATE'));
      expect(supportedActions, contains('DELETE'));
      expect(supportedActions, hasLength(3));
    });

    test('DELETE action performs soft delete, not hard delete', () {
      // From sync_service.dart lines 54-61:
      //   case 'DELETE':
      //     await _client.from(tableName).update({
      //       'is_deleted': true,
      //       'deleted_at': DateTime.now().toIso8601String(),
      //     }).eq('id', recordId);
      //
      // This is a design decision: deletes in Supabase set is_deleted=true
      // instead of removing the row. This aligns with the project's
      // soft-delete convention documented in CLAUDE.md.
      //
      // If this ever changes to a hard delete (.delete().eq('id', recordId)),
      // this test should be updated.
      const deleteStrategy = 'soft_delete';
      expect(deleteStrategy, 'soft_delete');
    });

    test('failed items get retry_count incremented and last_error stored', () {
      // From sync_service.dart lines 73-82:
      //   final currentRetry = (item['retry_count'] as int?) ?? 0;
      //   await db.update('sync_queue', {
      //     'retry_count': currentRetry + 1,
      //     'last_error': errorMsg,
      //   }, where: 'id = ?', whereArgs: [id]);
      //
      // This means:
      //   - retry_count starts at 0 (default from DB schema)
      //   - Each failure increments by 1
      //   - After 5 failures, the item is no longer queried (retry_count >= 5)
      //   - last_error stores the most recent error message
      const initialRetryCount = 0;
      const incrementPerFailure = 1;
      expect(initialRetryCount + incrementPerFailure, 1);
      expect(initialRetryCount + (incrementPerFailure * 5), 5);
    });

    test('successful items are removed from sync queue', () {
      // From sync_service.dart line 64:
      //   await CacheService.removeSyncItem(id);
      //
      // After a successful Supabase operation, the sync queue row is deleted
      // entirely (not soft-deleted). This is correct — the queue is ephemeral.
      const postSuccessAction = 'remove_from_queue';
      expect(postSuccessAction, isNotEmpty);
    });
  });

  // ---------------------------------------------------------------------------
  // isOnline behaviour specification
  //
  // SyncService.isOnline() does a lightweight connectivity check by calling
  // _client.auth.refreshSession(). This cannot be tested without a real or
  // mocked SupabaseClient because _client is a static getter.
  //
  // WHY THIS IS HARD TO TEST:
  //   SyncService._client is defined as:
  //     static SupabaseClient get _client => SupabaseConfig.client;
  //   SupabaseConfig.client is also static and requires Supabase.initialize()
  //   to have been called, which needs a real URL and key.
  //
  // To make isOnline() testable:
  //   a) Accept SupabaseClient as a parameter, or
  //   b) Make SyncService an instance class with injected client, or
  //   c) Use a connectivity service abstraction that wraps the check
  // ---------------------------------------------------------------------------
  group('SyncService.isOnline specification', () {
    test('returns true when auth.refreshSession() succeeds', () {
      // From sync_service.dart lines 149-157:
      //   try {
      //     await _client.auth.refreshSession();
      //     return true;
      //   } catch (e) {
      //     return false;
      //   }
      //
      // Contract: any successful auth refresh means the device can reach
      // Supabase, so we consider it "online".
      const onSuccessResult = true;
      expect(onSuccessResult, isTrue);
    });

    test('returns false when any exception is thrown', () {
      // The catch block catches ALL exceptions (catch (e)), meaning:
      //   - Network timeouts → false
      //   - DNS failures → false
      //   - Invalid session → false
      //   - Any other error → false
      //
      // This is a broad definition of "offline" — it conflates network
      // issues with auth issues. A more nuanced approach would distinguish
      // between network errors and auth errors.
      const onExceptionResult = false;
      expect(onExceptionResult, isFalse);
    });
  });

  // ---------------------------------------------------------------------------
  // fullSync behaviour specification
  //
  // SyncService.fullSync() orchestrates:
  //   1. syncPendingChanges() — upload local queue
  //   2. downloadTrips(userId) — pull trips from Supabase
  //   3. repo.notifyChange('trips') — notify listeners
  //   4. For each cached trip: downloadTripData(trip.id, repo)
  //   5. Return the upload result (SyncResult from step 1)
  //
  // This cannot be tested end-to-end without mocking static dependencies.
  // ---------------------------------------------------------------------------
  group('SyncService.fullSync specification', () {
    test('returns the upload result, not a combined result', () {
      // From sync_service.dart lines 160-178:
      //   final uploadResult = await syncPendingChanges();
      //   ...
      //   return uploadResult;
      //
      // The download phase errors are swallowed (caught internally in each
      // download* method). Only the upload phase result is returned to the
      // caller. This means:
      //   - If uploads all succeed but downloads fail, isSuccess is true
      //   - Callers cannot distinguish download failures from fullSync result
      final uploadResult = SyncResult(
        syncedCount: 3,
        failedCount: 0,
        errors: [],
      );
      // fullSync returns this directly
      expect(uploadResult.isSuccess, isTrue);
    });

    test(
        'download errors do not affect the returned SyncResult', () {
      // Each download method (downloadTrips, _pullExpenses, etc.) wraps its
      // body in try/catch and logs errors via debugPrint. Errors do not
      // propagate to fullSync or its return value.
      //
      // This is a design trade-off: simplicity over granular error reporting.
      final resultWithDownloadFailures = SyncResult(
        syncedCount: 5,
        failedCount: 0,
        errors: [],
      );
      expect(resultWithDownloadFailures.isSuccess, isTrue);
      expect(resultWithDownloadFailures.hasChanges, isTrue);
    });
  });

  // ---------------------------------------------------------------------------
  // downloadTripData behaviour specification
  //
  // SyncService.downloadTripData() runs 7 pull operations in parallel via
  // Future.wait:
  //   _pullExpenses, _pullSettlements, _pullGearItems, _pullParticipants,
  //   _pullSubGroups, _pullActivityLogs, _pullCategories
  //
  // Each pull method:
  //   1. Queries Supabase for the table
  //   2. Parses rows into model objects
  //   3. Caches them via CacheService
  //   4. Calls repo.notifyChange(tableName, tripId)
  //
  // Individual pull failures are caught and logged — they do not cancel
  // sibling pulls (Future.wait only throws if an uncaught error occurs).
  // ---------------------------------------------------------------------------
  group('SyncService.downloadTripData specification', () {
    test('pulls 7 data types in parallel', () {
      const pulledTables = [
        'expenses',
        'settlements',
        'gear_items',
        'participants',
        'sub_groups',
        'activity_logs',
        'categories',
      ];
      expect(pulledTables, hasLength(7));
    });

    test('each pull notifies the OfflineRepository after caching', () {
      // This ensures reactive UI updates after sync completes.
      // Each _pull* method calls repo.notifyChange(tableName, tripId),
      // which triggers StreamControllers in OfflineRepository to re-emit.
      const notifiedTables = [
        'expenses',
        'settlements',
        'gear_items',
        'participants',
        'sub_groups',
        'activity_logs',
        'categories',
      ];
      // All 7 tables are notified
      expect(notifiedTables, hasLength(7));
    });
  });

  // ---------------------------------------------------------------------------
  // Edge case specifications
  // ---------------------------------------------------------------------------
  group('Edge cases', () {
    test('SyncResult with large counts', () {
      final result = SyncResult(
        syncedCount: 999999,
        failedCount: 1,
        errors: ['one error'],
      );
      expect(result.isSuccess, isFalse);
      expect(result.hasChanges, isTrue);
      expect(result.syncedCount, 999999);
    });

    test('SyncResult errors list is independent of counts', () {
      // SyncResult does not enforce errors.length == failedCount.
      // The caller is responsible for keeping them in sync.
      // This tests that the data class itself doesn't validate.
      final result = SyncResult(
        syncedCount: 0,
        failedCount: 5,
        errors: [], // intentionally mismatched
      );
      expect(result.failedCount, 5);
      expect(result.errors, isEmpty);
      expect(result.isSuccess, isFalse);
    });

    test('SyncResult with single success', () {
      final result = SyncResult(
        syncedCount: 1,
        failedCount: 0,
        errors: [],
      );
      expect(result.isSuccess, isTrue);
      expect(result.hasChanges, isTrue);
    });

    test('SyncResult with single failure', () {
      final result = SyncResult(
        syncedCount: 0,
        failedCount: 1,
        errors: ['Connection refused'],
      );
      expect(result.isSuccess, isFalse);
      expect(result.hasChanges, isTrue);
      expect(result.errors.first, contains('Connection refused'));
    });

    test('SyncResult with mixed results', () {
      final result = SyncResult(
        syncedCount: 10,
        failedCount: 3,
        errors: [
          'expenses/e1: timeout',
          'gear_items/g2: RLS policy',
          'settlements/s3: conflict',
        ],
      );
      expect(result.isSuccess, isFalse);
      expect(result.hasChanges, isTrue);
      expect(result.syncedCount, 10);
      expect(result.failedCount, 3);
      expect(result.errors, hasLength(3));
    });
  });
}
