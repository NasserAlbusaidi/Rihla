import 'dart:developer' as dev;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

import '../../firebase_options.dart';

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
  static Future<void> ensureAnonymousSession() async {
    // Wait for auth state restoration from disk (fires once on startup).
    final restoredUser = await auth.authStateChanges().first;
    if (restoredUser != null) {
      log('Firebase session restored (uid: ${restoredUser.uid})');
      await recoverRestoredSessionIfNeeded(
        verifyToken: () async {
          await restoredUser.getIdToken();
        },
        signOut: auth.signOut,
        signInAnonymously: _signInAnonymously,
      );
      return;
    }

    log('No persisted Firebase session — signing in anonymously');
    await _signInAnonymously();
  }

  static Future<void> _signInAnonymously() async {
    try {
      await auth.signInAnonymously();
      log(
        'Firebase anonymous session established (uid: ${auth.currentUser?.uid})',
      );
    } on FirebaseAuthException catch (e) {
      log(
        'Firebase anonymous sign-in failed: ${e.code} — ${e.message}',
        error: e,
      );
      rethrow;
    }
  }

  @visibleForTesting
  static Future<bool> recoverRestoredSessionIfNeeded({
    required Future<void> Function() verifyToken,
    required Future<void> Function() signOut,
    required Future<void> Function() signInAnonymously,
  }) async {
    try {
      await verifyToken();
      log('Firebase restored session token verified');
      return false;
    } on FirebaseAuthException catch (e, stackTrace) {
      if (e.code != 'internal-error') {
        log(
          'Firebase restored session token check failed: ${e.code} — ${e.message}',
          error: e,
          stackTrace: stackTrace,
        );
        return false;
      }

      log(
        'Firebase restored session token is invalid; creating a fresh anonymous session',
        error: e,
        stackTrace: stackTrace,
      );
      await signOut();
      await signInAnonymously();
      return true;
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
