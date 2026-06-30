import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/services/firestore_repository.dart';
import '../models/activity_log_model.dart';

final activityServiceProvider = Provider<ActivityService>(
  (ref) => ActivityService(),
);

/// Firestore-backed service for activity log operations.
///
/// Extends [FirestoreRepository] to write activity logs to the
/// `groups/{groupId}/events/{eventId}/activity_logs` subcollection.
class ActivityService extends FirestoreRepository {
  ActivityService() : super();

  @visibleForTesting
  ActivityService.withFirestore(super.db) : super.withFirestore();

  /// Cursor-paginated fetch of event activity logs (50/page, D-34 parity with
  /// the group feed). Returns the raw [QuerySnapshot] so callers read
  /// `docs.last` as the next cursor and map docs to [ActivityLog] themselves.
  ///
  /// Default [GetOptions] (cache-first) — do NOT force Source.server, or offline
  /// viewing breaks. `createdAt` is an ISO8601 UTC string, so descending
  /// lexicographic order is chronological.
  Future<QuerySnapshot<Map<String, dynamic>>> fetchActivityPageRaw(
    String groupId,
    String eventId, {
    DocumentSnapshot? startAfter,
    int limit = 50,
  }) async {
    var query = eventSubcollection(groupId, eventId, 'activity_logs')
        .orderBy('createdAt', descending: true);
    // Apply startAfterDocument BEFORE limit: fake_cloud_firestore evaluates query
    // clauses in call order and returns the wrong slice (or throws "document
    // specified wasn't found") if limit precedes the cursor.
    // Real Firestore is order-insensitive, so production is unaffected either way.
    if (startAfter != null) {
      query = query.startAfterDocument(startAfter);
    }
    return query.limit(limit).get();
  }

  /// Loads (up to [cap]) of one event's audit logs for the Trip Receipt (#704).
  ///
  /// A single `createdAt` DESC query — no composite index — so when the [cap] is
  /// hit the MOST RECENT corrections are kept (the audit-relevant ones). Default
  /// cache-first [GetOptions] (never `Source.server`) so an offline export reads
  /// whatever is cached. Reports [capHit] (raw rows incl. CREATEs reached [cap])
  /// and [fromCacheEmpty] (offline with nothing cached) so the receipt can stamp
  /// honest coverage rather than present a partial/offline audit as complete.
  /// Malformed docs are skipped (one bad row can't blank the whole section).
  Future<({List<ActivityLog> logs, bool capHit, bool fromCacheEmpty})>
      fetchAllEventAuditLogs(
    String groupId,
    String eventId, {
    int cap = 500,
  }) async {
    final snap = await eventSubcollection(groupId, eventId, 'activity_logs')
        .orderBy('createdAt', descending: true)
        .limit(cap)
        .get();
    final logs = <ActivityLog>[];
    for (final doc in snap.docs) {
      try {
        logs.add(ActivityLog.fromFirestore(doc.data()));
      } catch (_) {
        // Skip a malformed/legacy doc; coverage stays honest via capHit.
      }
    }
    return (
      logs: logs,
      capHit: snap.docs.length >= cap,
      fromCacheEmpty: snap.metadata.isFromCache && snap.docs.isEmpty,
    );
  }
}
