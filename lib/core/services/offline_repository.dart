import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import '../../features/activity/models/activity_log_model.dart';
import '../../features/gear/models/gear_item_model.dart';
import '../../features/ledger/models/expense_category_model.dart';
import '../../features/ledger/models/expense_model.dart';
import '../../features/ledger/models/settlement_model.dart';
import '../../features/logistics/models/sub_group_model.dart';
import '../../features/trip/models/trip_model.dart';
import 'cache_service.dart';
import 'local_database.dart';

/// Riverpod provider for OfflineRepository
final offlineRepositoryProvider = Provider<OfflineRepository>((ref) {
  final repo = OfflineRepository();
  ref.onDispose(() => repo.dispose());
  return repo;
});

/// Reactive SQLite wrapper for offline-first data access.
///
/// Provides:
/// - watch*() methods: reactive streams from SQLite (providers use these)
/// - save*()/delete*() methods: write to SQLite + sync queue (services use these)
/// - notify(): trigger stream re-emission after external writes (sync engine uses this)
class OfflineRepository {
  final Map<String, StreamController<void>> _changeNotifiers = {};
  static const _uuid = Uuid();

  StreamController<void> _getNotifier(String key) {
    return _changeNotifiers.putIfAbsent(
      key,
      () => StreamController<void>.broadcast(),
    );
  }

  /// Notify that data changed for a table+tripId combination.
  /// Called after writes or after sync engine downloads new data.
  void notifyChange(String table, [String? tripId]) {
    final key = tripId != null ? '$table:$tripId' : table;
    if (_changeNotifiers.containsKey(key)) {
      _changeNotifiers[key]!.add(null);
    }
    // Also notify the table-level key for global listeners (e.g., trips list)
    if (tripId != null && _changeNotifiers.containsKey(table)) {
      _changeNotifiers[table]!.add(null);
    }
  }

  void dispose() {
    for (final controller in _changeNotifiers.values) {
      controller.close();
    }
    _changeNotifiers.clear();
  }

  // -- TRIPS ----------------------------------------------------------------

  Stream<List<Trip>> watchTrips() async* {
    yield await CacheService.getCachedTrips();
    yield* _getNotifier('trips').stream
        .asyncMap((_) => CacheService.getCachedTrips());
  }

  // -- EXPENSES -------------------------------------------------------------

  Stream<List<Expense>> watchExpenses(String tripId) async* {
    yield await CacheService.getCachedExpenses(tripId);
    yield* _getNotifier('expenses:$tripId').stream
        .asyncMap((_) => CacheService.getCachedExpenses(tripId));
  }

  Future<void> saveExpense(Expense expense) async {
    final db = await LocalDatabase.database;
    await db.insert(
      'expenses',
      {
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
        'synced_at': null,
        'is_deleted': expense.isDeleted ? 1 : 0,
        'deleted_at': expense.deletedAt?.toIso8601String(),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );

    await CacheService.addToSyncQueue(
      tableName: 'expenses',
      recordId: expense.id,
      action: SyncAction.create,
      data: expense.toJson(),
    );
    notifyChange('expenses', expense.tripId);
  }

  Future<void> updateExpense(
    Expense expense,
    Map<String, dynamic> updates,
  ) async {
    final db = await LocalDatabase.database;
    final localUpdates = Map<String, dynamic>.from(updates);
    localUpdates['synced_at'] = null;

    await db.update(
      'expenses',
      localUpdates,
      where: 'id = ?',
      whereArgs: [expense.id],
    );

    await CacheService.addToSyncQueue(
      tableName: 'expenses',
      recordId: expense.id,
      action: SyncAction.update,
      data: Map<String, dynamic>.from(updates),
    );
    notifyChange('expenses', expense.tripId);
  }

  Future<void> deleteExpense(String expenseId, String tripId) async {
    final db = await LocalDatabase.database;
    await db.update(
      'expenses',
      {
        'is_deleted': 1,
        'deleted_at': DateTime.now().toIso8601String(),
        'synced_at': null,
      },
      where: 'id = ?',
      whereArgs: [expenseId],
    );

    await CacheService.addToSyncQueue(
      tableName: 'expenses',
      recordId: expenseId,
      action: SyncAction.delete,
      data: {'id': expenseId},
    );
    notifyChange('expenses', tripId);
  }

  // -- SETTLEMENTS ----------------------------------------------------------

  Stream<List<Settlement>> watchSettlements(String tripId) async* {
    yield await CacheService.getCachedSettlements(tripId);
    yield* _getNotifier('settlements:$tripId').stream
        .asyncMap((_) => CacheService.getCachedSettlements(tripId));
  }

  Future<void> saveSettlement(Settlement settlement) async {
    final db = await LocalDatabase.database;
    await db.insert(
      'settlements',
      {
        'id': settlement.id,
        'trip_id': settlement.tripId,
        'payer_participant_id': settlement.payerParticipantId,
        'recipient_participant_id': settlement.recipientParticipantId,
        'amount': settlement.amount.toString(),
        'note': settlement.note,
        'created_at': settlement.settledAt.toIso8601String(),
        'synced_at': null,
        'is_deleted': settlement.isDeleted ? 1 : 0,
        'deleted_at': settlement.deletedAt?.toIso8601String(),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );

    await CacheService.addToSyncQueue(
      tableName: 'settlements',
      recordId: settlement.id,
      action: SyncAction.create,
      data: settlement.toJson(),
    );
    notifyChange('settlements', settlement.tripId);
  }

  Future<void> deleteSettlement(String settlementId, String tripId) async {
    final db = await LocalDatabase.database;
    await db.update(
      'settlements',
      {
        'is_deleted': 1,
        'deleted_at': DateTime.now().toIso8601String(),
        'synced_at': null,
      },
      where: 'id = ?',
      whereArgs: [settlementId],
    );

    await CacheService.addToSyncQueue(
      tableName: 'settlements',
      recordId: settlementId,
      action: SyncAction.delete,
      data: {'id': settlementId},
    );
    notifyChange('settlements', tripId);
  }

  // -- GEAR ITEMS -----------------------------------------------------------

  Stream<List<GearItem>> watchGearItems(String tripId) async* {
    yield await CacheService.getCachedGearItems(tripId);
    yield* _getNotifier('gear_items:$tripId').stream
        .asyncMap((_) => CacheService.getCachedGearItems(tripId));
  }

  Future<void> saveGearItem(GearItem item) async {
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
        'synced_at': null,
        'is_deleted': 0,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );

    await CacheService.addToSyncQueue(
      tableName: 'gear_items',
      recordId: item.id,
      action: SyncAction.create,
      data: item.toJson(),
    );
    notifyChange('gear_items', item.tripId);
  }

  Future<void> updateGearItem(
    String itemId,
    String tripId,
    Map<String, dynamic> updates,
  ) async {
    final db = await LocalDatabase.database;
    final safeCopy = Map<String, dynamic>.from(updates);
    safeCopy['synced_at'] = null;
    await db.update(
      'gear_items',
      safeCopy,
      where: 'id = ?',
      whereArgs: [itemId],
    );

    // Convert SQLite integers back to booleans for Supabase sync
    final syncData = Map<String, dynamic>.from(updates);
    for (final key in ['is_packed', 'is_high_priority', 'is_deleted']) {
      if (syncData.containsKey(key) && syncData[key] is int) {
        syncData[key] = syncData[key] == 1;
      }
    }

    await CacheService.addToSyncQueue(
      tableName: 'gear_items',
      recordId: itemId,
      action: SyncAction.update,
      data: syncData,
    );
    notifyChange('gear_items', tripId);
  }

  Future<void> deleteGearItem(String itemId, String tripId) async {
    final db = await LocalDatabase.database;
    await db.update(
      'gear_items',
      {
        'is_deleted': 1,
        'deleted_at': DateTime.now().toIso8601String(),
        'synced_at': null,
      },
      where: 'id = ?',
      whereArgs: [itemId],
    );

    await CacheService.addToSyncQueue(
      tableName: 'gear_items',
      recordId: itemId,
      action: SyncAction.delete,
      data: {'id': itemId},
    );
    notifyChange('gear_items', tripId);
  }

  // -- PARTICIPANTS ---------------------------------------------------------

  Stream<List<Participant>> watchParticipants(String tripId) async* {
    yield await CacheService.getCachedParticipants(tripId);
    yield* _getNotifier('participants:$tripId').stream
        .asyncMap((_) => CacheService.getCachedParticipants(tripId));
  }

  // -- SUB-GROUPS -----------------------------------------------------------

  Stream<List<SubGroup>> watchSubGroups(String tripId) async* {
    yield await CacheService.getCachedSubGroups(tripId);
    yield* _getNotifier('sub_groups:$tripId').stream
        .asyncMap((_) => CacheService.getCachedSubGroups(tripId));
  }

  // -- ACTIVITY LOGS --------------------------------------------------------

  Stream<List<ActivityLog>> watchActivityLogs(String tripId) async* {
    yield await CacheService.getCachedActivityLogs(tripId);
    yield* _getNotifier('activity_logs:$tripId').stream
        .asyncMap((_) => CacheService.getCachedActivityLogs(tripId));
  }

  // -- CATEGORIES -----------------------------------------------------------

  Stream<List<ExpenseCategory>> watchCategories(String tripId) async* {
    yield await CacheService.getCachedCategories(tripId);
    yield* _getNotifier('categories:$tripId').stream
        .asyncMap((_) => CacheService.getCachedCategories(tripId));
  }

  // -- HELPERS --------------------------------------------------------------

  /// Generate a UUID for new records created offline
  String generateId() => _uuid.v4();
}
