import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/config/supabase_config.dart';
import '../../../core/services/offline_repository.dart';
import '../models/activity_log_model.dart';

final activityServiceProvider = Provider<ActivityService>((ref) {
  return ActivityService();
});

/// Stream of activity logs — reads from SQLite
final tripActivityProvider = StreamProvider.family<List<ActivityLog>, String>((
  ref,
  tripId,
) {
  return ref.read(offlineRepositoryProvider).watchActivityLogs(tripId);
});

/// Transaction-only activity logs (filtered from cached data)
final tripTransactionActivityProvider =
    StreamProvider.family<List<ActivityLog>, String>((ref, tripId) {
  return ref.read(offlineRepositoryProvider).watchActivityLogs(tripId).map(
    (logs) => logs.where((log) => log.category == 'MONEY').toList(),
  );
});

class ActivityService {
  SupabaseClient get _client => SupabaseConfig.client;

  /// Fetch older logs for pagination
  Future<List<ActivityLog>> getLogs(
    String tripId, {
    int limit = 20,
    int offset = 0,
  }) async {
    try {
      final data = await _client
          .from('trip_activity_logs')
          .select('*')
          .eq('trip_id', tripId)
          .order('created_at', ascending: false)
          .range(offset, offset + limit - 1);

      return (data as List).map((json) => ActivityLog.fromJson(json)).toList();
    } catch (e) {
      return [];
    }
  }
}
