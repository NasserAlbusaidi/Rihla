import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../../../core/services/firestore_repository.dart';
import '../../../core/utils/safe_deserialize.dart';
import '../models/group_activity_log_model.dart';
import 'member_name_resolver.dart';

/// Firestore-backed service for group-level activity log operations.
///
/// Activity entries are stored in the subcollection:
///   `groups/{groupId}/activity/{activityId}`
///
/// This is separate from per-event activity logs (which live at
/// `groups/{groupId}/events/{eventId}/activity_logs`). Group activity
/// entries represent cross-group actions: settlements, member changes,
/// event lifecycle events.
///
/// Key design decisions (from D-32, D-33, D-34):
///   - [logGroupEvent] is fire-and-forget (returns `void`, not `Future<void>`)
///   - Timestamps are client-side ISO 8601 strings (not FieldValue.serverTimestamp)
///     per RESEARCH Pitfall 5 — avoids ordering issues with optimistic local reads
///   - [watchRecentActivity] defaults to the 5 most recent entries (D-34)
///   - [fetchActivityPage] / [fetchActivityPageRaw] enable cursor-based pagination
class GroupActivityService extends FirestoreRepository {
  GroupActivityService() : super();

  /// Test constructor — injects a [FakeFirebaseFirestore] for unit testing.
  @visibleForTesting
  GroupActivityService.withFirestore(super.db) : super.withFirestore();

  CollectionReference<Map<String, dynamic>> _activityRef(String groupId) =>
      db.collection('groups').doc(groupId).collection('activity');

  /// Stream of the [limit] most recent group activity entries (D-34: default 5).
  ///
  /// Ordered by timestamp descending (most recent first).
  Stream<List<GroupActivityLog>> watchRecentActivity(
    String groupId, {
    int limit = 5,
  }) {
    return recoverListen(() {
      return _activityRef(groupId)
          .orderBy('timestamp', descending: true)
          .limit(limit)
          .snapshots()
          .map(
            // #928: one malformed row must not blank the whole feed (this
            // stream feeds home RECENTLY + the unread dot, which swallow errors
            // as `[]`). Display-only rows have no oracle to stay in lockstep
            // with, so skip-and-report is the correct semantic (the Trip
            // Receipt precedent).
            (snap) => decodeDocsSkippingMalformed(
              snap.docs,
              (d) => GroupActivityLog.fromFirestore(
                {...d.data()! as Map<String, dynamic>, 'id': d.id},
              ),
              context: 'GroupActivityService.watchRecentActivity',
            ),
          );
    });
  }

  /// Cursor-paginated activity fetch for full activity log screen (D-34: 50/page).
  ///
  /// Pass [startAfter] (a [DocumentSnapshot] from [fetchActivityPageRaw]) to
  /// get the next page. Omit for the first page.
  Future<List<GroupActivityLog>> fetchActivityPage(
    String groupId, {
    DocumentSnapshot? startAfter,
    int limit = 50,
  }) async {
    var query = _activityRef(groupId).orderBy('timestamp', descending: true);
    // Apply startAfterDocument BEFORE limit: fake_cloud_firestore evaluates query
    // clauses in call order and returns the wrong slice (or throws "document
    // specified wasn't found") if limit precedes the cursor.
    // Real Firestore is order-insensitive, so production is unaffected either way.
    if (startAfter != null) {
      query = query.startAfterDocument(startAfter);
    }
    final snap = await query.limit(limit).get();
    // #928: skip a malformed feed row rather than failing the page.
    return decodeDocsSkippingMalformed(
      snap.docs,
      (d) => GroupActivityLog.fromFirestore(
        {...d.data()! as Map<String, dynamic>, 'id': d.id},
      ),
      context: 'GroupActivityService.fetchActivityPage',
    );
  }

  /// Returns the raw [QuerySnapshot] for cursor-based pagination.
  ///
  /// Use the last [DocumentSnapshot] from [QuerySnapshot.docs] as the
  /// [startAfter] argument to [fetchActivityPage] for the next page.
  Future<QuerySnapshot<Map<String, dynamic>>> fetchActivityPageRaw(
    String groupId, {
    DocumentSnapshot? startAfter,
    int limit = 50,
  }) async {
    var query = _activityRef(groupId).orderBy('timestamp', descending: true);
    // Apply startAfterDocument BEFORE limit: fake_cloud_firestore evaluates query
    // clauses in call order and returns the wrong slice (or throws "document
    // specified wasn't found") if limit precedes the cursor.
    // Real Firestore is order-insensitive, so production is unaffected either way.
    if (startAfter != null) {
      query = query.startAfterDocument(startAfter);
    }
    return query.limit(limit).get();
  }

  /// Coerces any actor label into a value that always passes the security
  /// rules' `isValidDisplayName` (#1140 D7), so an activity row folded into the
  /// SAME [WriteBatch] as its money/lifecycle mutation can never veto that
  /// mutation on a name-shape check. Control-strip runs FIRST so a crafted
  /// `'Bob (former member)\x01'` can't hide the suffix; the suffix strip loops
  /// so a doubled ` (former member)` can't survive; a final totality guard
  /// floors any residue to a guaranteed-valid constant.
  static String sanitizeActorName(String raw) {
    var s = raw.replaceAll(RegExp(r'[\x00-\x1f\x7f]'), '').trim();
    while (s.endsWith(MemberNameResolver.formerSuffix)) {
      s = s
          .substring(0, s.length - MemberNameResolver.formerSuffix.length)
          .trim();
    }
    if (s.length > 32) s = s.substring(0, 32).trim();
    // Totality guard: after every transform, if anything still violates
    // isValidDisplayName (empty, re-exposed suffix, residual control char, or
    // over-length), floor to the constant. Makes "every input → rule-valid".
    if (s.isEmpty ||
        s.endsWith(MemberNameResolver.formerSuffix) ||
        RegExp(r'[\x00-\x1f\x7f]').hasMatch(s) ||
        s.length > 32) {
      return 'Someone';
    }
    return s;
  }

  /// The SINGLE source of the group-activity document shape (#1140). Both the
  /// fire-and-forget [logGroupEvent] and the batch-folded mutation paths
  /// (event create/delete, settlements) build their activity row here, so the
  /// shape stays in lockstep. [actorName] is sanitized via [sanitizeActorName]
  /// so the doc always passes `validGroupActivityCreate`.
  static Map<String, dynamic> buildActivityDoc({
    required String id,
    required String type,
    required String actorId,
    required String actorName,
    required String description,
    required Map<String, dynamic> metadata,
    required DateTime timestampUtc,
  }) {
    return {
      'id': id,
      'type': type,
      'actorId': actorId,
      'actorName': sanitizeActorName(actorName),
      'description': description,
      'metadata': metadata,
      'timestamp': timestampUtc.toIso8601String(),
    };
  }

  /// Fire-and-forget activity log write (D-33).
  ///
  /// Returns `void` — callers do NOT await this. Errors are caught and logged
  /// via [debugPrint] to avoid crashing the caller's context.
  ///
  /// This is now the ONLY non-atomic activity write path — reserved for
  /// `member_joined` (logged only AFTER a confirmed `joinGroupByInviteCode`
  /// callable commit, so it can never record a join that did not happen; its
  /// only failure mode is a lost row, D-32). Every mutation-paired row (event
  /// create/delete, settlements) is instead folded into the mutation's own
  /// [WriteBatch] (#1140), so a denied mutation persists no phantom activity.
  ///
  /// Timestamp is client-side [DateTime.now().toUtc()] (not
  /// [FieldValue.serverTimestamp]) per RESEARCH Pitfall 5.
  void logGroupEvent({
    required String groupId,
    required String type,
    required String actorId,
    required String actorName,
    required String description,
    Map<String, dynamic>? metadata,
  }) {
    final id = const Uuid().v4();
    unawaited(
      _activityRef(groupId)
          .doc(id)
          .set(buildActivityDoc(
            id: id,
            type: type,
            actorId: actorId,
            actorName: actorName,
            description: description,
            metadata: metadata ?? const <String, dynamic>{},
            timestampUtc: DateTime.now().toUtc(),
          ))
          .catchError((Object e) { if (kDebugMode) debugPrint('[GroupActivity] log failed: $e'); }),
    );
  }
}
