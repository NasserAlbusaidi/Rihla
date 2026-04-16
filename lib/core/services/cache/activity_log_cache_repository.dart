// Conflict strategy: ConflictAlgorithm.replace (upsert by PK).
//
// [cacheActivityLogs] deletes all rows for the trip first, then batch-inserts
// the fresh snapshot. Logs are capped at 50 on read for performance.
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sqflite/sqflite.dart';

import '../../../features/activity/models/activity_log_model.dart';
import '../local_database.dart';

/// Riverpod provider for [ActivityLogCacheRepository].
final activityLogCacheRepositoryProvider =
    Provider<ActivityLogCacheRepository>(
  (ref) => ActivityLogCacheRepository(),
);

/// SQLite cache repository for [ActivityLog] records.
///
/// Owned table: `activity_logs` (schema version 6, column `trip_id`).
class ActivityLogCacheRepository {
  /// Persist [logs] for [tripId], replacing the entire snapshot.
  Future<void> cacheActivityLogs(
    String tripId,
    List<ActivityLog> logs,
  ) async {
    final db = await LocalDatabase.database;
    await db.delete('activity_logs', where: 'trip_id = ?', whereArgs: [tripId]);
    if (logs.isEmpty) return;
    final syncedAt = DateTime.now().toIso8601String();
    final batch = db.batch();
    for (final log in logs) {
      batch.insert(
        'activity_logs',
        {
          'id': log.id,
          'trip_id': log.tripId,
          'actor_id': log.actorId,
          'target_participant_id': log.targetParticipantId,
          'category': log.category,
          'event_type': log.eventType,
          'log_text': log.logText,
          'metadata': jsonEncode(log.metadata),
          'actor_name': log.actorName,
          'actor_avatar': log.actorAvatar,
          'created_at': log.createdAt.toIso8601String(),
          'last_synced_at': syncedAt,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    await batch.commit(noResult: true);
  }

  /// Read cached activity logs for [tripId], newest first, capped at 50.
  Future<List<ActivityLog>> getCachedActivityLogs(String tripId) async {
    final db = await LocalDatabase.database;
    final maps = await db.query(
      'activity_logs',
      where: 'trip_id = ?',
      whereArgs: [tripId],
      orderBy: 'created_at DESC',
      limit: 50,
    );
    return maps
        .map(
          (map) => ActivityLog(
            id: map['id'] as String,
            tripId: map['trip_id'] as String,
            actorId: map['actor_id'] as String?,
            targetParticipantId: map['target_participant_id'] as String?,
            category: map['category'] as String,
            eventType: map['event_type'] as String,
            logText: map['log_text'] as String,
            metadata: map['metadata'] != null
                ? jsonDecode(map['metadata'] as String) as Map<String, dynamic>
                : {},
            actorName: map['actor_name'] as String?,
            actorAvatar: map['actor_avatar'] as String?,
            createdAt: DateTime.parse(map['created_at'] as String),
          ),
        )
        .toList();
  }
}
