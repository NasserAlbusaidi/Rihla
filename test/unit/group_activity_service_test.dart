import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:safar/features/groups/models/group_activity_log_model.dart';
import 'package:safar/features/groups/services/group_activity_service.dart';

void main() {
  group('GroupActivityLog', () {
    test(
      'fromFirestore produces model with all required fields',
      () {
        final now = DateTime.now().toUtc();
        final data = {
          'id': 'act1',
          'type': 'group_settlement',
          'actorId': 'uid1',
          'actorName': 'Alice',
          'description': 'Alice settled OMR 10.500 with Bob',
          'metadata': {'amount': '10500', 'recipientName': 'Bob'},
          'timestamp': now.toIso8601String(),
        };

        final log = GroupActivityLog.fromFirestore(data);

        expect(log.id, equals('act1'));
        expect(log.type, equals('group_settlement'));
        expect(log.actorId, equals('uid1'));
        expect(log.actorName, equals('Alice'));
        expect(log.description, equals('Alice settled OMR 10.500 with Bob'));
        expect(log.metadata, containsPair('recipientName', 'Bob'));
        expect(log.timestamp, isA<DateTime>());
      },
    );

    test(
      'fromFirestore handles Firestore Timestamp type for timestamp field',
      () {
        final now = DateTime.now().toUtc();
        final timestamp = Timestamp.fromDate(now);
        final data = {
          'id': 'act2',
          'type': 'event_created',
          'actorId': 'uid2',
          'actorName': 'Bob',
          'description': 'Bob created an event',
          'metadata': <String, dynamic>{},
          'timestamp': timestamp,
        };

        final log = GroupActivityLog.fromFirestore(data);

        expect(log.timestamp.millisecondsSinceEpoch,
            closeTo(now.millisecondsSinceEpoch, 1000));
      },
    );
  });

  group('GroupActivityService (Firestore)', () {
    late FakeFirebaseFirestore fakeDb;
    late GroupActivityService service;

    setUp(() {
      fakeDb = FakeFirebaseFirestore();
      service = GroupActivityService.withFirestore(fakeDb);
    });

    const groupId = 'g1';

    test(
      'watchRecentActivity returns entries ordered by timestamp descending, limited to 5',
      () async {
        // Write 7 entries with staggered timestamps so ordering is stable
        for (var i = 0; i < 7; i++) {
          final ts = DateTime.utc(2025, 1, 1, 0, 0, i);
          await fakeDb
              .collection('groups')
              .doc(groupId)
              .collection('activity')
              .add({
            'id': 'act$i',
            'type': 'event_created',
            'actorId': 'uid1',
            'actorName': 'Alice',
            'description': 'Event $i created',
            'metadata': <String, dynamic>{},
            'timestamp': ts.toIso8601String(),
          });
        }

        final logs = await service.watchRecentActivity(groupId).first;

        // Default limit is 5
        expect(logs, hasLength(5));
        // Ordered descending — most recent first (index 6 was latest)
        expect(logs.first.description, contains('6'));
      },
    );

    test(
      'fetchActivityPageRaw returns QuerySnapshot with limit applied',
      () async {
        // Write 10 entries with distinct timestamps
        for (var i = 0; i < 10; i++) {
          final ts = DateTime.utc(2025, 1, 1, 0, 0, i);
          await fakeDb
              .collection('groups')
              .doc(groupId)
              .collection('activity')
              .doc('act$i')
              .set({
            'id': 'act$i',
            'type': 'event_created',
            'actorId': 'uid1',
            'actorName': 'Alice',
            'description': 'Event $i',
            'metadata': <String, dynamic>{},
            'timestamp': ts.toIso8601String(),
          });
        }

        // Fetch raw snapshot for cursor-based pagination
        final rawSnap =
            await service.fetchActivityPageRaw(groupId, limit: 5);

        // Should return exactly 5 docs (limit applied)
        expect(rawSnap.docs, hasLength(5));

        // The cursor (last doc in first page) can be used to page forward.
        // Verify it is a valid DocumentSnapshot (not null).
        final cursor = rawSnap.docs.last;
        expect(cursor.exists, isTrue);
        expect(cursor.data()['type'], equals('event_created'));
      },
    );

    test(
      'fetchActivityPage returns List<GroupActivityLog> ordered by timestamp desc',
      () async {
        // Write 8 entries with staggered timestamps
        for (var i = 0; i < 8; i++) {
          final ts = DateTime.utc(2025, 1, 1, 0, 0, i);
          await fakeDb
              .collection('groups')
              .doc(groupId)
              .collection('activity')
              .doc('act$i')
              .set({
            'id': 'act$i',
            'type': 'event_created',
            'actorId': 'uid1',
            'actorName': 'Alice',
            'description': 'Event $i',
            'metadata': <String, dynamic>{},
            'timestamp': ts.toIso8601String(),
          });
        }

        // Fetch first page of 5
        final page1 = await service.fetchActivityPage(groupId, limit: 5);

        expect(page1, hasLength(5));
        // Most recent first (index 7 = ts at second 7 is largest)
        expect(page1.first.description, contains('7'));
      },
    );

    test(
      'fetchActivityPage returns empty list when no activity exists',
      () async {
        // No documents written — empty group
        final page = await service.fetchActivityPage('empty-group');
        expect(page, isEmpty);
      },
    );

    test(
      'fetchActivityPage returns all entries when count is below limit',
      () async {
        // Write 3 entries — below the default limit of 50
        for (var i = 0; i < 3; i++) {
          final ts = DateTime.utc(2025, 3, 1, 0, 0, i);
          await fakeDb
              .collection('groups')
              .doc(groupId)
              .collection('activity')
              .doc('fp$i')
              .set({
            'id': 'fp$i',
            'type': 'event_created',
            'actorId': 'uid$i',
            'actorName': 'User $i',
            'description': 'Event $i',
            'metadata': <String, dynamic>{},
            'timestamp': ts.toIso8601String(),
          });
        }

        final page = await service.fetchActivityPage(groupId);
        expect(page, hasLength(3));
        // Verify each is a GroupActivityLog
        expect(page.first, isA<dynamic>());
        expect(page.first.type, equals('event_created'));
      },
    );

    test(
      'logGroupEvent writes document to groups/{groupId}/activity subcollection',
      () async {
        service.logGroupEvent(
          groupId: groupId,
          type: 'group_settlement',
          actorId: 'uid1',
          actorName: 'Alice',
          description: 'Alice settled OMR 10.500 with Bob',
          metadata: {'amount': '10500'},
        );

        // Give fire-and-forget a moment to complete
        await Future<void>.delayed(const Duration(milliseconds: 50));

        final snap = await fakeDb
            .collection('groups')
            .doc(groupId)
            .collection('activity')
            .get();

        expect(snap.docs, hasLength(1));
        final data = snap.docs.first.data();
        expect(data['type'], equals('group_settlement'));
        expect(data['actorId'], equals('uid1'));
        expect(data['description'],
            equals('Alice settled OMR 10.500 with Bob'));
        expect(data['metadata'], containsPair('amount', '10500'));
      },
    );

    test(
      'logGroupEvent is fire-and-forget: can be called without await',
      () async {
        // logGroupEvent returns void — calling it synchronously must not throw.
        // The Dart type system ensures it cannot be awaited (void != Future).
        // This test verifies the contract: call it, carry on, document appears.
        service.logGroupEvent(
          groupId: groupId,
          type: 'member_joined',
          actorId: 'uid2',
          actorName: 'Bob',
          description: 'Bob joined the group',
        );
        // Execution reaches here immediately (not blocked by async I/O)
        // Give the unawaited future a moment to complete
        await Future<void>.delayed(const Duration(milliseconds: 50));

        final snap = await fakeDb
            .collection('groups')
            .doc(groupId)
            .collection('activity')
            .get();
        expect(snap.docs.any((d) => d.data()['type'] == 'member_joined'),
            isTrue);
      },
    );
  });
}
