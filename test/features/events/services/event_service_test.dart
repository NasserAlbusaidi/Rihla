import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
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
  group('EventService.addParticipant', () {
    test('appends to participantIds and writes participantNames key',
        () async {
      final db = FakeFirebaseFirestore();
      await _seedEvent(db);

      final service = EventService.withFirestore(db);
      await service.addParticipant(
        groupId: _groupId,
        eventId: _eventId,
        participantId: 'uid-new',
        displayName: 'Carol',
      );

      final snap = await _eventRef(db).get();
      final data = snap.data()!;

      expect(
        (data['participantIds'] as List).cast<String>(),
        containsAll(['uid-creator', 'uid-existing', 'uid-new']),
      );
      expect(data['participantNames'], {
        'uid-creator': 'Alice',
        'uid-existing': 'Bob',
        'uid-new': 'Carol',
      });
      expect(data['updatedAt'], isNotNull);
    });

    test('is a no-op-ish second add (arrayUnion dedupes)', () async {
      final db = FakeFirebaseFirestore();
      await _seedEvent(db);
      final service = EventService.withFirestore(db);

      await service.addParticipant(
        groupId: _groupId,
        eventId: _eventId,
        participantId: 'uid-existing',
        displayName: 'Bob',
      );

      final snap = await _eventRef(db).get();
      final ids = (snap.data()!['participantIds'] as List).cast<String>();
      expect(ids.where((id) => id == 'uid-existing').length, 1);
    });
  });

  group('EventService.removeParticipant', () {
    test('removes from participantIds and deletes the participantNames key',
        () async {
      final db = FakeFirebaseFirestore();
      await _seedEvent(db);
      final service = EventService.withFirestore(db);

      await service.removeParticipant(
        groupId: _groupId,
        eventId: _eventId,
        participantId: 'uid-existing',
      );

      final snap = await _eventRef(db).get();
      final data = snap.data()!;

      expect(
        (data['participantIds'] as List).cast<String>(),
        ['uid-creator'],
      );
      expect(data['participantNames'], {'uid-creator': 'Alice'});
      expect(data['updatedAt'], isNotNull);
    });
  });
}
