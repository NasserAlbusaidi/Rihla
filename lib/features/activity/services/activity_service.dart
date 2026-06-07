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
}
