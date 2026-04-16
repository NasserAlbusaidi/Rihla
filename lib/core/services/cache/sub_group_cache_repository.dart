// Conflict strategy: ConflictAlgorithm.replace (upsert by PK).
//
// [cacheSubGroups] deletes sub_group_members before sub_groups to honour the
// FK constraint (sub_group_members.sub_group_id references sub_groups.id),
// then batch-inserts the fresh snapshot including nested members.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sqflite/sqflite.dart';

import '../../../features/logistics/models/sub_group_model.dart';
import '../local_database.dart';

/// Riverpod provider for [SubGroupCacheRepository].
final subGroupCacheRepositoryProvider = Provider<SubGroupCacheRepository>(
  (ref) => SubGroupCacheRepository(),
);

/// SQLite cache repository for [SubGroup] (and nested [SubGroupMember]) records.
///
/// Owned tables: `sub_groups`, `sub_group_members` (schema version 6).
class SubGroupCacheRepository {
  /// Persist [subGroups] (with their members) for [tripId].
  ///
  /// Deletes sub_group_members first (FK order), then sub_groups, then
  /// batch-inserts fresh groups and members.
  Future<void> cacheSubGroups(
    String tripId,
    List<SubGroup> subGroups,
  ) async {
    final db = await LocalDatabase.database;
    await db.execute(
      'DELETE FROM sub_group_members WHERE sub_group_id IN '
      '(SELECT id FROM sub_groups WHERE trip_id = ?)',
      [tripId],
    );
    await db.delete('sub_groups', where: 'trip_id = ?', whereArgs: [tripId]);
    if (subGroups.isEmpty) return;
    final syncedAt = DateTime.now().toIso8601String();
    final batch = db.batch();
    for (final sg in subGroups) {
      batch.insert(
        'sub_groups',
        {
          'id': sg.id,
          'trip_id': sg.tripId,
          'name': sg.name,
          'type': sg.type.value,
          'capacity': sg.capacity,
          'created_at': sg.createdAt?.toIso8601String(),
          'last_synced_at': syncedAt,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      for (final m in sg.members) {
        batch.insert(
          'sub_group_members',
          {
            'id': m.id,
            'sub_group_id': m.subGroupId,
            'participant_id': m.participantId,
            'display_name': m.displayName,
            'avatar_url': m.avatarUrl,
            'joined_at': m.joinedAt?.toIso8601String(),
            'last_synced_at': syncedAt,
          },
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
    }
    await batch.commit(noResult: true);
  }

  /// Read all cached sub-groups (with members) for [tripId].
  Future<List<SubGroup>> getCachedSubGroups(String tripId) async {
    final db = await LocalDatabase.database;
    final sgMaps = await db.query(
      'sub_groups',
      where: 'trip_id = ?',
      whereArgs: [tripId],
      orderBy: 'created_at ASC',
    );
    if (sgMaps.isEmpty) return [];

    final allMemberMaps = await db.rawQuery(
      'SELECT sgm.* FROM sub_group_members sgm '
      'INNER JOIN sub_groups sg ON sgm.sub_group_id = sg.id '
      'WHERE sg.trip_id = ?',
      [tripId],
    );

    final membersByGroup = <String, List<SubGroupMember>>{};
    for (final m in allMemberMaps) {
      final groupId = m['sub_group_id'] as String;
      membersByGroup.putIfAbsent(groupId, () => []).add(SubGroupMember(
        id: m['id'] as String,
        subGroupId: groupId,
        participantId: m['participant_id'] as String,
        displayName: m['display_name'] as String?,
        avatarUrl: m['avatar_url'] as String?,
        joinedAt: m['joined_at'] != null
            ? DateTime.parse(m['joined_at'] as String)
            : null,
      ));
    }

    return sgMaps.map((sgMap) {
      final sgId = sgMap['id'] as String;
      return SubGroup(
        id: sgId,
        tripId: sgMap['trip_id'] as String,
        name: sgMap['name'] as String,
        type: SubGroupType.fromValue(sgMap['type'] as String? ?? 'CAR'),
        capacity: sgMap['capacity'] as int? ?? 4,
        createdAt: sgMap['created_at'] != null
            ? DateTime.parse(sgMap['created_at'] as String)
            : null,
        members: membersByGroup[sgId] ?? [],
      );
    }).toList();
  }
}
