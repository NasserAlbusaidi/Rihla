import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:uuid/uuid.dart';

import '../../../core/config/firebase_config.dart';
import '../../../core/services/firestore_repository.dart';
import '../../../core/services/storage_exceptions.dart';
import '../../../core/services/storage_gateway.dart';
import '../models/memory_model.dart';

/// Firestore + gated-storage memory service.
///
/// Extends [FirestoreRepository] for Firestore path conventions. All trip
/// storage I/O routes through [StorageGateway] — `storage.rules` denies
/// direct SDK access to `trip-memories/*` (Phase 38 INFRA-01 #3).
class MemoryService extends FirestoreRepository {
  static const _uuid = Uuid();
  static const int _maxFileSizeBytes = 25 * 1024 * 1024;

  final StorageGateway _gateway;
  final http.Client _httpClient;
  final bool _ownsHttpClient;

  MemoryService({StorageGateway? gateway, http.Client? httpClient})
      : _gateway = gateway ?? StorageGateway(),
        _httpClient = httpClient ?? http.Client(),
        _ownsHttpClient = httpClient == null,
        super();

  @visibleForTesting
  MemoryService.withFirestore(
    FirebaseFirestore db, {
    StorageGateway? gateway,
    http.Client? httpClient,
  })  : _gateway = gateway ?? StorageGateway(),
        _httpClient = httpClient ?? http.Client(),
        _ownsHttpClient = httpClient == null,
        super.withFirestore(db);

  void dispose() {
    if (_ownsHttpClient) _httpClient.close();
  }

  /// Watch all memories for an event as a live stream.
  Stream<List<Memory>> watchMemories(String groupId, String eventId) {
    return eventSubcollection(groupId, eventId, 'memories')
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((snap) => snap.docs
            .map((doc) => Memory.fromFirestore({...doc.data(), 'id': doc.id}))
            .toList());
  }

  /// Test hook for writing memory metadata directly to Firestore.
  @visibleForTesting
  Future<void> writeMetadataToFirestore({
    required String groupId,
    required String eventId,
    required String memoryId,
    required Map<String, dynamic> data,
  }) async {
    await eventSubcollection(groupId, eventId, 'memories')
        .doc(memoryId)
        .set(data);
  }

  /// Pick an image, request a signed upload URL, PUT the bytes, and write metadata.
  ///
  /// Returns the created [Memory] on success, or null if the user cancels.
  Future<Memory?> uploadPhoto({
    required String groupId,
    required String eventId,
    required ImageSource source,
    String? caption,
  }) async {
    final picker = ImagePicker();
    final pickedFile = await picker.pickImage(
      source: source,
      maxWidth: 1920,
      maxHeight: 1920,
      imageQuality: 85,
    );
    if (pickedFile == null) return null;

    final uid = FirebaseConfig.currentUser?.uid;
    if (uid == null) throw const StorageException.notSignedIn();

    final id = _uuid.v4();
    final extension = pickedFile.path.split('.').last.toLowerCase();
    final contentType = 'image/$extension';
    final fileName = '$id.$extension';
    final bytes = await File(pickedFile.path).readAsBytes();

    // 1. Signed upload URL from callable.
    final signed = await _gateway.getSignedUploadUrl(
      bucket: 'memories',
      groupId: groupId,
      eventId: eventId,
      fileName: fileName,
      contentType: contentType,
      sizeBytes: bytes.length,
    );

    // 2. PUT direct-to-GCS.
    final response = await _httpClient.put(
      Uri.parse(signed.uploadUrl),
      headers: {
        'Content-Type': contentType,
        'x-goog-content-length-range': '0,$_maxFileSizeBytes',
      },
      body: bytes,
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      if (kDebugMode) {
        debugPrint(
          'MemoryService.uploadPhoto PUT failed: ${response.statusCode}',
        );
      }
      throw StorageException.uploadFailed(response.statusCode, response.body);
    }

    // 3. Firestore metadata with server-authoritative storagePath.
    final now = DateTime.now().toUtc();
    final data = <String, dynamic>{
      'id': id,
      'eventId': eventId,
      'uploadedBy': uid,
      'storagePath': signed.storagePath,
      'caption': caption,
      'createdAt': now.toIso8601String(),
    };
    try {
      await eventSubcollection(groupId, eventId, 'memories').doc(id).set(data);
    } on FirebaseException catch (e) {
      if (kDebugMode) {
        debugPrint(
          'MemoryService.uploadPhoto Firestore write failed: ${e.code} ${e.message}',
        );
      }
      rethrow;
    }

    return Memory.fromFirestore(data);
  }

  /// Batch-list memories with pre-issued signed download URLs.
  ///
  /// Replaces per-item `getDownloadURL` — single callable round-trip,
  /// server pre-signs all URLs in parallel (D-03).
  Future<List<MemoryWithUrl>> listMemoriesWithUrls({
    required String groupId,
    required String eventId,
  }) {
    return _gateway.listMemoriesWithUrls(groupId: groupId, eventId: eventId);
  }

  /// Test-only metadata delete (no storage side effect).
  @visibleForTesting
  Future<void> deleteMemoryMetadata({
    required String groupId,
    required String eventId,
    required String memoryId,
  }) async {
    await eventSubcollection(groupId, eventId, 'memories')
        .doc(memoryId)
        .delete();
  }

  /// Delete a memory from both gated storage and Firestore.
  Future<bool> deleteMemory({
    required String groupId,
    required String eventId,
    required String memoryId,
    required String storagePath,
  }) async {
    try {
      await _gateway.deleteStorageObject(
        storagePath: storagePath,
        groupId: groupId,
      );
      await eventSubcollection(groupId, eventId, 'memories')
          .doc(memoryId)
          .delete();
      return true;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('MemoryService: Failed to delete memory $memoryId: $e');
      }
      return false;
    }
  }
}
