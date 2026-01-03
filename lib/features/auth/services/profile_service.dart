import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/user_profile_model.dart';
import '../../../core/config/supabase_config.dart';

class ProfileService {
  final SupabaseClient _client = SupabaseConfig.client;

  /// Fetch user profile by ID
  Future<UserProfile?> getProfile(String userId) async {
    try {
      final data = await _client
          .from('profiles')
          .select()
          .eq('id', userId)
          .single();

      return UserProfile.fromJson(data);
    } catch (e) {
      return null;
    }
  }

  /// Update user profile
  Future<UserProfile?> updateProfile(UserProfile profile) async {
    try {
      final data = await _client
          .from('profiles')
          .update({
            'display_name': profile.displayName,
            'avatar_url': profile.avatarUrl,
            'updated_at': DateTime.now().toIso8601String(),
          })
          .eq('id', profile.id)
          .select()
          .single();

      return UserProfile.fromJson(data);
    } catch (e) {
      rethrow;
    }
  }

  /// List of available SVG avatars (keys/identifiers)
  static const List<String> availableAvatars = [
    'mountains',
    'tent',
    'backpack',
    'compass',
    'map',
    'fire',
    'tree',
    'car',
    'camera',
    'stars',
  ];
}
