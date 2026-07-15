// AuthRecoveryService Apple pair (#1256): linkAppleToCurrentUser +
// restoreWithApple, mirroring the Google pair's protocol byte-for-byte —
// same load-bearing ordering (credential FIRST, FCM before isolation,
// guaranteed restart), same no-signOut-on-failure contract (#414/#213).

import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:safar/core/services/cache_isolation_controller.dart';
import 'package:safar/core/services/cache_uid_barrier.dart';
import 'package:safar/features/auth/services/apple_sign_in_gateway.dart';
import 'package:safar/features/auth/services/auth_recovery_service.dart';
import 'package:safar/features/auth/services/durable_credential_exception.dart';
import 'package:safar/features/auth/services/recovery_outcome.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';

class _MockFirebaseAuth extends Mock implements FirebaseAuth {}

class _MockUser extends Mock implements User {}

class _MockUserCredential extends Mock implements UserCredential {}

class _MockFirestore extends Mock implements FirebaseFirestore {}

class _FakeAuthCredential extends Fake implements AuthCredential {}

class _RecordingController implements CacheIsolationController {
  _RecordingController(this.events);
  final List<String> events;
  @override
  void engageIsolation() => events.add('engage');
  @override
  Future<void> restart() async => events.add('restart');
}

AppleCredentialBundle _bundle(AuthCredential credential) =>
    (credential: credential, authorizationCode: 'auth-code');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

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

  AuthRecoveryService buildService({
    required List<String> events,
    AppleCredentialFactory? appleCredentialFactory,
    FcmTokenRemover? removeFcmToken,
  }) {
    return AuthRecoveryService(
      auth: auth,
      prefs: prefs,
      firestore: firestore,
      cacheIsolationController: _RecordingController(events),
      appleCredentialFactory: appleCredentialFactory,
      removeFcmToken: removeFcmToken,
    );
  }

  group('linkAppleToCurrentUser (same-UID link)', () {
    test('links the factory credential to the current user', () async {
      final credential = _FakeAuthCredential();
      final userCredential = _MockUserCredential();
      when(() => userCredential.user).thenReturn(anonUser);
      when(
        () => anonUser.linkWithCredential(credential),
      ).thenAnswer((_) async => userCredential);

      final service = buildService(
        events: [],
        appleCredentialFactory: () async => _bundle(credential),
      );

      final result = await service.linkAppleToCurrentUser();

      expect(result, same(userCredential));
      verify(() => anonUser.linkWithCredential(credential)).called(1);
      verifyNever(() => auth.signOut());
    });

    test('no current user → StateError before any Apple sheet', () async {
      when(() => auth.currentUser).thenReturn(null);
      var factoryInvoked = false;

      final service = buildService(
        events: [],
        appleCredentialFactory: () async {
          factoryInvoked = true;
          return _bundle(_FakeAuthCredential());
        },
      );

      await expectLater(service.linkAppleToCurrentUser(), throwsStateError);
      expect(factoryInvoked, isFalse);
    });

    test('conflict rethrows AppleLinkConflictException carrying the SAME '
        'credential instance — never GoogleLinkConflictException', () async {
      final credential = _FakeAuthCredential();
      final cause = FirebaseAuthException(code: 'credential-already-in-use');
      when(() => anonUser.linkWithCredential(credential)).thenThrow(cause);

      final service = buildService(
        events: [],
        appleCredentialFactory: () async => _bundle(credential),
      );

      await expectLater(
        service.linkAppleToCurrentUser(),
        throwsA(
          isA<AppleLinkConflictException>()
              .having((e) => e.credential, 'credential', same(credential))
              .having((e) => e.cause, 'cause', same(cause)),
        ),
      );
    });

    test('email-already-in-use also classifies as a conflict', () async {
      final credential = _FakeAuthCredential();
      when(() => anonUser.linkWithCredential(credential))
          .thenThrow(FirebaseAuthException(code: 'email-already-in-use'));

      final service = buildService(
        events: [],
        appleCredentialFactory: () async => _bundle(credential),
      );

      await expectLater(
        service.linkAppleToCurrentUser(),
        throwsA(isA<AppleLinkConflictException>()),
      );
    });

    test('non-conflict FirebaseAuthException propagates unchanged', () async {
      final credential = _FakeAuthCredential();
      when(() => anonUser.linkWithCredential(credential))
          .thenThrow(FirebaseAuthException(code: 'network-request-failed'));

      final service = buildService(
        events: [],
        appleCredentialFactory: () async => _bundle(credential),
      );

      await expectLater(
        service.linkAppleToCurrentUser(),
        throwsA(
          isA<FirebaseAuthException>()
              .having((e) => e.code, 'code', 'network-request-failed'),
        ),
      );
    });
  });

  group('restoreWithApple (cross-UID discard-shell swap)', () {
    test(
      'obtains the credential, removes the FCM token, engages isolation, '
      'marks the cache dirty BEFORE the swap, signs in, then restarts',
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
          appleCredentialFactory: () async {
            events.add('obtainCredential');
            return _bundle(credential);
          },
          removeFcmToken: () async => events.add('removeToken'),
        );

        final result = await service.restoreWithApple();

        expect(result, same(userCredential));
        expect(events, [
          'obtainCredential',
          'removeToken',
          'engage',
          'signIn',
          'restart',
        ]);
        expect(dirtyAtSwap, isTrue);
        verifyNever(() => auth.signOut());
      },
    );

    test('success writes an opApple outcome with the expected uid', () async {
      final credential = _FakeAuthCredential();
      final userCredential = _MockUserCredential();
      final restoredUser = _MockUser();
      when(() => restoredUser.uid).thenReturn('durable-uid');
      when(() => userCredential.user).thenReturn(restoredUser);
      when(
        () => auth.signInWithCredential(credential),
      ).thenAnswer((_) async => userCredential);

      final service = buildService(
        events: [],
        appleCredentialFactory: () async => _bundle(credential),
      );

      await service.restoreWithApple();

      final outcome = readAndClearRecoveryOutcome(prefs);
      expect(outcome, isNotNull);
      expect(outcome!.op, RecoveryOutcome.opApple);
      expect(outcome.ok, isTrue);
      expect(outcome.expectedUid, 'durable-uid');
    });

    test('failure writes a failed opApple outcome, rethrows, still restarts, '
        'never signs out (#414/#213)', () async {
      final events = <String>[];
      final credential = _FakeAuthCredential();
      when(() => auth.signInWithCredential(credential)).thenAnswer((_) async {
        events.add('signIn');
        throw FirebaseAuthException(code: 'user-disabled');
      });

      final service = buildService(
        events: events,
        appleCredentialFactory: () async => _bundle(credential),
        removeFcmToken: () async => events.add('removeToken'),
      );

      await expectLater(
        service.restoreWithApple(),
        throwsA(isA<FirebaseAuthException>()),
      );
      expect(events, ['removeToken', 'engage', 'signIn', 'restart']);
      verifyNever(() => auth.signOut());

      final outcome = readAndClearRecoveryOutcome(prefs);
      expect(outcome!.op, RecoveryOutcome.opApple);
      expect(outcome.ok, isFalse);
      expect(outcome.code, 'user-disabled');
    });

    test('a cancelled Apple sheet aborts cleanly — no FCM removal, no '
        'isolation, no swap, no restart, anon shell untouched', () async {
      final events = <String>[];
      final service = buildService(
        events: events,
        appleCredentialFactory: () async =>
            throw const SignInWithAppleAuthorizationException(
          code: AuthorizationErrorCode.canceled,
          message: 'user canceled',
        ),
        removeFcmToken: () async => events.add('removeToken'),
      );

      await expectLater(
        service.restoreWithApple(),
        throwsA(isA<SignInWithAppleAuthorizationException>()),
      );
      expect(events, isEmpty);
      verifyNever(() => auth.signInWithCredential(any()));
      verifyNever(() => auth.signOut());
      expect(readAndClearRecoveryOutcome(prefs), isNull);
    });

    test('uses an injected credential without invoking the Apple sheet '
        '(the gate-conflict reuse path)', () async {
      final credential = _FakeAuthCredential();
      final userCredential = _MockUserCredential();
      when(() => userCredential.user).thenReturn(anonUser);
      when(
        () => auth.signInWithCredential(credential),
      ).thenAnswer((_) async => userCredential);
      var factoryInvoked = false;

      final service = buildService(
        events: [],
        appleCredentialFactory: () async {
          factoryInvoked = true;
          return _bundle(_FakeAuthCredential());
        },
      );

      await service.restoreWithApple(credential: credential);

      expect(factoryInvoked, isFalse);
      verify(() => auth.signInWithCredential(credential)).called(1);
    });

    test('still swaps and restarts when waitForPendingWrites exceeds the '
        'timeout', () async {
      final events = <String>[];
      final credential = _FakeAuthCredential();
      final userCredential = _MockUserCredential();
      when(() => userCredential.user).thenReturn(anonUser);
      when(
        firestore.waitForPendingWrites,
      ).thenAnswer((_) => Completer<void>().future);
      when(() => auth.signInWithCredential(credential)).thenAnswer((_) async {
        events.add('signIn');
        return userCredential;
      });

      final service = buildService(
        events: events,
        appleCredentialFactory: () async => _bundle(credential),
        removeFcmToken: () async => events.add('removeToken'),
      );

      await service.restoreWithApple(
        pendingWritesTimeout: const Duration(milliseconds: 50),
      );

      expect(events, ['removeToken', 'engage', 'signIn', 'restart']);
    });

    test('a non-timeout removeFcmToken error still aborts cleanly — no '
        'isolation, no swap, no restart (the bound is timeout-only)', () async {
      final events = <String>[];
      final credential = _FakeAuthCredential();
      final service = buildService(
        events: events,
        appleCredentialFactory: () async => _bundle(credential),
        removeFcmToken: () async => throw StateError('fcm delete failed'),
      );

      await expectLater(service.restoreWithApple(), throwsStateError);
      expect(events, isEmpty);
      verifyNever(() => auth.signInWithCredential(any()));
      verifyNever(() => auth.signOut());
    });

    test('default (un-injected) apple factory reaches the real gateway and '
        'aborts PRE-isolation in a test environment — shell untouched',
        () async {
      final events = <String>[];
      final service = AuthRecoveryService(
        auth: auth,
        prefs: prefs,
        firestore: firestore,
        cacheIsolationController: _RecordingController(events),
      );

      // No platform channel is live: the default factory must throw, and the
      // throw must land BEFORE isolation (credential-first ordering).
      await expectLater(service.restoreWithApple(), throwsA(anything));
      expect(events, isEmpty);
      verifyNever(() => auth.signInWithCredential(any()));
      verifyNever(() => auth.signOut());
    });
  });

  group('AppleLinkConflictException (#1256)', () {
    test('toString names Apple + the auth code, never the credential', () {
      final e = AppleLinkConflictException(
        credential: _FakeAuthCredential(),
        cause: FirebaseAuthException(code: 'credential-already-in-use'),
      );
      expect('$e', contains('Apple'));
      expect('$e', contains('credential-already-in-use'));
    });
  });
}
