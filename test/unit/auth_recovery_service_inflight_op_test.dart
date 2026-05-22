import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:safar/features/auth/models/account_job_status.dart';
import 'package:safar/features/auth/services/auth_recovery_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _MockFirebaseAuth extends Mock implements FirebaseAuth {}

class _MockUser extends Mock implements User {}

class _MockUserCredential extends Mock implements UserCredential {}

class _MockFirestore extends Mock implements FirebaseFirestore {}

class _FakeActionCodeSettings extends Fake implements ActionCodeSettings {}

class _FakeAuthCredential extends Fake implements AuthCredential {}

void main() {
  setUpAll(() {
    registerFallbackValue(_FakeActionCodeSettings());
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
    when(() => anonUser.uid).thenReturn('anon-uid');
    when(() => anonUser.email).thenReturn(null);
    when(() => anonUser.isAnonymous).thenReturn(true);
    when(firestore.waitForPendingWrites).thenAnswer((_) async {});
    when(
      () => auth.sendSignInLinkToEmail(
        email: any(named: 'email'),
        actionCodeSettings: any(named: 'actionCodeSettings'),
      ),
    ).thenAnswer((_) async {});
  });

  AuthRecoveryService buildService() => AuthRecoveryService(
    auth: auth,
    prefs: prefs,
    firestore: firestore,
    claimRecoveryCleanupJob: ({required oldUid, required cleanupSecret}) async {
      return const AccountJobStatusSnapshot(
        jobId: 'recovery-job',
        kind: AccountJobKind.recoveryCleanup,
        status: AccountJobRunStatus.complete,
        phase: 'Complete',
      );
    },
    advanceRecoveryCleanupJob: ({required jobId}) async {
      return AccountJobStatusSnapshot(
        jobId: jobId,
        kind: AccountJobKind.recoveryCleanup,
        status: AccountJobRunStatus.complete,
        phase: 'Complete',
      );
    },
    cleanupIntentFactory: (_) async => 'test-cleanup-secret',
  );

  group('inFlightOp tracking', () {
    test('starts as null', () {
      expect(buildService().readInFlightOp(), isNull);
    });

    test('linkEmailToCurrentUser sets opLink', () async {
      final service = buildService();
      await service.linkEmailToCurrentUser('foo@example.com');

      expect(service.readInFlightOp(), AuthRecoveryService.opLink);
    });

    test('sendRecoveryLink sets opRecover', () async {
      final service = buildService();
      await service.sendRecoveryLink('foo@example.com');

      expect(service.readInFlightOp(), AuthRecoveryService.opRecover);
    });

    test('clearInFlightOp resets to null', () async {
      final service = buildService();
      await service.linkEmailToCurrentUser('foo@example.com');
      await service.clearInFlightOp();

      expect(service.readInFlightOp(), isNull);
    });

    test('readInFlightOp ignores unknown stored values', () async {
      await prefs.setString('auth.inFlightOp', 'garbage');
      expect(buildService().readInFlightOp(), isNull);
    });

    test(
      'completeEmailLink clears both pending email and inFlightOp',
      () async {
        final service = buildService();
        await service.linkEmailToCurrentUser('foo@example.com');
        expect(service.readPendingEmail(), 'foo@example.com');
        expect(service.readInFlightOp(), AuthRecoveryService.opLink);

        final cred = _MockUserCredential();
        when(
          () => anonUser.linkWithCredential(any()),
        ).thenAnswer((_) async => cred);
        when(() => cred.user).thenReturn(anonUser);

        await service.completeEmailLink('https://example/link');

        expect(service.readPendingEmail(), isNull);
        expect(service.readInFlightOp(), isNull);
      },
    );

    test('completeRecovery clears both pending email and inFlightOp', () async {
      final service = buildService();
      await service.sendRecoveryLink('foo@example.com');

      final cred = _MockUserCredential();
      when(
        () => auth.signInWithEmailLink(
          email: any(named: 'email'),
          emailLink: any(named: 'emailLink'),
        ),
      ).thenAnswer((_) async => cred);
      when(() => cred.user).thenReturn(anonUser);

      await service.completeRecovery('https://example/link');

      expect(service.readPendingEmail(), isNull);
      expect(service.readInFlightOp(), isNull);
    });
  });
}
