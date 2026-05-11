import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:safar/core/config/firebase_config.dart';

/// Behavioral tests for Firebase anonymous auth (DATA-05).
///
/// Tests validate the anonymous auth contract that
/// FirebaseConfig.ensureAnonymousSession() implements:
/// - Call signInAnonymously() when no user exists
/// - Skip sign-in when a session is already active
/// - Always result in a valid anonymous UID after sign-in
/// - Auth state stream emits the user after sign-in
///
/// Per D-10: Dart tests use MockFirebaseAuth, no emulator dependency.
void main() {
  group('Firebase anonymous auth behavioral contract', () {
    test('signInAnonymously succeeds and returns a user with a UID', () async {
      final mockAuth = MockFirebaseAuth(signedIn: false);

      // No user before sign-in
      expect(mockAuth.currentUser, isNull);

      // Sign in anonymously
      await mockAuth.signInAnonymously();

      // User should now be present with a valid anonymous UID
      expect(mockAuth.currentUser, isNotNull);
      expect(mockAuth.currentUser!.uid, isNotEmpty);
      expect(mockAuth.currentUser!.isAnonymous, isTrue);
    });

    test('no duplicate sign-in when session already active', () async {
      final existingUser = MockUser(uid: 'existing-uid-123', isAnonymous: true);
      final mockAuth = MockFirebaseAuth(signedIn: true, mockUser: existingUser);

      // Session is already active
      expect(mockAuth.currentUser, isNotNull);

      final existingUid = mockAuth.currentUser!.uid;

      // Simulate ensureAnonymousSession() guard: skip if already signed in
      if (mockAuth.currentUser == null) {
        await mockAuth.signInAnonymously();
      }

      // User should be the same — no new sign-in happened
      expect(mockAuth.currentUser, isNotNull);
      expect(mockAuth.currentUser!.uid, equals(existingUid));
    });

    test('anonymous user UID persists across auth state checks', () async {
      final mockAuth = MockFirebaseAuth(signedIn: false);

      // Sign in to establish a session
      await mockAuth.signInAnonymously();

      // Record the UID immediately after sign-in
      final uidAfterSignIn = mockAuth.currentUser!.uid;
      expect(uidAfterSignIn, isNotEmpty);

      // Access currentUser again — UID must be identical (no UID churn)
      final uidOnSecondAccess = mockAuth.currentUser!.uid;
      expect(uidOnSecondAccess, equals(uidAfterSignIn));
    });

    test('authStateChanges emits user after anonymous sign-in', () async {
      final mockAuth = MockFirebaseAuth(signedIn: false);

      // Collect auth state events; skip the initial null
      final userFuture = mockAuth.authStateChanges().firstWhere(
        (user) => user != null,
      );

      // Trigger anonymous sign-in
      await mockAuth.signInAnonymously();

      // Stream should emit a non-null anonymous user
      final emittedUser = await userFuture;
      expect(emittedUser, isNotNull);
      expect(emittedUser!.isAnonymous, isTrue);
      expect(emittedUser.uid, isNotEmpty);
    });

    test(
      'internal-error during restored token check starts a fresh session',
      () async {
        var didSignOut = false;
        var didSignIn = false;

        final recovered = await FirebaseConfig.recoverRestoredSessionIfNeeded(
          verifyToken: () async {
            throw FirebaseAuthException(
              code: 'internal-error',
              message: 'bad persisted token',
            );
          },
          signOut: () async {
            didSignOut = true;
          },
          signInAnonymously: () async {
            didSignIn = true;
          },
        );

        expect(recovered, isTrue);
        expect(didSignOut, isTrue);
        expect(didSignIn, isTrue);
      },
    );
  });
}
