import 'package:firebase_auth/firebase_auth.dart' as firebase_auth;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/firebase_config.dart';

/// Firebase auth state provider — listens to Firebase auth state changes.
///
/// Mirrors the Supabase authStateProvider pattern. Emits the current
/// Firebase User whenever auth state changes (sign-in, sign-out, token refresh).
final firebaseAuthStateProvider = StreamProvider<firebase_auth.User?>((ref) {
  return FirebaseConfig.authStateChanges;
});

/// Current Firebase user provider.
///
/// Returns the current Firebase user synchronously from the auth state stream.
/// Returns null if no user is signed in or the stream has not yet emitted.
final firebaseCurrentUserProvider = Provider<firebase_auth.User?>((ref) {
  return ref.watch(firebaseAuthStateProvider).valueOrNull;
});
