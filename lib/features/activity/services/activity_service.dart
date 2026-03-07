import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/config/supabase_config.dart';
import '../models/activity_log_model.dart';

final activityServiceProvider = Provider<ActivityService>((ref) {
  return ActivityService();
});

/// Stream of activity logs for a trip
final tripActivityProvider = StreamProvider.family<List<ActivityLog>, String>((
  ref,
  tripId,
) {
  return SupabaseConfig.client
      .from('trip_activity_logs')
      .stream(primaryKey: ['id'])
      .eq('trip_id', tripId)
      .order('created_at', ascending: false)
      .limit(50)
      .asyncMap((data) async {
        if (data.isEmpty) return <ActivityLog>[];

        // Optimized: Fetch unique actor profiles involved in this batch
        final actorIds = data
            .map((e) => e['actor_id'] as String?)
            .where((id) => id != null)
            .toSet()
            .toList();

        if (actorIds.isEmpty) {
          return data.map((json) => ActivityLog.fromJson(json)).toList();
        }

        final participants = await SupabaseConfig.client
            .from('participants')
            .select('user_id, display_name')
            .eq('trip_id', tripId)
            .inFilter('user_id', actorIds);

        final participantMap = {for (var p in (participants as List)) p['user_id']: p};

        return data.map((json) {
          final actorId = json['actor_id'];
          if (actorId != null && participantMap.containsKey(actorId)) {
            json['actor'] = participantMap[actorId];
          }
          return ActivityLog.fromJson(json);
        }).toList();
      });
});

/// Stream of transaction-only activity logs for a trip (expenses & settlements)
final tripTransactionActivityProvider =
    StreamProvider.family<List<ActivityLog>, String>((ref, tripId) {
      return SupabaseConfig.client
          .from('trip_activity_logs')
          .stream(primaryKey: ['id'])
          .eq('trip_id', tripId)
          .order('created_at', ascending: false)
          .limit(50)
          .asyncMap((data) async {
            // Filter to only MONEY category (expenses & settlements)
            final filteredData = data
                .where((e) => e['category'] == 'MONEY')
                .toList();

            if (filteredData.isEmpty) return <ActivityLog>[];

            final actorIds = filteredData
                .map((e) => e['actor_id'] as String?)
                .where((id) => id != null)
                .toSet()
                .toList();

            if (actorIds.isEmpty) {
              return filteredData
                  .map((json) => ActivityLog.fromJson(json))
                  .toList();
            }

            final participants = await SupabaseConfig.client
                .from('participants')
                .select('user_id, display_name')
                .eq('trip_id', tripId)
                .inFilter('user_id', actorIds);

            final participantMap = {for (var p in (participants as List)) p['user_id']: p};

            return filteredData.map((json) {
              final actorId = json['actor_id'];
              if (actorId != null && participantMap.containsKey(actorId)) {
                json['actor'] = participantMap[actorId];
              }
              return ActivityLog.fromJson(json);
            }).toList();
          });
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
