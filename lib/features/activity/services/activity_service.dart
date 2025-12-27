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

        final profiles = await SupabaseConfig.client
            .from('profiles')
            .select('id, display_name, avatar_url')
            .inFilter('id', actorIds);

        final profileMap = {for (var p in (profiles as List)) p['id']: p};

        return data.map((json) {
          final actorId = json['actor_id'];
          if (actorId != null && profileMap.containsKey(actorId)) {
            json['actor'] = profileMap[actorId];
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
          .select('*, actor:profiles!actor_id(display_name, avatar_url)')
          .eq('trip_id', tripId)
          .order('created_at', ascending: false)
          .range(offset, offset + limit - 1);

      return (data as List).map((json) => ActivityLog.fromJson(json)).toList();
    } catch (e) {
      return [];
    }
  }
}
