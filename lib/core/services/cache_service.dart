import 'dart:convert';
import 'package:decimal/decimal.dart';
import 'package:sqflite/sqflite.dart';

import '../../features/trip/models/trip_model.dart';
import '../../features/ledger/models/expense_model.dart';
import '../../features/ledger/models/settlement_model.dart';
import 'local_database.dart';

/// Cache service for offline data management
class CacheService {
  /// Cache a trip locally
  static Future<void> cacheTrip(Trip trip) async {
    final db = await LocalDatabase.database;
    await db.insert('trips', {
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
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  /// Get cached trips
  static Future<List<Trip>> getCachedTrips() async {
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

  /// Cache expenses for a trip
  static Future<void> cacheExpenses(
    String tripId,
    List<Expense> expenses,
  ) async {
    final db = await LocalDatabase.database;
    final batch = db.batch();

    for (final expense in expenses) {
      batch.insert('expenses', {
        'id': expense.id,
        'trip_id': expense.tripId,
        'payer_participant_id': expense.payerParticipantId,
        'amount': expense.amount.toString(),
        'description': expense.description,
        'category_id': expense.categoryId,
        'category_name': expense.categoryName,
        'scope': expense.scope.value,
        'sub_group_id': expense.subGroupId,
        'created_at': expense.createdAt.toIso8601String(),
        'synced_at': DateTime.now().toIso8601String(),
        'is_deleted': expense.isDeleted ? 1 : 0,
        'deleted_at': expense.deletedAt?.toIso8601String(),
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    }

    await batch.commit(noResult: true);
  }

  /// Get cached expenses for a trip
  static Future<List<Expense>> getCachedExpenses(String tripId) async {
    final db = await LocalDatabase.database;
    final maps = await db.query(
      'expenses',
      where: 'trip_id = ? AND is_deleted = 0',
      whereArgs: [tripId],
      orderBy: 'created_at DESC',
    );

    return maps.map((map) {
      return Expense(
        id: map['id'] as String,
        tripId: map['trip_id'] as String,
        payerParticipantId:
            map['payer_participant_id'] as String? ?? map['payer_id'] as String,
        amount: Decimal.parse(map['amount'] as String),
        description: map['description'] as String?,
        categoryId: map['category_id'] as String?,
        categoryName: map['category_name'] as String?,
        scope: ExpenseScope.values.firstWhere(
          (s) => s.value == map['scope'],
          orElse: () => ExpenseScope.global,
        ),
        subGroupId: map['sub_group_id'] as String?,
        createdAt: DateTime.parse(map['created_at'] as String),
        isDeleted: (map['is_deleted'] as int?) == 1,
        deletedAt: map['deleted_at'] != null
            ? DateTime.parse(map['deleted_at'] as String)
            : null,
      );
    }).toList();
  }

  /// Cache settlements for a trip
  static Future<void> cacheSettlements(
    String tripId,
    List<Settlement> settlements,
  ) async {
    final db = await LocalDatabase.database;
    final batch = db.batch();

    for (final s in settlements) {
      batch.insert('settlements', {
        'id': s.id,
        'trip_id': s.tripId,
        'payer_participant_id': s.payerParticipantId,
        'recipient_participant_id': s.recipientParticipantId,
        'amount': s.amount.toString(),
        'note': s.note,
        'created_at': s.settledAt.toIso8601String(),
        'synced_at': DateTime.now().toIso8601String(),
        'is_deleted': s.isDeleted ? 1 : 0,
        'deleted_at': s.deletedAt?.toIso8601String(),
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    }

    await batch.commit(noResult: true);
  }

  /// Get cached settlements for a trip
  static Future<List<Settlement>> getCachedSettlements(String tripId) async {
    final db = await LocalDatabase.database;
    final maps = await db.query(
      'settlements',
      where: 'trip_id = ? AND is_deleted = 0',
      whereArgs: [tripId],
      orderBy: 'created_at DESC',
    );

    return maps.map((map) {
      return Settlement(
        id: map['id'] as String,
        tripId: map['trip_id'] as String,
        payerParticipantId: map['payer_participant_id'] as String?,
        recipientParticipantId: map['recipient_participant_id'] as String?,
        amount: double.parse(map['amount'] as String),
        note: map['note'] as String?,
        settledAt: DateTime.parse(map['created_at'] as String),
        isDeleted: (map['is_deleted'] as int?) == 1,
        deletedAt: map['deleted_at'] != null
            ? DateTime.parse(map['deleted_at'] as String)
            : null,
      );
    }).toList();
  }

  /// Add item to sync queue for later upload
  static Future<void> addToSyncQueue({
    required String tableName,
    required String recordId,
    required SyncAction action,
    required Map<String, dynamic> data,
  }) async {
    final db = await LocalDatabase.database;
    await db.insert('sync_queue', {
      'table_name': tableName,
      'record_id': recordId,
      'action': action.value,
      'data': jsonEncode(data),
      'created_at': DateTime.now().toIso8601String(),
    });
  }

  /// Get pending sync items
  static Future<List<Map<String, dynamic>>> getPendingSyncItems() async {
    final db = await LocalDatabase.database;
    return await db.query('sync_queue', orderBy: 'created_at ASC', limit: 50);
  }

  /// Remove item from sync queue
  static Future<void> removeSyncItem(int id) async {
    final db = await LocalDatabase.database;
    await db.delete('sync_queue', where: 'id = ?', whereArgs: [id]);
  }

  /// Check if there are pending sync items
  static Future<bool> hasPendingSync() async {
    final db = await LocalDatabase.database;
    final result = await db.rawQuery(
      'SELECT COUNT(*) as count FROM sync_queue',
    );
    return (result.first['count'] as int) > 0;
  }

  /// Get sync queue count
  static Future<int> getSyncQueueCount() async {
    final db = await LocalDatabase.database;
    final result = await db.rawQuery(
      'SELECT COUNT(*) as count FROM sync_queue',
    );
    return result.first['count'] as int;
  }
}
