import 'package:cloud_functions/cloud_functions.dart';

import 'storage_exceptions.dart';

/// Response from [StorageGateway.getSignedUploadUrl]: short-lived signed PUT URL.
class SignedUpload {
  const SignedUpload({
    required this.uploadUrl,
    required this.storagePath,
    required this.expiresAt,
  });

  final String uploadUrl;
  final String storagePath;
  final DateTime expiresAt;

  factory SignedUpload.fromMap(Map<String, dynamic> m) => SignedUpload(
        uploadUrl: m['uploadUrl'] as String,
        storagePath: m['storagePath'] as String,
        expiresAt: DateTime.parse(m['expiresAt'] as String),
      );
}

/// Firestore document fields + pre-issued signed download URL.
class DocumentWithUrl {
  const DocumentWithUrl({
    required this.fields,
    required this.signedUrl,
    required this.expiresAt,
  });

  final Map<String, dynamic> fields;
  final String signedUrl;
  final DateTime expiresAt;

  factory DocumentWithUrl.fromMap(Map<String, dynamic> m) {
    final signedUrl = m['signedUrl'] as String;
    final expiresAt = DateTime.parse(m['expiresAt'] as String);
    final fields = Map<String, dynamic>.from(m)
      ..remove('signedUrl')
      ..remove('expiresAt');
    return DocumentWithUrl(
      fields: fields,
      signedUrl: signedUrl,
      expiresAt: expiresAt,
    );
  }
}

/// Firestore memory fields + pre-issued signed download URL.
class MemoryWithUrl {
  const MemoryWithUrl({
    required this.fields,
    required this.signedUrl,
    required this.expiresAt,
  });

  final Map<String, dynamic> fields;
  final String signedUrl;
  final DateTime expiresAt;

  factory MemoryWithUrl.fromMap(Map<String, dynamic> m) {
    final signedUrl = m['signedUrl'] as String;
    final expiresAt = DateTime.parse(m['expiresAt'] as String);
    final fields = Map<String, dynamic>.from(m)
      ..remove('signedUrl')
      ..remove('expiresAt');
    return MemoryWithUrl(
      fields: fields,
      signedUrl: signedUrl,
      expiresAt: expiresAt,
    );
  }
}

/// Single entry point for all trip-bucket storage operations.
///
/// Wraps the 4 Cloud Functions callables (`getSignedUploadUrl`,
/// `listDocumentsWithUrls`, `listMemoriesWithUrls`, `deleteStorageObject`)
/// and maps [FirebaseFunctionsException] onto [StorageException] variants.
///
/// Never call the Firebase Storage SDK directly for trip-documents/,
/// trip-memories/, or receipts/ paths — storage.rules denies them all.
class StorageGateway {
  StorageGateway({FirebaseFunctions? functions})
      : _functions =
            functions ?? FirebaseFunctions.instanceFor(region: 'us-central1');

  final FirebaseFunctions _functions;

  /// Request a short-lived signed PUT URL for a single upload.
  ///
  /// [bucket] must be `'documents'`, `'memories'`, or `'receipts'`. When
  /// [bucket] is `'receipts'`, [expenseId] is required (server enforces).
  Future<SignedUpload> getSignedUploadUrl({
    required String bucket,
    required String groupId,
    required String eventId,
    required String fileName,
    required String contentType,
    required int sizeBytes,
    String? expenseId,
  }) async {
    try {
      final payload = <String, dynamic>{
        'bucket': bucket,
        'groupId': groupId,
        'eventId': eventId,
        'fileName': fileName,
        'contentType': contentType,
        'sizeBytes': sizeBytes,
      };
      if (expenseId != null) payload['expenseId'] = expenseId;
      final result =
          await _functions.httpsCallable('getSignedUploadUrl').call(payload);
      return SignedUpload.fromMap(Map<String, dynamic>.from(result.data as Map));
    } on FirebaseFunctionsException catch (e) {
      throw _mapError(e);
    }
  }

  /// List all documents for an event with pre-issued signed download URLs.
  Future<List<DocumentWithUrl>> listDocumentsWithUrls({
    required String groupId,
    required String eventId,
  }) async {
    try {
      final result =
          await _functions.httpsCallable('listDocumentsWithUrls').call({
        'groupId': groupId,
        'eventId': eventId,
      });
      final data = Map<String, dynamic>.from(result.data as Map);
      final rawDocs = (data['documents'] as List).cast<Map>();
      return rawDocs
          .map((m) => DocumentWithUrl.fromMap(Map<String, dynamic>.from(m)))
          .toList();
    } on FirebaseFunctionsException catch (e) {
      throw _mapError(e);
    }
  }

  /// List all memories for an event with pre-issued signed download URLs.
  Future<List<MemoryWithUrl>> listMemoriesWithUrls({
    required String groupId,
    required String eventId,
  }) async {
    try {
      final result =
          await _functions.httpsCallable('listMemoriesWithUrls').call({
        'groupId': groupId,
        'eventId': eventId,
      });
      final data = Map<String, dynamic>.from(result.data as Map);
      final rawMems = (data['memories'] as List).cast<Map>();
      return rawMems
          .map((m) => MemoryWithUrl.fromMap(Map<String, dynamic>.from(m)))
          .toList();
    } on FirebaseFunctionsException catch (e) {
      throw _mapError(e);
    }
  }

  /// Delete a single object via the gated callable (idempotent server-side).
  Future<void> deleteStorageObject({
    required String storagePath,
    required String groupId,
  }) async {
    try {
      await _functions.httpsCallable('deleteStorageObject').call({
        'storagePath': storagePath,
        'groupId': groupId,
      });
    } on FirebaseFunctionsException catch (e) {
      throw _mapError(e);
    }
  }

  StorageException _mapError(FirebaseFunctionsException e) {
    switch (e.code) {
      case 'unauthenticated':
        return const StorageException.notSignedIn();
      case 'permission-denied':
        return const StorageException.notMember();
      case 'not-found':
        return const StorageException.missing();
      case 'invalid-argument':
        return StorageException.invalidInput(e.message ?? '');
      default:
        return StorageException.unknown(e.message ?? e.code);
    }
  }
}
