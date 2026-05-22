import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:safar/features/auth/models/account_job_status.dart';
import 'package:safar/features/auth/models/delete_account_output.dart';
import 'package:safar/features/auth/services/data_deletion_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _MockFirebaseAuth extends Mock implements FirebaseAuth {}

class _MockUser extends Mock implements User {}

const _output = DeleteAccountOutput(
  groupsProcessed: 1,
  tombstoneIds: ['deleted-1'],
  expensesScrubbed: 2,
  settlementsScrubbed: 3,
  activityLogsScrubbed: 4,
  membersDeleted: 1,
  groupsOrphanedAndSoftDeleted: 0,
  fcmTokenDeleted: true,
  joinAttemptsDeleted: true,
  authUserDeleted: true,
);

Map<String, dynamic> get _outputJson => {
  'groupsProcessed': _output.groupsProcessed,
  'tombstoneIds': _output.tombstoneIds,
  'expensesScrubbed': _output.expensesScrubbed,
  'settlementsScrubbed': _output.settlementsScrubbed,
  'activityLogsScrubbed': _output.activityLogsScrubbed,
  'membersDeleted': _output.membersDeleted,
  'groupsOrphanedAndSoftDeleted': _output.groupsOrphanedAndSoftDeleted,
  'fcmTokenDeleted': _output.fcmTokenDeleted,
  'joinAttemptsDeleted': _output.joinAttemptsDeleted,
  'authUserDeleted': _output.authUserDeleted,
};

const _pendingDeletionJobIdKey = 'auth.pendingDeletionJobId';

AccountJobStatusSnapshot _jobStatus({
  AccountJobRunStatus status = AccountJobRunStatus.running,
  String? errorCode,
  Map<String, dynamic>? output,
}) {
  return AccountJobStatusSnapshot(
    jobId: 'uid-1',
    kind: AccountJobKind.deleteAccount,
    status: status,
    phase: status == AccountJobRunStatus.complete ? 'Complete' : 'Deleting',
    current: status == AccountJobRunStatus.complete ? 2 : 1,
    total: 2,
    retryable: status == AccountJobRunStatus.failed,
    errorCode: errorCode,
    output: output,
  );
}

void main() {
  late _MockFirebaseAuth auth;
  late _MockUser user;

  setUp(() {
    auth = _MockFirebaseAuth();
    user = _MockUser();
    when(() => user.uid).thenReturn('uid-1');
    when(() => auth.signOut()).thenAnswer((_) async {});
  });

  test('returns noUser when there is no current user', () async {
    when(() => auth.currentUser).thenReturn(null);
    final service = DataDeletionService(auth: auth);

    expect(await service.deleteAccount(), isA<DeletionNoUser>());
  });

  test('calls callable, wipes local cache, and signs out on success', () async {
    final calls = <String>[];
    when(() => auth.currentUser).thenReturn(user);
    when(() => auth.signOut()).thenAnswer((_) async {
      calls.add('signOut');
    });
    final service = DataDeletionService(
      auth: auth,
      deleteAccountCallable: () async {
        calls.add('callable');
        return _output;
      },
      wipeLocalCache: () async {
        calls.add('wipe');
      },
    );

    expect(await service.deleteAccount(), isA<DeletionOk>());
    expect(calls, ['callable', 'wipe', 'signOut']);
    verify(() => auth.signOut()).called(1);
  });

  test('returns error when the callable fails', () async {
    final calls = <String>[];
    when(() => auth.currentUser).thenReturn(user);
    final service = DataDeletionService(
      auth: auth,
      deleteAccountCallable: () async {
        calls.add('callable');
        throw StateError('boom');
      },
      wipeLocalCache: () async {
        calls.add('wipe');
      },
    );

    expect(await service.deleteAccount(), isA<DeletionError>());
    expect(calls, ['callable']);
    verifyNever(() => auth.signOut());
  });

  test('returns error when local cache wipe fails', () async {
    final calls = <String>[];
    when(() => auth.currentUser).thenReturn(user);
    final service = DataDeletionService(
      auth: auth,
      deleteAccountCallable: () async {
        calls.add('callable');
        return _output;
      },
      wipeLocalCache: () async {
        calls.add('wipe');
        throw StateError('wipe failed');
      },
    );

    expect(await service.deleteAccount(), isA<DeletionLocalCleanupFailed>());
    expect(calls, ['callable', 'wipe']);
    verify(() => auth.signOut()).called(1);
  });

  test('returns error when signOut fails', () async {
    final calls = <String>[];
    when(() => auth.currentUser).thenReturn(user);
    when(() => auth.signOut()).thenAnswer((_) async {
      calls.add('signOut');
      throw StateError('signOut failed');
    });
    final service = DataDeletionService(
      auth: auth,
      deleteAccountCallable: () async {
        calls.add('callable');
        return _output;
      },
      wipeLocalCache: () async {
        calls.add('wipe');
      },
    );

    expect(await service.deleteAccount(), isA<DeletionLocalSignOutFailed>());
    expect(calls, ['callable', 'wipe', 'signOut']);
  });

  test(
    'returns partial result when server scrubbed data but auth delete failed',
    () async {
      final calls = <String>[];
      when(() => auth.currentUser).thenReturn(user);
      final service = DataDeletionService(
        auth: auth,
        deleteAccountCallable: () async {
          calls.add('callable');
          throw const DeleteAccountPartialFailure(
            output: _output,
            code: 'internal',
            message: 'auth delete failed',
          );
        },
        wipeLocalCache: () async {
          calls.add('wipe');
        },
      );

      expect(
        await service.deleteAccount(),
        isA<DeletionServerScrubbedAuthDeleteFailed>(),
      );
      expect(calls, ['callable']);
      verifyNever(() => auth.signOut());
    },
  );

  test(
    'drives resumable deletion job, wipes cache, signs out, and clears marker',
    () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final calls = <String>[];
      when(() => auth.currentUser).thenReturn(user);
      when(() => auth.signOut()).thenAnswer((_) async {
        calls.add('signOut');
      });

      final service = DataDeletionService(
        auth: auth,
        prefs: prefs,
        startOrResumeDeleteAccountJob: () async {
          calls.add('start');
          return _jobStatus();
        },
        advanceDeleteAccountJob: ({required String jobId}) async {
          calls.add('advance:$jobId');
          return _jobStatus(
            status: AccountJobRunStatus.complete,
            output: _outputJson,
          );
        },
        wipeLocalCache: () async {
          calls.add('wipe');
        },
      );

      expect(await service.deleteAccount(), isA<DeletionOk>());
      expect(calls, ['start', 'advance:uid-1', 'wipe', 'signOut']);
      expect(prefs.getString(_pendingDeletionJobIdKey), isNull);
    },
  );

  test(
    'keeps deletion marker and returns partial result when auth delete fails',
    () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      when(() => auth.currentUser).thenReturn(user);

      final service = DataDeletionService(
        auth: auth,
        prefs: prefs,
        startOrResumeDeleteAccountJob: () async => _jobStatus(),
        advanceDeleteAccountJob: ({required String jobId}) async => _jobStatus(
          status: AccountJobRunStatus.failed,
          errorCode: 'auth-delete-failed',
          output: _outputJson,
        ),
        wipeLocalCache: () async {},
      );

      expect(
        await service.deleteAccount(),
        isA<DeletionServerScrubbedAuthDeleteFailed>(),
      );
      expect(prefs.getString(_pendingDeletionJobIdKey), 'uid-1');
      verifyNever(() => auth.signOut());
    },
  );

  test('retries a stored retryable deletion job from deleteAccount', () async {
    SharedPreferences.setMockInitialValues({_pendingDeletionJobIdKey: 'uid-1'});
    final prefs = await SharedPreferences.getInstance();
    final calls = <String>[];
    when(() => auth.currentUser).thenReturn(user);
    when(() => auth.signOut()).thenAnswer((_) async {
      calls.add('signOut');
    });

    final service = DataDeletionService(
      auth: auth,
      prefs: prefs,
      startOrResumeDeleteAccountJob: () async {
        calls.add('start');
        return _jobStatus(
          status: AccountJobRunStatus.failed,
          errorCode: 'auth-delete-failed',
          output: _outputJson,
        );
      },
      advanceDeleteAccountJob: ({required String jobId}) async {
        calls.add('advance:$jobId');
        return _jobStatus(
          status: AccountJobRunStatus.complete,
          output: _outputJson,
        );
      },
      wipeLocalCache: () async {
        calls.add('wipe');
      },
    );

    expect(await service.deleteAccount(), isA<DeletionOk>());
    expect(calls, ['start', 'advance:uid-1', 'wipe', 'signOut']);
    expect(prefs.getString(_pendingDeletionJobIdKey), isNull);
  });

  test('resumePendingDeletion returns stored running job status', () async {
    SharedPreferences.setMockInitialValues({_pendingDeletionJobIdKey: 'uid-1'});
    final prefs = await SharedPreferences.getInstance();

    final service = DataDeletionService(
      auth: auth,
      prefs: prefs,
      getDeleteAccountJobStatus: ({required String jobId}) async {
        expect(jobId, 'uid-1');
        return _jobStatus();
      },
      wipeLocalCache: () async {},
    );

    final status = await service.resumePendingDeletion();
    expect(status?.kind, AccountJobKind.deleteAccount);
    expect(status?.status, AccountJobRunStatus.running);
  });

  test(
    'advanceAccountJob finishes local cleanup when resumed job completes',
    () async {
      SharedPreferences.setMockInitialValues({
        _pendingDeletionJobIdKey: 'uid-1',
      });
      final prefs = await SharedPreferences.getInstance();
      final calls = <String>[];
      when(() => auth.signOut()).thenAnswer((_) async {
        calls.add('signOut');
      });

      final service = DataDeletionService(
        auth: auth,
        prefs: prefs,
        advanceDeleteAccountJob: ({required String jobId}) async {
          calls.add('advance:$jobId');
          return _jobStatus(
            status: AccountJobRunStatus.complete,
            output: _outputJson,
          );
        },
        wipeLocalCache: () async {
          calls.add('wipe');
        },
      );

      final status = await service.advanceAccountJob(_jobStatus());
      expect(status.status, AccountJobRunStatus.complete);
      expect(calls, ['advance:uid-1', 'wipe', 'signOut']);
      expect(prefs.getString(_pendingDeletionJobIdKey), isNull);
    },
  );
}
