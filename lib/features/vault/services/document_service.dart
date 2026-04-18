import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:uuid/uuid.dart';

import '../../../core/config/firebase_config.dart';
import '../../../core/services/firestore_repository.dart';
import '../../../core/services/storage_exceptions.dart';
import '../../../core/services/storage_gateway.dart';
import '../models/document_model.dart';

/// Firestore + gated-storage document service.
///
/// Extends [FirestoreRepository] for Firestore path conventions. All trip
/// storage I/O routes through [StorageGateway] — the Firebase Storage SDK is
/// never invoked directly for `trip-documents/*` because `storage.rules`
/// denies it (Phase 38 INFRA-01 #3).
class DocumentService extends FirestoreRepository {
  static const int maxFileSizeBytes = 25 * 1024 * 1024; // 25 MB
  static const List<String> _allowedExtensions = [
    'pdf', 'jpg', 'jpeg', 'png', 'gif', 'doc', 'docx',
    'xls', 'xlsx', 'txt', 'csv', 'heic', 'webp',
  ];

  final StorageGateway _gateway;
  final http.Client _httpClient;
  final bool _ownsHttpClient;

  DocumentService({StorageGateway? gateway, http.Client? httpClient})
      : _gateway = gateway ?? StorageGateway(),
        _httpClient = httpClient ?? http.Client(),
        _ownsHttpClient = httpClient == null,
        super();

  @visibleForTesting
  DocumentService.withFirestore(
    FirebaseFirestore db, {
    StorageGateway? gateway,
    http.Client? httpClient,
  })  : _gateway = gateway ?? StorageGateway(),
        _httpClient = httpClient ?? http.Client(),
        _ownsHttpClient = httpClient == null,
        super.withFirestore(db);

  /// Releases the internally-managed http client. Callers that injected a
  /// client are responsible for their own cleanup.
  void dispose() {
    if (_ownsHttpClient) _httpClient.close();
  }

  /// Watch all documents for an event as a live stream.
  Stream<List<Document>> watchDocuments(String groupId, String eventId) {
    return eventSubcollection(groupId, eventId, 'documents')
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((snap) => snap.docs
            .map((doc) => Document.fromFirestore({...doc.data(), 'id': doc.id}))
            .toList());
  }

  /// Write document metadata directly to Firestore (tests + post-upload).
  @visibleForTesting
  Future<void> writeMetadataToFirestore({
    required String groupId,
    required String eventId,
    required String documentId,
    required Map<String, dynamic> data,
  }) async {
    await eventSubcollection(groupId, eventId, 'documents')
        .doc(documentId)
        .set(data);
  }

  /// Request a signed upload URL, PUT the bytes, then write Firestore metadata.
  ///
  /// Throws [StorageException] on any gateway or HTTP PUT failure.
  Future<Document> uploadFile({
    required String groupId,
    required String eventId,
    required String filePath,
    required String fileName,
    required int fileSize,
    String? mimeType,
  }) async {
    final uid = FirebaseConfig.currentUser?.uid;
    if (uid == null) throw const StorageException.notSignedIn();

    final contentType = mimeType ?? 'application/octet-stream';

    // 1. Ask the callable for a signed PUT URL.
    final signed = await _gateway.getSignedUploadUrl(
      bucket: 'documents',
      groupId: groupId,
      eventId: eventId,
      fileName: fileName,
      contentType: contentType,
      sizeBytes: fileSize,
    );

    // 2. PUT the bytes direct-to-GCS using the signed URL.
    final bytes = await File(filePath).readAsBytes();
    final response = await _httpClient.put(
      Uri.parse(signed.uploadUrl),
      headers: {
        'Content-Type': contentType,
        'x-goog-content-length-range': '0,$maxFileSizeBytes',
      },
      body: bytes,
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      if (kDebugMode) {
        debugPrint(
          'DocumentService.uploadFile PUT failed: ${response.statusCode}',
        );
      }
      throw StorageException.uploadFailed(response.statusCode, response.body);
    }

    // 3. Write Firestore metadata with the server-authoritative storagePath.
    final id = const Uuid().v4();
    final now = DateTime.now().toUtc();
    final data = <String, dynamic>{
      'id': id,
      'eventId': eventId,
      'uploaderId': uid,
      'uploadedBy': uid,
      'storagePath': signed.storagePath,
      'fileName': fileName,
      'fileSize': fileSize,
      'sizeBytes': fileSize,
      'mimeType': mimeType,
      'createdAt': now.toIso8601String(),
      'isDeleted': false,
    };
    try {
      await eventSubcollection(groupId, eventId, 'documents').doc(id).set(data);
    } on FirebaseException catch (e) {
      if (kDebugMode) {
        debugPrint(
          'DocumentService.uploadFile Firestore write failed: ${e.code} ${e.message}',
        );
      }
      rethrow;
    }
    return Document.fromFirestore(data);
  }

  /// Pick a file via [FilePicker] and upload it.
  Future<Document?> pickAndUpload({
    required String groupId,
    required String eventId,
    Ref? ref,
    StateController<bool>? loadingNotifier,
    StateController<String?>? errorNotifier,
    StateController<double>? progressNotifier,
  }) async {
    loadingNotifier?.state = true;
    errorNotifier?.state = null;
    progressNotifier?.state = 0;

    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: _allowedExtensions,
        allowMultiple: false,
      );

      if (result == null || result.files.isEmpty) {
        loadingNotifier?.state = false;
        return null;
      }

      final file = result.files.first;
      if (file.path == null) {
        throw Exception('Could not access file');
      }

      if (file.size > maxFileSizeBytes) {
        errorNotifier?.state = 'File too large. Maximum size is 25 MB.';
        loadingNotifier?.state = false;
        return null;
      }

      final mimeType = _getMimeType(file.extension ?? '');
      final document = await uploadFile(
        groupId: groupId,
        eventId: eventId,
        filePath: file.path!,
        fileName: file.name,
        fileSize: file.size,
        mimeType: mimeType,
      );

      progressNotifier?.state = 1.0;
      loadingNotifier?.state = false;
      return document;
    } catch (e) {
      errorNotifier?.state = e.toString();
      loadingNotifier?.state = false;
      return null;
    }
  }

  /// Fetch a signed download URL for a single document via the callable.
  ///
  /// Returns null on failure. For bulk listing, use [listDocumentsWithUrls]
  /// which pre-issues URLs in a single round-trip.
  Future<String?> getDownloadUrl({
    required String groupId,
    required String eventId,
    required String storagePath,
  }) async {
    try {
      final docs = await _gateway.listDocumentsWithUrls(
        groupId: groupId,
        eventId: eventId,
      );
      for (final d in docs) {
        if (d.fields['storagePath'] == storagePath) return d.signedUrl;
      }
      return null;
    } on StorageException catch (e) {
      if (kDebugMode) {
        debugPrint(
          'DocumentService.getDownloadUrl failed for $storagePath: $e',
        );
      }
      return null;
    }
  }

  /// Batch-list documents with pre-issued signed URLs (single callable trip).
  Future<List<DocumentWithUrl>> listDocumentsWithUrls({
    required String groupId,
    required String eventId,
  }) {
    return _gateway.listDocumentsWithUrls(groupId: groupId, eventId: eventId);
  }

  /// Delete document metadata from Firestore only (tests).
  @visibleForTesting
  Future<void> deleteDocumentMetadata({
    required String groupId,
    required String eventId,
    required String documentId,
  }) async {
    await eventSubcollection(groupId, eventId, 'documents')
        .doc(documentId)
        .delete();
  }

  /// Delete a document from both gated storage and Firestore.
  Future<bool> deleteDocument({
    required String groupId,
    required String eventId,
    required String documentId,
    required String storagePath,
  }) async {
    try {
      await _gateway.deleteStorageObject(
        storagePath: storagePath,
        groupId: groupId,
      );
      await eventSubcollection(groupId, eventId, 'documents')
          .doc(documentId)
          .delete();
      return true;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('DocumentService: Failed to delete document $documentId: $e');
      }
      return false;
    }
  }

  String _getMimeType(String extension) {
    final ext = extension.toLowerCase();
    switch (ext) {
      case 'pdf':
        return 'application/pdf';
      case 'jpg':
      case 'jpeg':
        return 'image/jpeg';
      case 'png':
        return 'image/png';
      case 'gif':
        return 'image/gif';
      case 'doc':
        return 'application/msword';
      case 'docx':
        return 'application/vnd.openxmlformats-officedocument.wordprocessingml.document';
      case 'xls':
        return 'application/vnd.ms-excel';
      case 'xlsx':
        return 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';
      case 'txt':
        return 'text/plain';
      default:
        return 'application/octet-stream';
    }
  }
}
