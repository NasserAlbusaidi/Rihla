import 'dart:io';

import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:uuid/uuid.dart';

/// Provider for receipt service.
final receiptServiceProvider = Provider<ReceiptService>((ref) {
  return ReceiptService();
});

/// Service for capturing and uploading receipt images to Firebase Storage.
class ReceiptService {
  final _picker = ImagePicker();
  FirebaseStorage get _storage => FirebaseStorage.instance;

  /// Pick a receipt image from camera or gallery.
  Future<File?> pickReceipt({bool fromCamera = true}) async {
    final xFile = await _picker.pickImage(
      source: fromCamera ? ImageSource.camera : ImageSource.gallery,
      maxWidth: 1920,
      maxHeight: 1920,
      imageQuality: 85,
    );
    if (xFile == null) return null;
    return File(xFile.path);
  }

  /// Upload a receipt image to Firebase Storage.
  ///
  /// Returns the storage path on success, null on failure.
  Future<String?> uploadReceipt({
    required String tripId,
    required String expenseId,
    required File imageFile,
  }) async {
    try {
      final ext = imageFile.path.split('.').last;
      final fileName = '${const Uuid().v4()}.$ext';
      final storagePath = 'receipts/$tripId/$expenseId/$fileName';
      final ref = _storage.ref().child(storagePath);
      final metadata = SettableMetadata(contentType: 'image/jpeg');
      await ref.putFile(imageFile, metadata);
      if (kDebugMode) debugPrint('Receipt uploaded: $storagePath');
      return storagePath;
    } catch (e) {
      if (kDebugMode) debugPrint('Receipt upload failed: $e');
      return null;
    }
  }

  /// Get the Firebase Storage download URL for a receipt.
  Future<String?> getReceiptUrl(String storagePath) async {
    try {
      final ref = _storage.ref().child(storagePath);
      return await ref.getDownloadURL();
    } catch (e) {
      if (kDebugMode) debugPrint('Failed to get receipt URL: $e');
      return null;
    }
  }

  /// Delete a receipt from Firebase Storage.
  Future<bool> deleteReceipt(String storagePath) async {
    try {
      await _storage.ref().child(storagePath).delete();
      return true;
    } catch (e) {
      if (kDebugMode) debugPrint('Failed to delete receipt: $e');
      return false;
    }
  }
}
