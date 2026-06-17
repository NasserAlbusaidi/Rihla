import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:safar/core/services/cache_isolation_controller.dart';
import 'package:safar/core/services/cache_uid_barrier.dart';
import 'package:safar/features/auth/services/auth_recovery_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _MockFirebaseAuth extends Mock implements FirebaseAuth {}

class _MockUser extends Mock implements User {}

class _MockUserCredential extends Mock implements UserCredential {}

class _MockFirestore extends Mock implements FirebaseFirestore {}

class _FakeActionCodeSettings extends Fake implements ActionCodeSettings {}

class _FakeAuthCredential extends Fake implements AuthCredential {}

class _NoopController implements CacheIsolationController {
  @override
  void engageIsolation() {}
  @override
  Future<void> restart() async {}
}

/// Records the isolation/restart lifecycle into a shared event list so swap
/// ordering can be asserted alongside the auth-mock events.
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
    registerFallbackValue(_FakeActionCodeSettings());
    registerFallbackValue(_FakeAuthCredential());
  });

  late _MockFirebaseAuth auth;
  late _MockUser anonUser;
  late _MockFirestore defaultFirestore;
  late SharedPreferences prefs;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    auth = _MockFirebaseAuth();
    anonUser = _MockUser();
    when(() => auth.currentUser).thenReturn(anonUser);
    when(() => auth.signOut()).thenAnswer((_) async {});
    when(() => anonUser.uid).thenReturn('anon-uid-123');
    when(() => anonUser.email).thenReturn(null);
    when(() => anonUser.isAnonymous).thenReturn(true);
    when(() => anonUser.getIdToken(any())).thenAnswer((_) async => 'token');
    defaultFirestore = _MockFirestore();
    when(defaultFirestore.waitForPendingWrites).thenAnswer((_) async {});
  });

  AuthRecoveryService buildService({
    FirebaseFirestore? firestore,
    CacheIsolationController? cacheIsolationController,
  }) {
    return AuthRecoveryService(
      auth: auth,
      prefs: prefs,
      cacheIsolationController: cacheIsolationController ?? _NoopController(),
      firestore: firestore ?? defaultFirestore,
    );
  }

  group('pending email storage', () {
    test(
      'setPendingEmail trims and persists, readPendingEmail returns it',
      () async {
        final service = buildService();

        await service.setPendingEmail('  foo@example.com  ');

        expect(service.readPendingEmail(), 'foo@example.com');
        expect(prefs.getString('auth.pendingLinkEmail'), 'foo@example.com');
      },
    );

    test('setPendingEmail rejects empty / whitespace-only input', () async {
      final service = buildService();

      expect(() => service.setPendingEmail(''), throwsArgumentError);
      expect(() => service.setPendingEmail('   '), throwsArgumentError);
    });

    test('readPendingEmail returns null when nothing was saved', () {
      expect(buildService().readPendingEmail(), isNull);
    });

    test('clearPendingEmail removes the stored value', () async {
      final service = buildService();
      await service.setPendingEmail('foo@example.com');

      await service.clearPendingEmail();

      expect(service.readPendingEmail(), isNull);
    });
  });

  group('linkEmailToCurrentUser', () {
    test('persists email and forwards to sendSignInLinkToEmail', () async {
      when(
        () => auth.sendSignInLinkToEmail(
          email: any(named: 'email'),
          actionCodeSettings: any(named: 'actionCodeSettings'),
        ),
      ).thenAnswer((_) async {});
      final service = buildService();

      await service.linkEmailToCurrentUser('foo@example.com');

      expect(service.readPendingEmail(), 'foo@example.com');
      verify(
        () => auth.sendSignInLinkToEmail(
          email: 'foo@example.com',
          actionCodeSettings: any(named: 'actionCodeSettings'),
        ),
      ).called(1);
    });

    test('does not clear pending email if the send call throws', () async {
      when(
        () => auth.sendSignInLinkToEmail(
          email: any(named: 'email'),
          actionCodeSettings: any(named: 'actionCodeSettings'),
        ),
      ).thenThrow(FirebaseAuthException(code: 'too-many-requests'));
      final service = buildService();
      await service.setPendingEmail('foo@example.com');

      await expectLater(
        () => service.linkEmailToCurrentUser('foo@example.com'),
        throwsA(isA<FirebaseAuthException>()),
      );
      expect(service.readPendingEmail(), 'foo@example.com');
    });
  });

  group('completeEmailLink', () {
    const link =
        'https://rihla-safar.firebaseapp.com/__/auth/links/continue?mode=signIn&oobCode=abc';

    test('uses the persisted email and clears it on success', () async {
      final credential = _MockUserCredential();
      when(
        () => anonUser.linkWithCredential(any()),
      ).thenAnswer((_) async => credential);
      when(() => credential.user).thenReturn(anonUser);
      final service = buildService();
      await service.setPendingEmail('foo@example.com');

      final result = await service.completeEmailLink(link);

      expect(result, same(credential));
      verify(() => anonUser.linkWithCredential(any())).called(1);
      expect(service.readPendingEmail(), isNull);
    });

    test('uses overrideEmail when no pending email is saved', () async {
      final credential = _MockUserCredential();
      when(
        () => anonUser.linkWithCredential(any()),
      ).thenAnswer((_) async => credential);
      final service = buildService();

      await service.completeEmailLink(link, overrideEmail: 'bar@example.com');

      verify(() => anonUser.linkWithCredential(any())).called(1);
    });

    test('throws StateError when no email is available', () async {
      final service = buildService();

      await expectLater(
        () => service.completeEmailLink(link),
        throwsStateError,
      );
      verifyNever(() => anonUser.linkWithCredential(any()));
    });

    test('throws StateError when there is no current user', () async {
      when(() => auth.currentUser).thenReturn(null);
      final service = buildService();
      await service.setPendingEmail('foo@example.com');

      await expectLater(
        () => service.completeEmailLink(link),
        throwsStateError,
      );
    });

    test(
      'force-refreshes the ID token after linking so the next durable-gated '
      'write sees a non-anonymous token (#522)',
      () async {
        final credential = _MockUserCredential();
        when(
          () => anonUser.linkWithCredential(any()),
        ).thenAnswer((_) async => credential);
        when(() => credential.user).thenReturn(anonUser);
        final service = buildService();
        await service.setPendingEmail('foo@example.com');

        await service.completeEmailLink(link);

        verify(() => anonUser.getIdToken(true)).called(1);
      },
    );

    test(
      'a force-refresh failure does not fail an already-successful link (#522)',
      () async {
        final credential = _MockUserCredential();
        when(
          () => anonUser.linkWithCredential(any()),
        ).thenAnswer((_) async => credential);
        when(() => credential.user).thenReturn(anonUser);
        when(() => anonUser.getIdToken(any()))
            .thenThrow(FirebaseAuthException(code: 'network-request-failed'));
        final service = buildService();
        await service.setPendingEmail('foo@example.com');

        final result = await service.completeEmailLink(link);

        expect(result, same(credential));
        expect(service.readPendingEmail(), isNull);
      },
    );

    test(
      'leaves pending email intact when linkWithCredential throws',
      () async {
        when(
          () => anonUser.linkWithCredential(any()),
        ).thenThrow(FirebaseAuthException(code: 'credential-already-in-use'));
        final service = buildService();
        await service.setPendingEmail('foo@example.com');

        await expectLater(
          () => service.completeEmailLink(link),
          throwsA(isA<FirebaseAuthException>()),
        );
        expect(service.readPendingEmail(), 'foo@example.com');
      },
    );
  });

  group('signOutCurrentDevice', () {
    test('throws StateError for an ANONYMOUS user — the data-loss guard '
        '(#428: gate is durability, not email)', () async {
      when(() => anonUser.email).thenReturn(null);
      when(() => anonUser.isAnonymous).thenReturn(true);
      final service = buildService();

      await expectLater(service.signOutCurrentDevice, throwsStateError);
      verifyNever(() => auth.signOut());
    });

    test('proceeds for a Google-linked user with NO top-level email '
        '(#428 PR-B: durable gates sign-out, not email)', () async {
      when(() => anonUser.email).thenReturn(null);
      when(() => anonUser.isAnonymous).thenReturn(false);
      final firestore = _MockFirestore();
      when(firestore.waitForPendingWrites).thenAnswer((_) async {});
      final events = <String>[];
      when(() => auth.signOut()).thenAnswer((_) async => events.add('signOut'));
      final service = buildService(
        firestore: firestore,
        cacheIsolationController: _RecordingController(events),
      );

      await service.signOutCurrentDevice();

      expect(events, ['engage', 'signOut', 'restart']);
    });

    test(
      'engages isolation, marks dirty before signOut, then restarts '
      '(no in-session anon mint)',
      () async {
        when(() => anonUser.email).thenReturn('foo@example.com');
        when(() => anonUser.isAnonymous).thenReturn(false);
        final firestore = _MockFirestore();
        when(firestore.waitForPendingWrites).thenAnswer((_) async {});
        final events = <String>[];
        bool? dirtyAtSignOut;
        when(() => auth.signOut()).thenAnswer((_) async {
          dirtyAtSignOut = prefs.getBool(kFirestorePersistenceDirtyKey);
          events.add('signOut');
        });
        final service = buildService(
          firestore: firestore,
          cacheIsolationController: _RecordingController(events),
        );

        await service.signOutCurrentDevice();

        verify(firestore.waitForPendingWrites).called(1);
        expect(events, ['engage', 'signOut', 'restart']);
        expect(dirtyAtSignOut, isTrue);
      },
    );

    test('still restarts when waitForPendingWrites exceeds the timeout', () async {
      when(() => anonUser.email).thenReturn('foo@example.com');
      when(() => anonUser.isAnonymous).thenReturn(false);
      final firestore = _MockFirestore();
      // Future that never completes so we exercise the timeout branch.
      when(
        firestore.waitForPendingWrites,
      ).thenAnswer((_) => Completer<void>().future);
      final events = <String>[];
      when(() => auth.signOut()).thenAnswer((_) async => events.add('signOut'));
      final service = buildService(
        firestore: firestore,
        cacheIsolationController: _RecordingController(events),
      );

      await service.signOutCurrentDevice(
        pendingWritesTimeout: const Duration(milliseconds: 50),
      );

      expect(events, ['engage', 'signOut', 'restart']);
    });

    test('restarts even if signOut throws (overlay never strands)', () async {
      when(() => anonUser.email).thenReturn('foo@example.com');
      when(() => anonUser.isAnonymous).thenReturn(false);
      final firestore = _MockFirestore();
      when(firestore.waitForPendingWrites).thenAnswer((_) async {});
      final events = <String>[];
      when(() => auth.signOut()).thenAnswer((_) async {
        events.add('signOut');
        throw StateError('signOut boom');
      });
      final service = buildService(
        firestore: firestore,
        cacheIsolationController: _RecordingController(events),
      );

      await expectLater(service.signOutCurrentDevice(), throwsStateError);
      expect(events, ['engage', 'signOut', 'restart']);
    });
  });
}
