import 'dart:developer' as dev;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

import '../../firebase_options.dart';

/// Firebase client configuration and initialization.
///
/// Mirrors the SupabaseConfig pattern. All Firebase initialization,
/// anonymous auth, and accessor getters live here.
class FirebaseConfig {
  static FirebaseAuth get auth => FirebaseAuth.instance;
  static FirebaseFirestore get firestore => FirebaseFirestore.instance;

  /// Initialize Firebase and configure Firestore offline persistence.
  ///
  /// Firestore settings MUST be applied before any other Firestore call
  /// (per Firebase SDK requirement — settings cannot be changed after use).
  static Future<void> initialize() async {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );

    // Configure Firestore offline persistence. Must be set before any
    // Firestore read/write to avoid "settings immutable" runtime error.
    FirebaseFirestore.instance.settings = const Settings(
      persistenceEnabled: true,
      cacheSizeBytes: Settings.CACHE_SIZE_UNLIMITED,
    );

    log('Firebase initialized with Firestore offline persistence enabled');
  }

  /// Ensure an anonymous Firebase session exists.
  ///
  /// If no user is currently signed in, signs in anonymously so that
  /// Firebase Auth UID is available for Firestore security rules.
  /// Mirrors the SupabaseConfig.ensureAnonymousSession() pattern (D-07).
  static Future<void> ensureAnonymousSession() async {
    if (auth.currentUser != null) {
      log('Firebase session already active (uid: ${auth.currentUser!.uid})');
      return;
    }
    log('No Firebase session found — signing in anonymously');
    try {
      await auth.signInAnonymously();
      log(
          'Firebase anonymous session established (uid: ${auth.currentUser?.uid})');
    } on FirebaseAuthException catch (e) {
      log('Firebase anonymous sign-in failed: ${e.code} — ${e.message}',
          error: e);
      // App continues without Firebase auth — features requiring auth
      // will degrade gracefully (null currentUser checks already in place).
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
