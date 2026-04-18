import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:mocktail/mocktail.dart';
import 'package:safar/core/services/storage_exceptions.dart';
import 'package:safar/core/services/storage_gateway.dart';
import 'package:safar/features/ledger/services/receipt_service.dart';

class _MockGateway extends Mock implements StorageGateway {}

class _MockHttpClient extends Mock implements http.Client {}

class _FakeUri extends Fake implements Uri {}

class _FakeFile extends Fake implements File {
  _FakeFile(this._bytes, this.path);
  final List<int> _bytes;
  @override
  final String path;
  @override
  Future<Uint8List> readAsBytes() async => Uint8List.fromList(_bytes);
}

class _StubResponse implements http.Response {
  _StubResponse({required this.statusCode, this.body = ''});
  @override
  final int statusCode;
  @override
  final String body;
  // unused members for the http.Response interface — throw in tests if touched.
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  setUpAll(() {
    registerFallbackValue(_FakeUri());
    registerFallbackValue(Uint8List(0));
  });

  group('ReceiptService.uploadReceipt', () {
    late _MockGateway gateway;
    late _MockHttpClient httpClient;

    setUp(() {
      gateway = _MockGateway();
      httpClient = _MockHttpClient();
    });

    test(
        'routes through gateway with bucket="receipts", eventId and expenseId',
        () async {
      final service = ReceiptService(gateway: gateway, httpClient: httpClient);
      final file = _FakeFile(const [1, 2, 3], '/tmp/receipt.jpg');
      when(
        () => gateway.getSignedUploadUrl(
          bucket: any(named: 'bucket'),
          groupId: any(named: 'groupId'),
          eventId: any(named: 'eventId'),
          fileName: any(named: 'fileName'),
          contentType: any(named: 'contentType'),
          sizeBytes: any(named: 'sizeBytes'),
          expenseId: any(named: 'expenseId'),
        ),
      ).thenAnswer((_) async => SignedUpload(
            uploadUrl: 'https://signed/put',
            storagePath: 'receipts/e1/exp1/1.jpg',
            expiresAt: DateTime.now().add(const Duration(minutes: 15)),
          ));
      when(
        () => httpClient.put(
          any(),
          headers: any(named: 'headers'),
          body: any(named: 'body'),
        ),
      ).thenAnswer((_) async => _StubResponse(statusCode: 200));

      final storagePath = await service.uploadReceipt(
        groupId: 'g1',
        eventId: 'e1',
        expenseId: 'exp1',
        imageFile: file,
      );

      expect(storagePath, 'receipts/e1/exp1/1.jpg');
      verify(
        () => gateway.getSignedUploadUrl(
          bucket: 'receipts',
          groupId: 'g1',
          eventId: 'e1',
          fileName: 'receipt.jpg',
          contentType: 'image/jpeg',
          sizeBytes: 3,
          expenseId: 'exp1',
        ),
      ).called(1);
    });

    test('returns null on non-2xx PUT response', () async {
      final service = ReceiptService(gateway: gateway, httpClient: httpClient);
      final file = _FakeFile(const [0], '/tmp/r.jpg');
      when(
        () => gateway.getSignedUploadUrl(
          bucket: any(named: 'bucket'),
          groupId: any(named: 'groupId'),
          eventId: any(named: 'eventId'),
          fileName: any(named: 'fileName'),
          contentType: any(named: 'contentType'),
          sizeBytes: any(named: 'sizeBytes'),
          expenseId: any(named: 'expenseId'),
        ),
      ).thenAnswer((_) async => SignedUpload(
            uploadUrl: 'https://signed/put',
            storagePath: 'receipts/e1/exp1/2.jpg',
            expiresAt: DateTime.now().add(const Duration(minutes: 15)),
          ));
      when(
        () => httpClient.put(
          any(),
          headers: any(named: 'headers'),
          body: any(named: 'body'),
        ),
      ).thenAnswer((_) async => _StubResponse(statusCode: 413, body: 'too big'));

      final result = await service.uploadReceipt(
        groupId: 'g1',
        eventId: 'e1',
        expenseId: 'exp1',
        imageFile: file,
      );
      expect(result, isNull);
    });

    test('legacy tripId param still works when eventId omitted', () async {
      final service = ReceiptService(gateway: gateway, httpClient: httpClient);
      final file = _FakeFile(const [0], '/tmp/r.jpg');
      when(
        () => gateway.getSignedUploadUrl(
          bucket: any(named: 'bucket'),
          groupId: any(named: 'groupId'),
          eventId: any(named: 'eventId'),
          fileName: any(named: 'fileName'),
          contentType: any(named: 'contentType'),
          sizeBytes: any(named: 'sizeBytes'),
          expenseId: any(named: 'expenseId'),
        ),
      ).thenAnswer((_) async => SignedUpload(
            uploadUrl: 'https://signed/put',
            storagePath: 'receipts/legacy-trip/exp1/r.jpg',
            expiresAt: DateTime.now().add(const Duration(minutes: 15)),
          ));
      when(
        () => httpClient.put(
          any(),
          headers: any(named: 'headers'),
          body: any(named: 'body'),
        ),
      ).thenAnswer((_) async => _StubResponse(statusCode: 204));

      // ignore: deprecated_member_use_from_same_package
      final result = await service.uploadReceipt(
        groupId: 'g1',
        tripId: 'legacy-trip',
        expenseId: 'exp1',
        imageFile: file,
      );
      expect(result, 'receipts/legacy-trip/exp1/r.jpg');
      verify(
        () => gateway.getSignedUploadUrl(
          bucket: 'receipts',
          groupId: 'g1',
          eventId: 'legacy-trip',
          fileName: 'r.jpg',
          contentType: 'image/jpeg',
          sizeBytes: 1,
          expenseId: 'exp1',
        ),
      ).called(1);
    });

    test('surfaces null when gateway throws StorageException', () async {
      final service = ReceiptService(gateway: gateway, httpClient: httpClient);
      final file = _FakeFile(const [0], '/tmp/r.jpg');
      when(
        () => gateway.getSignedUploadUrl(
          bucket: any(named: 'bucket'),
          groupId: any(named: 'groupId'),
          eventId: any(named: 'eventId'),
          fileName: any(named: 'fileName'),
          contentType: any(named: 'contentType'),
          sizeBytes: any(named: 'sizeBytes'),
          expenseId: any(named: 'expenseId'),
        ),
      ).thenThrow(const StorageException.notMember());

      final result = await service.uploadReceipt(
        groupId: 'g1',
        eventId: 'e1',
        expenseId: 'exp1',
        imageFile: file,
      );
      expect(result, isNull);
    });
  });

  group('ReceiptService.deleteReceipt', () {
    test('routes through gateway.deleteStorageObject', () async {
      final gateway = _MockGateway();
      final service = ReceiptService(gateway: gateway, httpClient: _MockHttpClient());
      when(
        () => gateway.deleteStorageObject(
          storagePath: any(named: 'storagePath'),
          groupId: any(named: 'groupId'),
        ),
      ).thenAnswer((_) async {});
      final ok = await service.deleteReceipt(
        groupId: 'g1',
        storagePath: 'receipts/e1/exp1/x.jpg',
      );
      expect(ok, isTrue);
      verify(
        () => gateway.deleteStorageObject(
          storagePath: 'receipts/e1/exp1/x.jpg',
          groupId: 'g1',
        ),
      ).called(1);
    });

    test('returns false on StorageException', () async {
      final gateway = _MockGateway();
      final service = ReceiptService(gateway: gateway, httpClient: _MockHttpClient());
      when(
        () => gateway.deleteStorageObject(
          storagePath: any(named: 'storagePath'),
          groupId: any(named: 'groupId'),
        ),
      ).thenThrow(const StorageException.notMember());
      final ok = await service.deleteReceipt(
        groupId: 'g1',
        storagePath: 'receipts/e1/exp1/x.jpg',
      );
      expect(ok, isFalse);
    });
  });
}
