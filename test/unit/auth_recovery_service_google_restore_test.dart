import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:mocktail/mocktail.dart';
import 'package:safar/core/services/cache_isolation_controller.dart';
import 'package:safar/core/services/cache_uid_barrier.dart';
import 'package:safar/features/auth/services/auth_recovery_service.dart';
import 'package:safar/features/auth/services/recovery_outcome.dart';
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

  // The merge engine must NEVER be touched by the restore swap. Callers must
  // prove the outgoing shell empty before invoking this raw cross-UID swap; the
  // service itself has no merge machinery to rescue a populated shell.
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

    test('aborts before the swap when waitForPendingWrites exceeds the '
        'timeout', () async {
      final events = <String>[];
      final credential = _FakeAuthCredential();
      final userCredential = _MockUserCredential();
      when(() => userCredential.user).thenReturn(anonUser);
      // Never completes → exercises the timeout branch.
      when(
        firestore.waitForPendingWrites,
      ).thenAnswer((_) => Completer<void>().future);
      var factoryInvoked = false;
      when(() => auth.signInWithCredential(credential)).thenAnswer((_) async {
        events.add('signIn');
        return userCredential;
      });

      final service = buildService(
        events: events,
        googleCredentialFactory: () async {
          factoryInvoked = true;
          return credential;
        },
        removeFcmToken: () async => events.add('removeToken'),
      );

      await expectLater(
        service.restoreWithGoogle(
          pendingWritesTimeout: const Duration(milliseconds: 50),
        ),
        throwsA(isA<PendingWritesNotFlushedException>()),
      );

      // #1281: the preflight runs BEFORE the credential factory, FCM
      // removal, isolation, and the swap itself — an abort here leaves the
      // shell fully intact (no restart, nothing stranded).
      expect(factoryInvoked, isFalse);
      expect(events, isEmpty);
      verifyNever(() => auth.signInWithCredential(any()));
      verifyNever(() => auth.signOut());
      expect(readAndClearRecoveryOutcome(prefs), isNull);
    });

    test('still swaps and restarts when removeFcmToken hangs offline — the '
        'unbounded fcm_tokens delete never acks (#412/#664)', () async {
      final events = <String>[];
      final credential = _FakeAuthCredential();
      final userCredential = _MockUserCredential();
      when(() => userCredential.user).thenReturn(anonUser);
      when(() => auth.signInWithCredential(credential)).thenAnswer((_) async {
        events.add('signIn');
        return userCredential;
      });

      final service = buildService(
        events: events,
        googleCredentialFactory: () async => credential,
        // Never completes → models the offline unbounded fcm_tokens delete
        // (#412): the future does not ack until reconnect.
        removeFcmToken: () => Completer<void>().future,
      );

      // Test-side bound proves the PRODUCTION code returns; without the fix the
      // restore hangs on the FCM await and this fails fast at onTimeout.
      await service
          .restoreWithGoogle(
            pendingWritesTimeout: const Duration(milliseconds: 50),
          )
          .timeout(
            const Duration(seconds: 2),
            onTimeout: () => fail(
              'restoreWithGoogle hung on removeFcmToken — the unbounded await '
              'never returned (offline #412/#664)',
            ),
          );

      // FCM removal was bounded and skipped (no 'removeToken'); swap completed.
      expect(events, ['engage', 'signIn', 'restart']);
    });

    test('a non-timeout removeFcmToken error still aborts cleanly — no '
        'isolation, no swap, no restart (the bound is timeout-only)', () async {
      final events = <String>[];
      final credential = _FakeAuthCredential();
      final service = buildService(
        events: events,
        googleCredentialFactory: () async => credential,
        removeFcmToken: () async => throw StateError('fcm delete failed'),
      );

      await expectLater(service.restoreWithGoogle(), throwsStateError);
      expect(events, isEmpty);
      verifyNever(() => auth.signInWithCredential(any()));
      verifyNever(() => auth.signOut());
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
