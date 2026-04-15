import 'dart:async';

import 'package:decimal/decimal.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sqflite/sqflite.dart';

import '../../features/ledger/models/expense_model.dart';
import '../../features/ledger/models/settlement_model.dart';
import 'local_database.dart';

/// Riverpod provider for [BalanceCacheRepository].
final balanceCacheRepositoryProvider =
    Provider<BalanceCacheRepository>((ref) => BalanceCacheRepository());

/// Narrow SQLite wrapper that serves [BalanceCalculator] queries.
///
/// Responsibilities:
/// - [cacheExpenses]/[cacheSettlements]: side-write targets for the
///   [eventExpensesProvider] and [eventSettlementsProvider] asyncMap pipelines
///   (D-15). Data written here is keyed by `eventId` (same as Firestore eventId).
/// - [getExpenses]/[getSettlements]: synchronous-ish reads used by
///   [BalanceCalculator] and the legacy trip-scoped balance providers.
/// - [watchExpenses]/[watchSettlements]: deprecated stream interface retained
///   for backward-compat providers until Plan 04-05 removes them.
///
/// Does NOT extend [FirestoreRepository] — this class is a pure SQLite wrapper.
class BalanceCacheRepository {
  final Map<String, StreamController<void>> _notifiers = {};

  StreamController<void> _getNotifier(String key) {
    return _notifiers.putIfAbsent(key, StreamController<void>.broadcast);
  }

  void _notifyChange(String key) {
    if (_notifiers.containsKey(key)) {
      _notifiers[key]!.add(null);
    }
  }

  void dispose() {
    for (final ctrl in _notifiers.values) {
      ctrl.close();
    }
    _notifiers.clear();
  }

  // ---------------------------------------------------------------------------
  // Write: side-write from Firestore snapshot asyncMap pipelines (D-15)
  // ---------------------------------------------------------------------------

  /// Cache a list of [expenses] keyed by [eventId] (= Firestore event ID).
  ///
  /// Called as a side-effect inside [eventExpensesProvider]'s asyncMap.
  /// Deletes all existing rows for the event first, then batch-inserts the
  /// fresh set. This prevents ghost rows from server-side deletes persisting
  /// in SQLite (ConflictAlgorithm.replace alone cannot remove deleted records).
  Future<void> cacheExpenses(
    String eventId,
    List<Expense> expenses,
  ) async {
    final db = await LocalDatabase.database;
    await db.delete('expenses', where: 'trip_id = ?', whereArgs: [eventId]);
    final syncedAt = DateTime.now().toIso8601String();
    final batch = db.batch();
    for (final expense in expenses) {
      batch.insert(
        'expenses',
        {
          'id': expense.id,
          // NOTE: The SQLite column is named 'trip_id' for historical reasons.
          // For Firestore-only events this value is the Firestore event document ID.
          // Do NOT rename without a SQLite schema migration (version bump in
          // LocalDatabase._createDb and corresponding migration in _onUpgrade).
          'trip_id': expense.tripId,
          'payer_participant_id': expense.payerParticipantId,
          'amount': expense.amount.toString(),
          'description': expense.description,
          'category_id': expense.categoryId,
          'category_name': expense.categoryName,
          'scope': expense.scope.value,
          'sub_group_id': expense.subGroupId,
          'created_at': expense.createdAt.toIso8601String(),
          'synced_at': syncedAt,
          'is_deleted': expense.isDeleted ? 1 : 0,
          'deleted_at': expense.deletedAt?.toIso8601String(),
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    await batch.commit(noResult: true);
    _notifyChange('expenses:$eventId');
  }

  /// Cache a list of [settlements] keyed by [eventId].
  ///
  /// Called as a side-effect inside [eventSettlementsProvider]'s asyncMap.
  /// Deletes all existing rows for the event first, then batch-inserts the
  /// fresh set (same ghost-row prevention as [cacheExpenses]).
  Future<void> cacheSettlements(
    String eventId,
    List<Settlement> settlements,
  ) async {
    final db = await LocalDatabase.database;
    await db.delete('settlements', where: 'trip_id = ?', whereArgs: [eventId]);
    final syncedAt = DateTime.now().toIso8601String();
    final batch = db.batch();
    for (final s in settlements) {
      batch.insert(
        'settlements',
        {
          'id': s.id,
          // NOTE: 'trip_id' column stores eventId — see cacheExpenses() for details.
          'trip_id': s.tripId,
          'payer_participant_id': s.payerParticipantId,
          'recipient_participant_id': s.recipientParticipantId,
          'amount': s.amount.toString(),
          'note': s.note,
          'created_at': s.settledAt.toIso8601String(),
          'synced_at': syncedAt,
          'is_deleted': s.isDeleted ? 1 : 0,
          'deleted_at': s.deletedAt?.toIso8601String(),
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    await batch.commit(noResult: true);
    _notifyChange('settlements:$eventId');
  }

  // ---------------------------------------------------------------------------
  // Read: used by BalanceCalculator
  // ---------------------------------------------------------------------------

  /// Read non-deleted expenses from SQLite for [eventId].
  Future<List<Expense>> getExpenses(String eventId) async {
    final db = await LocalDatabase.database;
    // NOTE: 'trip_id' column stores eventId — see cacheExpenses() for details.
    final maps = await db.query(
      'expenses',
      where: 'trip_id = ? AND is_deleted = 0',
      whereArgs: [eventId],
      orderBy: 'created_at DESC',
    );
    return maps.map((map) {
      return Expense(
        id: map['id'] as String,
        tripId: map['trip_id'] as String,
        payerParticipantId:
            map['payer_participant_id'] as String? ??
            map['payer_id'] as String? ??
            '',
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

  /// Read non-deleted settlements from SQLite for [eventId].
  Future<List<Settlement>> getSettlements(String eventId) async {
    final db = await LocalDatabase.database;
    // NOTE: 'trip_id' column stores eventId — see cacheExpenses() for details.
    final maps = await db.query(
      'settlements',
      where: 'trip_id = ? AND is_deleted = 0',
      whereArgs: [eventId],
      orderBy: 'created_at DESC',
    );
    return maps.map((map) {
      return Settlement(
        id: map['id'] as String,
        tripId: map['trip_id'] as String,
        payerParticipantId: map['payer_participant_id'] as String?,
        recipientParticipantId: map['recipient_participant_id'] as String?,
        amount: Decimal.parse(map['amount'] as String),
        note: map['note'] as String?,
        settledAt: DateTime.parse(map['created_at'] as String),
        isDeleted: (map['is_deleted'] as int?) == 1,
        deletedAt: map['deleted_at'] != null
            ? DateTime.parse(map['deleted_at'] as String)
            : null,
      );
    }).toList();
  }

  // ---------------------------------------------------------------------------
  // Deprecated: stream interface retained for backward-compat providers
  // These will be removed in Plan 04-05.
  // ---------------------------------------------------------------------------

  /// @Deprecated('Use eventExpensesProvider. Will be removed in 04-05.')
  ///
  /// Reactive stream of expenses from SQLite for [eventId].
  Stream<List<Expense>> watchExpenses(String eventId) async* {
    yield await getExpenses(eventId);
    yield* _getNotifier('expenses:$eventId').stream
        .asyncMap((_) => getExpenses(eventId));
  }

  /// @Deprecated('Use eventSettlementsProvider. Will be removed in 04-05.')
  ///
  /// Reactive stream of settlements from SQLite for [eventId].
  Stream<List<Settlement>> watchSettlements(String eventId) async* {
    yield await getSettlements(eventId);
    yield* _getNotifier('settlements:$eventId').stream
        .asyncMap((_) => getSettlements(eventId));
  }
}
