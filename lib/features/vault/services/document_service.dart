import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:file_picker/file_picker.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../../core/config/firebase_config.dart';
import '../../../core/services/firestore_repository.dart';
import '../models/document_model.dart';

/// Firestore + Firebase Storage backed document service.
///
/// Extends [FirestoreRepository] for consistent Firestore path conventions.
/// Files are uploaded to Firebase Storage; metadata is stored in the event's
/// `documents` subcollection at `groups/{groupId}/events/{eventId}/documents`.
class DocumentService extends FirestoreRepository {
  static const int maxFileSizeBytes = 25 * 1024 * 1024; // 25 MB
  static const List<String> _allowedExtensions = [
    'pdf', 'jpg', 'jpeg', 'png', 'gif', 'doc', 'docx',
    'xls', 'xlsx', 'txt', 'csv', 'heic', 'webp',
  ];

  DocumentService() : super();

  @visibleForTesting
  DocumentService.withFirestore(FirebaseFirestore db) : super.withFirestore(db);

  FirebaseStorage get _storage => FirebaseStorage.instance;

  /// Watch all documents for an event as a live stream.
  ///
  /// Returns a [Stream<List<Document>>] ordered by [createdAt] descending.
  Stream<List<Document>> watchDocuments(String groupId, String eventId) {
    return eventSubcollection(groupId, eventId, 'documents')
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((snap) => snap.docs
            .map((doc) => Document.fromFirestore({...doc.data(), 'id': doc.id}))
            .toList());
  }

  /// Write document metadata directly to Firestore (used in tests and
  /// after successful Storage upload).
  ///
  /// This is [visibleForTesting] to allow unit tests to exercise the
  /// Firestore path without triggering actual Firebase Storage uploads.
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

  /// Upload a file to Firebase Storage and write metadata to Firestore.
  ///
  /// Returns the created [Document] on success.
  /// Throws [Exception] if the user is not authenticated.
  Future<Document> uploadFile({
    required String groupId,
    required String eventId,
    required String filePath,
    required String fileName,
    required int fileSize,
    String? mimeType,
  }) async {
    final uid = FirebaseConfig.currentUser?.uid;
    if (uid == null) throw Exception('Not authenticated');

    final id = const Uuid().v4();
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final storagePath = 'trip-documents/$eventId/$timestamp-$fileName';

    // Upload to Firebase Storage
    try {
      final ref = _storage.ref().child(storagePath);
      final metadata = SettableMetadata(contentType: mimeType);
      await ref.putFile(File(filePath), metadata);
    } on FirebaseException catch (e) {
      if (kDebugMode) debugPrint('DocumentService.uploadFile storage upload failed: ${e.code} ${e.message}');
      rethrow;
    }

    // Write metadata to Firestore subcollection
    final now = DateTime.now().toUtc();
    final data = {
      'id': id,
      'eventId': eventId,
      'uploaderId': uid,
      'storagePath': storagePath,
      'fileName': fileName,
      'fileSize': fileSize,
      'mimeType': mimeType,
      'createdAt': now.toIso8601String(),
    };
    try {
      await eventSubcollection(groupId, eventId, 'documents').doc(id).set(data);
    } on FirebaseException catch (e) {
      if (kDebugMode) debugPrint('DocumentService.uploadFile Firestore write failed: ${e.code} ${e.message}');
      rethrow;
    }
    return Document.fromFirestore(data);
  }

  /// Pick a file using FilePicker and upload it.
  ///
  /// Updates loading/error/progress state providers if [ref] is provided.
  /// Returns the created [Document] on success, null if user cancelled.
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

  /// Get the Firebase Storage download URL for a given storage path.
  ///
  /// Returns null on error (e.g. file not found or not authenticated).
  Future<String?> getDownloadUrl(String storagePath) async {
    try {
      return await _storage.ref().child(storagePath).getDownloadURL();
    } catch (e) {
      if (kDebugMode) debugPrint('DocumentService: Failed to get download URL for $storagePath: $e');
      return null;
    }
  }

  /// Delete document metadata from Firestore only.
  ///
  /// Use this in tests where Firebase Storage is not available.
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

  /// Delete a document from both Firebase Storage and Firestore.
  ///
  /// Returns true on success, false on any error.
  Future<bool> deleteDocument({
    required String groupId,
    required String eventId,
    required String documentId,
    required String storagePath,
  }) async {
    try {
      await _storage.ref().child(storagePath).delete();
      await eventSubcollection(groupId, eventId, 'documents')
          .doc(documentId)
          .delete();
      return true;
    } catch (e) {
      if (kDebugMode) debugPrint('DocumentService: Failed to delete document $documentId: $e');
      return false;
    }
  }

  /// Mime type helper derived from file extension.
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
