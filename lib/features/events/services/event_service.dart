import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../../core/services/firestore_repository.dart';
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
          final events = snap.docs.map(Event.fromDoc).toList();
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

  /// Create a new event in Firestore.
  ///
  /// Steps:
  /// 1. Generate a UUID for the eventId.
  /// 2. Write event document to `groups/{groupId}/events/{eventId}`.
  ///
  /// Per Pitfall 3: createdAt uses a client-generated ISO 8601 string,
  /// not FieldValue.serverTimestamp(), so it is immediately readable.
  ///
  /// Returns the created [Event] with all fields populated.
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

    // Write to Firestore
    try {
      await db
          .collection('groups')
          .doc(groupId)
          .collection('events')
          .doc(eventId)
          .set(event.toFirestoreMap());
    } on FirebaseException catch (e) {
      if (kDebugMode) {
        debugPrint('EventService.createEvent failed: ${e.code} ${e.message}');
      }
      rethrow;
    }

    return event;
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
