// Conflict strategy: ConflictAlgorithm.replace (upsert by PK) for writes.
//
// [deleteTrip] performs a cascading delete across 9 related tables inside a
// single SQLite transaction — preserving referential integrity regardless of
// whether ON DELETE CASCADE is enforced by the platform's SQLite build.
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sqflite/sqflite.dart';

import '../../../features/trip/models/trip_model.dart';
import '../local_database.dart';

/// Riverpod provider for [TripCacheRepository].
final tripCacheRepositoryProvider = Provider<TripCacheRepository>(
  (ref) => TripCacheRepository(),
);

/// SQLite cache repository for [Trip] records.
///
/// Owned table: `trips` (schema version 6).
/// Cascade delete also clears: expenses, settlements, gear_items, participants,
/// sub_group_members, sub_groups, activity_logs, categories.
class TripCacheRepository {
  /// Persist [trip] to SQLite (insert or replace by PK).
  Future<void> cacheTrip(Trip trip) async {
    final db = await LocalDatabase.database;
    await db.insert(
      'trips',
      {
        'id': trip.id,
        'name': trip.name,
        'invite_code': trip.inviteCode,
        'leader_id': trip.leaderId,
        'icon': trip.icon,
        'start_date': trip.startDate?.toIso8601String(),
        'end_date': trip.endDate?.toIso8601String(),
        'modules': jsonEncode(trip.modules.toJson()),
        'created_at': trip.createdAt.toIso8601String(),
        'updated_at': trip.updatedAt?.toIso8601String(),
        'synced_at': DateTime.now().toIso8601String(),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// Read all cached trips ordered by creation date (newest first).
  Future<List<Trip>> getCachedTrips() async {
    final db = await LocalDatabase.database;
    final maps = await db.query('trips', orderBy: 'created_at DESC');
    return maps.map((map) {
      return Trip(
        id: map['id'] as String,
        name: map['name'] as String,
        inviteCode: map['invite_code'] as String,
        leaderId: map['leader_id'] as String,
        icon: map['icon'] as String? ?? 'airplane',
        startDate: map['start_date'] != null
            ? DateTime.parse(map['start_date'] as String)
            : null,
        endDate: map['end_date'] != null
            ? DateTime.parse(map['end_date'] as String)
            : null,
        modules: TripModules.fromJson(
          map['modules'] != null
              ? jsonDecode(map['modules'] as String) as Map<String, dynamic>
              : {},
        ),
        createdAt: DateTime.parse(map['created_at'] as String),
        updatedAt: map['updated_at'] != null
            ? DateTime.parse(map['updated_at'] as String)
            : null,
      );
    }).toList();
  }

  /// Delete a trip and all its related data from local cache.
  ///
  /// Runs inside a single [db.transaction] — atomic across all 9 tables.
  /// Deletes sub_group_members before sub_groups to honour the FK constraint.
  Future<void> deleteTrip(String tripId) async {
    final db = await LocalDatabase.database;
    await db.transaction((txn) async {
      // Child tables with trip_id foreign key
      await txn.delete('activity_logs',
          where: 'trip_id = ?', whereArgs: [tripId]);
      await txn.delete('categories',
          where: 'trip_id = ?', whereArgs: [tripId]);
      await txn.delete('expenses',
          where: 'trip_id = ?', whereArgs: [tripId]);
      await txn.delete('settlements',
          where: 'trip_id = ?', whereArgs: [tripId]);
      await txn.delete('gear_items',
          where: 'trip_id = ?', whereArgs: [tripId]);
      await txn.delete('participants',
          where: 'trip_id = ?', whereArgs: [tripId]);
      // Sub-group members reference sub_groups — delete members first.
      final subGroups = await txn.query('sub_groups',
          columns: ['id'], where: 'trip_id = ?', whereArgs: [tripId]);
      for (final sg in subGroups) {
        await txn.delete('sub_group_members',
            where: 'sub_group_id = ?', whereArgs: [sg['id']]);
      }
      await txn.delete('sub_groups',
          where: 'trip_id = ?', whereArgs: [tripId]);
      await txn.delete('trips', where: 'id = ?', whereArgs: [tripId]);
    });
  }
}
