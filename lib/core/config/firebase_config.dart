import 'dart:async';
import 'dart:developer' as dev;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../firebase_options.dart';
import '../services/cache_uid_barrier.dart';
import '../services/firestore_cache_gate.dart';
import '../services/post_deletion_auth_barrier.dart';

/// Firebase client configuration and initialization.
///
/// Centralizes all Firebase initialization and configuration.
/// Anonymous auth, and accessor getters live here.
class FirebaseConfig {
  static FirebaseAuth get auth => FirebaseAuth.instance;
  static FirebaseFirestore get firestore => FirebaseFirestore.instance;

  /// Region-pinned Cloud Functions accessor.
  ///
  /// Server-side callables are deployed with `setGlobalOptions({region:
  /// 'us-central1'})`, so the client must use the same region to resolve.
  /// Emulator hookup (when `USE_FIREBASE_EMULATOR=true`) is wired in
  /// `main.dart` against this same instance.
  static FirebaseFunctions get functions =>
      FirebaseFunctions.instanceFor(region: 'us-central1');

  /// Initialize Firebase and configure Firestore offline persistence.
  ///
  /// Firestore settings MUST be applied before any other Firestore call
  /// (per Firebase SDK requirement — settings cannot be changed after use).
  static Future<void> initialize({
    bool useDebugAppCheck = !kReleaseMode,
  }) async {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );

    await FirebaseAppCheck.instance.activate(
      providerAndroid: useDebugAppCheck
          ? const AndroidDebugProvider()
          : const AndroidPlayIntegrityProvider(),
      providerApple: useDebugAppCheck
          ? const AppleDebugProvider()
          : const AppleAppAttestWithDeviceCheckFallbackProvider(),
    );

    // Configure Firestore offline persistence. Must be set before any
    // Firestore read/write to avoid "settings immutable" runtime error.
    FirebaseFirestore.instance.settings = const Settings(
      persistenceEnabled: true,
      cacheSizeBytes: Settings.CACHE_SIZE_UNLIMITED,
    );

    log('Firebase initialized with Firestore offline persistence enabled');
  }

  /// Ensures an anonymous Firebase Auth session exists on launch.
  ///
  /// Waits for Firebase Auth to restore any persisted session before
  /// deciding to create a new one. Without this wait, `currentUser`
  /// is null immediately after `initializeApp()` even when a session
  /// IS persisted — causing a new anonymous UID on every restart.
  ///
  /// A restored session's token is verified but NEVER discarded on failure
  /// (#213): a transient error must not mint a fresh UID and orphan an anon
  /// user's data — see [recoverRestoredSessionIfNeeded].
  ///
  /// The sole exception is a matching post-deletion UID marker (#1100), which
  /// proves the server already deleted that account before the restart.
  ///
  /// After the session settles, runs the cold-start cache barrier (#45): if the
  /// booted UID differs from the last-active UID, or an in-session swap left the
  /// dirty flag set, it clears the Firestore SDK on-device cache BEFORE the
  /// first read. Skipped via [runCacheBarrier] = false for in-session reauth,
  /// where `clearPersistence()` would throw on the already-started instance.
  static Future<void> ensureAnonymousSession({
    bool runCacheBarrier = true,
    FirebaseAuth? authOverride,
    SharedPreferences? prefs,
    FirestoreCacheGate? cacheGate,
    @visibleForTesting
    Future<void> Function(User restoredUser)? verifyTokenOverride,
  }) async {
    final authInstance = authOverride ?? auth;
    var swapped = false;
    SharedPreferences? resolvedPrefs;

    // Wait for auth state restoration from disk (fires once on startup).
    final restoredUser = await authInstance.authStateChanges().first;
    if (runCacheBarrier) {
      resolvedPrefs = prefs ?? await SharedPreferences.getInstance();
      swapped = await reconcilePostDeletionAuthSession(
        prefs: resolvedPrefs,
        restoredUid: restoredUser?.uid,
        signOut: authInstance.signOut,
      );
    }

    if (swapped) {
      log('Deleted Firebase session cleared — signing in anonymously');
      await _signInAnonymously(authInstance);
    } else if (restoredUser != null) {
      log('Firebase session restored (uid: ${restoredUser.uid})');
      // #105: do NOT await the token verify. `getIdToken()` performs a network
      // refresh (securetoken.googleapis.com) that would block the first frame
      // on a slow/offline cold start — keeping the user from offline-cached
      // Firestore data they already own, purely to detect a rare bad-session
      // case. Since #213 the verify is non-destructive (always returns false,
      // never swaps), so there is nothing to wait for: fire it in the
      // background. The SDK refreshes the token lazily once connectivity
      // recovers. `swapped` therefore stays false on the restored path.
      // `MockUser.getIdToken` cannot throw, so an `internal-error` cannot be
      // driven through this path in tests without a seam (#213 regression
      // coverage). The override is test-only; production uses getIdToken().
      unawaited(
        recoverRestoredSessionIfNeeded(
          verifyToken: () => verifyTokenOverride != null
              ? verifyTokenOverride(restoredUser)
              : restoredUser.getIdToken().then((_) {}),
        ),
      );
    } else {
      log('No persisted Firebase session — signing in anonymously');
      await _signInAnonymously(authInstance);
    }

    if (runCacheBarrier) {
      await _runCacheBarrier(
        authInstance: authInstance,
        swapped: swapped,
        prefs: resolvedPrefs ?? prefs,
        cacheGate: cacheGate,
      );
    }
  }

  /// Clears the Firestore SDK cache before the first read when this boot's UID
  /// does not own the current cache. The single `clearPersistence()` site (#45);
  /// legal here because no Firestore read/write has occurred yet this boot.
  static Future<void> _runCacheBarrier({
    required FirebaseAuth authInstance,
    required bool swapped,
    SharedPreferences? prefs,
    FirestoreCacheGate? cacheGate,
  }) async {
    final uid = authInstance.currentUser?.uid;
    if (uid == null) {
      log('Cache barrier skipped — no current uid after session settle');
      return;
    }
    final resolvedPrefs = prefs ?? await SharedPreferences.getInstance();
    await CacheUidBarrier(
      prefs: resolvedPrefs,
      cacheGate: cacheGate ?? FirebaseFirestoreCacheGate(),
    ).reconcile(uid, forceClear: swapped);
  }

  static Future<void> _signInAnonymously([FirebaseAuth? authOverride]) async {
    final authInstance = authOverride ?? auth;
    try {
      await authInstance.signInAnonymously();
      log(
        'Firebase anonymous session established (uid: ${authInstance.currentUser?.uid})',
      );
    } on FirebaseAuthException catch (e) {
      log(
        'Firebase anonymous sign-in failed: ${e.code} — ${e.message}',
        error: e,
      );
      rethrow;
    }
  }

  /// Verifies the restored session's ID token and records the result. Returns
  /// `false` always — it never discards the session.
  ///
  /// #213: a transient `getIdToken()` failure (App Check / Play Integrity
  /// rejection, or a network/backend hiccup during refresh) surfaces as
  /// `FirebaseAuthException` — most often `internal-error`, the SDK's catch-all.
  /// This must NEVER trigger `signOut()` + `signInAnonymously()`: for an
  /// anonymous user with no linked email, signing out mints a brand-new UID and
  /// irreversibly orphans all of their data under the abandoned UID. Keep the
  /// session — the SDK refreshes the token lazily once connectivity / App Check
  /// recovers, and Firestore offline persistence serves cached reads meanwhile.
  /// The UID is preserved throughout, so nothing is lost.
  ///
  /// Returns `bool` (always `false`) to keep the cache-barrier `forceClear`
  /// plumbing in [ensureAnonymousSession] intact; removing that plumbing is a
  /// separate follow-up now that this path can no longer produce a swap.
  @visibleForTesting
  static Future<bool> recoverRestoredSessionIfNeeded({
    required Future<void> Function() verifyToken,
  }) async {
    try {
      await verifyToken();
      log('Firebase restored session token verified');
      return false;
    } on FirebaseAuthException catch (e, stackTrace) {
      log(
        'Firebase restored session token check failed (session kept): '
        '${e.code} — ${e.message}',
        error: e,
        stackTrace: stackTrace,
      );
      return false;
    } catch (e, stackTrace) {
      // #105: this now runs unawaited, so a non-auth error must not escape as
      // an unhandled async error. The session is kept regardless (#213) and the
      // SDK refreshes the token lazily once connectivity / App Check recovers.
      log(
        'Firebase restored session token check failed with non-auth error '
        '(session kept): $e',
        error: e,
        stackTrace: stackTrace,
      );
      return false;
    }
  }

  /// Get the current Firebase authenticated user.
  static User? get currentUser => auth.currentUser;

  /// Check if a Firebase user is authenticated.
  static bool get isAuthenticated => currentUser != null;

  /// Firebase auth state changes stream.
  static Stream<User?> get authStateChanges => auth.authStateChanges();

  /// Log helper for Firebase operations (only logs in debug mode).
  static void log(String message, {Object? error, StackTrace? stackTrace}) {
    if (!kDebugMode) return;

    final timestamp = DateTime.now().toIso8601String().substring(11, 23);
    dev.log('[$timestamp] $message', name: 'Firebase');
    if (error != null) {
      dev.log('[$timestamp] Error: $error', name: 'Firebase');
      if (stackTrace != null) {
        dev.log('Stack: $stackTrace', name: 'Firebase');
      }
    }
  }
}
