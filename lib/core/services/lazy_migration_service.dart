import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:decimal/decimal.dart';
import 'package:flutter/foundation.dart';

import '../config/firebase_config.dart';
import '../config/supabase_config.dart';
import 'money_serializer.dart';

/// Service for lazily migrating legacy Supabase data to Firestore on first access.
///
/// Called when a user opens an event module screen (e.g., Ledger, Gear) for
/// an event that has a [bridgeTripId]. If the Firestore subcollection for that
/// module is empty, this service fetches data from Supabase via the bridge
/// trip ID and writes it to Firestore.
///
/// Per D-18: migrations are non-fatal. All errors are caught and logged.
/// The calling screen interprets `false` as a migration error and shows
/// an appropriate UI state (EmptyStateView with "Try Again").
class LazyMigrationService {
  final FirebaseFirestore _db;

  /// Production constructor — uses [FirebaseConfig.firestore] singleton.
  LazyMigrationService() : _db = FirebaseConfig.firestore;

  /// Test constructor — injects a [FakeFirebaseFirestore] for unit testing.
  @visibleForTesting
  LazyMigrationService.withFirestore(FirebaseFirestore db) : _db = db;

  /// Check if a module's Firestore subcollection needs migration.
  ///
  /// Returns `true` if migration was performed successfully.
  /// Returns `false` if:
  ///   - [bridgeTripId] is null or empty (no legacy data to migrate)
  ///   - Firestore already has data (already migrated)
  ///   - Supabase is unavailable or not authenticated
  ///   - Migration fails for any reason (non-fatal error handling)
  ///
  /// Supported [module] values: `expenses`, `settlements`, `gear_items`,
  /// `sub_groups`, `activity_logs`.
  Future<bool> migrateModuleIfNeeded({
    required String groupId,
    required String eventId,
    required String? bridgeTripId,
    required String module,
  }) async {
    if (bridgeTripId == null || bridgeTripId.isEmpty) return false;

    // Check if Firestore already has data for this module
    try {
      final snapshot = await _db
          .collection('groups/$groupId/events/$eventId/$module')
          .limit(1)
          .get();
      if (snapshot.docs.isNotEmpty) return false; // Already migrated
    } catch (e) {
      debugPrint(
          'LazyMigration: Failed to check Firestore subcollection $module for event $eventId: $e');
      return false;
    }

    // Check if Supabase is available before attempting migration
    try {
      if (!SupabaseConfig.isAuthenticated) return false;
    } catch (e) {
      // Supabase may not be initialized in Firebase-only or test environments
      debugPrint(
          'LazyMigration: Supabase not available — skipping migration for $module');
      return false;
    }

    try {
      switch (module) {
        case 'expenses':
          return await _migrateExpenses(groupId, eventId, bridgeTripId);
        case 'settlements':
          return await _migrateSettlements(groupId, eventId, bridgeTripId);
        case 'gear_items':
          return await _migrateGearItems(groupId, eventId, bridgeTripId);
        case 'sub_groups':
          return await _migrateSubGroups(groupId, eventId, bridgeTripId);
        case 'activity_logs':
          return await _migrateActivityLogs(groupId, eventId, bridgeTripId);
        default:
          debugPrint(
              'LazyMigration: Unknown module "$module" — no migration handler');
          return false;
      }
    } catch (e) {
      debugPrint(
          'LazyMigration: Failed to migrate $module for event $eventId: $e');
      return false;
    }
  }

  /// Migrate expenses from Supabase to Firestore.
  ///
  /// Reads from `expenses` table where `trip_id = bridgeTripId`.
  /// Converts Supabase snake_case to Firestore camelCase.
  /// Money stored as integer fils via [MoneySerializer].
  Future<bool> _migrateExpenses(
      String groupId, String eventId, String bridgeTripId) async {
    final rows = await SupabaseConfig.client
        .from('expenses')
        .select()
        .eq('trip_id', bridgeTripId);

    if ((rows as List).isEmpty) return true; // No legacy data

    final batch = _db.batch();
    final colRef =
        _db.collection('groups/$groupId/events/$eventId/expenses');

    for (final row in rows) {
      final currency = (row['currency'] as String?) ?? 'OMR';
      final amountStr = row['amount']?.toString() ?? '0';
      final amountFils = MoneySerializer.toSubunits(
        Decimal.parse(amountStr),
        currency,
      );

      final List<dynamic>? customSplit =
          row['custom_split_participants'] as List?;

      final data = <String, dynamic>{
        'id': row['id'] as String,
        'eventId': eventId,
        'payerParticipantId':
            (row['payer_participant_id'] ?? row['payer_id']) as String? ?? '',
        'amountFils': amountFils,
        'currency': currency,
        'description': row['description'] as String?,
        'scope': row['scope'] as String? ?? 'global',
        'subGroupId': row['sub_group_id'] as String?,
        'customSplitParticipants':
            customSplit?.map((e) => e.toString()).toList() ?? [],
        'receiptUrl': row['receipt_url'] as String?,
        'createdAt': (row['created_at'] as String?) ??
            DateTime.now().toIso8601String(),
        'categoryId': row['category_id'] as String?,
        'note': row['note'] as String?,
        'isDeleted': row['is_deleted'] as bool? ?? false,
        'deletedAt': row['deleted_at'] as String?,
      };

      final docRef = colRef.doc(row['id'] as String);
      batch.set(docRef, data);
    }

    await batch.commit();
    debugPrint(
        'LazyMigration: Migrated ${rows.length} expenses for event $eventId');
    return true;
  }

  /// Migrate settlements from Supabase to Firestore.
  Future<bool> _migrateSettlements(
      String groupId, String eventId, String bridgeTripId) async {
    final rows = await SupabaseConfig.client
        .from('settlements')
        .select()
        .eq('trip_id', bridgeTripId);

    if ((rows as List).isEmpty) return true;

    final batch = _db.batch();
    final colRef =
        _db.collection('groups/$groupId/events/$eventId/settlements');

    for (final row in rows) {
      const currency = 'OMR';
      final amountStr = row['amount']?.toString() ?? '0';
      final amountFils = MoneySerializer.toSubunits(
        Decimal.parse(amountStr),
        currency,
      );

      final data = <String, dynamic>{
        'id': row['id'] as String,
        'eventId': eventId,
        'payerParticipantId':
            (row['payer_participant_id'] ?? row['payer_id']) as String?,
        'recipientParticipantId':
            (row['recipient_participant_id'] ?? row['recipient_id'])
                as String?,
        'amountFils': amountFils,
        'currency': currency,
        'note': row['note'] as String?,
        'settledAt': (row['settled_at'] as String?) ??
            DateTime.now().toIso8601String(),
        'isDeleted': row['is_deleted'] as bool? ?? false,
        'deletedAt': row['deleted_at'] as String?,
      };

      final docRef = colRef.doc(row['id'] as String);
      batch.set(docRef, data);
    }

    await batch.commit();
    debugPrint(
        'LazyMigration: Migrated ${rows.length} settlements for event $eventId');
    return true;
  }

  /// Migrate gear items from Supabase to Firestore.
  Future<bool> _migrateGearItems(
      String groupId, String eventId, String bridgeTripId) async {
    final rows = await SupabaseConfig.client
        .from('gear_items')
        .select()
        .eq('trip_id', bridgeTripId);

    if ((rows as List).isEmpty) return true;

    final batch = _db.batch();
    final colRef =
        _db.collection('groups/$groupId/events/$eventId/gear_items');

    for (final row in rows) {
      final data = <String, dynamic>{
        'id': row['id'] as String,
        'eventId': eventId,
        'itemName': row['item_name'] as String,
        'assignedTo': row['assigned_to'] as String?,
        'isPacked': row['is_packed'] as bool? ?? false,
        'sequenceId': row['sequence_id'] as int? ?? 0,
        'isHighPriority': row['is_high_priority'] as bool? ?? false,
        'isDeleted': row['is_deleted'] as bool? ?? false,
        'deletedAt': row['deleted_at'] as String?,
        'createdAt': row['created_at'] as String?,
      };

      final docRef = colRef.doc(row['id'] as String);
      batch.set(docRef, data);
    }

    await batch.commit();
    debugPrint(
        'LazyMigration: Migrated ${rows.length} gear items for event $eventId');
    return true;
  }

  /// Migrate sub-groups from Supabase to Firestore.
  Future<bool> _migrateSubGroups(
      String groupId, String eventId, String bridgeTripId) async {
    final rows = await SupabaseConfig.client
        .from('sub_groups')
        .select()
        .eq('trip_id', bridgeTripId);

    if ((rows as List).isEmpty) return true;

    final batch = _db.batch();
    final colRef =
        _db.collection('groups/$groupId/events/$eventId/sub_groups');

    for (final row in rows) {
      final data = <String, dynamic>{
        'id': row['id'] as String,
        'eventId': eventId,
        'name': row['name'] as String,
        'vehicle': row['vehicle'] as String?,
        'capacity': row['capacity'] as int?,
        'departureTime': row['departure_time'] as String?,
        'meetingPoint': row['meeting_point'] as String?,
        'notes': row['notes'] as String?,
        'members': const [], // members are in a separate subcollection
        'createdAt': row['created_at'] as String?,
      };

      final docRef = colRef.doc(row['id'] as String);
      batch.set(docRef, data);
    }

    await batch.commit();
    debugPrint(
        'LazyMigration: Migrated ${rows.length} sub-groups for event $eventId');
    return true;
  }

  /// Migrate activity logs from Supabase to Firestore.
  Future<bool> _migrateActivityLogs(
      String groupId, String eventId, String bridgeTripId) async {
    final rows = await SupabaseConfig.client
        .from('trip_activity_logs')
        .select()
        .eq('trip_id', bridgeTripId)
        .order('created_at', ascending: true);

    if ((rows as List).isEmpty) return true;

    final batch = _db.batch();
    final colRef =
        _db.collection('groups/$groupId/events/$eventId/activity_logs');

    for (final row in rows) {
      final data = <String, dynamic>{
        'id': row['id'] as String,
        'eventId': eventId,
        'actorId': row['actor_id'] as String?,
        'targetParticipantId': row['target_participant_id'] as String?,
        'category': row['category'] as String,
        'eventType': row['event_type'] as String,
        'logText': row['log_text'] as String,
        'metadata': row['metadata'] as Map<String, dynamic>? ?? {},
        'createdAt': (row['created_at'] as String?) ??
            DateTime.now().toIso8601String(),
      };

      final docRef = colRef.doc(row['id'] as String);
      batch.set(docRef, data);
    }

    await batch.commit();
    debugPrint(
        'LazyMigration: Migrated ${rows.length} activity logs for event $eventId');
    return true;
  }
}
