import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';
import 'package:uuid/uuid.dart';

import '../../../core/config/firebase_config.dart';
import '../../../core/services/firestore_repository.dart';
import '../models/memory_model.dart';

/// Firestore + Firebase Storage backed memory service.
///
/// Extends [FirestoreRepository] for consistent Firestore path conventions.
/// Photos are uploaded to Firebase Storage; metadata is stored in the event's
/// `memories` subcollection at `groups/{groupId}/events/{eventId}/memories`.
class MemoryService extends FirestoreRepository {
  static const _uuid = Uuid();

  /// In-memory cache of storage path → download URL.
  /// Firebase Storage URLs are long-lived; cache avoids redundant round-trips.
  final Map<String, String> _urlCache = {};

  MemoryService() : super();

  @visibleForTesting
  MemoryService.withFirestore(FirebaseFirestore db) : super.withFirestore(db);

  FirebaseStorage get _storage => FirebaseStorage.instance;

  /// Watch all memories for an event as a live stream.
  ///
  /// Returns a [Stream<List<Memory>>] ordered by [createdAt] descending.
  Stream<List<Memory>> watchMemories(String groupId, String eventId) {
    return eventSubcollection(groupId, eventId, 'memories')
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((snap) => snap.docs
            .map((doc) => Memory.fromFirestore({...doc.data(), 'id': doc.id}))
            .toList());
  }

  /// Write memory metadata directly to Firestore.
  ///
  /// Exposed [visibleForTesting] to allow unit tests to exercise the Firestore
  /// path without triggering actual Firebase Storage uploads.
  @visibleForTesting
  Future<void> writeMetadataToFirestore({
    required String groupId,
    required String eventId,
    required String memoryId,
    required Map<String, dynamic> data,
  }) async {
    await eventSubcollection(groupId, eventId, 'memories').doc(memoryId).set(data);
  }

  /// Pick an image and upload to Firebase Storage, writing metadata to Firestore.
  ///
  /// Returns the created [Memory] on success, null if user cancelled.
  /// Throws [Exception] if the user is not authenticated.
  Future<Memory?> uploadPhoto({
    required String groupId,
    required String eventId,
    required ImageSource source,
    String? caption,
  }) async {
    // 1. Pick image using ImagePicker
    final picker = ImagePicker();
    final pickedFile = await picker.pickImage(
      source: source,
      maxWidth: 1920,
      maxHeight: 1920,
      imageQuality: 85,
    );
    if (pickedFile == null) return null;

    // 2. Get current user for uploader attribution
    final uid = FirebaseConfig.currentUser?.uid;
    if (uid == null) throw Exception('Not authenticated');

    // 3. Build storage path and upload to Firebase Storage
    final id = _uuid.v4();
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final extension = pickedFile.path.split('.').last.toLowerCase();
    final storagePath = 'trip-memories/$eventId/$timestamp.$extension';

    try {
      final ref = _storage.ref().child(storagePath);
      final metadata = SettableMetadata(contentType: 'image/$extension');
      await ref.putFile(File(pickedFile.path), metadata);
    } on FirebaseException catch (e) {
      if (kDebugMode) debugPrint('MemoryService.uploadPhoto storage upload failed: ${e.code} ${e.message}');
      rethrow;
    }

    // 4. Write metadata to Firestore subcollection
    final now = DateTime.now().toUtc();
    final data = {
      'id': id,
      'eventId': eventId,
      'uploadedBy': uid,
      'storagePath': storagePath,
      'caption': caption,
      'createdAt': now.toIso8601String(),
    };
    try {
      await eventSubcollection(groupId, eventId, 'memories').doc(id).set(data);
    } on FirebaseException catch (e) {
      if (kDebugMode) debugPrint('MemoryService.uploadPhoto Firestore write failed: ${e.code} ${e.message}');
      rethrow;
    }

    // 5. Return Memory model from the written data
    return Memory.fromFirestore(data);
  }

  /// Get the Firebase Storage download URL for a given storage path.
  ///
  /// Returns null on error (e.g. file not found or network unavailable).
  Future<String?> getDownloadUrl(String storagePath) async {
    try {
      return await _storage.ref().child(storagePath).getDownloadURL();
    } catch (e) {
      if (kDebugMode) debugPrint('MemoryService: Failed to get download URL for $storagePath: $e');
      return null;
    }
  }

  /// Cached variant of [getDownloadUrl]. Returns the cached URL if available,
  /// otherwise fetches from Firebase Storage and caches the result.
  Future<String?> getDownloadUrlCached(String storagePath) async {
    if (storagePath.isEmpty) return null;
    final cached = _urlCache[storagePath];
    if (cached != null) return cached;
    final url = await getDownloadUrl(storagePath);
    if (url != null) {
      _urlCache[storagePath] = url;
    }
    return url;
  }

  /// Delete memory metadata from Firestore only.
  ///
  /// Use this in tests where Firebase Storage is not available.
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

  /// Delete a memory from both Firebase Storage and Firestore.
  ///
  /// Returns true on success, false on any error.
  Future<bool> deleteMemory({
    required String groupId,
    required String eventId,
    required String memoryId,
    required String storagePath,
  }) async {
    try {
      _urlCache.remove(storagePath);
      await _storage.ref().child(storagePath).delete();
      await eventSubcollection(groupId, eventId, 'memories')
          .doc(memoryId)
          .delete();
      return true;
    } catch (e) {
      if (kDebugMode) debugPrint('MemoryService: Failed to delete memory $memoryId: $e');
      return false;
    }
  }
}
