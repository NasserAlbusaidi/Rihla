import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:safar/features/activity/services/activity_service.dart';

const _groupId = 'g1';
const _eventId = 'e1';

CollectionReference<Map<String, dynamic>> _logsCollection(
  FakeFirebaseFirestore db,
) =>
    db
        .collection('groups')
        .doc(_groupId)
        .collection('events')
        .doc(_eventId)
        .collection('activity_logs');

void main() {
  group('ActivityService', () {
    late FakeFirebaseFirestore db;
    late ActivityService service;

    setUp(() {
      db = FakeFirebaseFirestore();
      service = ActivityService.withFirestore(db);
    });

    test('addActivityLog writes a doc with expected fields', () async {
      await service.addActivityLog(
        groupId: _groupId,
        eventId: _eventId,
        category: 'MONEY',
        action: 'paid 10 OMR',
        actorId: 'uid-1',
        actorName: 'Alice',
        metadata: const {'amount': '10.000'},
      );

      final snapshot = await _logsCollection(db).get();
      expect(snapshot.docs, hasLength(1));
      final data = snapshot.docs.first.data();
      expect(data['eventId'], _eventId);
      expect(data['category'], 'MONEY');
      expect(data['eventType'], 'paid 10 OMR');
      expect(data['logText'], 'Alice paid 10 OMR');
      expect(data['actorId'], 'uid-1');
      expect(data['actorName'], 'Alice');
      expect(data['metadata'], {'amount': '10.000'});
      expect(data['createdAt'], isA<String>());
    });

    test('addActivityLog defaults metadata to empty map when null', () async {
      await service.addActivityLog(
        groupId: _groupId,
        eventId: _eventId,
        category: 'MONEY',
        action: 'paid',
        actorId: 'uid-1',
        actorName: 'Bob',
      );

      final docs = await _logsCollection(db).get();
      expect(docs.docs.first.data()['metadata'], isEmpty);
    });

    test('addActivityLog falls back to "null" prefix when actorName is null',
        () async {
      await service.addActivityLog(
        groupId: _groupId,
        eventId: _eventId,
        category: 'MONEY',
        action: 'paid',
        actorId: 'uid-1',
      );

      final docs = await _logsCollection(db).get();
      expect(docs.docs.first.data()['logText'], 'null paid');
    });
  });
}
