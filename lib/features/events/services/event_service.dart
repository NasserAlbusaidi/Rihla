import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../../core/config/supabase_config.dart';
import '../../../core/services/cache_service.dart';
import '../../../core/services/firestore_repository.dart';
import '../../gear/providers/gear_provider.dart';
import '../../trip/models/trip_model.dart';
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
/// Each created event also creates a matching Supabase trip record (the
/// bridge pattern from D-22). Bridge failure does NOT throw — it logs
/// and continues so events can be created even during Supabase outages.
class EventService extends FirestoreRepository {
  final Ref? _ref;
  final GearService? _gearServiceOverride;

  /// Default constructor for Riverpod-managed use.
  EventService(Ref ref)
      : _ref = ref,
        _gearServiceOverride = null,
        _skipBridgeInTest = false,
        super();

  /// Test-only constructor: inject FakeFirebaseFirestore and a mock GearService.
  ///
  /// When using this constructor, the Supabase bridge is skipped entirely
  /// and [_skipBridgeInTest] is set to true so gear seeding still happens
  /// for Camping events.
  @visibleForTesting
  EventService.withFirestore(FirebaseFirestore firestoreDb, GearService gearService)
      : _ref = null,
        _gearServiceOverride = gearService,
        _skipBridgeInTest = true,
        super.withFirestore(firestoreDb);

  // Private flag used by the test constructor to skip bridge
  final bool _skipBridgeInTest;

  GearService get _gearService {
    final override = _gearServiceOverride;
    if (override != null) return override;
    final ref = _ref;
    if (ref == null) throw StateError('No Ref or GearService override');
    return ref.read(gearServiceProvider);
  }

  /// Generate a unique 8-character bridge invite code.
  ///
  /// Uses the same allowed-character set as GroupService._generateInviteCode
  /// but 8 chars instead of 6 to reduce collision probability.
  String _generateBridgeCode() {
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    final random = Random.secure();
    return List.generate(8, (_) => chars[random.nextInt(chars.length)]).join();
  }

  /// Create a new event in Firestore.
  ///
  /// Steps:
  /// 1. Generate a UUID for both eventId and bridgeTripId (same value).
  /// 2. Write event document to `groups/{groupId}/events/{eventId}`.
  /// 3. Attempt Supabase bridge trip creation (fire-and-forget).
  ///    - Skipped if Supabase is not authenticated.
  ///    - Bridge failure is caught and logged — does NOT throw.
  /// 4. If type is Camping and bridge succeeded, seed preset gear items.
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
    final bridgeTripId = eventId; // Same UUID per plan spec
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
      bridgeTripId: bridgeTripId,
    );

    // Step 1: Write to Firestore
    await db
        .collection('groups')
        .doc(groupId)
        .collection('events')
        .doc(eventId)
        .set(event.toFirestoreMap());

    // Step 2: Attempt Supabase bridge trip creation (fire-and-forget).
    // In test mode (_skipBridgeInTest=true) the bridge is skipped entirely.
    if (!_skipBridgeInTest) {
      try {
        // Check Supabase authentication safely — Supabase.instance may not be
        // initialized in Firebase-only mode or during cold starts.
        bool isAuthenticated = false;
        String? supabaseUid;
        try {
          isAuthenticated = SupabaseConfig.isAuthenticated;
          supabaseUid = SupabaseConfig.currentUser?.id;
        } catch (initError) {
          // Supabase not initialized (Firebase-only mode)
          debugPrint(
              '[EventService] Supabase not available — skipping bridge: $initError');
        }

        if (!isAuthenticated || supabaseUid == null) {
          debugPrint(
              '[EventService] Supabase not authenticated — skipping bridge');
        } else {
          debugPrint('[BRIDGE] Creating bridge trip:');
          debugPrint('[BRIDGE]   eventId=$eventId');
          debugPrint('[BRIDGE]   supabaseUid=$supabaseUid');
          debugPrint('[BRIDGE]   firebaseUid(createdBy)=$createdBy');
          debugPrint('[BRIDGE]   participantIds=$participantIds');
          debugPrint('[BRIDGE]   participantNames=$participantNames');
          await _createBridgeTrip(
            eventId: eventId,
            name: name,
            modules: resolvedModules,
            currency: currency,
            startDate: startDate,
            endDate: endDate,
            supabaseUid: supabaseUid,
            createdByFirebaseUid: createdBy,
            participantIds: participantIds,
            participantNames: participantNames,
          );
          debugPrint('[BRIDGE] Bridge trip INSERT succeeded for $eventId');

          // Cache bridge trip to SQLite so userTripsProvider can find it.
          if (_ref != null) {
            final bridgeTrip = Trip(
              id: bridgeTripId,
              name: name,
              inviteCode: '',
              leaderId: supabaseUid,
              modules: TripModules(
                docs: resolvedModules.vault,
                gear: resolvedModules.gear,
                itinerary: false,
                logistics: resolvedModules.logistics,
              ),
              currency: currency,
              startDate: startDate,
              endDate: endDate,
              createdAt: now,
            );
            debugPrint('[BRIDGE] Caching trip to SQLite: id=${bridgeTrip.id}, leaderId=${bridgeTrip.leaderId}');
            await CacheService.cacheTrip(bridgeTrip);
            debugPrint('[BRIDGE] Bridge trip cached to SQLite');
          }
        }
      } catch (e, st) {
        // Bridge failure must NOT throw — log and continue
        debugPrint('[EventService] Bridge trip creation failed: $e\n$st');
      }
    }

    // Step 3: Seed camping gear presets.
    // Gear items are now written to Firestore via GearService (Plan 04-02),
    // so seeding proceeds regardless of Supabase bridge state.
    if (type == EventType.camping) {
      await _seedCampingGear(groupId, eventId);
    }

    return event;
  }

  /// Creates a Supabase trip record mirroring the Firestore event.
  ///
  /// Per Pitfall 1: uses Supabase UID (NOT Firebase UID) for leader_id.
  Future<void> _createBridgeTrip({
    required String eventId,
    required String name,
    required EventModules modules,
    required String currency,
    required String supabaseUid,
    required String createdByFirebaseUid,
    required List<String> participantIds,
    required Map<String, String> participantNames,
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    final inviteCode = _generateBridgeCode();

    await SupabaseConfig.client.from('trips').insert({
      'id': eventId,
      'name': name,
      'invite_code': inviteCode,
      'leader_id': supabaseUid,
      'modules': {
        'docs': modules.vault,
        'gear': modules.gear,
        'itinerary': false,
        'logistics': modules.logistics,
      },
      'currency': currency,
      if (startDate != null)
        'start_date': startDate.toIso8601String().split('T').first,
      if (endDate != null)
        'end_date': endDate.toIso8601String().split('T').first,
    });

    debugPrint('[BRIDGE] Trip row inserted. Now inserting participants...');
    debugPrint('[BRIDGE]   createdByFirebaseUid=$createdByFirebaseUid');

    for (final uid in participantIds) {
      final isCreator = uid == createdByFirebaseUid;
      final displayName = participantNames[uid] ?? 'Unknown';
      final effectiveUserId = isCreator ? supabaseUid : null;
      debugPrint('[BRIDGE]   participant: firebaseUid=$uid, isCreator=$isCreator, '
          'effectiveUserId=$effectiveUserId, name=$displayName, '
          'role=${isCreator ? "LEADER" : "MEMBER"}');
      try {
        await SupabaseConfig.client.from('participants').insert({
          'trip_id': eventId,
          'user_id': effectiveUserId,
          'display_name': displayName,
          'role': isCreator ? 'LEADER' : 'MEMBER',
          'joined_at': DateTime.now().toIso8601String(),
        });
        debugPrint('[BRIDGE]   → INSERT OK');
      } catch (e) {
        debugPrint('[BRIDGE]   → INSERT FAILED: $e');
      }
    }
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
