// Conflict strategy: ConflictAlgorithm.replace (upsert by PK).
//
// [deleteGroupCache] explicitly deletes group_members before the group row
// for safety, even though ON DELETE CASCADE is declared in the schema.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sqflite/sqflite.dart';

import '../../../features/groups/models/group_member_model.dart';
import '../../../features/groups/models/group_model.dart';
import '../local_database.dart';

/// Riverpod provider for [GroupCacheRepository].
final groupCacheRepositoryProvider = Provider<GroupCacheRepository>(
  (ref) => GroupCacheRepository(),
);

/// SQLite cache repository for [Group] and [GroupMember] records.
///
/// Owned tables: `groups`, `group_members` (schema version 6).
class GroupCacheRepository {
  /// Persist [group] to SQLite (insert or replace by PK).
  Future<void> cacheGroup(Group group) async {
    final db = await LocalDatabase.database;
    await db.insert(
      'groups',
      group.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// Read all cached groups ordered by creation date (newest first).
  Future<List<Group>> getCachedGroups() async {
    final db = await LocalDatabase.database;
    final maps = await db.query('groups', orderBy: 'created_at DESC');
    return maps.map(Group.fromMap).toList();
  }

  /// Persist a single [member] to SQLite (insert or replace by PK).
  Future<void> cacheGroupMember(GroupMember member) async {
    final db = await LocalDatabase.database;
    await db.insert(
      'group_members',
      member.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// Read all cached members for [groupId] ordered by join time (oldest first).
  Future<List<GroupMember>> getCachedGroupMembers(String groupId) async {
    final db = await LocalDatabase.database;
    final maps = await db.query(
      'group_members',
      where: 'group_id = ?',
      whereArgs: [groupId],
      orderBy: 'joined_at ASC',
    );
    return maps.map(GroupMember.fromMap).toList();
  }

  /// Delete a group and all its members from the local cache.
  ///
  /// Deletes members first (explicit, for future schema resilience), then the
  /// group row. The SQLite schema declares ON DELETE CASCADE but we delete
  /// explicitly here to be safe with any future schema changes.
  Future<void> deleteGroupCache(String groupId) async {
    final db = await LocalDatabase.database;
    await db.delete(
      'group_members',
      where: 'group_id = ?',
      whereArgs: [groupId],
    );
    await db.delete(
      'groups',
      where: 'id = ?',
      whereArgs: [groupId],
    );
  }
}
