import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/config/supabase_config.dart';
import '../models/document_model.dart';

/// Loading state for document operations
final documentLoadingProvider = StateProvider<bool>((ref) => false);

/// Error state for document operations
final documentErrorProvider = StateProvider<String?>((ref) => null);

/// Upload progress state
final uploadProgressProvider = StateProvider<double>((ref) => 0);

/// Stream of documents for a trip
final tripDocumentsProvider = StreamProvider.family<List<Document>, String>((
  ref,
  tripId,
) {
  SupabaseConfig.log('tripDocumentsProvider: Starting stream for trip $tripId');

  return SupabaseConfig.client
      .from('documents')
      .stream(primaryKey: ['id'])
      .eq('trip_id', tripId)
      .order('created_at', ascending: false)
      .asyncMap((data) async {
        SupabaseConfig.log(
          'tripDocumentsProvider: Got ${data.length} documents',
        );

        try {
          // Fetch with uploader profile info
          final docs = await SupabaseConfig.client
              .from('documents')
              .select('*')
              .eq('trip_id', tripId)
              .order('created_at', ascending: false);

          return (docs).map((json) => Document.fromJson(json)).toList();
        } catch (e) {
          SupabaseConfig.log(
            'tripDocumentsProvider: FAILED to fetch',
            error: e,
          );
          return data.map((json) => Document.fromJson(json)).toList();
        }
      });
});

/// Document service provider
final documentServiceProvider = Provider<DocumentService>((ref) {
  return DocumentService(ref);
});

/// Document service for CRUD and storage operations
class DocumentService {
  final Ref _ref;
  static const String _bucketName = 'trip-documents';
  static const int _maxFileSizeBytes = 25 * 1024 * 1024; // 25 MB
  static const List<String> _allowedExtensions = [
    'pdf', 'jpg', 'jpeg', 'png', 'gif', 'doc', 'docx',
    'xls', 'xlsx', 'txt', 'csv', 'heic', 'webp',
  ];

  // Cache for signed URLs: {fileUrl: (signedUrl, expiresAt)}
  final Map<String, (String, DateTime)> _signedUrlCache = {};

  DocumentService(this._ref);

  SupabaseClient get _client => SupabaseConfig.client;

  /// Pick and upload a file
  Future<Document?> pickAndUpload({required String tripId}) async {
    _ref.read(documentLoadingProvider.notifier).state = true;
    _ref.read(documentErrorProvider.notifier).state = null;
    _ref.read(uploadProgressProvider.notifier).state = 0;

    try {
      // Pick file
      SupabaseConfig.log('pickAndUpload: Opening file picker');
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: _allowedExtensions,
        allowMultiple: false,
      );

      if (result == null || result.files.isEmpty) {
        SupabaseConfig.log('pickAndUpload: User cancelled');
        _ref.read(documentLoadingProvider.notifier).state = false;
        return null;
      }

      final file = result.files.first;
      if (file.path == null) {
        throw Exception('Could not access file');
      }

      // Validate file size
      if (file.size > _maxFileSizeBytes) {
        _ref.read(documentErrorProvider.notifier).state =
            'File too large. Maximum size is 25 MB.';
        _ref.read(documentLoadingProvider.notifier).state = false;
        return null;
      }

      SupabaseConfig.log(
        'pickAndUpload: Selected ${file.name} (${file.size} bytes)',
      );

      // Upload to storage
      final document = await uploadFile(
        tripId: tripId,
        filePath: file.path!,
        fileName: file.name,
        fileSize: file.size,
        mimeType: _getMimeType(file.extension ?? ''),
      );

      _ref.read(documentLoadingProvider.notifier).state = false;
      return document;
    } catch (e) {
      SupabaseConfig.log('pickAndUpload: FAILED', error: e);
      _ref.read(documentErrorProvider.notifier).state = e.toString();
      _ref.read(documentLoadingProvider.notifier).state = false;
      return null;
    }
  }

  /// Upload a file to storage and create document record
  Future<Document?> uploadFile({
    required String tripId,
    required String filePath,
    required String fileName,
    required int fileSize,
    String? mimeType,
  }) async {
    try {
      final userId = _client.auth.currentUser?.id;
      if (userId == null) throw Exception('Not authenticated');

      // Generate unique path
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final storagePath = '$tripId/$timestamp-$fileName';

      SupabaseConfig.log('uploadFile: Uploading to $storagePath');

      // Upload to Supabase Storage
      final file = File(filePath);
      final uploadPath = await _client.storage
          .from(_bucketName)
          .upload(
            storagePath,
            file,
            fileOptions: FileOptions(contentType: mimeType),
          );

      SupabaseConfig.log('uploadFile: Uploaded, path: $uploadPath');

      // Store the storage path, not a public URL — use signed URLs for access
      SupabaseConfig.log('uploadFile: Stored path: $storagePath');

      // Create document record
      final data = await _client
          .from('documents')
          .insert({
            'trip_id': tripId,
            'uploader_id': userId,
            'file_url': storagePath,
            'file_name': fileName,
            'file_size': fileSize,
            'mime_type': mimeType,
          })
          .select()
          .single();

      SupabaseConfig.log('uploadFile: SUCCESS - document id: ${data['id']}');
      _ref.read(uploadProgressProvider.notifier).state = 1.0;

      return Document.fromJson(data);
    } catch (e) {
      SupabaseConfig.log('uploadFile: FAILED', error: e);
      _ref.read(documentErrorProvider.notifier).state = e.toString();
      return null;
    }
  }

  /// Delete a document (uploader only)
  Future<bool> deleteDocument(Document document) async {
    SupabaseConfig.log('deleteDocument: ${document.id}');

    try {
      // Verify current user is the uploader
      final userId = _client.auth.currentUser?.id;
      if (userId == null) return false;
      if (document.uploaderId != userId) {
        _ref.read(documentErrorProvider.notifier).state =
            'Only the uploader can delete this document';
        return false;
      }

      // Determine storage path — handle both legacy URLs and new path format
      final fileUrl = document.fileUrl;
      String storagePath;
      if (fileUrl.startsWith('http')) {
        // Legacy: extract path from full URL
        final uri = Uri.parse(fileUrl);
        final pathSegments = uri.pathSegments;
        final bucketIndex = pathSegments.indexOf(_bucketName);
        if (bucketIndex >= 0 && bucketIndex < pathSegments.length - 1) {
          storagePath = pathSegments.sublist(bucketIndex + 1).join('/');
        } else {
          storagePath = fileUrl;
        }
      } else {
        // New format: fileUrl is already the storage path
        storagePath = fileUrl;
      }

      SupabaseConfig.log('deleteDocument: Removing from storage: $storagePath');
      await _client.storage.from(_bucketName).remove([storagePath]);

      // Delete database record
      await _client.from('documents').delete().eq('id', document.id);

      SupabaseConfig.log('deleteDocument: SUCCESS');
      return true;
    } catch (e) {
      SupabaseConfig.log('deleteDocument: FAILED', error: e);
      _ref.read(documentErrorProvider.notifier).state = e.toString();
      return false;
    }
  }

  /// Get signed URL for private file access with caching
  Future<String?> getSignedUrl(String fileUrl) async {
    // Check cache first (with 5-minute buffer)
    if (_signedUrlCache.containsKey(fileUrl)) {
      final (signedUrl, expiresAt) = _signedUrlCache[fileUrl]!;
      if (DateTime.now().isBefore(
        expiresAt.subtract(const Duration(minutes: 5)),
      )) {
        SupabaseConfig.log('getSignedUrl: Using cached URL');
        return signedUrl;
      }
    }

    try {
      // Determine storage path — handle both legacy URLs and new path format
      String storagePath;
      if (fileUrl.startsWith('http')) {
        // Legacy: extract path from full URL
        final uri = Uri.parse(fileUrl);
        final pathSegments = uri.pathSegments;
        final bucketIndex = pathSegments.indexOf(_bucketName);
        if (bucketIndex >= 0 && bucketIndex < pathSegments.length - 1) {
          storagePath = pathSegments.sublist(bucketIndex + 1).join('/');
        } else {
          return fileUrl; // Can't parse, return original
        }
      } else {
        // New format: fileUrl is already the storage path
        storagePath = fileUrl;
      }

      SupabaseConfig.log(
        'getSignedUrl: Fetching fresh signed URL for $storagePath',
      );

      final signedUrl = await _client.storage
          .from(_bucketName)
          .createSignedUrl(storagePath, 3600); // 1 hour expiry

      // Cache it
      _signedUrlCache[fileUrl] = (
        signedUrl,
        DateTime.now().add(const Duration(seconds: 3600)),
      );

      return signedUrl;
    } catch (e) {
      SupabaseConfig.log('getSignedUrl: FAILED', error: e);
      return null;
    }
  }

  /// Get mime type from extension
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
