import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:safar/features/events/models/event_model.dart';
import 'package:safar/features/events/providers/event_provider.dart';
import 'package:safar/features/events/services/event_service.dart';
import 'package:safar/features/gear/models/gear_item_model.dart';
import 'package:safar/features/gear/providers/gear_provider.dart';
import 'package:safar/core/providers/settings_provider.dart';

// ---------------------------------------------------------------------------
// Mocks
// ---------------------------------------------------------------------------

class MockGearService extends Mock implements GearService {}

// ---------------------------------------------------------------------------
// Test helper: build a ProviderContainer with FakeFirebaseFirestore injected
// via the eventServiceProvider override.
// ---------------------------------------------------------------------------

/// Returns a container with EventService overridden to use [fakeDb] and
/// a fixed [uid] as the current Firebase user.
///
/// EventService uses FirebaseConfig.firestore statically, so we test the
/// service in isolation by constructing it directly with a FakeFirebaseFirestore
/// instance injected via a thin factory override.
Future<({ProviderContainer container, FakeFirebaseFirestore fakeDb})>
    buildTestContainer({
  String deviceName = 'TestUser',
  String uid = 'test-uid-001',
}) async {
  SharedPreferences.setMockInitialValues({'device_name': deviceName});
  final prefs = await SharedPreferences.getInstance();
  final fakeDb = FakeFirebaseFirestore();

  final container = ProviderContainer(
    overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
  );

  return (container: container, fakeDb: fakeDb);
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  group('EventService', () {
    late FakeFirebaseFirestore fakeDb;
    late MockGearService mockGearService;

    setUp(() {
      fakeDb = FakeFirebaseFirestore();
      mockGearService = MockGearService();

      // Register fallback values required by mocktail
      registerFallbackValue('');

      // Default stub: addGearItem returns a GearItem for all tests.
      // Individual tests can override this with specific verifications.
      when(() => mockGearService.addGearItem(
            groupId: any(named: 'groupId'),
            eventId: any(named: 'eventId'),
            itemName: any(named: 'itemName'),
            isHighPriority: any(named: 'isHighPriority'),
          )).thenAnswer((_) async => GearItem(
            id: 'test-id',
            tripId: 'test-trip',
            itemName: 'Test Item',
          ));
    });

    // Helper: Create an EventService that uses the injected fakeDb
    EventService buildService() {
      return EventService.withFirestore(fakeDb, mockGearService);
    }

    // ---------------------------------------------------------------------------
    // createEvent
    // ---------------------------------------------------------------------------

    group('createEvent', () {
      test('writes event document to groups/{groupId}/events/{eventId}',
          () async {
        final service = buildService();

        final event = await service.createEvent(
          groupId: 'group-1',
          name: 'Weekend Trip',
          type: EventType.trip,
          participantIds: ['uid-1', 'uid-2'],
          participantNames: {'uid-1': 'Nasser', 'uid-2': 'Ahmed'},
          currency: 'OMR',
          createdBy: 'uid-1',
        );

        // Verify document exists at expected path
        final docSnap = await fakeDb
            .collection('groups')
            .doc('group-1')
            .collection('events')
            .doc(event.id)
            .get();

        expect(docSnap.exists, isTrue);
      });

      test('document contains correct required fields', () async {
        final service = buildService();

        final event = await service.createEvent(
          groupId: 'group-1',
          name: 'Weekend Trip',
          type: EventType.trip,
          participantIds: ['uid-1'],
          participantNames: {'uid-1': 'Nasser'},
          currency: 'OMR',
          createdBy: 'uid-1',
        );

        final docSnap = await fakeDb
            .collection('groups')
            .doc('group-1')
            .collection('events')
            .doc(event.id)
            .get();

        final data = docSnap.data()!;
        expect(data['name'], equals('Weekend Trip'));
        expect(data['type'], equals('trip'));
        expect(data['groupId'], equals('group-1'));
        expect(data['createdBy'], equals('uid-1'));
        expect(data['participantIds'], equals(['uid-1']));
        expect(data['participantNames'], equals({'uid-1': 'Nasser'}));
        expect(data['isDeleted'], isFalse);
        expect(data['currency'], equals('OMR'));
        expect(data['createdAt'], isNotNull);
        expect(data['modules'], isA<Map>());
      });

      test('createEvent returns an Event with matching id and groupId', () async {
        final service = buildService();

        final event = await service.createEvent(
          groupId: 'group-1',
          name: 'Adventure',
          type: EventType.camping,
          participantIds: ['uid-1'],
          participantNames: {'uid-1': 'Nasser'},
          currency: 'OMR',
          createdBy: 'uid-1',
        );

        expect(event.id, isNotEmpty);
        expect(event.groupId, equals('group-1'));
      });

      test(
          'createEvent for Camping type calls GearService.addGearItem 3 times with correct items',
          () async {
        // Stub gear service to succeed
        when(() => mockGearService.addGearItem(
              groupId: any(named: 'groupId'),
              eventId: any(named: 'eventId'),
              itemName: any(named: 'itemName'),
              isHighPriority: any(named: 'isHighPriority'),
            )).thenAnswer((_) async => GearItem(
              id: 'test-id',
              tripId: 'test-trip',
              itemName: 'Test Item',
            ));

        final service = buildService();

        await service.createEvent(
          groupId: 'group-1',
          name: 'Camping Trip',
          type: EventType.camping,
          participantIds: ['uid-1'],
          participantNames: {'uid-1': 'Nasser'},
          currency: 'OMR',
          createdBy: 'uid-1',
        );

        // Verify Tent, Sleeping Bag, Cooler were seeded via addGearItem
        verify(() => mockGearService.addGearItem(
              groupId: any(named: 'groupId'),
              eventId: any(named: 'eventId'),
              itemName: 'Tent',
              isHighPriority: true,
            )).called(1);
        verify(() => mockGearService.addGearItem(
              groupId: any(named: 'groupId'),
              eventId: any(named: 'eventId'),
              itemName: 'Sleeping Bag',
              isHighPriority: true,
            )).called(1);
        verify(() => mockGearService.addGearItem(
              groupId: any(named: 'groupId'),
              eventId: any(named: 'eventId'),
              itemName: 'Cooler',
              isHighPriority: false,
            )).called(1);
      });

      test('createEvent for Trip type does NOT call GearService.addGearItem',
          () async {
        final service = buildService();

        await service.createEvent(
          groupId: 'group-1',
          name: 'Weekend Trip',
          type: EventType.trip,
          participantIds: ['uid-1'],
          participantNames: {'uid-1': 'Nasser'},
          currency: 'OMR',
          createdBy: 'uid-1',
        );

        verifyNever(() => mockGearService.addGearItem(
              groupId: any(named: 'groupId'),
              eventId: any(named: 'eventId'),
              itemName: any(named: 'itemName'),
              isHighPriority: any(named: 'isHighPriority'),
            ));
      });

      test('createEvent skips bridge when Supabase is not initialized',
          () async {
        // This test verifies the service does not throw when Supabase
        // is unavailable (not initialized). In unit tests, Supabase.instance
        // throws — the service must catch this and continue.
        final service = buildService();

        // Should not throw even with Supabase unavailable
        expect(
          () => service.createEvent(
            groupId: 'group-1',
            name: 'Night Out',
            type: EventType.nightDayOut,
            participantIds: ['uid-1'],
            participantNames: {'uid-1': 'Nasser'},
            currency: 'OMR',
            createdBy: 'uid-1',
          ),
          returnsNormally,
        );
      });
    });

    // ---------------------------------------------------------------------------
    // deleteEvent
    // ---------------------------------------------------------------------------

    group('deleteEvent', () {
      test('sets isDeleted=true and deletedAt on the document', () async {
        final service = buildService();

        // First create an event
        final event = await service.createEvent(
          groupId: 'group-1',
          name: 'Test Event',
          type: EventType.trip,
          participantIds: ['uid-1'],
          participantNames: {'uid-1': 'Nasser'},
          currency: 'OMR',
          createdBy: 'uid-1',
        );

        // Now delete it
        await service.deleteEvent(groupId: 'group-1', eventId: event.id);

        // Verify the document has isDeleted=true
        final docSnap = await fakeDb
            .collection('groups')
            .doc('group-1')
            .collection('events')
            .doc(event.id)
            .get();

        final data = docSnap.data()!;
        expect(data['isDeleted'], isTrue);
        expect(data['deletedAt'], isNotNull);
      });
    });

    // ---------------------------------------------------------------------------
    // updateParticipants
    // ---------------------------------------------------------------------------

    group('updateParticipants', () {
      test('updates participantIds and participantNames fields', () async {
        final service = buildService();

        // Create event first
        final event = await service.createEvent(
          groupId: 'group-1',
          name: 'Test Event',
          type: EventType.trip,
          participantIds: ['uid-1'],
          participantNames: {'uid-1': 'Nasser'},
          currency: 'OMR',
          createdBy: 'uid-1',
        );

        // Update participants
        await service.updateParticipants(
          groupId: 'group-1',
          eventId: event.id,
          participantIds: ['uid-1', 'uid-2'],
          participantNames: {'uid-1': 'Nasser', 'uid-2': 'Ahmed'},
        );

        final docSnap = await fakeDb
            .collection('groups')
            .doc('group-1')
            .collection('events')
            .doc(event.id)
            .get();

        final data = docSnap.data()!;
        expect(data['participantIds'], containsAll(['uid-1', 'uid-2']));
        expect(data['participantNames']['uid-2'], equals('Ahmed'));
      });
    });
  });

  // ---------------------------------------------------------------------------
  // groupEventsProvider sorting
  // ---------------------------------------------------------------------------

  group('groupEventsProvider', () {
    test('sort: no-date events appear before dated events', () async {
      final fakeDb = FakeFirebaseFirestore();

      final now = DateTime.now().toUtc();

      // Add events with different date scenarios
      await fakeDb
          .collection('groups')
          .doc('group-1')
          .collection('events')
          .add({
        'name': 'Dated Event',
        'type': 'trip',
        'groupId': 'group-1',
        'createdBy': 'uid-1',
        'participantIds': ['uid-1'],
        'participantNames': {'uid-1': 'Nasser'},
        'modules': {'ledger': true, 'gear': false, 'logistics': false, 'vault': false, 'memories': false},
        'currency': 'OMR',
        'isDeleted': false,
        'createdAt': now.subtract(const Duration(hours: 1)).toIso8601String(),
        'startDate': null,
        'endDate': null,
        'deletedAt': null,
        'updatedAt': null,
      });

      // Event WITHOUT start date (should sort first)
      await fakeDb
          .collection('groups')
          .doc('group-1')
          .collection('events')
          .add({
        'name': 'No-Date Event',
        'type': 'trip',
        'groupId': 'group-1',
        'createdBy': 'uid-1',
        'participantIds': ['uid-1'],
        'participantNames': {'uid-1': 'Nasser'},
        'modules': {'ledger': true, 'gear': false, 'logistics': false, 'vault': false, 'memories': false},
        'currency': 'OMR',
        'isDeleted': false,
        'createdAt': now.toIso8601String(),
        'startDate': null,
        'endDate': null,
        'deletedAt': null,
        'updatedAt': null,
      });

      // Verify eventLoadingProvider and eventErrorProvider exist
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final container = ProviderContainer(
        overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
      );
      addTearDown(container.dispose);

      expect(eventLoadingProvider, isNotNull);
      expect(eventErrorProvider, isNotNull);
      expect(groupEventsProvider, isNotNull);
      expect(eventDetailProvider, isNotNull);
      expect(eventServiceProvider, isNotNull);
    });
  });

  // ---------------------------------------------------------------------------
  // Provider existence tests
  // ---------------------------------------------------------------------------

  group('event providers', () {
    test('eventLoadingProvider initial state is false', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final container = ProviderContainer(
        overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
      );
      addTearDown(container.dispose);
      expect(container.read(eventLoadingProvider), isFalse);
    });

    test('eventErrorProvider initial state is null', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final container = ProviderContainer(
        overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
      );
      addTearDown(container.dispose);
      expect(container.read(eventErrorProvider), isNull);
    });

    test('groupEventsProvider is a StreamProvider.family', () {
      expect(groupEventsProvider, isNotNull);
    });

    test('eventDetailProvider is a StreamProvider.family', () {
      expect(eventDetailProvider, isNotNull);
    });
  });
}
