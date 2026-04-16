// Conflict strategy: ConflictAlgorithm.replace (upsert by PK).
//
// [cacheGearItems] uses delete-all-for-trip + batch-insert (same table-level
// refresh as expense/settlement) because gear lists are synced as complete
// snapshots from Firestore. [cacheSingleGearItem] does a plain upsert —
// used by GearService.addItem to avoid wiping prior items during sequential
// preset seeding.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sqflite/sqflite.dart';

import '../../../features/gear/models/gear_item_model.dart';
import '../local_database.dart';

/// Riverpod provider for [GearCacheRepository].
final gearCacheRepositoryProvider = Provider<GearCacheRepository>(
  (ref) => GearCacheRepository(),
);

/// SQLite cache repository for [GearItem] records.
///
/// Owned table: `gear_items` (schema version 6, column `trip_id`).
class GearCacheRepository {
  /// Persist [items] for [tripId], replacing the entire snapshot for that trip.
  ///
  /// Deletes all existing rows for the trip first, then batch-inserts the
  /// fresh set. This mirrors the pattern used for expenses/settlements to
  /// prevent stale entries after server-side deletes.
  Future<void> cacheGearItems(String tripId, List<GearItem> items) async {
    final db = await LocalDatabase.database;
    await db.delete('gear_items', where: 'trip_id = ?', whereArgs: [tripId]);
    if (items.isEmpty) return;
    final syncedAt = DateTime.now().toIso8601String();
    final batch = db.batch();
    for (final item in items) {
      batch.insert(
        'gear_items',
        {
          'id': item.id,
          'trip_id': item.tripId,
          'item_name': item.itemName,
          'assigned_to': item.assignedTo,
          'is_packed': item.isPacked ? 1 : 0,
          'sequence_id': item.sequenceId,
          'is_high_priority': item.isHighPriority ? 1 : 0,
          'assigned_to_name': item.assignedToName,
          'assigned_to_avatar': item.assignedToAvatar,
          'created_at': item.createdAt?.toIso8601String(),
          'synced_at': syncedAt,
          'is_deleted': item.isDeleted ? 1 : 0,
          'deleted_at': item.deletedAt?.toIso8601String(),
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    await batch.commit(noResult: true);
  }

  /// Persist a single [item] without deleting existing items for the trip.
  ///
  /// Used by [GearService.addItem] to avoid wiping prior items when called
  /// sequentially (e.g. camping preset seeding).
  Future<void> cacheSingleGearItem(GearItem item) async {
    final db = await LocalDatabase.database;
    await db.insert(
      'gear_items',
      {
        'id': item.id,
        'trip_id': item.tripId,
        'item_name': item.itemName,
        'assigned_to': item.assignedTo,
        'is_packed': item.isPacked ? 1 : 0,
        'sequence_id': item.sequenceId,
        'is_high_priority': item.isHighPriority ? 1 : 0,
        'assigned_to_name': item.assignedToName,
        'assigned_to_avatar': item.assignedToAvatar,
        'created_at': item.createdAt?.toIso8601String(),
        'synced_at': DateTime.now().toIso8601String(),
        'is_deleted': item.isDeleted ? 1 : 0,
        'deleted_at': item.deletedAt?.toIso8601String(),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// Read non-deleted gear items for [tripId], ordered by sequence.
  Future<List<GearItem>> getCachedGearItems(String tripId) async {
    final db = await LocalDatabase.database;
    final maps = await db.query(
      'gear_items',
      where: 'trip_id = ? AND is_deleted = 0',
      whereArgs: [tripId],
      orderBy: 'sequence_id ASC',
    );
    return maps
        .map(
          (map) => GearItem(
            id: map['id'] as String,
            tripId: map['trip_id'] as String,
            itemName: map['item_name'] as String,
            assignedTo: map['assigned_to'] as String?,
            isPacked: (map['is_packed'] as int?) == 1,
            sequenceId: map['sequence_id'] as int? ?? 0,
            isHighPriority: (map['is_high_priority'] as int?) == 1,
            assignedToName: map['assigned_to_name'] as String?,
            assignedToAvatar: map['assigned_to_avatar'] as String?,
            createdAt: map['created_at'] != null
                ? DateTime.parse(map['created_at'] as String)
                : null,
            isDeleted: (map['is_deleted'] as int?) == 1,
            deletedAt: map['deleted_at'] != null
                ? DateTime.parse(map['deleted_at'] as String)
                : null,
          ),
        )
        .toList();
  }
}
