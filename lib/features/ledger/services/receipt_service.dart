import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';

import '../../../core/services/storage_exceptions.dart';
import '../../../core/services/storage_gateway.dart';

/// Provider for receipt service.
final receiptServiceProvider = Provider<ReceiptService>((ref) {
  final service = ReceiptService();
  ref.onDispose(service.dispose);
  return service;
});

/// Service for capturing and uploading receipt images to gated storage.
///
/// All receipt I/O routes through [StorageGateway]. `storage.rules` denies
/// direct Firebase Storage SDK access to `receipts/*` (Phase 38 INFRA-01 #3).
class ReceiptService {
  static const int _maxFileSizeBytes = 25 * 1024 * 1024;

  final StorageGateway _gateway;
  final ImagePicker _picker;
  final http.Client _httpClient;
  final bool _ownsHttpClient;

  ReceiptService({
    StorageGateway? gateway,
    ImagePicker? picker,
    http.Client? httpClient,
  }) : _gateway = gateway ?? StorageGateway(),
       _picker = picker ?? ImagePicker(),
       _httpClient = httpClient ?? http.Client(),
       _ownsHttpClient = httpClient == null;

  void dispose() {
    if (_ownsHttpClient) _httpClient.close();
  }

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

  /// Upload a receipt image via the gated callable + signed URL PUT.
  ///
  /// Accepts both [eventId] (preferred) and the legacy [tripId] parameter.
  /// When both are provided, [eventId] wins (per 38-RESEARCH.md A5 — trip
  /// and event ids are semantically identical under the new schema).
  ///
  /// Returns the server-authoritative storagePath on success, null on failure.
  Future<String?> uploadReceipt({
    required String groupId,
    required String expenseId,
    required File imageFile,
    String? eventId,
    @Deprecated('Use eventId instead') String? tripId,
  }) async {
    final resolvedEventId = eventId ?? tripId;
    if (resolvedEventId == null || resolvedEventId.isEmpty) {
      if (kDebugMode) {
        debugPrint('ReceiptService.uploadReceipt: eventId/tripId required');
      }
      return null;
    }
    if (kDebugMode && eventId == null && tripId != null) {
      debugPrint(
        'ReceiptService.uploadReceipt: tripId is deprecated — pass eventId',
      );
    }

    try {
      final ext = imageFile.path.split('.').last.toLowerCase();
      final contentType = 'image/${ext == 'jpg' ? 'jpeg' : ext}';
      final fileName = imageFile.path.split('/').last;
      final bytes = await imageFile.readAsBytes();

      final signed = await _gateway.getSignedUploadUrl(
        bucket: 'receipts',
        groupId: groupId,
        eventId: resolvedEventId,
        fileName: fileName,
        contentType: contentType,
        sizeBytes: bytes.length,
        expenseId: expenseId,
      );

      final uploadUri = Uri.parse(signed.uploadUrl);
      final uploadHeaders = {
        'Content-Type': contentType,
        'x-goog-content-length-range': '0,$_maxFileSizeBytes',
      };
      final response = _isStorageEmulatorUploadUrl(uploadUri)
          ? await _httpClient.post(
              uploadUri,
              headers: uploadHeaders,
              body: bytes,
            )
          : await _httpClient.put(
              uploadUri,
              headers: uploadHeaders,
              body: bytes,
            );
      if (response.statusCode < 200 || response.statusCode >= 300) {
        if (kDebugMode) {
          debugPrint(
            'ReceiptService.uploadReceipt upload failed: ${response.statusCode}',
          );
        }
        return null;
      }
      if (kDebugMode) debugPrint('Receipt uploaded: ${signed.storagePath}');
      return signed.storagePath;
    } on StorageException catch (e) {
      if (kDebugMode) debugPrint('Receipt upload failed: $e');
      return null;
    } catch (e) {
      if (kDebugMode) debugPrint('Receipt upload failed: $e');
      return null;
    }
  }

  bool _isStorageEmulatorUploadUrl(Uri uri) {
    return uri.path.startsWith('/upload/storage/v1/');
  }

  /// Fetch a signed download URL for a receipt via the callable.
  Future<String?> getReceiptUrl({
    required String groupId,
    required String eventId,
    required String storagePath,
  }) async {
    // Receipts are not in a Firestore subcollection the list callables cover,
    // so the consumer needs to derive the URL from getSignedUploadUrl is NOT
    // applicable for reads. Currently no list-receipts callable exists; the
    // UI reads receipts on-demand via deleteStorageObject + single download
    // pattern is deferred. For now return null to force callers to re-upload
    // paths, or wire a future getReceiptDownloadUrl callable.
    if (kDebugMode) {
      debugPrint(
        'ReceiptService.getReceiptUrl: no read callable — storagePath=$storagePath',
      );
    }
    return null;
  }

  /// Delete a receipt via the gated callable (idempotent server-side).
  Future<bool> deleteReceipt({
    required String groupId,
    required String storagePath,
  }) async {
    try {
      await _gateway.deleteStorageObject(
        storagePath: storagePath,
        groupId: groupId,
      );
      return true;
    } on StorageException catch (e) {
      if (kDebugMode) debugPrint('Failed to delete receipt: $e');
      return false;
    }
  }
}
