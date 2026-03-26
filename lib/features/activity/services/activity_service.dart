import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../../core/services/firestore_repository.dart';
import '../../../core/services/offline_repository.dart';
import '../../../core/types/event_ref.dart';
import '../models/activity_log_model.dart';

final activityServiceProvider =
    Provider<ActivityService>((ref) => ActivityService());

/// NEW: Firestore-backed stream of activity logs for an event.
///
/// Ordered by createdAt descending (most recent first).
/// Use this for all new code. Replaces [tripActivityProvider].
final eventActivityProvider =
    StreamProvider.family<List<ActivityLog>, EventRef>((ref, eventRef) {
  return ref
      .read(activityServiceProvider)
      .watchActivityLogs(eventRef.groupId, eventRef.eventId);
});

/// NEW: Transaction-only activity logs from Firestore (category == 'MONEY').
///
/// Use this for all new code. Replaces [tripTransactionActivityProvider].
final eventTransactionActivityProvider =
    StreamProvider.family<List<ActivityLog>, EventRef>((ref, eventRef) {
  return ref
      .read(activityServiceProvider)
      .watchActivityLogs(eventRef.groupId, eventRef.eventId)
      .map((logs) => logs.where((log) => log.category == 'MONEY').toList());
});

/// @Deprecated('Use eventActivityProvider with EventRef')
///
/// Legacy stream of activity logs from SQLite (Supabase path).
/// Retained for backward compatibility with screens not yet migrated to Firestore.
final tripActivityProvider =
    StreamProvider.family<List<ActivityLog>, String>((ref, tripId) {
  return ref.read(offlineRepositoryProvider).watchActivityLogs(tripId);
});

/// @Deprecated('Use eventTransactionActivityProvider with EventRef')
///
/// Legacy transaction-only logs from SQLite (Supabase path).
/// Retained for backward compatibility with screens not yet migrated to Firestore.
final tripTransactionActivityProvider =
    StreamProvider.family<List<ActivityLog>, String>((ref, tripId) {
  return ref
      .read(offlineRepositoryProvider)
      .watchActivityLogs(tripId)
      .map((logs) => logs.where((log) => log.category == 'MONEY').toList());
});

/// Firestore-backed service for activity log operations.
///
/// Extends [FirestoreRepository] to write activity logs to the
/// `groups/{groupId}/events/{eventId}/activity_logs` subcollection.
class ActivityService extends FirestoreRepository {
  ActivityService() : super();

  @visibleForTesting
  ActivityService.withFirestore(FirebaseFirestore db) : super.withFirestore(db);

  /// Stream of activity logs for an event, ordered by createdAt descending.
  Stream<List<ActivityLog>> watchActivityLogs(
    String groupId,
    String eventId,
  ) {
    return eventSubcollection(groupId, eventId, 'activity_logs')
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map(
          (snap) => snap.docs
              .map(
                (doc) =>
                    ActivityLog.fromFirestore({...doc.data(), 'id': doc.id}),
              )
              .toList(),
        );
  }

  /// Add an activity log entry to the event subcollection.
  Future<void> addActivityLog({
    required String groupId,
    required String eventId,
    required String category,
    required String action,
    required String actorId,
    String? actorName,
    Map<String, dynamic>? metadata,
  }) async {
    final id = const Uuid().v4();
    final now = DateTime.now().toUtc();
    await eventSubcollection(groupId, eventId, 'activity_logs').doc(id).set({
      'id': id,
      'eventId': eventId,
      'category': category,
      'eventType': action,
      'logText': '$actorName $action'.trim(),
      'actorId': actorId,
      'actorName': actorName,
      'metadata': metadata ?? const <String, dynamic>{},
      'createdAt': now.toIso8601String(),
    });
  }
}
