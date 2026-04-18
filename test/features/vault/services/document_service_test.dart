import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:mocktail/mocktail.dart';
import 'package:safar/core/services/storage_exceptions.dart';
import 'package:safar/core/services/storage_gateway.dart';
import 'package:safar/features/vault/services/document_service.dart';

class _MockGateway extends Mock implements StorageGateway {}

class _MockHttpClient extends Mock implements http.Client {}

class _FakeUri extends Fake implements Uri {}

/// Unit tests for [DocumentService] migration to [StorageGateway].
///
/// `uploadFile` requires a live [FirebaseConfig.currentUser] which depends on
/// `Firebase.initializeApp()` — exercised instead in the integration_test.
/// These tests cover the delete + download-URL paths exhaustively.
void main() {
  setUpAll(() {
    registerFallbackValue(_FakeUri());
  });

  group('DocumentService.deleteDocument', () {
    late FakeFirebaseFirestore firestore;
    late _MockGateway gateway;
    late _MockHttpClient httpClient;

    setUp(() {
      firestore = FakeFirebaseFirestore();
      gateway = _MockGateway();
      httpClient = _MockHttpClient();
    });

    test('routes through gateway.deleteStorageObject and removes metadata',
        () async {
      final service = DocumentService.withFirestore(
        firestore,
        gateway: gateway,
        httpClient: httpClient,
      );
      await firestore
          .collection('groups/g1/events/e1/documents')
          .doc('d1')
          .set({'id': 'd1', 'storagePath': 'trip-documents/e1/x.pdf'});

      when(
        () => gateway.deleteStorageObject(
          storagePath: any(named: 'storagePath'),
          groupId: any(named: 'groupId'),
        ),
      ).thenAnswer((_) async {});

      final ok = await service.deleteDocument(
        groupId: 'g1',
        eventId: 'e1',
        documentId: 'd1',
        storagePath: 'trip-documents/e1/x.pdf',
      );

      expect(ok, isTrue);
      verify(
        () => gateway.deleteStorageObject(
          storagePath: 'trip-documents/e1/x.pdf',
          groupId: 'g1',
        ),
      ).called(1);
      final doc = await firestore
          .collection('groups/g1/events/e1/documents')
          .doc('d1')
          .get();
      expect(doc.exists, isFalse);
    });

    test('returns false when gateway throws', () async {
      final service = DocumentService.withFirestore(
        firestore,
        gateway: gateway,
        httpClient: httpClient,
      );
      when(
        () => gateway.deleteStorageObject(
          storagePath: any(named: 'storagePath'),
          groupId: any(named: 'groupId'),
        ),
      ).thenThrow(const StorageException.notMember());
      final ok = await service.deleteDocument(
        groupId: 'g1',
        eventId: 'e1',
        documentId: 'd1',
        storagePath: 'trip-documents/e1/x.pdf',
      );
      expect(ok, isFalse);
    });
  });

  group('DocumentService.getDownloadUrl (via listDocumentsWithUrls)', () {
    late FakeFirebaseFirestore firestore;
    late _MockGateway gateway;
    late _MockHttpClient httpClient;

    setUp(() {
      firestore = FakeFirebaseFirestore();
      gateway = _MockGateway();
      httpClient = _MockHttpClient();
    });

    test('returns signedUrl when storagePath matches', () async {
      final service = DocumentService.withFirestore(
        firestore,
        gateway: gateway,
        httpClient: httpClient,
      );
      when(
        () => gateway.listDocumentsWithUrls(
          groupId: any(named: 'groupId'),
          eventId: any(named: 'eventId'),
        ),
      ).thenAnswer((_) async => [
            DocumentWithUrl(
              fields: {'storagePath': 'trip-documents/e1/x.pdf'},
              signedUrl: 'https://signed/x',
              expiresAt: DateTime.now().add(const Duration(hours: 1)),
            ),
          ]);
      final url = await service.getDownloadUrl(
        groupId: 'g1',
        eventId: 'e1',
        storagePath: 'trip-documents/e1/x.pdf',
      );
      expect(url, 'https://signed/x');
    });

    test('returns null when no match', () async {
      final service = DocumentService.withFirestore(
        firestore,
        gateway: gateway,
        httpClient: httpClient,
      );
      when(
        () => gateway.listDocumentsWithUrls(
          groupId: any(named: 'groupId'),
          eventId: any(named: 'eventId'),
        ),
      ).thenAnswer((_) async => const []);
      final url = await service.getDownloadUrl(
        groupId: 'g1',
        eventId: 'e1',
        storagePath: 'trip-documents/e1/missing.pdf',
      );
      expect(url, isNull);
    });

    test('returns null on StorageException', () async {
      final service = DocumentService.withFirestore(
        firestore,
        gateway: gateway,
        httpClient: httpClient,
      );
      when(
        () => gateway.listDocumentsWithUrls(
          groupId: any(named: 'groupId'),
          eventId: any(named: 'eventId'),
        ),
      ).thenThrow(const StorageException.notMember());
      final url = await service.getDownloadUrl(
        groupId: 'g1',
        eventId: 'e1',
        storagePath: 'trip-documents/e1/x.pdf',
      );
      expect(url, isNull);
    });
  });

  group('DocumentService.listDocumentsWithUrls', () {
    test('delegates to gateway', () async {
      final gateway = _MockGateway();
      final service = DocumentService.withFirestore(
        FakeFirebaseFirestore(),
        gateway: gateway,
        httpClient: _MockHttpClient(),
      );
      when(
        () => gateway.listDocumentsWithUrls(
          groupId: any(named: 'groupId'),
          eventId: any(named: 'eventId'),
        ),
      ).thenAnswer((_) async => const []);
      final result = await service.listDocumentsWithUrls(
        groupId: 'g1',
        eventId: 'e1',
      );
      expect(result, isEmpty);
      verify(() => gateway.listDocumentsWithUrls(groupId: 'g1', eventId: 'e1'))
          .called(1);
    });
  });
}
