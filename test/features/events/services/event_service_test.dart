import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:safar/features/events/models/event_model.dart';
import 'package:safar/features/events/services/event_service.dart';

const _groupId = 'group-1';
const _eventId = 'evt-1';

DocumentReference<Map<String, dynamic>> _eventRef(FakeFirebaseFirestore db) =>
    db.collection('groups').doc(_groupId).collection('events').doc(_eventId);

Future<void> _seedEvent(FakeFirebaseFirestore db) async {
  await _eventRef(db).set({
    'id': _eventId,
    'groupId': _groupId,
    'name': 'Beach Day',
    'type': 'trip',
    'createdBy': 'uid-creator',
    'participantIds': ['uid-creator', 'uid-existing'],
    'participantNames': {
      'uid-creator': 'Alice',
      'uid-existing': 'Bob',
    },
    'modules': const <String, dynamic>{},
    'isDeleted': false,
    'createdAt': '2026-03-01T00:00:00Z',
  });
}

void main() {
  group('EventService.createEvent', () {
    test('writes a doc with toFirestoreMap and returns the populated Event',
        () async {
      final db = FakeFirebaseFirestore();
      final service = EventService.withFirestore(db);

      final event = await service.createEvent(
        groupId: _groupId,
        name: 'Beach Day',
        type: EventType.trip,
        participantIds: const ['u1', 'u2'],
        participantNames: const {'u1': 'Alice', 'u2': 'Bob'},
        createdBy: 'u1',
        startDate: DateTime.utc(2026, 4, 1),
        endDate: DateTime.utc(2026, 4, 5),
      );

      expect(event.id, isNotEmpty);
      expect(event.groupId, _groupId);
      expect(event.name, 'Beach Day');
      expect(event.type, EventType.trip);
      expect(event.createdBy, 'u1');
      expect(event.participantIds, ['u1', 'u2']);
      expect(event.modules.ledger, isTrue);

      final snap = await db
          .collection('groups')
          .doc(_groupId)
          .collection('events')
          .doc(event.id)
          .get();
      expect(snap.exists, isTrue);
      expect(snap.data()!['name'], 'Beach Day');
      expect(snap.data()!['type'], 'trip');
    });

    test('uses explicit modules override when provided', () async {
      final db = FakeFirebaseFirestore();
      final service = EventService.withFirestore(db);

      final event = await service.createEvent(
        groupId: _groupId,
        name: 'X',
        type: EventType.custom,
        participantIds: const ['u1'],
        participantNames: const {'u1': 'Alice'},
        createdBy: 'u1',
        modules: const EventModules(ledger: false),
      );

      expect(event.modules.ledger, isFalse);
    });
  });

  group('EventService.deleteEvent', () {
    test('soft-deletes event by setting isDeleted=true', () async {
      final db = FakeFirebaseFirestore();
      await _seedEvent(db);
      final service = EventService.withFirestore(db);

      await service.deleteEvent(groupId: _groupId, eventId: _eventId);

      final snap = await _eventRef(db).get();
      expect(snap.data()!['isDeleted'], isTrue);
      expect(snap.data()!['deletedAt'], isNotNull);
      expect(snap.data()!['updatedAt'], isNotNull);
    });
  });

  group('EventService.updateEvent', () {
    test('only writes the fields that are provided', () async {
      final db = FakeFirebaseFirestore();
      await _seedEvent(db);
      final service = EventService.withFirestore(db);

      await service.updateEvent(
        groupId: _groupId,
        eventId: _eventId,
        name: 'Renamed',
      );

      final data = (await _eventRef(db).get()).data()!;
      expect(data['name'], 'Renamed');
      expect(data['startDate'], isNull);
      expect(data['endDate'], isNull);
      expect(data['description'], isNull);
      expect(data['updatedAt'], isNotNull);
    });

    test('writes startDate, endDate, description when provided', () async {
      final db = FakeFirebaseFirestore();
      await _seedEvent(db);
      final service = EventService.withFirestore(db);

      await service.updateEvent(
        groupId: _groupId,
        eventId: _eventId,
        startDate: DateTime.utc(2026, 4, 1),
        endDate: DateTime.utc(2026, 4, 5),
        description: 'Updated description',
      );

      final data = (await _eventRef(db).get()).data()!;
      expect(data['startDate'], isA<Timestamp>());
      expect(data['endDate'], isA<Timestamp>());
      expect(data['description'], 'Updated description');
    });

    test('updateEvent with no field changes only writes updatedAt', () async {
      final db = FakeFirebaseFirestore();
      await _seedEvent(db);
      final service = EventService.withFirestore(db);

      await service.updateEvent(groupId: _groupId, eventId: _eventId);

      final data = (await _eventRef(db).get()).data()!;
      expect(data['updatedAt'], isNotNull);
      expect(data['name'], 'Beach Day'); // unchanged
    });
  });

  group('EventService.closeEvent (#723)', () {
    test('sets isClosed/closedBy/closedAt/updatedAt', () async {
      final db = FakeFirebaseFirestore();
      await _seedEvent(db);
      final service = EventService.withFirestore(db);

      await service.closeEvent(
        groupId: _groupId,
        eventId: _eventId,
        closedBy: 'uid-creator',
      );

      final data = (await _eventRef(db).get()).data()!;
      expect(data['isClosed'], isTrue);
      expect(data['closedBy'], 'uid-creator');
      expect(data['closedAt'], isNotNull);
      expect(data['updatedAt'], isNotNull);
      // close must not touch soft-delete state
      expect(data['isDeleted'], isFalse);
    });

    test('writes spendingSnapshot map when provided (#766)', () async {
      final db = FakeFirebaseFirestore();
      await _seedEvent(db);
      final service = EventService.withFirestore(db);

      await service.closeEvent(
        groupId: _groupId,
        eventId: _eventId,
        closedBy: 'uid-creator',
        spendingSnapshot: const {
          'v': 1,
          'participantCount': 2,
          'totals': {'OMR': 100000},
        },
      );

      final data = (await _eventRef(db).get()).data()!;
      expect(data['isClosed'], isTrue);
      expect(data['spendingSnapshot'], isA<Map>());
      expect((data['spendingSnapshot'] as Map)['participantCount'], 2);
    });

    test('omits spendingSnapshot when not provided (#766)', () async {
      final db = FakeFirebaseFirestore();
      await _seedEvent(db);
      final service = EventService.withFirestore(db);

      await service.closeEvent(
        groupId: _groupId,
        eventId: _eventId,
        closedBy: 'uid-creator',
      );

      final data = (await _eventRef(db).get()).data()!;
      expect(data.containsKey('spendingSnapshot'), isFalse);
    });
  });

  group('EventService.reopenEvent (#723)', () {
    test('clears isClosed/closedAt/closedBy and bumps updatedAt', () async {
      final db = FakeFirebaseFirestore();
      await _seedEvent(db);
      final service = EventService.withFirestore(db);
      await service.closeEvent(
        groupId: _groupId,
        eventId: _eventId,
        closedBy: 'uid-creator',
      );

      await service.reopenEvent(groupId: _groupId, eventId: _eventId);

      final data = (await _eventRef(db).get()).data()!;
      expect(data['isClosed'], isFalse);
      expect(data['closedAt'], isNull);
      expect(data['closedBy'], isNull);
      expect(data['updatedAt'], isNotNull);
    });

    test('deletes spendingSnapshot on reopen (#766)', () async {
      final db = FakeFirebaseFirestore();
      await _seedEvent(db);
      final service = EventService.withFirestore(db);
      await service.closeEvent(
        groupId: _groupId,
        eventId: _eventId,
        closedBy: 'uid-creator',
        spendingSnapshot: const {'v': 1, 'participantCount': 2},
      );
      // sanity: present right after close
      expect(
        ((await _eventRef(db).get()).data()!).containsKey('spendingSnapshot'),
        isTrue,
      );

      await service.reopenEvent(groupId: _groupId, eventId: _eventId);

      final data = (await _eventRef(db).get()).data()!;
      // FieldValue.delete() removes the key entirely (null would fail the
      // opaque `is map` rules guard on a future close).
      expect(data.containsKey('spendingSnapshot'), isFalse);
    });
  });
}
