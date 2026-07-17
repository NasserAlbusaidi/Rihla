import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_test/flutter_test.dart';
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
    registerFallbackValue(ActionCodeSettings(url: 'https://example.com'));
  });

  late _MockFirebaseAuth auth;
  late _MockUser anonUser;
  late _MockFirestore firestore;
  late SharedPreferences prefs;

  const link =
      'https://rihla-safar.firebaseapp.com/__/auth/links/continue'
      '?mode=signIn&oobCode=test-oob';

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    auth = _MockFirebaseAuth();
    anonUser = _MockUser();
    firestore = _MockFirestore();
    when(() => auth.currentUser).thenReturn(anonUser);
    when(() => auth.signOut()).thenAnswer((_) async {});
    when(
      () => auth.sendSignInLinkToEmail(
        email: any(named: 'email'),
        actionCodeSettings: any(named: 'actionCodeSettings'),
      ),
    ).thenAnswer((_) async {});
    when(() => anonUser.uid).thenReturn('anon-uid-123');
    when(() => anonUser.isAnonymous).thenReturn(true);
    when(firestore.waitForPendingWrites).thenAnswer((_) async {});
  });

  // The merge engine was deleted in #441 PR4 — the no-merge pin is
  // structural (there is no cleanup-intent writer or callable wiring left
  // to invoke). These tests pin the swap protocol ordering and the
  // #414/#213 never-signOut invariant.
  AuthRecoveryService buildService({
    required List<String> events,
    FcmTokenRemover? removeFcmToken,
  }) {
    return AuthRecoveryService(
      auth: auth,
      prefs: prefs,
      firestore: firestore,
      cacheIsolationController: _RecordingController(events),
      removeFcmToken: removeFcmToken,
    );
  }

  group('restoreWithEmailLink (no-merge cross-UID discard-shell swap)', () {
    test(
      'removes the FCM token, engages isolation, marks the cache dirty '
      'BEFORE the swap, signs in with the email link, then restarts — '
      'and clears the op-state',
      () async {
        final events = <String>[];
        final userCredential = _MockUserCredential();
        when(() => userCredential.user).thenReturn(anonUser);

        bool? dirtyAtSwap;
        when(
          () => auth.signInWithEmailLink(
            email: 'saved@example.com',
            emailLink: link,
          ),
        ).thenAnswer((_) async {
          dirtyAtSwap = prefs.getBool(kFirestorePersistenceDirtyKey);
          events.add('signIn');
          return userCredential;
        });

        final service = buildService(
          events: events,
          removeFcmToken: () async => events.add('removeToken'),
        );
        // Arm the real op-state the way the send side does, so the
        // cleared-in-finally assertions below are non-vacuous.
        await service.sendRecoveryLink('saved@example.com');
        expect(service.readInFlightOp(), AuthRecoveryService.opRecover);

        final result = await service.restoreWithEmailLink(link);

        expect(result, same(userCredential));
        // removeToken BEFORE engage (owner-only fcm rule + provider
        // invalidation); restart LAST.
        expect(events, ['removeToken', 'engage', 'signIn', 'restart']);
        // markFirestorePersistenceDirty was awaited before the swap.
        expect(dirtyAtSwap, isTrue);
        expect(service.readPendingEmail(), isNull);
        expect(service.readInFlightOp(), isNull);
        verifyNever(() => auth.signOut());
      },
    );

    test('restarts AND clears op-state even if the swap throws '
        '(overlay never strands, no boot-loop), and never signs out', () async {
      final events = <String>[];
      when(
        () => auth.signInWithEmailLink(
          email: 'saved@example.com',
          emailLink: link,
        ),
      ).thenAnswer((_) async {
        events.add('signIn');
        throw FirebaseAuthException(code: 'invalid-action-code');
      });

      final service = buildService(
        events: events,
        removeFcmToken: () async => events.add('removeToken'),
      );
      await service.sendRecoveryLink('saved@example.com');

      await expectLater(
        service.restoreWithEmailLink(link),
        throwsA(isA<FirebaseAuthException>()),
      );
      expect(events, ['removeToken', 'engage', 'signIn', 'restart']);
      expect(service.readPendingEmail(), isNull);
      expect(service.readInFlightOp(), isNull);
      verifyNever(() => auth.signOut());
    });

    test('throws StateError BEFORE any side effect when no pending email '
        'and no override (shell fully intact)', () async {
      final events = <String>[];
      final service = buildService(
        events: events,
        removeFcmToken: () async => events.add('removeToken'),
      );

      await expectLater(service.restoreWithEmailLink(link), throwsStateError);
      expect(events, isEmpty);
      verifyNever(
        () => auth.signInWithEmailLink(
          email: any(named: 'email'),
          emailLink: any(named: 'emailLink'),
        ),
      );
    });

    test('overrideEmail wins over the persisted pending email', () async {
      final events = <String>[];
      final userCredential = _MockUserCredential();
      when(() => userCredential.user).thenReturn(anonUser);
      when(
        () => auth.signInWithEmailLink(
          email: 'override@example.com',
          emailLink: link,
        ),
      ).thenAnswer((_) async => userCredential);

      final service = buildService(events: events);
      await service.setPendingEmail('saved@example.com');

      await service.restoreWithEmailLink(
        link,
        overrideEmail: 'override@example.com',
      );

      verify(
        () => auth.signInWithEmailLink(
          email: 'override@example.com',
          emailLink: link,
        ),
      ).called(1);
    });

    test('aborts before the swap when waitForPendingWrites exceeds the '
        'timeout', () async {
      final events = <String>[];
      final userCredential = _MockUserCredential();
      when(() => userCredential.user).thenReturn(anonUser);
      // Never completes → exercises the timeout branch.
      when(
        firestore.waitForPendingWrites,
      ).thenAnswer((_) => Completer<void>().future);
      when(
        () => auth.signInWithEmailLink(
          email: 'saved@example.com',
          emailLink: link,
        ),
      ).thenAnswer((_) async {
        events.add('signIn');
        return userCredential;
      });

      final service = buildService(
        events: events,
        removeFcmToken: () async => events.add('removeToken'),
      );
      await service.setPendingEmail('saved@example.com');

      await expectLater(
        service.restoreWithEmailLink(
          link,
          pendingWritesTimeout: const Duration(milliseconds: 50),
        ),
        throwsA(isA<PendingWritesNotFlushedException>()),
      );

      // #1281: the preflight runs BEFORE FCM removal, isolation, and the
      // swap itself — an abort here leaves the shell fully intact (no
      // restart, nothing stranded). Decision 5: op-state is NOT cleared
      // (the try/finally that clears it is never entered).
      expect(events, isEmpty);
      verifyNever(
        () => auth.signInWithEmailLink(
          email: any(named: 'email'),
          emailLink: any(named: 'emailLink'),
        ),
      );
      verifyNever(() => auth.signOut());
      expect(service.readPendingEmail(), 'saved@example.com');
      expect(readAndClearRecoveryOutcome(prefs), isNull);
    });

    test('still swaps and restarts when removeFcmToken hangs offline — the '
        'unbounded fcm_tokens delete never acks (#412/#664)', () async {
      final events = <String>[];
      final userCredential = _MockUserCredential();
      when(() => userCredential.user).thenReturn(anonUser);
      when(
        () => auth.signInWithEmailLink(
          email: 'saved@example.com',
          emailLink: link,
        ),
      ).thenAnswer((_) async {
        events.add('signIn');
        return userCredential;
      });

      final service = buildService(
        events: events,
        // Never completes → models the offline unbounded fcm_tokens delete
        // (#412): the future does not ack until reconnect.
        removeFcmToken: () => Completer<void>().future,
      );
      await service.setPendingEmail('saved@example.com');

      // Test-side bound proves the PRODUCTION code returns; without the fix the
      // restore hangs on the FCM await and this fails fast at onTimeout.
      await service
          .restoreWithEmailLink(
            link,
            pendingWritesTimeout: const Duration(milliseconds: 50),
          )
          .timeout(
            const Duration(seconds: 2),
            onTimeout: () => fail(
              'restoreWithEmailLink hung on removeFcmToken — the unbounded '
              'await never returned (offline #412/#664)',
            ),
          );

      // FCM removal was bounded and skipped (no 'removeToken'); swap completed.
      expect(events, ['engage', 'signIn', 'restart']);
    });

    test('a non-timeout removeFcmToken error still aborts cleanly — no '
        'isolation, no swap, no restart (the bound is timeout-only)', () async {
      final events = <String>[];
      final service = buildService(
        events: events,
        removeFcmToken: () async => throw StateError('fcm delete failed'),
      );
      await service.setPendingEmail('saved@example.com');

      await expectLater(service.restoreWithEmailLink(link), throwsStateError);
      expect(events, isEmpty);
      verifyNever(
        () => auth.signInWithEmailLink(
          email: any(named: 'email'),
          emailLink: any(named: 'emailLink'),
        ),
      );
      verifyNever(() => auth.signOut());
    });
  });
}
