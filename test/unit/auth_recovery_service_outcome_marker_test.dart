// #439 regression: the three swap methods end in a guaranteed restart, so
// failures (and successes) were invisible — the rethrow dies with the
// process and PR4's op-state clear left zero persistent trace. Each swap
// must persist a PII-safe RecoveryOutcome BEFORE the restart fires.
//
// Invariants pinned here: marker written before restart() (order recorded),
// rethrow intact, restart still guaranteed, NO signOut, op-state clear
// untouched.

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:safar/core/services/cache_isolation_controller.dart';
import 'package:safar/features/auth/services/auth_recovery_service.dart';
import 'package:safar/features/auth/services/recovery_outcome.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _MockFirebaseAuth extends Mock implements FirebaseAuth {}

class _MockUser extends Mock implements User {}

class _MockUserCredential extends Mock implements UserCredential {}

class _MockFirestore extends Mock implements FirebaseFirestore {}

class _FakeAuthCredential extends Fake implements AuthCredential {}

/// Records restart() AND snapshots the marker present at restart time, so
/// the write-BEFORE-restart ordering is asserted directly, not inferred.
class _MarkerSnappingController implements CacheIsolationController {
  _MarkerSnappingController(this.prefs);
  final SharedPreferences prefs;
  final List<String> events = [];
  String? markerAtRestart;

  @override
  void engageIsolation() => events.add('engage');

  @override
  Future<void> restart() async {
    markerAtRestart = prefs.getString(RecoveryOutcome.prefsKey);
    events.add('restart');
  }
}

void main() {
  setUpAll(() {
    registerFallbackValue(_FakeAuthCredential());
  });

  late _MockFirebaseAuth auth;
  late _MockUser anonUser;
  late _MockFirestore firestore;
  late SharedPreferences prefs;
  late _MarkerSnappingController controller;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    auth = _MockFirebaseAuth();
    anonUser = _MockUser();
    firestore = _MockFirestore();
    controller = _MarkerSnappingController(prefs);
    when(() => auth.currentUser).thenReturn(anonUser);
    when(() => auth.signOut()).thenAnswer((_) async {});
    when(() => anonUser.uid).thenReturn('anon-uid-123');
    when(() => anonUser.isAnonymous).thenReturn(true);
    when(firestore.waitForPendingWrites).thenAnswer((_) async {});
  });

  AuthRecoveryService buildService() => AuthRecoveryService(
        auth: auth,
        prefs: prefs,
        firestore: firestore,
        cacheIsolationController: controller,
        googleCredentialFactory: () async => _FakeAuthCredential(),
        removeFcmToken: () async {},
      );

  group('restoreWithEmailLink (the #439 report path)', () {
    test(
      'dead oobCode: failure marker persisted BEFORE the restart, '
      'rethrow + op-state clear + restart all intact, no signOut',
      () async {
        when(
          () => auth.signInWithEmailLink(
            email: any(named: 'email'),
            emailLink: any(named: 'emailLink'),
          ),
        ).thenThrow(FirebaseAuthException(code: 'invalid-action-code'));
        final service = buildService();
        await service.setPendingEmail('foo@example.com');

        await expectLater(
          service.restoreWithEmailLink('https://rihla-safar.web.app/x'),
          throwsA(
            isA<FirebaseAuthException>()
                .having((e) => e.code, 'code', 'invalid-action-code'),
          ),
        );

        expect(controller.events, ['engage', 'restart']);
        expect(controller.markerAtRestart, isNotNull,
            reason: '#439: the marker must already be on disk when the '
                'process dies inside restart()');
        final outcome = readAndClearRecoveryOutcome(prefs);
        expect(outcome!.op, RecoveryOutcome.opRecover);
        expect(outcome.ok, isFalse);
        expect(outcome.code, 'invalid-action-code');
        // PR4's boot-loop guard still ran.
        expect(service.readPendingEmail(), isNull);
        expect(service.readInFlightOp(), isNull);
        verifyNever(() => auth.signOut());
      },
    );

    test('success marker on a completed restore', () async {
      final restoredUser = _MockUser();
      when(() => restoredUser.uid).thenReturn('durable-uid-456');
      final userCredential = _MockUserCredential();
      when(() => userCredential.user).thenReturn(restoredUser);
      when(
        () => auth.signInWithEmailLink(
          email: any(named: 'email'),
          emailLink: any(named: 'emailLink'),
        ),
      ).thenAnswer((_) async => userCredential);
      final service = buildService();
      await service.setPendingEmail('foo@example.com');

      await service.restoreWithEmailLink('https://rihla-safar.web.app/x');

      expect(controller.markerAtRestart, isNotNull);
      final outcome = readAndClearRecoveryOutcome(prefs);
      expect(outcome!.op, RecoveryOutcome.opRecover);
      expect(outcome.ok, isTrue);
      expect(outcome.code, isNull);
      // #458: the boot notice verifies the swap actually survived the
      // restart against this UID.
      expect(outcome.expectedUid, 'durable-uid-456');
    });
  });

  group('restoreWithGoogle', () {
    test('failed signInWithCredential persists a failure marker pre-restart',
        () async {
      when(() => auth.signInWithCredential(any()))
          .thenThrow(FirebaseAuthException(code: 'user-disabled'));
      final service = buildService();

      await expectLater(
        service.restoreWithGoogle(),
        throwsA(isA<FirebaseAuthException>()),
      );

      expect(controller.markerAtRestart, isNotNull);
      final outcome = readAndClearRecoveryOutcome(prefs);
      expect(outcome!.op, RecoveryOutcome.opGoogle);
      expect(outcome.ok, isFalse);
      expect(outcome.code, 'user-disabled');
      verifyNever(() => auth.signOut());
    });

    test('success marker on a completed restore', () async {
      final restoredUser = _MockUser();
      when(() => restoredUser.uid).thenReturn('durable-uid-456');
      final userCredential = _MockUserCredential();
      when(() => userCredential.user).thenReturn(restoredUser);
      when(() => auth.signInWithCredential(any()))
          .thenAnswer((_) async => userCredential);
      final service = buildService();

      await service.restoreWithGoogle();

      final outcome = readAndClearRecoveryOutcome(prefs);
      expect(outcome!.op, RecoveryOutcome.opGoogle);
      expect(outcome.ok, isTrue);
      expect(outcome.expectedUid, 'durable-uid-456');
    });

    test('pre-isolation failure (credential obtain) writes NO marker — '
        'the shell is intact and the error surfaces normally', () async {
      final service = AuthRecoveryService(
        auth: auth,
        prefs: prefs,
        firestore: firestore,
        cacheIsolationController: controller,
        googleCredentialFactory: () async => throw StateError('canceled'),
        removeFcmToken: () async {},
      );

      await expectLater(service.restoreWithGoogle(), throwsStateError);

      expect(controller.events, isEmpty);
      expect(readAndClearRecoveryOutcome(prefs), isNull);
    });
  });

  group('signOutCurrentDevice', () {
    setUp(() {
      when(() => anonUser.email).thenReturn('foo@example.com');
      when(() => anonUser.isAnonymous).thenReturn(false);
    });

    test('failure marker when signOut throws', () async {
      when(() => auth.signOut()).thenThrow(
        FirebaseAuthException(code: 'network-request-failed'),
      );
      final service = buildService();

      await expectLater(
        service.signOutCurrentDevice(),
        throwsA(isA<FirebaseAuthException>()),
      );

      expect(controller.markerAtRestart, isNotNull);
      final outcome = readAndClearRecoveryOutcome(prefs);
      expect(outcome!.op, RecoveryOutcome.opSignOut);
      expect(outcome.ok, isFalse);
      expect(outcome.code, 'network-request-failed');
    });

    test('success marker on a completed sign-out', () async {
      final service = buildService();

      await service.signOutCurrentDevice();

      final outcome = readAndClearRecoveryOutcome(prefs);
      expect(outcome!.op, RecoveryOutcome.opSignOut);
      expect(outcome.ok, isTrue);
      // #458: sign-out's post-restart UID is unknowable pre-restart (a fresh
      // anon is minted on boot) — no expectedUid, and no success notice.
      expect(outcome.expectedUid, isNull);
    });
  });
}
