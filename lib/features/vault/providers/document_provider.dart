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
              .select('*, profiles!uploader_id(display_name)')
              .eq('trip_id', tripId)
              .order('created_at', ascending: false);

          return (docs as List)
              .map((json) => Document.fromJson(json as Map<String, dynamic>))
              .toList();
        } catch (e) {
          SupabaseConfig.log(
            'tripDocumentsProvider: FAILED to fetch',
            error: e,
          );
          return data
              .map((json) => Document.fromJson(json as Map<String, dynamic>))
              .toList();
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
        type: FileType.any,
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

      // Get public URL
      final fileUrl = _client.storage
          .from(_bucketName)
          .getPublicUrl(storagePath);

      SupabaseConfig.log('uploadFile: URL: $fileUrl');

      // Create document record
      final data = await _client
          .from('documents')
          .insert({
            'trip_id': tripId,
            'uploader_id': userId,
            'file_url': fileUrl,
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

  /// Delete a document
  Future<bool> deleteDocument(Document document) async {
    SupabaseConfig.log('deleteDocument: ${document.id}');

    try {
      // Extract storage path from URL
      final uri = Uri.parse(document.fileUrl);
      final pathSegments = uri.pathSegments;
      final bucketIndex = pathSegments.indexOf(_bucketName);
      if (bucketIndex >= 0 && bucketIndex < pathSegments.length - 1) {
        final storagePath = pathSegments.sublist(bucketIndex + 1).join('/');
        SupabaseConfig.log(
          'deleteDocument: Removing from storage: $storagePath',
        );

        await _client.storage.from(_bucketName).remove([storagePath]);
      }

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

  /// Get signed URL for private file access
  Future<String?> getSignedUrl(String fileUrl) async {
    try {
      final uri = Uri.parse(fileUrl);
      final pathSegments = uri.pathSegments;
      final bucketIndex = pathSegments.indexOf(_bucketName);
      if (bucketIndex >= 0 && bucketIndex < pathSegments.length - 1) {
        final storagePath = pathSegments.sublist(bucketIndex + 1).join('/');
        final signedUrl = await _client.storage
            .from(_bucketName)
            .createSignedUrl(storagePath, 3600); // 1 hour expiry
        return signedUrl;
      }
      return fileUrl; // Return original if can't parse
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
