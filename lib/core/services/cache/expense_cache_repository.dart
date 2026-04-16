// Conflict strategy: delete-all-for-event-then-batch-insert (ghost-row-free).
//
// Prevents ghost rows after server-side Firestore deletes — `ConflictAlgorithm.replace`
// alone cannot remove deleted records. This pattern was introduced in Phase 9
// via [BalanceCacheRepository] and is now the canonical write for the expenses table.
//
// NOTE: The `trip_id` column stores the Firestore event ID for historical
// schema reasons. Do NOT rename without a SQLite migration (version bump in
// LocalDatabase._databaseVersion and corresponding _onUpgrade entry).
import 'package:decimal/decimal.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sqflite/sqflite.dart';

import '../../../features/ledger/models/expense_model.dart';
import '../local_database.dart';

/// Riverpod provider for [ExpenseCacheRepository].
final expenseCacheRepositoryProvider = Provider<ExpenseCacheRepository>(
  (ref) => ExpenseCacheRepository(),
);

/// SQLite cache repository for [Expense] records.
///
/// Owned table: `expenses` (schema version 6, column `trip_id` stores eventId).
class ExpenseCacheRepository {
  /// Persist [expenses] for [eventId], replacing any prior snapshot atomically.
  ///
  /// Deletes all existing rows for the event first, then batch-inserts the
  /// fresh set. This prevents ghost rows from server-side Firestore deletes
  /// persisting in SQLite (see BalanceCacheRepository history — Phase 9 fix).
  ///
  /// Called as a side-effect inside [eventExpensesProvider]'s asyncMap (D-15).
  Future<void> cacheExpenses(String eventId, List<Expense> expenses) async {
    final db = await LocalDatabase.database;
    // NOTE: 'trip_id' column stores eventId (historical schema — do not rename).
    await db.delete('expenses', where: 'trip_id = ?', whereArgs: [eventId]);
    if (expenses.isEmpty) return;
    final syncedAt = DateTime.now().toIso8601String();
    final batch = db.batch();
    for (final expense in expenses) {
      batch.insert(
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
          'synced_at': syncedAt,
          'is_deleted': expense.isDeleted ? 1 : 0,
          'deleted_at': expense.deletedAt?.toIso8601String(),
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    await batch.commit(noResult: true);
  }

  /// Read non-deleted expenses from SQLite for [eventId].
  Future<List<Expense>> getExpenses(String eventId) async {
    final db = await LocalDatabase.database;
    // NOTE: 'trip_id' column stores eventId.
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
}
