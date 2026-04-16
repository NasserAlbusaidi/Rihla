// Conflict strategy: delete-all-for-event-then-batch-insert (ghost-row-free).
//
// Same pattern as [ExpenseCacheRepository] — `ConflictAlgorithm.replace` alone
// cannot remove server-deleted records. Delete all rows for the event first,
// then batch-insert the fresh snapshot.
//
// NOTE: The `trip_id` column stores the Firestore event ID for historical
// schema reasons. Do NOT rename without a SQLite migration.
import 'package:decimal/decimal.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sqflite/sqflite.dart';

import '../../../features/ledger/models/settlement_model.dart';
import '../local_database.dart';

/// Riverpod provider for [SettlementCacheRepository].
final settlementCacheRepositoryProvider = Provider<SettlementCacheRepository>(
  (ref) => SettlementCacheRepository(),
);

/// SQLite cache repository for [Settlement] records.
///
/// Owned table: `settlements` (schema version 6, column `trip_id` stores eventId).
class SettlementCacheRepository {
  /// Persist [settlements] for [eventId], replacing any prior snapshot atomically.
  ///
  /// Deletes all existing rows for the event first, then batch-inserts the
  /// fresh set (same ghost-row prevention as [ExpenseCacheRepository]).
  ///
  /// Called as a side-effect inside [eventSettlementsProvider]'s asyncMap (D-15).
  Future<void> cacheSettlements(
    String eventId,
    List<Settlement> settlements,
  ) async {
    final db = await LocalDatabase.database;
    // NOTE: 'trip_id' column stores eventId (historical schema — do not rename).
    await db.delete('settlements', where: 'trip_id = ?', whereArgs: [eventId]);
    if (settlements.isEmpty) return;
    final syncedAt = DateTime.now().toIso8601String();
    final batch = db.batch();
    for (final s in settlements) {
      batch.insert(
        'settlements',
        {
          'id': s.id,
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
  }

  /// Read non-deleted settlements from SQLite for [eventId].
  Future<List<Settlement>> getSettlements(String eventId) async {
    final db = await LocalDatabase.database;
    // NOTE: 'trip_id' column stores eventId.
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
}
