import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
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
    defaultFirestore = _MockFirestore();
    when(defaultFirestore.waitForPendingWrites).thenAnswer((_) async {});
  });

  AuthRecoveryService buildService({
    FirebaseFirestore? firestore,
    Future<void> Function()? anonymousSessionFactory,
    Future<void> Function(String oldUid)? cleanupAnonUidArtifacts,
    void Function({
      required String message,
      required Map<String, Object?> data,
    })?
    recoveryCleanupFailureRecorder,
  }) {
    return AuthRecoveryService(
      auth: auth,
      prefs: prefs,
      firestore: firestore ?? defaultFirestore,
      anonymousSessionFactory: anonymousSessionFactory ?? () async {},
      cleanupAnonUidArtifacts: cleanupAnonUidArtifacts ?? (_) async {},
      recoveryCleanupFailureRecorder: recoveryCleanupFailureRecorder,
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

  group('completeRecovery', () {
    const link =
        'https://rihla-safar.firebaseapp.com/__/auth/links/continue?mode=signIn&oobCode=abc';

    test(
      'calls signInWithEmailLink with the persisted email and clears it',
      () async {
        final credential = _MockUserCredential();
        when(
          () => auth.signInWithEmailLink(
            email: any(named: 'email'),
            emailLink: any(named: 'emailLink'),
          ),
        ).thenAnswer((_) async => credential);
        final service = buildService();
        await service.setPendingEmail('foo@example.com');

        final result = await service.completeRecovery(link);

        expect(result, same(credential));
        verify(
          () => auth.signInWithEmailLink(
            email: 'foo@example.com',
            emailLink: link,
          ),
        ).called(1);
        expect(service.readPendingEmail(), isNull);
      },
    );

    test(
      'drains pending writes and signs out anon UID before recovery',
      () async {
        final credential = _MockUserCredential();
        final firestore = _MockFirestore();
        when(firestore.waitForPendingWrites).thenAnswer((_) async {});
        when(() => auth.signOut()).thenAnswer((_) async {});
        when(
          () => auth.signInWithEmailLink(
            email: any(named: 'email'),
            emailLink: any(named: 'emailLink'),
          ),
        ).thenAnswer((_) async => credential);
        final service = buildService(firestore: firestore);
        await service.setPendingEmail('foo@example.com');

        await service.completeRecovery(link);

        verifyInOrder([
          firestore.waitForPendingWrites,
          () => auth.signOut(),
          () => auth.signInWithEmailLink(
            email: 'foo@example.com',
            emailLink: link,
          ),
        ]);
      },
    );

    test(
      'invokes cleanup callable after signInWithEmailLink with captured anon UID',
      () async {
        final credential = _MockUserCredential();
        final calls = <String>[];
        when(defaultFirestore.waitForPendingWrites).thenAnswer((_) async {
          calls.add('waitForPendingWrites');
        });
        when(() => auth.signOut()).thenAnswer((_) async {
          calls.add('signOut');
        });
        when(
          () => auth.signInWithEmailLink(
            email: any(named: 'email'),
            emailLink: any(named: 'emailLink'),
          ),
        ).thenAnswer((_) async {
          calls.add('signInWithEmailLink');
          return credential;
        });
        final service = buildService(
          cleanupAnonUidArtifacts: (oldUid) async {
            calls.add('cleanup:$oldUid');
          },
        );
        await service.setPendingEmail('foo@example.com');

        final result = await service.completeRecovery(link);

        expect(result, same(credential));
        expect(calls, [
          'waitForPendingWrites',
          'signOut',
          'signInWithEmailLink',
          'cleanup:anon-uid-123',
        ]);
      },
    );

    test('recovery succeeds when cleanup callable throws', () async {
      final credential = _MockUserCredential();
      when(
        () => auth.signInWithEmailLink(
          email: any(named: 'email'),
          emailLink: any(named: 'emailLink'),
        ),
      ).thenAnswer((_) async => credential);
      final breadcrumbs = <Map<String, Object?>>[];
      final service = buildService(
        cleanupAnonUidArtifacts: (_) async {
          throw StateError('cleanup failed for foo@example.com');
        },
        recoveryCleanupFailureRecorder: ({required message, required data}) {
          breadcrumbs.add({'message': message, ...data});
        },
      );
      await service.setPendingEmail('foo@example.com');

      final result = await service.completeRecovery(link);
      await Future<void>.delayed(Duration.zero);

      expect(result, same(credential));
      expect(breadcrumbs, hasLength(1));
    });

    test('cleanup failure breadcrumb excludes email PII', () async {
      final credential = _MockUserCredential();
      when(
        () => auth.signInWithEmailLink(
          email: any(named: 'email'),
          emailLink: any(named: 'emailLink'),
        ),
      ).thenAnswer((_) async => credential);
      final breadcrumbs = <Map<String, Object?>>[];
      final service = buildService(
        cleanupAnonUidArtifacts: (_) async {
          throw StateError('cleanup failed for foo@example.com');
        },
        recoveryCleanupFailureRecorder: ({required message, required data}) {
          breadcrumbs.add({'message': message, ...data});
        },
      );
      await service.setPendingEmail('foo@example.com');

      await service.completeRecovery(link);
      await Future<void>.delayed(Duration.zero);

      final serialized = breadcrumbs.single.toString();
      expect(serialized, isNot(contains('foo@example.com')));
      expect(serialized, contains('StateError'));
    });

    test('continues recovery when pending writes exceed the timeout', () async {
      final credential = _MockUserCredential();
      final firestore = _MockFirestore();
      when(
        firestore.waitForPendingWrites,
      ).thenAnswer((_) => Completer<void>().future);
      when(() => auth.signOut()).thenAnswer((_) async {});
      when(
        () => auth.signInWithEmailLink(
          email: any(named: 'email'),
          emailLink: any(named: 'emailLink'),
        ),
      ).thenAnswer((_) async => credential);
      final service = buildService(firestore: firestore);
      await service.setPendingEmail('foo@example.com');

      final result = await service.completeRecovery(
        link,
        pendingWritesTimeout: const Duration(milliseconds: 50),
      );

      expect(result, same(credential));
      verify(() => auth.signOut()).called(1);
      verify(
        () =>
            auth.signInWithEmailLink(email: 'foo@example.com', emailLink: link),
      ).called(1);
    });

    test('throws StateError when no email is available', () async {
      final service = buildService();

      await expectLater(() => service.completeRecovery(link), throwsStateError);
    });
  });

  group('signOutCurrentDevice', () {
    test('throws StateError when the user has no linked email', () async {
      when(() => anonUser.email).thenReturn(null);
      final service = buildService();

      await expectLater(service.signOutCurrentDevice, throwsStateError);
      verifyNever(() => auth.signOut());
    });

    test(
      'signs out and re-establishes anon session when email is linked',
      () async {
        when(() => anonUser.email).thenReturn('foo@example.com');
        when(() => auth.signOut()).thenAnswer((_) async {});
        final firestore = _MockFirestore();
        when(firestore.waitForPendingWrites).thenAnswer((_) async {});
        var anonSessionCalled = false;
        final service = buildService(
          firestore: firestore,
          anonymousSessionFactory: () async {
            anonSessionCalled = true;
          },
        );

        await service.signOutCurrentDevice();

        verify(firestore.waitForPendingWrites).called(1);
        verify(() => auth.signOut()).called(1);
        expect(anonSessionCalled, isTrue);
      },
    );

    test(
      'still signs out when waitForPendingWrites exceeds the timeout',
      () async {
        when(() => anonUser.email).thenReturn('foo@example.com');
        when(() => auth.signOut()).thenAnswer((_) async {});
        final firestore = _MockFirestore();
        // Future that never completes so we exercise the timeout branch.
        when(
          firestore.waitForPendingWrites,
        ).thenAnswer((_) => Completer<void>().future);
        var anonSessionCalled = false;
        final service = buildService(
          firestore: firestore,
          anonymousSessionFactory: () async {
            anonSessionCalled = true;
          },
        );

        await service.signOutCurrentDevice(
          pendingWritesTimeout: const Duration(milliseconds: 50),
        );

        verify(() => auth.signOut()).called(1);
        expect(anonSessionCalled, isTrue);
      },
    );
  });
}
