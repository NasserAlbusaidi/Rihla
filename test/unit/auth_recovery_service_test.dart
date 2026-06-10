import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:safar/core/services/cache_isolation_controller.dart';
import 'package:safar/core/services/cache_uid_barrier.dart';
import 'package:safar/core/services/firebase_functions_service.dart';
import 'package:safar/features/auth/services/auth_recovery_service.dart';
import 'package:safar/features/auth/services/recovery_diagnostics.dart';
import 'package:safar/features/auth/services/recovery_failure_notice.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../helpers/recording_recovery_diagnostics.dart';

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
    defaultFirestore = _MockFirestore();
    when(defaultFirestore.waitForPendingWrites).thenAnswer((_) async {});
  });

  AuthRecoveryService buildService({
    FirebaseFirestore? firestore,
    CacheIsolationController? cacheIsolationController,
    Future<CleanupOutcome> Function({
      required String oldUid,
      required String cleanupSecret,
    })?
    cleanupAnonUidArtifacts,
    Future<String> Function(String oldUid)? cleanupIntentFactory,
    void Function({
      required String message,
      required Map<String, Object?> data,
    })?
    recoveryCleanupFailureRecorder,
    RecoveryDiagnostics? diagnostics,
  }) {
    return AuthRecoveryService(
      auth: auth,
      prefs: prefs,
      cacheIsolationController: cacheIsolationController ?? _NoopController(),
      firestore: firestore ?? defaultFirestore,
      cleanupAnonUidArtifacts:
          cleanupAnonUidArtifacts ??
          ({required oldUid, required cleanupSecret}) async =>
              const CleanupOutcome(cascadeFailed: []),
      cleanupIntentFactory:
          cleanupIntentFactory ?? (_) async => 'test-cleanup-secret',
      recoveryCleanupFailureRecorder: recoveryCleanupFailureRecorder,
      diagnostics: diagnostics ?? const SentryRecoveryDiagnostics(),
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
      'drains pending writes before sign-in and never explicitly signs out',
      () async {
        final credential = _MockUserCredential();
        final firestore = _MockFirestore();
        when(firestore.waitForPendingWrites).thenAnswer((_) async {});
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
          () => auth.signInWithEmailLink(
            email: 'foo@example.com',
            emailLink: link,
          ),
        ]);
        // #414: the sign-in itself replaces the session; an explicit signOut
        // beforehand is how a failed swap orphans a no-email anon account.
        verifyNever(() => auth.signOut());
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
        // signOut stub records so the expected-calls list below proves it
        // is never invoked (#414).
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
          cacheIsolationController: _RecordingController(calls),
          cleanupIntentFactory: (oldUid) async {
            calls.add('intent:$oldUid');
            return 'client-secret';
          },
          cleanupAnonUidArtifacts:
              ({required oldUid, required cleanupSecret}) async {
                calls.add('cleanup:$oldUid:$cleanupSecret');
                return const CleanupOutcome(cascadeFailed: []);
              },
        );
        await service.setPendingEmail('foo@example.com');

        final result = await service.completeRecovery(link);

        expect(result, same(credential));
        expect(calls, [
          'engage',
          'intent:anon-uid-123',
          'waitForPendingWrites',
          'signInWithEmailLink',
          'cleanup:anon-uid-123:client-secret',
          'restart',
        ]);
      },
    );

    test('engages isolation first and marks the cache dirty before sign-in', () async {
      final credential = _MockUserCredential();
      final events = <String>[];
      bool? dirtyAtSignIn;
      when(
        () => auth.signInWithEmailLink(
          email: any(named: 'email'),
          emailLink: any(named: 'emailLink'),
        ),
      ).thenAnswer((_) async {
        dirtyAtSignIn = prefs.getBool(kFirestorePersistenceDirtyKey);
        events.add('signIn');
        return credential;
      });
      final service = buildService(
        cacheIsolationController: _RecordingController(events),
      );
      await service.setPendingEmail('foo@example.com');

      await service.completeRecovery(link);

      expect(events.first, 'engage');
      expect(events.last, 'restart');
      expect(dirtyAtSignIn, isTrue);
    });

    test(
      'clears op-state and restarts even when signInWithEmailLink fails '
      '(no stranded overlay, no next-boot loop)',
      () async {
        final events = <String>[];
        when(() => auth.signOut()).thenAnswer((_) async {
          events.add('signOut');
        });
        when(
          () => auth.signInWithEmailLink(
            email: any(named: 'email'),
            emailLink: any(named: 'emailLink'),
          ),
        ).thenThrow(FirebaseAuthException(code: 'expired-action-code'));
        final service = buildService(
          cacheIsolationController: _RecordingController(events),
        );
        await service.setPendingEmail('foo@example.com');
        await prefs.setString('auth.inFlightOp', AuthRecoveryService.opRecover);

        await expectLater(
          () => service.completeRecovery(link),
          throwsA(isA<FirebaseAuthException>()),
        );

        expect(events, ['engage', 'restart']);
        // #414: a failed swap must leave the current session signed in — the
        // restart returns to it instead of minting a fresh empty anon.
        verifyNever(() => auth.signOut());
        // Cleared in the finally so the cold boot doesn't re-run the dead link.
        expect(service.readPendingEmail(), isNull);
        expect(service.readInFlightOp(), isNull);
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
      var cleanupInvocations = 0;
      final service = buildService(
        cleanupAnonUidArtifacts:
            ({required oldUid, required cleanupSecret}) async {
              cleanupInvocations += 1;
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
      // Inline retry (#427): a thrown first attempt is retried once before the
      // terminal failure is recorded.
      expect(cleanupInvocations, 2);
      expect(breadcrumbs, hasLength(1));
      expect(breadcrumbs.single['message'], 'Recovery cleanup incomplete');
    });

    test(
      'partial cleanup outcome is retried inline and converges silently',
      () async {
        final credential = _MockUserCredential();
        when(
          () => auth.signInWithEmailLink(
            email: any(named: 'email'),
            emailLink: any(named: 'emailLink'),
          ),
        ).thenAnswer((_) async => credential);
        final breadcrumbs = <Map<String, Object?>>[];
        var cleanupInvocations = 0;
        final service = buildService(
          cleanupAnonUidArtifacts:
              ({required oldUid, required cleanupSecret}) async {
                cleanupInvocations += 1;
                return cleanupInvocations == 1
                    ? const CleanupOutcome(cascadeFailed: ['g1'])
                    : const CleanupOutcome(cascadeFailed: []);
              },
          recoveryCleanupFailureRecorder: ({required message, required data}) {
            breadcrumbs.add({'message': message, ...data});
          },
        );
        await service.setPendingEmail('foo@example.com');

        final result = await service.completeRecovery(link);

        expect(result, same(credential));
        expect(cleanupInvocations, 2);
        expect(breadcrumbs, isEmpty);
      },
    );

    test(
      'persistently-partial cleanup records the failed groups and still '
      'returns the credential',
      () async {
        final credential = _MockUserCredential();
        when(
          () => auth.signInWithEmailLink(
            email: any(named: 'email'),
            emailLink: any(named: 'emailLink'),
          ),
        ).thenAnswer((_) async => credential);
        final events = <String>[];
        final breadcrumbs = <Map<String, Object?>>[];
        var cleanupInvocations = 0;
        final service = buildService(
          cacheIsolationController: _RecordingController(events),
          cleanupAnonUidArtifacts:
              ({required oldUid, required cleanupSecret}) async {
                cleanupInvocations += 1;
                return const CleanupOutcome(cascadeFailed: ['g1']);
              },
          recoveryCleanupFailureRecorder: ({required message, required data}) {
            breadcrumbs.add({'message': message, ...data});
          },
        );
        await service.setPendingEmail('foo@example.com');

        final result = await service.completeRecovery(link);

        expect(result, same(credential));
        expect(cleanupInvocations, 2);
        expect(breadcrumbs.single['message'], 'Recovery cleanup incomplete');
        expect(breadcrumbs.single['groupsFailed'], ['g1']);
        expect(events.last, 'restart');
      },
    );

    test('thrown first attempt followed by a clean retry stays silent', () async {
      final credential = _MockUserCredential();
      when(
        () => auth.signInWithEmailLink(
          email: any(named: 'email'),
          emailLink: any(named: 'emailLink'),
        ),
      ).thenAnswer((_) async => credential);
      final breadcrumbs = <Map<String, Object?>>[];
      var cleanupInvocations = 0;
      final service = buildService(
        cleanupAnonUidArtifacts:
            ({required oldUid, required cleanupSecret}) async {
              cleanupInvocations += 1;
              if (cleanupInvocations == 1) {
                throw StateError('transient cleanup failure');
              }
              return const CleanupOutcome(cascadeFailed: []);
            },
        recoveryCleanupFailureRecorder: ({required message, required data}) {
          breadcrumbs.add({'message': message, ...data});
        },
      );
      await service.setPendingEmail('foo@example.com');

      final result = await service.completeRecovery(link);

      expect(result, same(credential));
      expect(cleanupInvocations, 2);
      expect(breadcrumbs, isEmpty);
    });

    test(
      'permission-denied on retry after a thrown first attempt is '
      'success-equivalent (intent consumed by a completed first invocation)',
      () async {
        final credential = _MockUserCredential();
        when(
          () => auth.signInWithEmailLink(
            email: any(named: 'email'),
            emailLink: any(named: 'emailLink'),
          ),
        ).thenAnswer((_) async => credential);
        final events = <String>[];
        final breadcrumbs = <Map<String, Object?>>[];
        var cleanupInvocations = 0;
        final service = buildService(
          cacheIsolationController: _RecordingController(events),
          cleanupAnonUidArtifacts:
              ({required oldUid, required cleanupSecret}) async {
                cleanupInvocations += 1;
                if (cleanupInvocations == 1) {
                  throw FirebaseFunctionsException(
                    message: 'deadline exceeded',
                    code: 'deadline-exceeded',
                  );
                }
                throw FirebaseFunctionsException(
                  message: 'No valid cleanup intent',
                  code: 'permission-denied',
                );
              },
          recoveryCleanupFailureRecorder: ({required message, required data}) {
            breadcrumbs.add({'message': message, ...data});
          },
        );
        await service.setPendingEmail('foo@example.com');

        final result = await service.completeRecovery(link);

        expect(result, same(credential));
        expect(cleanupInvocations, 2);
        expect(breadcrumbs, isEmpty);
        expect(events.last, 'restart');
      },
    );

    test(
      'permission-denied on retry after a STRUCTURED partial failure is a '
      'genuine anomaly and records',
      () async {
        final credential = _MockUserCredential();
        when(
          () => auth.signInWithEmailLink(
            email: any(named: 'email'),
            emailLink: any(named: 'emailLink'),
          ),
        ).thenAnswer((_) async => credential);
        final breadcrumbs = <Map<String, Object?>>[];
        var cleanupInvocations = 0;
        final service = buildService(
          cleanupAnonUidArtifacts:
              ({required oldUid, required cleanupSecret}) async {
                cleanupInvocations += 1;
                if (cleanupInvocations == 1) {
                  return const CleanupOutcome(cascadeFailed: ['g1']);
                }
                throw FirebaseFunctionsException(
                  message: 'No valid cleanup intent',
                  code: 'permission-denied',
                );
              },
          recoveryCleanupFailureRecorder: ({required message, required data}) {
            breadcrumbs.add({'message': message, ...data});
          },
        );
        await service.setPendingEmail('foo@example.com');

        final result = await service.completeRecovery(link);

        expect(result, same(credential));
        expect(cleanupInvocations, 2);
        expect(breadcrumbs.single['message'], 'Recovery cleanup incomplete');
      },
    );

    test(
      'records a breadcrumb and continues when cleanup-intent creation fails',
      () async {
        final credential = _MockUserCredential();
        when(
          () => auth.signInWithEmailLink(
            email: any(named: 'email'),
            emailLink: any(named: 'emailLink'),
          ),
        ).thenAnswer((_) async => credential);
        var cleanupInvoked = false;
        final breadcrumbs = <Map<String, Object?>>[];
        final service = buildService(
          cleanupIntentFactory: (_) async =>
              throw StateError('intent boom for foo@example.com'),
          cleanupAnonUidArtifacts:
              ({required oldUid, required cleanupSecret}) async {
                cleanupInvoked = true;
                return const CleanupOutcome(cascadeFailed: []);
              },
          recoveryCleanupFailureRecorder: ({required message, required data}) {
            breadcrumbs.add({'message': message, ...data});
          },
        );
        await service.setPendingEmail('foo@example.com');

        final result = await service.completeRecovery(link);

        expect(result, same(credential));
        expect(
          breadcrumbs.single['message'],
          'Recovery cleanup intent creation failed',
        );
        // No secret was produced, so the cleanup callable must be skipped.
        expect(cleanupInvoked, isFalse);
        expect(breadcrumbs.single.toString(), isNot(contains('foo@example.com')));
      },
    );

    test('cleanup failure breadcrumb excludes email PII', () async {
      final credential = _MockUserCredential();
      when(
        () => auth.signInWithEmailLink(
          email: any(named: 'email'),
          emailLink: any(named: 'emailLink'),
        ),
      ).thenAnswer((_) async => credential);
      final breadcrumbs = <Map<String, Object?>>[];
      var cleanupInvocations = 0;
      final service = buildService(
        cleanupAnonUidArtifacts:
            ({required oldUid, required cleanupSecret}) async {
              cleanupInvocations += 1;
              throw StateError('cleanup failed for foo@example.com');
            },
        recoveryCleanupFailureRecorder: ({required message, required data}) {
          breadcrumbs.add({'message': message, ...data});
        },
      );
      await service.setPendingEmail('foo@example.com');

      await service.completeRecovery(link);
      await Future<void>.delayed(Duration.zero);

      // Inline retry (#427): both attempts throw, one terminal record.
      expect(cleanupInvocations, 2);
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
      verifyNever(() => auth.signOut());
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

  group('completeRecovery failure marker + diagnostics (Task 4)', () {
    const link =
        'https://rihla-safar.firebaseapp.com/__/auth/links/continue?mode=signIn&oobCode=abc';

    void stubSignInThrows(String code) {
      when(
        () => auth.signInWithEmailLink(
          email: any(named: 'email'),
          emailLink: any(named: 'emailLink'),
        ),
      ).thenThrow(FirebaseAuthException(code: code));
    }

    test(
      'persists a {code, op:recover} marker when signInWithEmailLink fails, '
      'still rethrows, never signs out, still restarts',
      () async {
        final events = <String>[];
        stubSignInThrows('invalid-action-code');
        final service = buildService(
          cacheIsolationController: _RecordingController(events),
        );
        await service.setPendingEmail('foo@example.com');

        await expectLater(
          () => service.completeRecovery(link),
          throwsA(isA<FirebaseAuthException>()),
        );

        final notice = readRecoveryFailureNotice(prefs);
        expect(notice, isNotNull);
        expect(notice!.code, 'invalid-action-code');
        expect(notice.op, AuthRecoveryService.opRecover);
        verifyNever(() => auth.signOut());
        expect(events.last, 'restart');
      },
    );

    test('writes no failure marker on a successful recovery', () async {
      final credential = _MockUserCredential();
      when(
        () => auth.signInWithEmailLink(
          email: any(named: 'email'),
          emailLink: any(named: 'emailLink'),
        ),
      ).thenAnswer((_) async => credential);
      final service = buildService();
      await service.setPendingEmail('foo@example.com');

      await service.completeRecovery(link);

      expect(readRecoveryFailureNotice(prefs), isNull);
    });

    test('clears a stale failure marker on a successful recovery', () async {
      await writeRecoveryFailureNotice(
        prefs,
        code: 'expired-action-code',
        op: AuthRecoveryService.opRecover,
      );
      final credential = _MockUserCredential();
      when(
        () => auth.signInWithEmailLink(
          email: any(named: 'email'),
          emailLink: any(named: 'emailLink'),
        ),
      ).thenAnswer((_) async => credential);
      final service = buildService();
      await service.setPendingEmail('foo@example.com');

      await service.completeRecovery(link);

      expect(readRecoveryFailureNotice(prefs), isNull);
    });

    test('failure diagnostics carry the code and fingerprint, never PII', () async {
      stubSignInThrows('invalid-action-code');
      final recording = RecordingRecoveryDiagnostics();
      final service = buildService(diagnostics: recording);
      await service.setPendingEmail('foo@example.com');

      await expectLater(
        () => service.completeRecovery(link),
        throwsA(isA<FirebaseAuthException>()),
      );

      final values = recording.allValues.toList();
      // No PII anywhere in the breadcrumb data.
      expect(values, isNot(contains('foo@example.com')));
      expect(values, isNot(contains('anon-uid-123')));
      for (final v in values) {
        expect(v, isNot(contains('oobCode')));
        expect(v, isNot(contains('abc'))); // the raw oobCode value
        expect(v, isNot(contains('firebaseapp.com'))); // the raw link
      }
      // The UID is correlated only via its fingerprint.
      expect(values, contains(RecoveryDiagnostics.fingerprint('anon-uid-123')));
      // The failing phase recorded the error code.
      expect(recording.phases, contains('recover.signIn.fail'));
      final failCall =
          recording.calls.firstWhere((c) => c.phase == 'recover.signIn.fail');
      expect(failCall.data['code'], 'invalid-action-code');
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
      'engages isolation, marks dirty before signOut, then restarts '
      '(no in-session anon mint)',
      () async {
        when(() => anonUser.email).thenReturn('foo@example.com');
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
