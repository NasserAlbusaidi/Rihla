import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../../core/config/firebase_config.dart';
import '../../../core/config/supabase_config.dart';
import '../../gear/providers/gear_provider.dart';
import '../models/event_model.dart';

/// Service for Event CRUD operations against Firestore.
///
/// Mirrors the [GroupService] pattern. Constructor takes a [Ref] for
/// Riverpod integration and an optional [GearService] for testability.
///
/// Events are stored as a subcollection:
///   `groups/{groupId}/events/{eventId}`
///
/// Each created event also creates a matching Supabase trip record (the
/// bridge pattern from D-22). Bridge failure does NOT throw — it logs
/// and continues so events can be created even during Supabase outages.
class EventService {
  final Ref? _ref;
  final FirebaseFirestore _db;
  final GearService? _gearServiceOverride;

  /// Default constructor for Riverpod-managed use.
  EventService(Ref ref)
      : _ref = ref,
        _db = FirebaseConfig.firestore,
        _gearServiceOverride = null,
        _skipBridgeInTest = false;

  /// Test-only constructor: inject FakeFirebaseFirestore and a mock GearService.
  ///
  /// When using this constructor, the Supabase bridge is skipped entirely
  /// and [_skipBridgeInTest] is set to true so gear seeding still happens
  /// for Camping events (bridge is treated as succeeded in test context).
  @visibleForTesting
  EventService.withFirestore(FirebaseFirestore db, GearService gearService)
      : _ref = null,
        _db = db,
        _gearServiceOverride = gearService,
        _skipBridgeInTest = true;

  // Private flag used by the test constructor to skip bridge + still seed gear
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
  }) async {
    const uuid = Uuid();
    final eventId = uuid.v4();
    final bridgeTripId = eventId; // Same UUID per plan spec
    final now = DateTime.now().toUtc();
    final modules = EventModules.forType(type);

    final event = Event(
      id: eventId,
      name: name,
      type: type,
      groupId: groupId,
      createdBy: createdBy,
      participantIds: List.unmodifiable(participantIds),
      participantNames: Map.unmodifiable(participantNames),
      modules: modules,
      startDate: startDate,
      endDate: endDate,
      currency: currency,
      isDeleted: false,
      createdAt: now,
      bridgeTripId: bridgeTripId,
    );

    // Step 1: Write to Firestore
    await _db
        .collection('groups')
        .doc(groupId)
        .collection('events')
        .doc(eventId)
        .set(event.toFirestoreMap());

    // Step 2: Attempt Supabase bridge trip creation (fire-and-forget).
    // In test mode (_skipBridgeInTest=true) the bridge is skipped entirely
    // but gear seeding still proceeds so GearService calls can be verified.
    bool bridgeSucceeded = false;
    if (_skipBridgeInTest) {
      // Test context: treat bridge as succeeded for gear-seeding purposes
      bridgeSucceeded = true;
    } else {
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
          await _createBridgeTrip(
            eventId: eventId,
            name: name,
            modules: modules,
            currency: currency,
            startDate: startDate,
            endDate: endDate,
            supabaseUid: supabaseUid,
            participantIds: participantIds,
            participantNames: participantNames,
          );
          bridgeSucceeded = true;
          debugPrint('[EventService] Bridge trip created for event $eventId');
        }
      } catch (e, st) {
        // Bridge failure must NOT throw — log and continue
        debugPrint('[EventService] Bridge trip creation failed: $e\n$st');
      }
    }

    // Step 3: Seed camping gear presets only if bridge succeeded.
    // Per Pitfall 4: only seed if bridge created the Supabase trip,
    // since gear items are written to Supabase via GearService.
    if (type == EventType.camping && bridgeSucceeded) {
      await _seedCampingGear(eventId);
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
      'source': 'event_bridge',
      if (startDate != null)
        'start_date': startDate.toIso8601String().split('T').first,
      if (endDate != null)
        'end_date': endDate.toIso8601String().split('T').first,
    });

    // Insert participants for each participantId
    for (final uid in participantIds) {
      final displayName = participantNames[uid] ?? 'Unknown';
      try {
        await SupabaseConfig.client.from('participants').insert({
          'trip_id': eventId,
          'user_id': uid,
          'display_name': displayName,
          'role': 'member',
          'joined_at': DateTime.now().toIso8601String(),
        });
      } catch (e) {
        debugPrint('[EventService] Failed to insert bridge participant $uid: $e');
      }
    }
  }

  /// Seed the three camping preset gear items.
  ///
  /// Per D-13: Tent (high priority), Sleeping Bag (high priority), Cooler
  /// (normal priority) are added to the event's gear list on creation.
  Future<void> _seedCampingGear(String eventId) async {
    await _gearService.addItem(
      tripId: eventId,
      itemName: 'Tent',
      isHighPriority: true,
    );
    await _gearService.addItem(
      tripId: eventId,
      itemName: 'Sleeping Bag',
      isHighPriority: true,
    );
    await _gearService.addItem(
      tripId: eventId,
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
    await _db
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

    await _db
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
    await _db
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
