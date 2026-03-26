import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../../core/services/firestore_repository.dart';
import '../../gear/providers/gear_provider.dart';
import '../models/event_model.dart';

/// Service for Event CRUD operations against Firestore.
///
/// Extends [FirestoreRepository] so all Firestore access flows through the
/// base class `db` getter (MIG-05). Constructor takes a [Ref] for
/// Riverpod integration and an optional [GearService] for testability.
///
/// Events are stored as a subcollection:
///   `groups/{groupId}/events/{eventId}`
///
/// The Supabase bridge pattern (D-22) has been removed in Plan 04-05.
/// Events are now Firestore-only.
class EventService extends FirestoreRepository {
  final Ref? _ref;
  final GearService? _gearServiceOverride;

  /// Default constructor for Riverpod-managed use.
  EventService(Ref ref)
      : _ref = ref,
        _gearServiceOverride = null,
        super();

  /// Test-only constructor: inject FakeFirebaseFirestore and a mock GearService.
  @visibleForTesting
  EventService.withFirestore(FirebaseFirestore firestoreDb, GearService gearService)
      : _ref = null,
        _gearServiceOverride = gearService,
        super.withFirestore(firestoreDb);

  GearService get _gearService {
    final override = _gearServiceOverride;
    if (override != null) return override;
    final ref = _ref;
    if (ref == null) throw StateError('No Ref or GearService override');
    return ref.read(gearServiceProvider);
  }

  /// Create a new event in Firestore.
  ///
  /// Steps:
  /// 1. Generate a UUID for the eventId.
  /// 2. Write event document to `groups/{groupId}/events/{eventId}`.
  /// 3. If type is Camping, seed preset gear items via GearService.
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
    required String currency,
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
      currency: currency,
      isDeleted: false,
      createdAt: now,
    );

    // Write to Firestore
    await db
        .collection('groups')
        .doc(groupId)
        .collection('events')
        .doc(eventId)
        .set(event.toFirestoreMap());

    // Seed camping gear presets via Firestore-backed GearService.
    if (type == EventType.camping) {
      await _seedCampingGear(groupId, eventId);
    }

    return event;
  }

  /// Seed the three camping preset gear items using the Firestore GearService API.
  ///
  /// Per D-13: Tent (high priority), Sleeping Bag (high priority), Cooler
  /// (normal priority) are added to the event's gear list on creation.
  ///
  /// Uses [GearService.addGearItem] (groupId, eventId, itemName) per the
  /// Firestore-backed GearService API from Plan 04-02.
  Future<void> _seedCampingGear(String groupId, String eventId) async {
    await _gearService.addGearItem(
      groupId: groupId,
      eventId: eventId,
      itemName: 'Tent',
      isHighPriority: true,
    );
    await _gearService.addGearItem(
      groupId: groupId,
      eventId: eventId,
      itemName: 'Sleeping Bag',
      isHighPriority: true,
    );
    await _gearService.addGearItem(
      groupId: groupId,
      eventId: eventId,
      itemName: 'Cooler',
      isHighPriority: false,
    );
  }

  /// Soft-delete an event (sets isDeleted=true).
  ///
  /// Per D-09: hard deletes are forbidden on events to preserve financial
  /// records. Uses FieldValue.serverTimestamp() for deletedAt per Pitfall 3.
  Future<void> deleteEvent({
    required String groupId,
    required String eventId,
  }) async {
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
  }

  /// Update event metadata (name and/or dates).
  ///
  /// Only non-null fields are updated. Always updates [updatedAt].
  Future<void> updateEvent({
    required String groupId,
    required String eventId,
    String? name,
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    final updateMap = <String, dynamic>{
      'updatedAt': FieldValue.serverTimestamp(),
    };
    if (name != null) updateMap['name'] = name;
    if (startDate != null) {
      updateMap['startDate'] = Timestamp.fromDate(startDate);
    }
    if (endDate != null) {
      updateMap['endDate'] = Timestamp.fromDate(endDate);
    }

    await db
        .collection('groups')
        .doc(groupId)
        .collection('events')
        .doc(eventId)
        .update(updateMap);
  }

  /// Update the participant list for an event.
  ///
  /// Replaces participantIds and participantNames entirely (not merged).
  /// Per D-10: only group members can be selected as participants.
  Future<void> updateParticipants({
    required String groupId,
    required String eventId,
    required List<String> participantIds,
    required Map<String, String> participantNames,
  }) async {
    await db
        .collection('groups')
        .doc(groupId)
        .collection('events')
        .doc(eventId)
        .update({
      'participantIds': participantIds,
      'participantNames': participantNames,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }
}
