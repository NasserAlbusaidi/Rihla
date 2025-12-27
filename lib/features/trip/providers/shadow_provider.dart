import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/config/supabase_config.dart';
import '../providers/trip_provider.dart';
import '../models/trip_model.dart';

/// Provider for shadow profile operations
final shadowServiceProvider = Provider<ShadowService>((ref) {
  return ShadowService();
});

/// Provider for shadow profiles only (watches the main logistics participant stream)
final shadowProfilesProvider =
    Provider.family<AsyncValue<List<Participant>>, String>((ref, tripId) {
      final participants = ref.watch(tripLogisticsParticipantsProvider(tripId));
      return participants.whenData(
        (list) => list.where((p) => p.isShadow).toList(),
      );
    });

/// Provider for real (non-shadow) participants only
final realParticipantsProvider =
    Provider.family<AsyncValue<List<Participant>>, String>((ref, tripId) {
      final participants = ref.watch(tripLogisticsParticipantsProvider(tripId));
      return participants.whenData(
        (list) => list.where((p) => !p.isShadow).toList(),
      );
    });

/// Shadow profile service for CRUD operations
class ShadowService {
  SupabaseClient get _client => SupabaseConfig.client;

  Future<Participant?> createShadow({
    required String tripId,
    required String displayName,
  }) async {
    try {
      final userId = _client.auth.currentUser?.id;
      if (userId == null) return null;

      final data = await _client
          .from('participants')
          .insert({
            'trip_id': tripId,
            'display_name': displayName,
            'is_shadow': true,
            'created_by': userId,
            'role': 'MEMBER',
          })
          .select('*, profiles!user_id(display_name, avatar_url)')
          .single();

      return Participant.fromJson(data);
    } catch (e) {
      print('Error creating shadow: $e');
      return null;
    }
  }

  /// Merge a shadow profile with a real user (atomic)
  Future<bool> mergeParticipant({
    required String shadowId,
    required String realUserId,
  }) async {
    try {
      await _client.rpc(
        'merge_shadow_profile',
        params: {'p_shadow_id': shadowId, 'p_real_user_id': realUserId},
      );
      return true;
    } catch (e) {
      print('Error merging shadow: $e');
      return false;
    }
  }

  /// Vanish (delete) a shadow profile with all associated data
  Future<bool> vanishShadow(String shadowId) async {
    try {
      await _client.rpc(
        'vanish_shadow_profile',
        params: {'p_shadow_id': shadowId},
      );
      return true;
    } catch (e) {
      print('Error vanishing shadow: $e');
      return false;
    }
  }

  /// Update shadow display name
  Future<bool> updateShadowName({
    required String shadowId,
    required String newName,
  }) async {
    try {
      await _client
          .from('participants')
          .update({'display_name': newName})
          .eq('id', shadowId)
          .eq('is_shadow', true);
      return true;
    } catch (e) {
      print('Error updating shadow name: $e');
      return false;
    }
  }

  /// Get mergeable shadows (unmerged shadow profiles)
  Future<List<Participant>> getMergeableShadows(String tripId) async {
    try {
      final data = await _client
          .from('participants')
          .select('*, profiles!user_id(display_name, avatar_url)')
          .eq('trip_id', tripId)
          .eq('is_shadow', true)
          .isFilter('user_id', null);

      return data.map((json) => Participant.fromJson(json)).toList();
    } catch (e) {
      print('Error getting mergeable shadows: $e');
      return [];
    }
  }

  /// Get new participants (real users who might be merged)
  Future<List<Participant>> getNewParticipants(String tripId) async {
    try {
      final data = await _client
          .from('participants')
          .select('*, profiles!user_id(display_name, avatar_url)')
          .eq('trip_id', tripId)
          .eq('is_shadow', false);

      return data.map((json) => Participant.fromJson(json)).toList();
    } catch (e) {
      print('Error getting new participants: $e');
      return [];
    }
  }
}
