import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/config/supabase_config.dart';
import '../../../core/services/local_database.dart';

/// Auth state provider - listens to Supabase auth changes
final authStateProvider = StreamProvider<User?>((ref) {
  return SupabaseConfig.client.auth.onAuthStateChange.map(
    (event) => event.session?.user,
  );
});

/// Current user provider
final currentUserProvider = Provider<User?>((ref) {
  return ref.watch(authStateProvider).valueOrNull;
});

/// Auth loading state
final authLoadingProvider = StateProvider<bool>((ref) => false);

/// Auth error state
final authErrorProvider = StateProvider<String?>((ref) => null);

/// Auth mode - sign in or sign up
final authModeProvider = StateProvider<AuthMode>((ref) => AuthMode.signIn);

enum AuthMode { signIn, signUp }

/// Auth service provider
final authServiceProvider = Provider<AuthService>((ref) {
  return AuthService(ref);
});

/// Authentication service class
class AuthService {
  final Ref _ref;

  AuthService(this._ref);

  SupabaseClient get _client => SupabaseConfig.client;

  /// Sign up with email and password
  Future<bool> signUp(String email, String password) async {
    _ref.read(authLoadingProvider.notifier).state = true;
    _ref.read(authErrorProvider.notifier).state = null;

    try {
      final response = await _client.auth.signUp(
        email: email,
        password: password,
        emailRedirectTo: null,
      );

      _ref.read(authLoadingProvider.notifier).state = false;

      if (response.user != null) {
        return true;
      } else {
        _ref.read(authErrorProvider.notifier).state =
            'Sign up failed. Please try again.';
        return false;
      }
    } on AuthException catch (e) {
      _ref.read(authErrorProvider.notifier).state = e.message;
      _ref.read(authLoadingProvider.notifier).state = false;
      return false;
    } catch (e) {
      _ref.read(authErrorProvider.notifier).state =
          'An unexpected error occurred';
      _ref.read(authLoadingProvider.notifier).state = false;
      return false;
    }
  }

  /// Sign in with email and password
  Future<bool> signIn(String email, String password) async {
    _ref.read(authLoadingProvider.notifier).state = true;
    _ref.read(authErrorProvider.notifier).state = null;

    try {
      final response = await _client.auth.signInWithPassword(
        email: email,
        password: password,
      );

      _ref.read(authLoadingProvider.notifier).state = false;
      return response.session != null;
    } on AuthException catch (e) {
      _ref.read(authErrorProvider.notifier).state = e.message;
      _ref.read(authLoadingProvider.notifier).state = false;
      return false;
    } catch (e) {
      _ref.read(authErrorProvider.notifier).state = 'Invalid email or password';
      _ref.read(authLoadingProvider.notifier).state = false;
      return false;
    }
  }

  /// Sign out current user
  Future<void> signOut() async {
    _ref.read(authLoadingProvider.notifier).state = true;

    try {
      // Clear local cache to ensure next user doesn't see this user's data
      await LocalDatabase.clearAll();
      await _client.auth.signOut();
    } finally {
      _ref.read(authLoadingProvider.notifier).state = false;
    }
  }

  /// Send password reset email
  Future<bool> sendPasswordResetEmail(String email) async {
    _ref.read(authLoadingProvider.notifier).state = true;
    _ref.read(authErrorProvider.notifier).state = null;

    try {
      await _client.auth.resetPasswordForEmail(
        email,
        redirectTo: 'io.supabase.rihla://reset-password',
      );
      _ref.read(authLoadingProvider.notifier).state = false;
      return true;
    } on AuthException catch (e) {
      _ref.read(authErrorProvider.notifier).state = e.message;
      _ref.read(authLoadingProvider.notifier).state = false;
      return false;
    } catch (e) {
      _ref.read(authErrorProvider.notifier).state =
          'An unexpected error occurred';
      _ref.read(authLoadingProvider.notifier).state = false;
      return false;
    }
  }

  /// Update password for the current user (used after reset link or from settings)
  Future<bool> updatePassword(String newPassword) async {
    _ref.read(authLoadingProvider.notifier).state = true;
    _ref.read(authErrorProvider.notifier).state = null;

    try {
      await _client.auth.updateUser(UserAttributes(password: newPassword));
      _ref.read(authLoadingProvider.notifier).state = false;
      return true;
    } on AuthException catch (e) {
      _ref.read(authErrorProvider.notifier).state = e.message;
      _ref.read(authLoadingProvider.notifier).state = false;
      return false;
    } catch (e) {
      _ref.read(authErrorProvider.notifier).state =
          'An unexpected error occurred';
      _ref.read(authLoadingProvider.notifier).state = false;
      return false;
    }
  }

  /// Get current session
  Session? get currentSession => _client.auth.currentSession;

  /// Check if user is authenticated
  bool get isAuthenticated => _client.auth.currentUser != null;
}
