import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:mocktail/mocktail.dart';
import 'package:safar/core/services/storage_exceptions.dart';
import 'package:safar/core/services/storage_gateway.dart';
import 'package:safar/features/memories/services/memory_service.dart';

class _MockGateway extends Mock implements StorageGateway {}

class _MockHttpClient extends Mock implements http.Client {}

class _FakeUri extends Fake implements Uri {}

/// [MemoryService] tests covering the gateway-routed paths. `uploadPhoto`
/// requires a real Firebase user; the integration_test covers that end-to-end.
void main() {
  setUpAll(() {
    registerFallbackValue(_FakeUri());
  });

  group('MemoryService.listMemoriesWithUrls', () {
    test('delegates to gateway', () async {
      final gateway = _MockGateway();
      final service = MemoryService.withFirestore(
        FakeFirebaseFirestore(),
        gateway: gateway,
        httpClient: _MockHttpClient(),
      );
      when(
        () => gateway.listMemoriesWithUrls(
          groupId: any(named: 'groupId'),
          eventId: any(named: 'eventId'),
        ),
      ).thenAnswer((_) async => [
            MemoryWithUrl(
              fields: {'id': 'm1', 'storagePath': 'trip-memories/e1/x.jpg'},
              signedUrl: 'https://signed/m1',
              expiresAt: DateTime.now().add(const Duration(hours: 1)),
            ),
          ]);

      final result = await service.listMemoriesWithUrls(
        groupId: 'g1',
        eventId: 'e1',
      );

      expect(result, hasLength(1));
      expect(result.first.signedUrl, 'https://signed/m1');
      verify(() => gateway.listMemoriesWithUrls(groupId: 'g1', eventId: 'e1'))
          .called(1);
    });
  });

  group('MemoryService.deleteMemory', () {
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
      final service = MemoryService.withFirestore(
        firestore,
        gateway: gateway,
        httpClient: httpClient,
      );
      await firestore
          .collection('groups/g1/events/e1/memories')
          .doc('m1')
          .set({'id': 'm1', 'storagePath': 'trip-memories/e1/x.jpg'});

      when(
        () => gateway.deleteStorageObject(
          storagePath: any(named: 'storagePath'),
          groupId: any(named: 'groupId'),
        ),
      ).thenAnswer((_) async {});

      final ok = await service.deleteMemory(
        groupId: 'g1',
        eventId: 'e1',
        memoryId: 'm1',
        storagePath: 'trip-memories/e1/x.jpg',
      );

      expect(ok, isTrue);
      verify(
        () => gateway.deleteStorageObject(
          storagePath: 'trip-memories/e1/x.jpg',
          groupId: 'g1',
        ),
      ).called(1);
      final doc = await firestore
          .collection('groups/g1/events/e1/memories')
          .doc('m1')
          .get();
      expect(doc.exists, isFalse);
    });

    test('returns false when gateway throws', () async {
      final service = MemoryService.withFirestore(
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
      final ok = await service.deleteMemory(
        groupId: 'g1',
        eventId: 'e1',
        memoryId: 'm1',
        storagePath: 'trip-memories/e1/x.jpg',
      );
      expect(ok, isFalse);
    });
  });
}
