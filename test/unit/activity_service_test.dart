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

    group('watchActivityLogs', () {
      test(
        'returns a stream of activity logs from Firestore subcollection',
        () async {
          await service.addActivityLog(
            groupId: groupId,
            eventId: eventId,
            category: 'GEAR',
            action: 'CREATE',
            actorId: 'user1',
            actorName: 'Alice',
          );

          final logs = await service
              .watchActivityLogs(groupId, eventId)
              .first;

          expect(logs.length, equals(1));
          expect(logs.first.category, equals('GEAR'));
          expect(logs.first.tripId, equals(eventId));
          expect(logs.first.actorName, equals('Alice'));
        },
      );

      test(
        'orders logs by createdAt descending',
        () async {
          // Add two logs with different times
          await service.addActivityLog(
            groupId: groupId,
            eventId: eventId,
            category: 'GEAR',
            action: 'CREATE',
            actorId: 'user1',
            actorName: 'Alice',
          );

          // Small delay to ensure different timestamps
          await Future<void>.delayed(const Duration(milliseconds: 10));

          await service.addActivityLog(
            groupId: groupId,
            eventId: eventId,
            category: 'MONEY',
            action: 'CREATE',
            actorId: 'user2',
            actorName: 'Bob',
          );

          final logs = await service
              .watchActivityLogs(groupId, eventId)
              .first;

          expect(logs.length, equals(2));
          // Most recent first — MONEY was added last so it should be first
          expect(logs.first.category, equals('MONEY'));
          expect(logs.last.category, equals('GEAR'));
        },
      );
    });

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

    test(
      'Filtering for MONEY category works on the stream output',
      () async {
        await service.addActivityLog(
          groupId: groupId,
          eventId: eventId,
          category: 'GEAR',
          action: 'CREATE',
          actorId: 'user1',
        );

        await service.addActivityLog(
          groupId: groupId,
          eventId: eventId,
          category: 'MONEY',
          action: 'CREATE',
          actorId: 'user1',
        );

        final allLogs = await service
            .watchActivityLogs(groupId, eventId)
            .first;

        final moneyLogs =
            allLogs.where((log) => log.category == 'MONEY').toList();

        expect(allLogs.length, equals(2));
        expect(moneyLogs.length, equals(1));
        expect(moneyLogs.first.category, equals('MONEY'));
      },
    );
  });
}
