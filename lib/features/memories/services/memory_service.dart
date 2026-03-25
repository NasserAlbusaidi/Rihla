import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../../../core/config/supabase_config.dart';
import '../models/memory_model.dart';

/// Service for managing trip photo memories
class MemoryService {
  static const String _bucket = 'trip-memories';
  static const _uuid = Uuid();

  /// Get all memories for a trip, with signed URLs
  Future<List<Memory>> getMemories(String tripId) async {
    try {
      final data = await SupabaseConfig.client
          .from('trip_memories')
          .select('*')
          .eq('trip_id', tripId)
          .order('created_at', ascending: false);

      final memories =
          (data as List).map((json) => Memory.fromJson(json)).toList();

      // Generate signed URLs for all memories
      final withUrls = <Memory>[];
      for (final memory in memories) {
        try {
          final url = await SupabaseConfig.client.storage
              .from(_bucket)
              .createSignedUrl(memory.storagePath, 3600);
          withUrls.add(memory.copyWith(signedUrl: url));
        } catch (e) {
          debugPrint('Failed to get signed URL for ${memory.id}: $e');
          withUrls.add(memory);
        }
      }

      return withUrls;
    } catch (e) {
      debugPrint('Error fetching memories: $e');
      return [];
    }
  }

  /// Upload a photo from camera or gallery
  Future<Memory?> uploadPhoto({
    required String tripId,
    required ImageSource source,
    String? caption,
  }) async {
    try {
      final picker = ImagePicker();
      final picked = await picker.pickImage(
        source: source,
        maxWidth: 1920,
        maxHeight: 1920,
        imageQuality: 85,
      );

      if (picked == null) return null;

      final userId = SupabaseConfig.client.auth.currentUser?.id;
      if (userId == null) return null;

      final fileBytes = await picked.readAsBytes();
      final ext = picked.path.split('.').last.toLowerCase();
      final fileName = '${_uuid.v4()}.$ext';
      final storagePath = '$tripId/$fileName';

      // Upload to Supabase Storage
      await SupabaseConfig.client.storage
          .from(_bucket)
          .uploadBinary(storagePath, fileBytes, fileOptions: FileOptions(
            contentType: 'image/$ext',
          ));

      // Create database record
      final data = await SupabaseConfig.client
          .from('trip_memories')
          .insert({
            'trip_id': tripId,
            'uploaded_by': userId,
            'storage_path': storagePath,
            'caption': caption,
          })
          .select('*')
          .single();

      final memory = Memory.fromJson(data);

      // Get signed URL
      final url = await SupabaseConfig.client.storage
          .from(_bucket)
          .createSignedUrl(storagePath, 3600);

      return memory.copyWith(signedUrl: url);
    } catch (e) {
      debugPrint('Error uploading memory: $e');
      return null;
    }
  }

  /// Delete a memory
  Future<bool> deleteMemory(Memory memory) async {
    try {
      // Delete from storage
      await SupabaseConfig.client.storage
          .from(_bucket)
          .remove([memory.storagePath]);

      // Delete from database
      await SupabaseConfig.client
          .from('trip_memories')
          .delete()
          .eq('id', memory.id);

      return true;
    } catch (e) {
      debugPrint('Error deleting memory: $e');
      return false;
    }
  }
}
