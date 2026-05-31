import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:safar/features/activity/services/activity_service.dart';

void main() {
  group('ActivityService (Firestore)', () {
    late FakeFirebaseFirestore fakeFirestore;
    late ActivityService service;

    setUp(() {
      fakeFirestore = FakeFirebaseFirestore();
      service = ActivityService.withFirestore(fakeFirestore);
    });

    const groupId = 'g1';
    const eventId = 'e1';

    group('addActivityLog', () {
      test(
        'writes activity log document to groups/{groupId}/events/{eventId}/activity_logs',
        () async {
          await service.addActivityLog(
            groupId: groupId,
            eventId: eventId,
            category: 'MONEY',
            action: 'CREATE',
            actorId: 'user1',
            actorName: 'Alice',
            metadata: {'amount': '10.500'},
          );

          final snap = await fakeFirestore
              .collection('groups')
              .doc(groupId)
              .collection('events')
              .doc(eventId)
              .collection('activity_logs')
              .get();

          expect(snap.docs.length, equals(1));
          final data = snap.docs.first.data();
          expect(data['category'], equals('MONEY'));
          expect(data['actorId'], equals('user1'));
          expect(data['eventId'], equals(eventId));
          expect(data['metadata'], containsPair('amount', '10.500'));
        },
      );
    });

    group('fetchActivityPageRaw (cursor pagination)', () {
      Future<void> seedLogs(int n) async {
        for (var i = 0; i < n; i++) {
          final ts = DateTime.utc(2026, 1, 1).add(Duration(seconds: i)); // strictly increasing
          await fakeFirestore
              .collection('groups').doc(groupId)
              .collection('events').doc(eventId)
              // doc-id padded only for stable debugging sort; ordering is by createdAt
              .collection('activity_logs').doc('a${i.toString().padLeft(4, '0')}')
              .set({
                'id': 'a$i', 'eventId': eventId, 'category': 'MONEY', 'eventType': 'CREATE',
                'logText': 'log $i', 'actorId': 'u1', 'actorName': 'Alice',
                'metadata': <String, dynamic>{}, 'createdAt': ts.toIso8601String(),
              });
        }
      }

      test('pages forward with startAfter cursor, newest-first, no overlap', () async {
        await seedLogs(120);

        final p1 = await service.fetchActivityPageRaw(groupId, eventId, limit: 50);
        expect(p1.docs, hasLength(50));
        expect(p1.docs.first.data()['logText'], equals('log 119')); // newest first

        final p2 = await service.fetchActivityPageRaw(
          groupId, eventId, startAfter: p1.docs.last, limit: 50);
        expect(p2.docs, hasLength(50));

        final p3 = await service.fetchActivityPageRaw(
          groupId, eventId, startAfter: p2.docs.last, limit: 50);
        expect(p3.docs, hasLength(20)); // 120 - 100

        final ids = [...p1.docs, ...p2.docs, ...p3.docs].map((d) => d.id).toList();
        expect(ids.toSet(), hasLength(120)); // zero overlap across pages
      });

      test('returns empty for a log-free event', () async {
        final page = await service.fetchActivityPageRaw('g', 'no-logs', limit: 50);
        expect(page.docs, isEmpty);
      });
    });
  });
}
