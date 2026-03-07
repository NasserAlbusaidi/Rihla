import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../../../core/config/supabase_config.dart';

/// Provider for receipt service
final receiptServiceProvider = Provider<ReceiptService>((ref) {
  return ReceiptService();
});

/// Service for capturing and uploading receipt images to Supabase Storage
class ReceiptService {
  final _picker = ImagePicker();
  SupabaseClient get _client => SupabaseConfig.client;

  static const _bucket = 'receipts';

  /// Pick a receipt image from camera or gallery
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

  /// Upload a receipt image to Supabase Storage (private bucket)
  /// Returns the storage path (not a public URL)
  Future<String?> uploadReceipt({
    required String tripId,
    required String expenseId,
    required File imageFile,
  }) async {
    try {
      final ext = imageFile.path.split('.').last;
      final fileName = '${const Uuid().v4()}.$ext';
      final storagePath = '$tripId/$expenseId/$fileName';

      await _client.storage.from(_bucket).upload(
        storagePath,
        imageFile,
        fileOptions: const FileOptions(
          contentType: 'image/jpeg',
          upsert: true,
        ),
      );

      debugPrint('Receipt uploaded: $storagePath');
      return storagePath;
    } catch (e) {
      debugPrint('Receipt upload failed: $e');
      return null;
    }
  }

  /// Get a signed URL for viewing a receipt (valid for 1 hour)
  Future<String?> getReceiptUrl(String storagePath) async {
    try {
      final signedUrl = await _client.storage
          .from(_bucket)
          .createSignedUrl(storagePath, 3600); // 1 hour
      return signedUrl;
    } catch (e) {
      debugPrint('Failed to get receipt URL: $e');
      return null;
    }
  }

  /// Delete a receipt from storage
  Future<bool> deleteReceipt(String storagePath) async {
    try {
      await _client.storage.from(_bucket).remove([storagePath]);
      return true;
    } catch (e) {
      debugPrint('Failed to delete receipt: $e');
      return false;
    }
  }

  /// Update the expense record with the receipt path
  Future<bool> linkReceiptToExpense({
    required String expenseId,
    required String receiptPath,
  }) async {
    try {
      await _client
          .from('expenses')
          .update({'receipt_url': receiptPath})
          .eq('id', expenseId);
      return true;
    } catch (e) {
      debugPrint('Failed to link receipt: $e');
      return false;
    }
  }
}
