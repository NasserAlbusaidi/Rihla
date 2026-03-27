import 'package:firebase_auth/firebase_auth.dart' as firebase_auth;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/firebase_config.dart';

/// Auth state provider — listens to Firebase auth changes.
final authStateProvider = StreamProvider<firebase_auth.User?>((ref) {
  return FirebaseConfig.authStateChanges;
});

/// Current user provider.
final currentUserProvider = Provider<firebase_auth.User?>((ref) {
  return ref.watch(authStateProvider).valueOrNull;
});

/// Auth service provider.
final authServiceProvider = Provider<AuthService>((ref) {
  return AuthService();
});

/// Minimal authentication service for anonymous auth.
class AuthService {
  /// Get current session token (Firebase ID token).
  Future<String?> get currentToken async {
    return await FirebaseConfig.currentUser?.getIdToken();
  }

  /// Check if user is authenticated.
  bool get isAuthenticated => FirebaseConfig.currentUser != null;
}
