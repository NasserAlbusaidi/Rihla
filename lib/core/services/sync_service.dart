import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../features/activity/models/activity_log_model.dart';
import '../../features/gear/models/gear_item_model.dart';
import '../../features/ledger/models/expense_category_model.dart';
import '../../features/ledger/models/expense_model.dart';
import '../../features/ledger/models/settlement_model.dart';
import '../../features/logistics/models/sub_group_model.dart';
import '../../features/trip/models/trip_model.dart';
import '../config/supabase_config.dart';
import 'cache_service.dart';
import 'local_database.dart';
import 'offline_repository.dart';

/// Sync service handles synchronizing local cache with Supabase
class SyncService {
  static SupabaseClient get _client => SupabaseConfig.client;

  /// Sync all pending changes to Supabase with retry tracking
  static Future<SyncResult> syncPendingChanges() async {
    int synced = 0;
    int failed = 0;
    final List<String> errors = [];

    try {
      final db = await LocalDatabase.database;
      final pendingItems = await db.query(
        'sync_queue',
        where: 'retry_count < ?',
        whereArgs: [5],
        orderBy: 'created_at ASC',
        limit: 50,
      );

      for (final item in pendingItems) {
        final id = item['id'] as int;
        final tableName = item['table_name'] as String;
        final recordId = item['record_id'] as String;
        final action = item['action'] as String;
        final data =
            jsonDecode(item['data'] as String) as Map<String, dynamic>;

        try {
          switch (action) {
            case 'CREATE':
              await _client.from(tableName).insert(data);
              break;
            case 'UPDATE':
              await _client.from(tableName).update(data).eq('id', recordId);
              break;
            case 'DELETE':
              await _client
                  .from(tableName)
                  .update({
                    'is_deleted': true,
                    'deleted_at': DateTime.now().toIso8601String(),
                  })
                  .eq('id', recordId);
              break;
          }

          await CacheService.removeSyncItem(id);
          synced++;
        } catch (e) {
          failed++;
          final errorMsg = e.toString();
          errors.add(errorMsg);
          debugPrint('Sync error for $tableName/$recordId: $e');

          // Increment retry_count and store last_error
          final currentRetry = (item['retry_count'] as int?) ?? 0;
          await db.update(
            'sync_queue',
            {
              'retry_count': currentRetry + 1,
              'last_error': errorMsg,
            },
            where: 'id = ?',
            whereArgs: [id],
          );
        }
      }
    } catch (e) {
      errors.add('Sync failed: $e');
    }

    return SyncResult(syncedCount: synced, failedCount: failed, errors: errors);
  }

  /// Download and cache all trips for user
  static Future<void> downloadTrips(String userId) async {
    try {
      // Get trips where user is a participant
      final data = await _client
          .from('participants')
          .select('trip_id, trips(*)')
          .eq('user_id', userId);

      for (final row in data) {
        if (row['trips'] != null) {
          final trip = Trip.fromJson(row['trips'] as Map<String, dynamic>);
          await CacheService.cacheTrip(trip);
        }
      }
    } catch (e) {
      debugPrint('Error downloading trips: $e');
    }
  }

  /// Download and cache expenses for a trip
  static Future<void> downloadExpenses(String tripId) async {
    try {
      // Download all expenses (including deleted ones to update cache)
      final data = await _client
          .from('expenses')
          .select('*, expense_categories(name, icon)')
          .eq('trip_id', tripId)
          .order('created_at', ascending: false);

      final expenses = data.map((json) => Expense.fromJson(json)).toList();
      await CacheService.cacheExpenses(tripId, expenses);
    } catch (e) {
      debugPrint('Error downloading expenses: $e');
    }
  }

  /// Download and cache settlements for a trip
  static Future<void> downloadSettlements(String tripId) async {
    try {
      final data = await _client
          .from('settlements')
          .select('*')
          .eq('trip_id', tripId)
          .order('created_at', ascending: false);

      debugPrint('Downloaded ${data.length} settlements');
      final settlements = data
          .map((json) => Settlement.fromJson(json))
          .toList();
      await CacheService.cacheSettlements(tripId, settlements);
    } catch (e) {
      debugPrint('Error downloading settlements: $e');
    }
  }

  /// Check if device is online
  static Future<bool> isOnline() async {
    try {
      // Lightweight connectivity check using auth — no RLS/table dependency
      await _client.auth.refreshSession();
      return true;
    } catch (e) {
      return false;
    }
  }

  /// Full sync: upload pending changes, then download fresh data
  static Future<SyncResult> fullSync(
    String userId,
    OfflineRepository repo,
  ) async {
    // First upload any pending changes
    final uploadResult = await syncPendingChanges();

    // Then download fresh data
    await downloadTrips(userId);
    repo.notifyChange('trips');

    // Download data for each cached trip
    final trips = await CacheService.getCachedTrips();
    for (final trip in trips) {
      await downloadTripData(trip.id, repo);
    }

    return uploadResult;
  }

  // ---------------------------------------------------------------------------
  // Pull methods — download data from Supabase and write to cache
  // ---------------------------------------------------------------------------

  /// Download and cache all trip-level data in parallel
  static Future<void> downloadTripData(
    String tripId,
    OfflineRepository repo,
  ) async {
    try {
      await Future.wait([
        _pullExpenses(tripId, repo),
        _pullSettlements(tripId, repo),
        _pullGearItems(tripId, repo),
        _pullParticipants(tripId, repo),
        _pullSubGroups(tripId, repo),
        _pullActivityLogs(tripId, repo),
        _pullCategories(tripId, repo),
      ]);
    } catch (e) {
      debugPrint('Error downloading trip data for $tripId: $e');
    }
  }

  /// Pull expenses from Supabase and cache locally
  static Future<void> _pullExpenses(
    String tripId,
    OfflineRepository repo,
  ) async {
    try {
      final data = await _client
          .from('expenses')
          .select(
            '*, expense_categories(name, icon), participants!payer_participant_id(*)',
          )
          .eq('trip_id', tripId)
          .order('created_at', ascending: false);

      final expenses =
          (data as List).map((json) => Expense.fromJson(json)).toList();
      await CacheService.cacheExpenses(tripId, expenses);
      repo.notifyChange('expenses', tripId);
    } catch (e) {
      debugPrint('Error pulling expenses: $e');
    }
  }

  /// Pull settlements from Supabase and cache locally
  static Future<void> _pullSettlements(
    String tripId,
    OfflineRepository repo,
  ) async {
    try {
      final data = await _client
          .from('settlements')
          .select(
            '*, payer_participant:participants!payer_participant_id(*), recipient_participant:participants!recipient_participant_id(*)',
          )
          .eq('trip_id', tripId)
          .order('settled_at', ascending: false);

      final settlements =
          (data as List).map((json) => Settlement.fromJson(json)).toList();
      await CacheService.cacheSettlements(tripId, settlements);
      repo.notifyChange('settlements', tripId);
    } catch (e) {
      debugPrint('Error pulling settlements: $e');
    }
  }

  /// Pull gear items from Supabase and cache locally
  static Future<void> _pullGearItems(
    String tripId,
    OfflineRepository repo,
  ) async {
    try {
      final data = await _client
          .from('gear_items')
          .select('*')
          .eq('trip_id', tripId)
          .order('sequence_id', ascending: true);

      final items =
          (data as List).map((json) => GearItem.fromJson(json)).toList();
      await CacheService.cacheGearItems(tripId, items);
      repo.notifyChange('gear_items', tripId);
    } catch (e) {
      debugPrint('Error pulling gear items: $e');
    }
  }

  /// Pull participants from Supabase and cache locally
  static Future<void> _pullParticipants(
    String tripId,
    OfflineRepository repo,
  ) async {
    try {
      final data = await _client
          .from('participants')
          .select('*')
          .eq('trip_id', tripId);

      final participants =
          (data as List).map((json) => Participant.fromJson(json)).toList();
      await CacheService.cacheParticipants(tripId, participants);
      repo.notifyChange('participants', tripId);
    } catch (e) {
      debugPrint('Error pulling participants: $e');
    }
  }

  /// Pull sub-groups (with members) from Supabase and cache locally
  static Future<void> _pullSubGroups(
    String tripId,
    OfflineRepository repo,
  ) async {
    try {
      final sgData = await _client
          .from('sub_groups')
          .select('*, sub_group_members(*, participants!participant_id(*))')
          .eq('trip_id', tripId)
          .order('created_at', ascending: true);

      final subGroups = (sgData as List)
          .map((json) => SubGroup.fromJson(json as Map<String, dynamic>))
          .toList();

      await CacheService.cacheSubGroups(tripId, subGroups);
      repo.notifyChange('sub_groups', tripId);
    } catch (e) {
      debugPrint('Error pulling sub-groups: $e');
    }
  }

  /// Pull activity logs from Supabase and cache locally
  static Future<void> _pullActivityLogs(
    String tripId,
    OfflineRepository repo,
  ) async {
    try {
      final data = await _client
          .from('trip_activity_logs')
          .select('*')
          .eq('trip_id', tripId)
          .order('created_at', ascending: false)
          .limit(50);

      final logs =
          (data as List).map((json) => ActivityLog.fromJson(json)).toList();
      await CacheService.cacheActivityLogs(tripId, logs);
      repo.notifyChange('activity_logs', tripId);
    } catch (e) {
      debugPrint('Error pulling activity logs: $e');
    }
  }

  /// Pull expense categories from Supabase and cache locally
  static Future<void> _pullCategories(
    String tripId,
    OfflineRepository repo,
  ) async {
    try {
      final data = await _client
          .from('expense_categories')
          .select('*')
          .eq('trip_id', tripId);

      final categories = (data as List)
          .map((json) => ExpenseCategory.fromJson(json as Map<String, dynamic>))
          .toList();
      await CacheService.cacheCategories(tripId, categories);
      repo.notifyChange('categories', tripId);
    } catch (e) {
      debugPrint('Error pulling categories: $e');
    }
  }
}

/// Result of a sync operation
class SyncResult {
  final int syncedCount;
  final int failedCount;
  final List<String> errors;

  SyncResult({
    required this.syncedCount,
    required this.failedCount,
    required this.errors,
  });

  bool get isSuccess => failedCount == 0;
  bool get hasChanges => syncedCount > 0 || failedCount > 0;
}
