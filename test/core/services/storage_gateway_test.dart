import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:safar/core/services/storage_exceptions.dart';
import 'package:safar/core/services/storage_gateway.dart';

class _MockFunctions extends Mock implements FirebaseFunctions {}

class _MockCallable extends Mock implements HttpsCallable {}

class _MockResult extends Mock implements HttpsCallableResult {}

void main() {
  late _MockFunctions functions;
  late _MockCallable callable;
  late StorageGateway gateway;

  setUpAll(() {
    registerFallbackValue(<String, dynamic>{});
  });

  setUp(() {
    functions = _MockFunctions();
    callable = _MockCallable();
    when(() => functions.httpsCallable(any())).thenReturn(callable);
    gateway = StorageGateway(functions: functions);
  });

  group('getSignedUploadUrl error mapping', () {
    test('permission-denied -> StorageException.notMember', () async {
      when(() => callable.call(any())).thenThrow(
        FirebaseFunctionsException(code: 'permission-denied', message: 'nope'),
      );
      await expectLater(
        gateway.getSignedUploadUrl(
          bucket: 'documents',
          groupId: 'g1',
          eventId: 'e1',
          fileName: 'a.pdf',
          contentType: 'application/pdf',
          sizeBytes: 100,
        ),
        throwsA(
          isA<StorageException>().having(
            (e) => e.toString(),
            'toString',
            contains('Not a member'),
          ),
        ),
      );
    });

    test('unauthenticated -> notSignedIn', () async {
      when(() => callable.call(any())).thenThrow(
        FirebaseFunctionsException(code: 'unauthenticated', message: 'x'),
      );
      await expectLater(
        gateway.getSignedUploadUrl(
          bucket: 'documents',
          groupId: 'g1',
          eventId: 'e1',
          fileName: 'a.pdf',
          contentType: 'application/pdf',
          sizeBytes: 100,
        ),
        throwsA(
          isA<StorageException>().having(
            (e) => e.toString(),
            'toString',
            contains('Sign-in'),
          ),
        ),
      );
    });

    test('not-found -> missing', () async {
      when(() => callable.call(any())).thenThrow(
        FirebaseFunctionsException(code: 'not-found', message: 'gone'),
      );
      await expectLater(
        gateway.getSignedUploadUrl(
          bucket: 'documents',
          groupId: 'g1',
          eventId: 'e1',
          fileName: 'a.pdf',
          contentType: 'application/pdf',
          sizeBytes: 100,
        ),
        throwsA(
          isA<StorageException>().having(
            (e) => e.toString(),
            'toString',
            contains('not found'),
          ),
        ),
      );
    });

    test('invalid-argument -> invalidInput', () async {
      when(() => callable.call(any())).thenThrow(
        FirebaseFunctionsException(code: 'invalid-argument', message: 'bad'),
      );
      await expectLater(
        gateway.getSignedUploadUrl(
          bucket: 'documents',
          groupId: 'g1',
          eventId: 'e1',
          fileName: 'a.pdf',
          contentType: 'application/pdf',
          sizeBytes: 100,
        ),
        throwsA(
          isA<StorageException>().having(
            (e) => e.toString(),
            'toString',
            contains('Invalid input'),
          ),
        ),
      );
    });

    test('happy path returns SignedUpload', () async {
      final result = _MockResult();
      final expires =
          DateTime.now().add(const Duration(minutes: 15)).toIso8601String();
      when(() => result.data).thenReturn({
        'uploadUrl': 'https://signed.example/x',
        'storagePath': 'trip-documents/e1/123-a.pdf',
        'expiresAt': expires,
      });
      when(() => callable.call(any())).thenAnswer((_) async => result);
      final signed = await gateway.getSignedUploadUrl(
        bucket: 'documents',
        groupId: 'g1',
        eventId: 'e1',
        fileName: 'a.pdf',
        contentType: 'application/pdf',
        sizeBytes: 100,
      );
      expect(signed.uploadUrl, startsWith('https://'));
      expect(signed.storagePath, contains('trip-documents/e1/'));
      expect(signed.expiresAt.isAfter(DateTime.now()), isTrue);
    });
  });

  group('list + delete', () {
    test('listDocumentsWithUrls parses response', () async {
      final result = _MockResult();
      when(() => result.data).thenReturn({
        'documents': [
          {
            'id': 'd1',
            'fileName': 'a.pdf',
            'storagePath': 'trip-documents/e1/1-a.pdf',
            'signedUrl': 'http://u1',
            'expiresAt': '2026-12-31T00:00:00.000Z',
          },
        ],
      });
      when(() => callable.call(any())).thenAnswer((_) async => result);
      final docs =
          await gateway.listDocumentsWithUrls(groupId: 'g1', eventId: 'e1');
      expect(docs, hasLength(1));
      expect(docs.first.signedUrl, 'http://u1');
      expect(docs.first.fields['fileName'], 'a.pdf');
      expect(docs.first.fields['id'], 'd1');
      expect(docs.first.fields.containsKey('signedUrl'), isFalse);
      expect(docs.first.fields.containsKey('expiresAt'), isFalse);
    });

    test('listMemoriesWithUrls parses response', () async {
      final result = _MockResult();
      when(() => result.data).thenReturn({
        'memories': [
          {
            'id': 'm1',
            'storagePath': 'trip-memories/e1/1-x.jpg',
            'signedUrl': 'http://m1',
            'expiresAt': '2026-12-31T00:00:00.000Z',
          },
        ],
      });
      when(() => callable.call(any())).thenAnswer((_) async => result);
      final mems =
          await gateway.listMemoriesWithUrls(groupId: 'g1', eventId: 'e1');
      expect(mems, hasLength(1));
      expect(mems.first.signedUrl, 'http://m1');
      expect(mems.first.fields['id'], 'm1');
    });

    test('deleteStorageObject resolves void', () async {
      final result = _MockResult();
      when(() => result.data).thenReturn({'deleted': true});
      when(() => callable.call(any())).thenAnswer((_) async => result);
      await gateway.deleteStorageObject(
        storagePath: 'trip-documents/e1/x.pdf',
        groupId: 'g1',
      );
      verify(
        () => callable.call({
          'storagePath': 'trip-documents/e1/x.pdf',
          'groupId': 'g1',
        }),
      ).called(1);
    });

    test('receipts upload without expenseId surfaces invalidInput from server',
        () async {
      when(() => callable.call(any())).thenThrow(
        FirebaseFunctionsException(
          code: 'invalid-argument',
          message: 'expenseId required',
        ),
      );
      await expectLater(
        gateway.getSignedUploadUrl(
          bucket: 'receipts',
          groupId: 'g1',
          eventId: 'e1',
          fileName: 'r.png',
          contentType: 'image/png',
          sizeBytes: 100,
        ),
        throwsA(
          isA<StorageException>().having(
            (e) => e.toString(),
            'toString',
            contains('Invalid input'),
          ),
        ),
      );
    });
  });
}
