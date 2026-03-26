import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:safar/features/vault/models/document_model.dart';
import 'package:safar/features/vault/services/document_service.dart';

void main() {
  group('DocumentService', () {
    late FakeFirebaseFirestore fakeFirestore;
    late DocumentService service;

    setUp(() {
      fakeFirestore = FakeFirebaseFirestore();
      service = DocumentService.withFirestore(fakeFirestore);
    });

    group('watchDocuments', () {
      test('returns empty list when no documents exist', () async {
        final stream = service.watchDocuments('group1', 'event1');
        final result = await stream.first;
        expect(result, isEmpty);
      });

      test('returns documents from Firestore snapshot', () async {
        // Seed Firestore with a test document
        final now = DateTime.now().toUtc();
        await fakeFirestore
            .collection('groups')
            .doc('group1')
            .collection('events')
            .doc('event1')
            .collection('documents')
            .doc('doc1')
            .set({
          'id': 'doc1',
          'eventId': 'event1',
          'uploaderId': 'user1',
          'storagePath': 'trip-documents/event1/123-test.pdf',
          'fileName': 'test.pdf',
          'fileSize': 12345,
          'mimeType': 'application/pdf',
          'createdAt': now.toIso8601String(),
        });

        final stream = service.watchDocuments('group1', 'event1');
        final result = await stream.first;

        expect(result, hasLength(1));
        expect(result.first.id, equals('doc1'));
        expect(result.first.fileName, equals('test.pdf'));
        expect(result.first.mimeType, equals('application/pdf'));
      });

      test('returns multiple documents ordered by createdAt descending',
          () async {
        final older =
            DateTime.now().toUtc().subtract(const Duration(hours: 1));
        final newer = DateTime.now().toUtc();

        await fakeFirestore
            .collection('groups/group1/events/event1/documents')
            .doc('older')
            .set({
          'id': 'older',
          'eventId': 'event1',
          'uploaderId': 'user1',
          'storagePath': 'path/older.pdf',
          'fileName': 'older.pdf',
          'fileSize': 100,
          'mimeType': 'application/pdf',
          'createdAt': older.toIso8601String(),
        });

        await fakeFirestore
            .collection('groups/group1/events/event1/documents')
            .doc('newer')
            .set({
          'id': 'newer',
          'eventId': 'event1',
          'uploaderId': 'user1',
          'storagePath': 'path/newer.pdf',
          'fileName': 'newer.pdf',
          'fileSize': 200,
          'mimeType': 'application/pdf',
          'createdAt': newer.toIso8601String(),
        });

        final stream = service.watchDocuments('group1', 'event1');
        final result = await stream.first;

        expect(result, hasLength(2));
        // newest first (descending createdAt)
        expect(result.first.id, equals('newer'));
        expect(result.last.id, equals('older'));
      });
    });

    group('writeMetadataToFirestore', () {
      test('writes document metadata to correct Firestore path', () async {
        final now = DateTime.now().toUtc();
        final docData = {
          'id': 'test-id',
          'eventId': 'event1',
          'uploaderId': 'user1',
          'storagePath': 'trip-documents/event1/123-myfile.pdf',
          'fileName': 'myfile.pdf',
          'fileSize': 50000,
          'mimeType': 'application/pdf',
          'createdAt': now.toIso8601String(),
        };

        await service.writeMetadataToFirestore(
          groupId: 'group1',
          eventId: 'event1',
          documentId: 'test-id',
          data: docData,
        );

        final doc = await fakeFirestore
            .collection('groups/group1/events/event1/documents')
            .doc('test-id')
            .get();

        expect(doc.exists, isTrue);
        expect(doc.data()!['fileName'], equals('myfile.pdf'));
        expect(doc.data()!['storagePath'],
            equals('trip-documents/event1/123-myfile.pdf'));
        expect(doc.data()!['uploaderId'], equals('user1'));
      });
    });

    group('deleteDocumentMetadata', () {
      test('removes the Firestore metadata document', () async {
        // Seed document
        await fakeFirestore
            .collection('groups/group1/events/event1/documents')
            .doc('doc-to-delete')
            .set({
          'id': 'doc-to-delete',
          'eventId': 'event1',
          'uploaderId': 'user1',
          'storagePath': 'path/file.pdf',
          'fileName': 'file.pdf',
          'fileSize': 1000,
          'mimeType': 'application/pdf',
          'createdAt': DateTime.now().toIso8601String(),
        });

        // Verify it exists before deletion
        final beforeDelete = await fakeFirestore
            .collection('groups/group1/events/event1/documents')
            .doc('doc-to-delete')
            .get();
        expect(beforeDelete.exists, isTrue);

        // Delete Firestore metadata only (Storage tested in integration)
        await service.deleteDocumentMetadata(
          groupId: 'group1',
          eventId: 'event1',
          documentId: 'doc-to-delete',
        );

        // Verify it is gone
        final afterDelete = await fakeFirestore
            .collection('groups/group1/events/event1/documents')
            .doc('doc-to-delete')
            .get();
        expect(afterDelete.exists, isFalse);
      });
    });

    group('Document.fromFirestore / toFirestore', () {
      test('round-trip preserves all fields', () {
        final now = DateTime.utc(2024, 1, 15, 10, 30, 0);
        final original = Document(
          id: 'doc123',
          tripId: 'event456',
          uploaderId: 'user789',
          fileUrl: 'trip-documents/event456/ts-report.pdf',
          fileName: 'report.pdf',
          fileSize: 102400,
          mimeType: 'application/pdf',
          createdAt: now,
        );

        final firestoreData = original.toFirestore();
        final restored =
            Document.fromFirestore({...firestoreData, 'id': 'doc123'});

        expect(restored.id, equals('doc123'));
        expect(restored.tripId, equals('event456'));
        expect(restored.uploaderId, equals('user789'));
        expect(restored.fileUrl,
            equals('trip-documents/event456/ts-report.pdf'));
        expect(restored.fileName, equals('report.pdf'));
        expect(restored.fileSize, equals(102400));
        expect(restored.mimeType, equals('application/pdf'));
        expect(restored.createdAt, equals(now));
      });

      test('fromFirestore handles missing optional fields gracefully', () {
        final data = {
          'id': 'doc999',
          'eventId': 'event1',
          'uploaderId': null,
          'storagePath': 'path/file.txt',
          'fileName': 'file.txt',
          'fileSize': null,
          'mimeType': null,
          'createdAt': DateTime.now().toIso8601String(),
        };

        final doc = Document.fromFirestore(data);
        expect(doc.id, equals('doc999'));
        expect(doc.uploaderId, isNull);
        expect(doc.fileSize, isNull);
        expect(doc.mimeType, isNull);
      });
    });
  });
}
