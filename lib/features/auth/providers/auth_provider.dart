import 'package:firebase_auth/firebase_auth.dart' as firebase_auth;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/firebase_config.dart';
import '../../../core/providers/settings_provider.dart';
import '../../../core/services/notification_service.dart';
import '../services/auth_recovery_service.dart';
import 'cache_isolation_controller_provider.dart';

/// Auth state provider — listens to Firebase auth changes.
final authStateProvider = StreamProvider<firebase_auth.User?>((ref) {
  return FirebaseConfig.authStateChanges;
});

/// Current user provider.
final currentUserProvider = Provider<firebase_auth.User?>((ref) {
  return ref.watch(authStateProvider).valueOrNull;
});

/// User-changes stream — fires on sign in/out AND on profile/email mutations
/// (the latter being what `linkWithCredential` triggers without changing the
/// UID). Use this anywhere downstream state depends on the linked email,
/// not just on whether *some* user is signed in.
///
/// Tolerates Firebase not being initialized (widget tests that mount real
/// screens but skip `Firebase.initializeApp`) by emitting `null` instead of
/// propagating the synchronous `core/no-app` exception.
final authUserChangesProvider = StreamProvider<firebase_auth.User?>((ref) {
  try {
    return FirebaseConfig.auth.userChanges();
  } catch (_) {
    return Stream<firebase_auth.User?>.value(null);
  }
});

/// Current Firebase UID, or null if no user is signed in. Re-emits on
/// every UID change (sign-in, sign-out, recovery flow).
final uidProvider = Provider<String?>((ref) {
  return ref.watch(authUserChangesProvider).valueOrNull?.uid;
});

/// The Google identity linked to the active Firebase user, or null when no
/// `google.com` provider entry exists (#428 PR-B). The email can be null
/// even when linked — render "linked" state from the record itself, never
/// from the email alone.
final googleAccountProvider = Provider<({String? email})?>((ref) {
  final user = ref.watch(authUserChangesProvider).valueOrNull;
  if (user == null) return null;
  for (final info in user.providerData) {
    if (info.providerId == 'google.com') {
      final email = info.email;
      return (email: (email == null || email.isEmpty) ? null : email);
    }
  }
  return null;
});

/// True when the current user holds ANY durable credential (Google or email
/// link) — i.e. is not anonymous. The Account card gates sign-out on this
/// (#428 PR-B): signing out an anonymous user orphans their data, while a
/// durable user can always sign back in.
final isDurableUserProvider = Provider<bool>((ref) {
  final user = ref.watch(authUserChangesProvider).valueOrNull;
  return user != null && !user.isAnonymous;
});

/// Email currently linked to the active Firebase user, or null when the
/// user is purely anonymous. Set by [AuthRecoveryService.completeEmailLink].
final linkedEmailProvider = Provider<String?>((ref) {
  final user = ref.watch(authUserChangesProvider).valueOrNull;
  final email = user?.email;
  if (email == null || email.isEmpty) return null;
  return email;
});

/// Singleton accessor for [FirebaseAuth] with a Riverpod-friendly wrapper so
/// tests can override the instance. In non-test builds it always returns
/// `FirebaseConfig.auth`; widget tests that mount production screens without
/// initializing Firebase override this with a fake [FirebaseAuth] (or just
/// leave it un-overridden and let the service-level providers no-op).
final firebaseAuthProvider = Provider<firebase_auth.FirebaseAuth>((ref) {
  return FirebaseConfig.auth;
});

final authRecoveryServiceProvider = Provider<AuthRecoveryService>((ref) {
  final prefs = ref.watch(sharedPreferencesProvider);
  final auth = ref.watch(firebaseAuthProvider);
  return AuthRecoveryService(
    auth: auth,
    prefs: prefs,
    cacheIsolationController: ref.read(cacheIsolationControllerProvider),
    // #441 PR3: delete fcm_tokens/{oldUid} BEFORE the discard-shell restore
    // swap (owner-only rules block it afterward). Read lazily at call time so
    // it hits the live notification service before engageIsolation invalidates it.
    removeFcmToken: () => ref.read(notificationServiceProvider).removeToken(),
  );
});
