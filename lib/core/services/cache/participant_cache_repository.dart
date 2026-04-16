// Conflict strategy: ConflictAlgorithm.replace (upsert by PK).
//
// [cacheParticipants] deletes all rows for the trip first, then batch-inserts
// the fresh snapshot — consistent with the overall cache refresh pattern.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sqflite/sqflite.dart';

import '../../../features/trip/models/trip_model.dart';
import '../local_database.dart';

/// Riverpod provider for [ParticipantCacheRepository].
final participantCacheRepositoryProvider = Provider<ParticipantCacheRepository>(
  (ref) => ParticipantCacheRepository(),
);

/// SQLite cache repository for [Participant] records.
///
/// Owned table: `participants` (schema version 6, column `trip_id`).
class ParticipantCacheRepository {
  /// Persist [participants] for [tripId], replacing the entire snapshot.
  ///
  /// Deletes existing rows for the trip first, then batch-inserts.
  Future<void> cacheParticipants(
    String tripId,
    List<Participant> participants,
  ) async {
    final db = await LocalDatabase.database;
    await db.delete('participants', where: 'trip_id = ?', whereArgs: [tripId]);
    if (participants.isEmpty) return;
    final syncedAt = DateTime.now().toIso8601String();
    final batch = db.batch();
    for (final p in participants) {
      batch.insert(
        'participants',
        {
          'id': p.id,
          'trip_id': p.tripId,
          'user_id': p.userId,
          'role': p.role.value,
          'display_name': p.displayName,
          'avatar_url': p.avatarUrl,
          'is_shadow': p.isShadow ? 1 : 0,
          'joined_at': p.joinedAt.toIso8601String(),
          'last_synced_at': syncedAt,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    await batch.commit(noResult: true);
  }

  /// Read all cached participants for [tripId].
  Future<List<Participant>> getCachedParticipants(String tripId) async {
    final db = await LocalDatabase.database;
    final maps = await db.query(
      'participants',
      where: 'trip_id = ?',
      whereArgs: [tripId],
    );
    return maps
        .map(
          (map) => Participant(
            id: map['id'] as String,
            tripId: map['trip_id'] as String,
            userId: map['user_id'] as String?,
            role: ParticipantRole.fromString(
              map['role'] as String? ?? 'MEMBER',
            ),
            displayName: map['display_name'] as String?,
            avatarUrl: map['avatar_url'] as String?,
            isShadow: (map['is_shadow'] as int?) == 1,
            joinedAt: map['joined_at'] != null &&
                    (map['joined_at'] as String).isNotEmpty
                ? DateTime.parse(map['joined_at'] as String)
                : DateTime.now(),
          ),
        )
        .toList();
  }
}
