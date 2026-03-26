import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:safar/features/memories/models/memory_model.dart';
import 'package:safar/features/memories/services/memory_service.dart';

void main() {
  group('MemoryService', () {
    late FakeFirebaseFirestore fakeFirestore;
    late MemoryService service;

    setUp(() {
      fakeFirestore = FakeFirebaseFirestore();
      service = MemoryService.withFirestore(fakeFirestore);
    });

    group('watchMemories', () {
      test('returns empty list when no memories exist', () async {
        final stream = service.watchMemories('group1', 'event1');
        final result = await stream.first;
        expect(result, isEmpty);
      });

      test('returns memories from Firestore snapshot', () async {
        final now = DateTime.now().toUtc();
        await fakeFirestore
            .collection('groups')
            .doc('group1')
            .collection('events')
            .doc('event1')
            .collection('memories')
            .doc('mem1')
            .set({
          'id': 'mem1',
          'eventId': 'event1',
          'uploadedBy': 'user1',
          'storagePath': 'trip-memories/event1/123.jpg',
          'caption': 'Beach sunset',
          'createdAt': now.toIso8601String(),
        });

        final stream = service.watchMemories('group1', 'event1');
        final result = await stream.first;

        expect(result, hasLength(1));
        expect(result.first.id, equals('mem1'));
        expect(result.first.caption, equals('Beach sunset'));
        expect(result.first.uploadedBy, equals('user1'));
      });

      test('returns multiple memories ordered by createdAt descending',
          () async {
        final older =
            DateTime.now().toUtc().subtract(const Duration(hours: 2));
        final newer = DateTime.now().toUtc();

        await fakeFirestore
            .collection('groups/group1/events/event1/memories')
            .doc('older')
            .set({
          'id': 'older',
          'eventId': 'event1',
          'uploadedBy': 'user1',
          'storagePath': 'path/older.jpg',
          'caption': null,
          'createdAt': older.toIso8601String(),
        });

        await fakeFirestore
            .collection('groups/group1/events/event1/memories')
            .doc('newer')
            .set({
          'id': 'newer',
          'eventId': 'event1',
          'uploadedBy': 'user2',
          'storagePath': 'path/newer.jpg',
          'caption': 'New photo',
          'createdAt': newer.toIso8601String(),
        });

        final stream = service.watchMemories('group1', 'event1');
        final result = await stream.first;

        expect(result, hasLength(2));
        // newest first (descending createdAt)
        expect(result.first.id, equals('newer'));
        expect(result.last.id, equals('older'));
      });
    });

    group('writeMetadataToFirestore', () {
      test('writes memory metadata to correct Firestore path', () async {
        final now = DateTime.now().toUtc();
        final memData = {
          'id': 'mem-test',
          'eventId': 'event1',
          'uploadedBy': 'user1',
          'storagePath': 'trip-memories/event1/ts.jpg',
          'caption': 'Mountain view',
          'createdAt': now.toIso8601String(),
        };

        await service.writeMetadataToFirestore(
          groupId: 'group1',
          eventId: 'event1',
          memoryId: 'mem-test',
          data: memData,
        );

        final doc = await fakeFirestore
            .collection('groups/group1/events/event1/memories')
            .doc('mem-test')
            .get();

        expect(doc.exists, isTrue);
        expect(doc.data()!['storagePath'],
            equals('trip-memories/event1/ts.jpg'));
        expect(doc.data()!['caption'], equals('Mountain view'));
        expect(doc.data()!['uploadedBy'], equals('user1'));
      });
    });

    group('deleteMemoryMetadata', () {
      test('removes the Firestore memory metadata document', () async {
        // Seed memory
        await fakeFirestore
            .collection('groups/group1/events/event1/memories')
            .doc('mem-to-delete')
            .set({
          'id': 'mem-to-delete',
          'eventId': 'event1',
          'uploadedBy': 'user1',
          'storagePath': 'path/photo.jpg',
          'caption': null,
          'createdAt': DateTime.now().toIso8601String(),
        });

        // Verify it exists
        final beforeDelete = await fakeFirestore
            .collection('groups/group1/events/event1/memories')
            .doc('mem-to-delete')
            .get();
        expect(beforeDelete.exists, isTrue);

        // Delete Firestore metadata only
        await service.deleteMemoryMetadata(
          groupId: 'group1',
          eventId: 'event1',
          memoryId: 'mem-to-delete',
        );

        // Verify it is gone
        final afterDelete = await fakeFirestore
            .collection('groups/group1/events/event1/memories')
            .doc('mem-to-delete')
            .get();
        expect(afterDelete.exists, isFalse);
      });
    });

    group('Memory.fromFirestore / toFirestore', () {
      test('round-trip preserves all fields', () {
        final now = DateTime.utc(2024, 3, 10, 14, 0, 0);
        final original = Memory(
          id: 'mem123',
          tripId: 'event456',
          uploadedBy: 'user789',
          storagePath: 'trip-memories/event456/sunset.jpg',
          caption: 'Golden hour',
          createdAt: now,
        );

        final firestoreData = original.toFirestore();
        final restored =
            Memory.fromFirestore({...firestoreData, 'id': 'mem123'});

        expect(restored.id, equals('mem123'));
        expect(restored.tripId, equals('event456'));
        expect(restored.uploadedBy, equals('user789'));
        expect(restored.storagePath,
            equals('trip-memories/event456/sunset.jpg'));
        expect(restored.caption, equals('Golden hour'));
        expect(restored.createdAt, equals(now));
      });

      test('fromFirestore handles null caption gracefully', () {
        final data = {
          'id': 'mem999',
          'eventId': 'event1',
          'uploadedBy': 'user1',
          'storagePath': 'path/photo.jpg',
          'caption': null,
          'createdAt': DateTime.now().toIso8601String(),
        };

        final mem = Memory.fromFirestore(data);
        expect(mem.id, equals('mem999'));
        expect(mem.caption, isNull);
        expect(mem.tripId, equals('event1'));
      });
    });
  });
}
