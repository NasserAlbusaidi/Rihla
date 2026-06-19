import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../../core/services/firestore_repository.dart';
import '../../../core/utils/safe_deserialize.dart';
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
  }

  /// Reactive stream for a single event by compound key.
  ///
  /// Returns null if the event does not exist or has been hard-deleted.
  Stream<Event?> watchEvent({
    required String groupId,
    required String eventId,
  }) {
    return db
        .collection('groups')
        .doc(groupId)
        .collection('events')
        .doc(eventId)
        .snapshots()
        .map((doc) => doc.exists ? Event.fromDoc(doc) : null);
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
  Future<void> deleteEvent({
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
            'isDeleted': true,
            'deletedAt': FieldValue.serverTimestamp(),
            'updatedAt': FieldValue.serverTimestamp(),
          });
    } on FirebaseException catch (e) {
      if (kDebugMode) {
        debugPrint('EventService.deleteEvent failed: ${e.code} ${e.message}');
      }
      rethrow;
    }
  }

  /// Update event metadata (name, dates, and/or description).
  ///
  /// Only non-null fields are updated. Always updates [updatedAt].
  Future<void> updateEvent({
    required String groupId,
    required String eventId,
    String? name,
    DateTime? startDate,
    DateTime? endDate,
    String? description,
  }) async {
    final updateMap = <String, dynamic>{
      'updatedAt': FieldValue.serverTimestamp(),
    };
    if (name != null) {
      updateMap['name'] = name;
    }
    if (startDate != null) {
      updateMap['startDate'] = Timestamp.fromDate(startDate);
    }
    if (endDate != null) {
      updateMap['endDate'] = Timestamp.fromDate(endDate);
    }
    if (description != null) {
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
