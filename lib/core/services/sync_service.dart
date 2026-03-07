import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../features/trip/models/trip_model.dart';
import '../../features/ledger/models/expense_model.dart';
import '../../features/ledger/models/settlement_model.dart';
import '../config/supabase_config.dart';
import 'cache_service.dart';

/// Sync service handles synchronizing local cache with Supabase
class SyncService {
  static SupabaseClient get _client => SupabaseConfig.client;

  /// Sync all pending changes to Supabase
  static Future<SyncResult> syncPendingChanges() async {
    int synced = 0;
    int failed = 0;
    final List<String> errors = [];

    try {
      final pendingItems = await CacheService.getPendingSyncItems();

      for (final item in pendingItems) {
        try {
          final tableName = item['table_name'] as String;
          final recordId = item['record_id'] as String;
          final action = item['action'] as String;
          final data =
              jsonDecode(item['data'] as String) as Map<String, dynamic>;
          final id = item['id'] as int;

          bool success = false;

          switch (action) {
            case 'CREATE':
              await _client.from(tableName).insert(data);
              success = true;
              break;
            case 'UPDATE':
              await _client.from(tableName).update(data).eq('id', recordId);
              success = true;
              break;
            case 'DELETE':
              // Soft delete on the server
              await _client
                  .from(tableName)
                  .update({
                    'is_deleted': true,
                    'deleted_at': DateTime.now().toIso8601String(),
                  })
                  .eq('id', recordId);
              success = true;
              break;
          }

          if (success) {
            await CacheService.removeSyncItem(id);
            synced++;
          }
        } catch (e) {
          failed++;
          errors.add(e.toString());
          debugPrint('Sync error: $e');
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
  static Future<SyncResult> fullSync(String userId) async {
    // First upload any pending changes
    final uploadResult = await syncPendingChanges();

    // Then download fresh data
    await downloadTrips(userId);

    return uploadResult;
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
