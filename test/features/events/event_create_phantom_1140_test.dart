// test/features/events/event_create_phantom_1140_test.dart
//
// #1140: stageEvent folds the event_created activity row into the SAME
// WriteBatch as the event doc, so a create denied at replay persists no phantom
// "created X" row. Service-level proof of the atomic coupling (batch atomicity
// itself — denied ⇒ neither leg — is inherited from Firestore and pinned by the
// settlement #929 stub-batch tests).

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:safar/features/events/models/event_model.dart';
import 'package:safar/features/events/services/event_service.dart';

void main() {
  late FakeFirebaseFirestore fake;
  late EventService service;

  setUp(() {
    fake = FakeFirebaseFirestore();
    service = EventService.withFirestore(fake);
  });

  Future<Map<String, dynamic>?> onlyActivity() async {
    final snap =
        await fake.collection('groups').doc('g1').collection('activity').get();
    expect(snap.docs.length, lessThanOrEqualTo(1));
    return snap.docs.isEmpty ? null : snap.docs.single.data();
  }

  test(
    'stageEvent with activity params writes the event AND exactly one '
    'evt_created_<id> activity row, in one batch',
    () async {
      final staged = service.stageEvent(
        groupId: 'g1',
        name: 'Beach Day',
        type: EventType.camping,
        participantIds: const ['uid-alice'],
        participantNames: const {'uid-alice': 'Alice'},
        createdBy: 'uid-alice',
        activityActorId: 'uid-alice',
        activityActorName: 'Alice (former member)', // must be sanitized
      );
      await staged.ack;

      // Event doc landed.
      final eventDoc = await fake
          .collection('groups')
          .doc('g1')
          .collection('events')
          .doc(staged.event.id)
          .get();
      expect(eventDoc.exists, isTrue);
      expect(eventDoc.data()!['name'], equals('Beach Day'));

      // Exactly one activity row, keyed and sanitized.
      final act = await onlyActivity();
      expect(act, isNotNull);
      expect(act!['id'], equals('evt_created_${staged.event.id}'));
      expect(act['type'], equals('event_created'));
      expect(act['actorId'], equals('uid-alice'));
      expect(act['actorName'], equals('Alice')); // suffix stripped
      expect(act['description'], equals('created Beach Day'));
      expect(act['metadata'], containsPair('eventName', 'Beach Day'));
    },
  );

  test(
    'stageEvent WITHOUT activity params is the legacy single-write (no activity)',
    () async {
      final staged = service.stageEvent(
        groupId: 'g1',
        name: 'Solo Trip',
        type: EventType.trip,
        participantIds: const ['uid-alice'],
        participantNames: const {'uid-alice': 'Alice'},
        createdBy: 'uid-alice',
      );
      await staged.ack;

      final eventDoc = await fake
          .collection('groups')
          .doc('g1')
          .collection('events')
          .doc(staged.event.id)
          .get();
      expect(eventDoc.exists, isTrue);
      expect(await onlyActivity(), isNull);
    },
  );
}
