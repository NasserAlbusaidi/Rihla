import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../../core/services/firestore_repository.dart';
import '../../../core/utils/calendar_date.dart';
import '../../../core/utils/safe_deserialize.dart';
import '../../groups/services/group_activity_service.dart';
import '../models/event_model.dart';

/// Service for Event CRUD operations against Firestore.
///
/// Extends [FirestoreRepository] so all Firestore access flows through the
/// base class `db` getter (MIG-05).
///
/// Events are stored as a subcollection:
///   `groups/{groupId}/events/{eventId}`
///
/// Events are Firestore-only.
class EventService extends FirestoreRepository {
  /// Default constructor for Riverpod-managed use.
  EventService(Ref ref) : super();

  /// Test-only constructor: inject FakeFirebaseFirestore.
  @visibleForTesting
  EventService.withFirestore(super.db) : super.withFirestore();

  /// Reactive stream of all non-deleted events in a group.
  ///
  /// Sort order per D-25:
  ///   - Events without a startDate sort to the top (null-date first).
  ///   - All others sorted by createdAt descending (newest first).
  ///
  /// The Firestore query filters isDeleted=false and orders by createdAt DESC.
  /// Client-side sort overrides the order for null-date events (D-25).
  Stream<List<Event>> watchGroupEvents(String groupId) {
    return recoverListen(() {
      return db
          .collection('groups')
          .doc(groupId)
          .collection('events')
          .where('isDeleted', isEqualTo: false)
          .orderBy('createdAt', descending: true)
          .snapshots()
          .map((snap) {
            // #532: decode per-doc so one malformed event can't error the whole
            // stream — mirrors the Group/Member path in group_provider.dart.
            final events = decodeDocsSkippingMalformed(
              snap.docs,
              Event.fromDoc,
              context: 'watchGroupEvents',
            );
            events.sort((a, b) {
              if (a.startDate == null && b.startDate == null) {
                return b.createdAt.compareTo(a.createdAt);
              }
              if (a.startDate == null) return -1;
              if (b.startDate == null) return 1;
              return b.createdAt.compareTo(a.createdAt);
            });
            return List.unmodifiable(events);
          });
    });
  }

  /// Reactive stream for a single event by compound key.
  ///
  /// Returns null if the event does not exist or has been hard-deleted.
  Stream<Event?> watchEvent({
    required String groupId,
    required String eventId,
  }) {
    return recoverListen(() {
      return db
          .collection('groups')
          .doc(groupId)
          .collection('events')
          .doc(eventId)
          .snapshots()
          .map((doc) {
            if (!doc.exists) return null;
            final event = Event.fromDoc(doc);
            // #518: fence out soft-deleted docs — a single-doc snapshot always
            // EXISTS, so isDeleted must be checked in-memory (no server-side
            // .where filter on a .doc().snapshots() stream).
            return event.isDeleted ? null : event;
          });
    });
  }

  /// Stages a new event: applies the write to the local Firestore cache and
  /// returns the locally-built [Event] IMMEDIATELY, plus the server-ack future
  /// (#412). The ack resolves only when the server confirms — offline it stays
  /// pending until reconnect while the SDK queues the replay, so UI callers race
  /// it (`awaitServerAck`) instead of awaiting it raw (which strands the
  /// "Creating…" spinner forever offline — #516).
  ///
  /// Per Pitfall 3: createdAt uses a client-generated UTC timestamp, not
  /// FieldValue.serverTimestamp(), so it is immediately readable.
  ({Event event, Future<void> ack}) stageEvent({
    required String groupId,
    required String name,
    required EventType type,
    required List<String> participantIds,
    required Map<String, String> participantNames,
    required String createdBy,
    DateTime? startDate,
    DateTime? endDate,
    EventModules? modules,
  }) {
    const uuid = Uuid();
    final eventId = uuid.v4();
    final now = DateTime.now().toUtc();
    // Use provided modules (Custom type override) or derive from type
    final resolvedModules = modules ?? EventModules.forType(type);

    final event = Event(
      id: eventId,
      name: name,
      type: type,
      groupId: groupId,
      createdBy: createdBy,
      participantIds: List.unmodifiable(participantIds),
      participantNames: Map.unmodifiable(participantNames),
      modules: resolvedModules,
      startDate: startDate,
      endDate: endDate,
      isDeleted: false,
      createdAt: now,
    );

    final ack = db
        .collection('groups')
        .doc(groupId)
        .collection('events')
        .doc(eventId)
        .set(event.toFirestoreMap());

    return (event: event, ack: ack);
  }

  /// Create a new event in Firestore and return it once the SERVER has
  /// acknowledged the write.
  ///
  /// Offline, that ack only arrives on reconnect — UI flows that must not block
  /// on it use [stageEvent] instead (#412/#516). Retained for tests/scripts and
  /// any caller that genuinely wants to await server confirmation.
  Future<Event> createEvent({
    required String groupId,
    required String name,
    required EventType type,
    required List<String> participantIds,
    required Map<String, String> participantNames,
    required String createdBy,
    DateTime? startDate,
    DateTime? endDate,
    EventModules? modules,
  }) async {
    final staged = stageEvent(
      groupId: groupId,
      name: name,
      type: type,
      participantIds: participantIds,
      participantNames: participantNames,
      createdBy: createdBy,
      startDate: startDate,
      endDate: endDate,
      modules: modules,
    );
    try {
      await staged.ack;
    } on FirebaseException catch (e) {
      if (kDebugMode) {
        debugPrint('EventService.createEvent failed: ${e.code} ${e.message}');
      }
      rethrow;
    }
    return staged.event;
  }

  /// Soft-delete an event (sets isDeleted=true).
  ///
  /// Per D-09: hard deletes are forbidden on events to preserve financial
  /// records. Uses FieldValue.serverTimestamp() for deletedAt per Pitfall 3.
  /// Soft-delete an event; when the [activityId] + activity fields are
  /// supplied, the `event_deleted` activity row is folded into the SAME atomic
  /// [WriteBatch] as the soft-delete (#1140) — a rules rejection of the delete
  /// (e.g. a departed actor no longer passing `validEventAdminUpdate`) persists
  /// NEITHER, so a denied delete can never leave phantom history. With no
  /// activity params it is the legacy single `.update()` (tests/scripts, and
  /// the D7 no-actor fallback where a delete must never be blocked by activity).
  Future<void> deleteEvent({
    required String groupId,
    required String eventId,
    String? activityId,
    String? activityActorId,
    String? activityActorName,
    String? activityDescription,
    Map<String, dynamic>? activityMetadata,
  }) async {
    final eventRef =
        db.collection('groups').doc(groupId).collection('events').doc(eventId);
    final delta = <String, dynamic>{
      'isDeleted': true,
      'deletedAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    };
    try {
      if (activityId == null) {
        await eventRef.update(delta);
        return;
      }
      final batch = db.batch()
        ..update(eventRef, delta)
        ..set(
          db
              .collection('groups')
              .doc(groupId)
              .collection('activity')
              .doc(activityId),
          GroupActivityService.buildActivityDoc(
            id: activityId,
            type: 'event_deleted',
            actorId: activityActorId!,
            actorName: activityActorName!,
            description: activityDescription!,
            metadata: activityMetadata!,
            timestampUtc: DateTime.now().toUtc(),
          ),
        );
      await batch.commit();
    } on FirebaseException catch (e) {
      if (kDebugMode) {
        debugPrint('EventService.deleteEvent failed: ${e.code} ${e.message}');
      }
      rethrow;
    }
  }

  /// Close an event (#723): freezes its spending (no new/edited expenses) while
  /// settlements stay live. Partial `.update()` so the rules see a clean 3-key
  /// diff (`validEventCloseToggle`). [closedBy] is the acting UID, pinned by the
  /// rule to `request.auth.uid`.
  Future<void> closeEvent({
    required String groupId,
    required String eventId,
    required String closedBy,
    Map<String, dynamic>? spendingSnapshot,
  }) async {
    try {
      await db
          .collection('groups')
          .doc(groupId)
          .collection('events')
          .doc(eventId)
          .update({
            'isClosed': true,
            'closedAt': FieldValue.serverTimestamp(),
            'closedBy': closedBy,
            'updatedAt': FieldValue.serverTimestamp(),
            // #766: the frozen SPENDING half, captured opaque at close. The
            // null-aware `?` omits the entry when null (empty event / inputs
            // unloaded) so the close write stays a 4-key diff;
            // `validEventCloseToggle` accepts the 5th key bounded.
            'spendingSnapshot': ?spendingSnapshot,
          });
    } on FirebaseException catch (e) {
      if (kDebugMode) {
        debugPrint('EventService.closeEvent failed: ${e.code} ${e.message}');
      }
      rethrow;
    }
  }

  /// Reopen a closed event (#723): clears the close triple so expenses are
  /// editable again. Admin-gated by `validEventCloseToggle`.
  Future<void> reopenEvent({
    required String groupId,
    required String eventId,
  }) async {
    try {
      await db
          .collection('groups')
          .doc(groupId)
          .collection('events')
          .doc(eventId)
          .update({
            'isClosed': false,
            'closedAt': null,
            'closedBy': null,
            'updatedAt': FieldValue.serverTimestamp(),
            // #766: clear the frozen snapshot so the recap goes fully live again.
            // DELETE (not null) — an explicit null fails the opaque `is map`
            // rules guard; deletion removes the key so `!hasAny` passes.
            'spendingSnapshot': FieldValue.delete(),
          });
    } on FirebaseException catch (e) {
      if (kDebugMode) {
        debugPrint('EventService.reopenEvent failed: ${e.code} ${e.message}');
      }
      rethrow;
    }
  }

  /// Update event metadata (name, dates, and/or description).
  ///
  /// Only non-null fields are updated. Always updates [updatedAt].
  /// Set [clearDescription] to true to clear the description (#1103). The
  /// clear writes an explicit null, NEVER FieldValue.delete(): every event doc
  /// is born with the key (`toFirestoreMap`) and `validEventBase` reads
  /// `data.description` unguarded, so an absent post-write key errors the
  /// rules evaluation into PERMISSION_DENIED (opposite polarity to the #287
  /// glyph clear, whose guards admit absent and reject null).
  Future<void> updateEvent({
    required String groupId,
    required String eventId,
    String? name,
    DateTime? startDate,
    DateTime? endDate,
    String? description,
    bool clearDescription = false,
  }) async {
    final updateMap = <String, dynamic>{
      'updatedAt': FieldValue.serverTimestamp(),
    };
    if (name != null) {
      updateMap['name'] = name;
    }
    if (startDate != null) {
      updateMap['startDate'] = Timestamp.fromDate(anchorCalendarDate(startDate));
    }
    if (endDate != null) {
      updateMap['endDate'] = Timestamp.fromDate(anchorCalendarDate(endDate));
    }
    if (clearDescription) {
      updateMap['description'] = null;
    } else if (description != null) {
      updateMap['description'] = description;
    }

    try {
      await db
          .collection('groups')
          .doc(groupId)
          .collection('events')
          .doc(eventId)
          .update(updateMap);
    } on FirebaseException catch (e) {
      if (kDebugMode) {
        debugPrint('EventService.updateEvent failed: ${e.code} ${e.message}');
      }
      rethrow;
    }
  }
}
