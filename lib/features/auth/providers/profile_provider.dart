import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/user_profile_model.dart';
import '../services/profile_service.dart';
import '../providers/auth_provider.dart';

/// Provider for ProfileService
final profileServiceProvider = Provider<ProfileService>((ref) {
  return ProfileService();
});

/// Stream provider for the current user's profile
final userProfileProvider = StreamProvider<UserProfile?>((ref) {
  final user = ref.watch(currentUserProvider);
  if (user == null) return Stream.value(null);

  final service = ref.read(profileServiceProvider);

  // Create a stream that emits the profile and listens for updates
  // For now, we'll just fetch once and allow manual invalidation,
  // or use Supabase realtime if needed later.
  return Stream.fromFuture(service.getProfile(user.id));
});

/// Notifier to manage profile updates
class ProfileNotifier extends StateNotifier<AsyncValue<UserProfile?>> {
  final ProfileService _service;
  final Ref _ref;

  ProfileNotifier(this._service, this._ref)
    : super(const AsyncValue.loading()) {
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    final user = _ref.read(currentUserProvider);
    if (user == null) {
      state = const AsyncValue.data(null);
      return;
    }

    state = const AsyncValue.loading();
    try {
      final profile = await _service.getProfile(user.id);
      state = AsyncValue.data(profile);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }

  Future<void> updateProfile({String? displayName, String? avatarUrl}) async {
    final currentProfile = state.valueOrNull;
    if (currentProfile == null) return;

    final updatedProfile = currentProfile.copyWith(
      displayName: displayName,
      avatarUrl: avatarUrl,
    );

    state = const AsyncValue.loading();
    try {
      final result = await _service.updateProfile(updatedProfile);
      state = AsyncValue.data(result);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
      rethrow;
    }
  }
}

/// Provider for ProfileNotifier
final profileNotifierProvider =
    StateNotifierProvider<ProfileNotifier, AsyncValue<UserProfile?>>((ref) {
      final service = ref.read(profileServiceProvider);
      return ProfileNotifier(service, ref);
    });
