import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:mocktail/mocktail.dart';
import 'package:safar/core/services/cache_isolation_controller.dart';
import 'package:safar/core/services/cache_uid_barrier.dart';
import 'package:safar/features/auth/services/auth_recovery_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _MockFirebaseAuth extends Mock implements FirebaseAuth {}

class _MockUser extends Mock implements User {}

class _MockUserCredential extends Mock implements UserCredential {}

class _MockFirestore extends Mock implements FirebaseFirestore {}

class _FakeAuthCredential extends Fake implements AuthCredential {}

/// Records the isolation/restart lifecycle into a shared event list so the
/// cross-UID restore swap ordering can be asserted alongside the auth-mock
/// and FCM events.
class _RecordingController implements CacheIsolationController {
  _RecordingController(this.events);
  final List<String> events;
  @override
  void engageIsolation() => events.add('engage');
  @override
  Future<void> restart() async => events.add('restart');
}

void main() {
  setUpAll(() {
    registerFallbackValue(_FakeAuthCredential());
  });

  late _MockFirebaseAuth auth;
  late _MockUser anonUser;
  late _MockFirestore firestore;
  late SharedPreferences prefs;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    auth = _MockFirebaseAuth();
    anonUser = _MockUser();
    firestore = _MockFirestore();
    when(() => auth.currentUser).thenReturn(anonUser);
    when(() => auth.signOut()).thenAnswer((_) async {});
    when(() => anonUser.uid).thenReturn('anon-uid-123');
    when(() => anonUser.isAnonymous).thenReturn(true);
    when(firestore.waitForPendingWrites).thenAnswer((_) async {});
  });

  // The merge engine must NEVER be touched by the restore swap — the
  // post-gate shell is provably empty, so there is nothing to migrate. Since
  // #441 PR4 the pin is structural: the client merge machinery no longer
  // exists on AuthRecoveryService.
  AuthRecoveryService buildService({
    required List<String> events,
    GoogleCredentialFactory? googleCredentialFactory,
    FcmTokenRemover? removeFcmToken,
    CacheIsolationController? cacheIsolationController,
  }) {
    return AuthRecoveryService(
      auth: auth,
      prefs: prefs,
      firestore: firestore,
      cacheIsolationController:
          cacheIsolationController ?? _RecordingController(events),
      googleCredentialFactory: googleCredentialFactory,
      removeFcmToken: removeFcmToken,
    );
  }

  group('restoreWithGoogle (cross-UID discard-shell swap)', () {
    test(
      'obtains the credential, removes the FCM token, engages isolation, marks '
      'the cache dirty BEFORE the swap, signs in, then restarts',
      () async {
        final events = <String>[];
        final credential = _FakeAuthCredential();
        final userCredential = _MockUserCredential();
        when(() => userCredential.user).thenReturn(anonUser);

        bool? dirtyAtSwap;
        when(() => auth.signInWithCredential(credential)).thenAnswer((_) async {
          dirtyAtSwap = prefs.getBool(kFirestorePersistenceDirtyKey);
          events.add('signIn');
          return userCredential;
        });

        final service = buildService(
          events: events,
          googleCredentialFactory: () async {
            events.add('obtainCredential');
            return credential;
          },
          removeFcmToken: () async => events.add('removeToken'),
        );

        final result = await service.restoreWithGoogle();

        expect(result, same(userCredential));
        // removeToken BEFORE engage (owner-only fcm rule + provider invalidation);
        // credential obtained FIRST (cancel-safe); restart LAST.
        expect(events, [
          'obtainCredential',
          'removeToken',
          'engage',
          'signIn',
          'restart',
        ]);
        // markFirestorePersistenceDirty was awaited before the swap.
        expect(dirtyAtSwap, isTrue);
        verifyNever(() => auth.signOut());
      },
    );

    test('uses an injected credential without invoking the Google sheet '
        '(the PR2 gate-conflict reuse path)', () async {
      final events = <String>[];
      final credential = _FakeAuthCredential();
      final userCredential = _MockUserCredential();
      when(() => userCredential.user).thenReturn(anonUser);
      when(
        () => auth.signInWithCredential(credential),
      ).thenAnswer((_) async => userCredential);
      var factoryInvoked = false;

      final service = buildService(
        events: events,
        googleCredentialFactory: () async {
          factoryInvoked = true;
          return _FakeAuthCredential();
        },
        removeFcmToken: () async => events.add('removeToken'),
      );

      await service.restoreWithGoogle(credential: credential);

      expect(factoryInvoked, isFalse);
      verify(() => auth.signInWithCredential(credential)).called(1);
    });

    test('restarts even if the swap throws (overlay never strands), '
        'and never signs out', () async {
      final events = <String>[];
      final credential = _FakeAuthCredential();
      when(() => auth.signInWithCredential(credential)).thenAnswer((_) async {
        events.add('signIn');
        throw FirebaseAuthException(code: 'network-request-failed');
      });

      final service = buildService(
        events: events,
        googleCredentialFactory: () async => credential,
        removeFcmToken: () async => events.add('removeToken'),
      );

      await expectLater(
        service.restoreWithGoogle(),
        throwsA(isA<FirebaseAuthException>()),
      );
      expect(events, ['removeToken', 'engage', 'signIn', 'restart']);
      verifyNever(() => auth.signOut());
    });

    test('a cancelled / failed sheet aborts cleanly — no FCM removal, no '
        'isolation, no swap, no restart, anon shell untouched', () async {
      final events = <String>[];
      final service = buildService(
        events: events,
        googleCredentialFactory: () async => throw const GoogleSignInException(
          code: GoogleSignInExceptionCode.canceled,
        ),
        removeFcmToken: () async => events.add('removeToken'),
      );

      await expectLater(
        service.restoreWithGoogle(),
        throwsA(isA<GoogleSignInException>()),
      );
      expect(events, isEmpty);
      verifyNever(() => auth.signInWithCredential(any()));
      verifyNever(() => auth.signOut());
    });

    test('still swaps and restarts when waitForPendingWrites exceeds the '
        'timeout', () async {
      final events = <String>[];
      final credential = _FakeAuthCredential();
      final userCredential = _MockUserCredential();
      when(() => userCredential.user).thenReturn(anonUser);
      // Never completes → exercises the timeout branch.
      when(
        firestore.waitForPendingWrites,
      ).thenAnswer((_) => Completer<void>().future);
      when(() => auth.signInWithCredential(credential)).thenAnswer((_) async {
        events.add('signIn');
        return userCredential;
      });

      final service = buildService(
        events: events,
        googleCredentialFactory: () async => credential,
        removeFcmToken: () async => events.add('removeToken'),
      );

      await service.restoreWithGoogle(
        pendingWritesTimeout: const Duration(milliseconds: 50),
      );

      expect(events, ['removeToken', 'engage', 'signIn', 'restart']);
    });
  });

  group('isGoogleAccountAlreadyInUse (conflict classifier for the gate)', () {
    test('true for credential-already-in-use and email-already-in-use, '
        'without reading e.credential', () {
      expect(
        isGoogleAccountAlreadyInUse(
          FirebaseAuthException(code: 'credential-already-in-use'),
        ),
        isTrue,
      );
      expect(
        isGoogleAccountAlreadyInUse(
          FirebaseAuthException(code: 'email-already-in-use'),
        ),
        isTrue,
      );
    });

    test('false for unrelated codes and non-FirebaseAuthException errors', () {
      expect(
        isGoogleAccountAlreadyInUse(
          FirebaseAuthException(code: 'wrong-password'),
        ),
        isFalse,
      );
      expect(isGoogleAccountAlreadyInUse(StateError('nope')), isFalse);
      expect(isGoogleAccountAlreadyInUse(Exception('nope')), isFalse);
    });
  });
}
