// Conflict strategy: ConflictAlgorithm.replace (upsert by PK).
//
// [cacheCategories] deletes all rows for the trip first, then batch-inserts
// the fresh snapshot.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sqflite/sqflite.dart';

import '../../../features/ledger/models/expense_category_model.dart';
import '../local_database.dart';

/// Riverpod provider for [CategoryCacheRepository].
final categoryCacheRepositoryProvider = Provider<CategoryCacheRepository>(
  (ref) => CategoryCacheRepository(),
);

/// SQLite cache repository for [ExpenseCategory] records.
///
/// Owned table: `categories` (schema version 6, column `trip_id`).
class CategoryCacheRepository {
  /// Persist [categories] for [tripId], replacing the entire snapshot.
  Future<void> cacheCategories(
    String ownerUid,
    String tripId,
    List<ExpenseCategory> categories,
  ) async {
    final db = await LocalDatabase.database;
    await db.delete(
      'categories',
      where: 'owner_uid = ? AND trip_id = ?',
      whereArgs: [ownerUid, tripId],
    );
    if (categories.isEmpty) return;
    final syncedAt = DateTime.now().toIso8601String();
    final batch = db.batch();
    for (final cat in categories) {
      batch.insert('categories', {
        'id': cat.id,
        'owner_uid': ownerUid,
        'trip_id': tripId,
        'name': cat.name,
        'icon': cat.icon,
        'last_synced_at': syncedAt,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    }
    await batch.commit(noResult: true);
  }

  /// Read all cached categories for [tripId].
  Future<List<ExpenseCategory>> getCachedCategories(
    String ownerUid,
    String tripId,
  ) async {
    final db = await LocalDatabase.database;
    final maps = await db.query(
      'categories',
      where: 'owner_uid = ? AND trip_id = ?',
      whereArgs: [ownerUid, tripId],
    );
    return maps
        .map(
          (m) => ExpenseCategory(
            id: m['id'] as String,
            tripId: tripId,
            name: m['name'] as String,
            icon: m['icon'] as String? ?? 'other',
          ),
        )
        .toList();
  }
}
