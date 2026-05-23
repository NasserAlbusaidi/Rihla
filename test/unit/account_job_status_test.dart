import 'package:flutter_test/flutter_test.dart';
import 'package:safar/features/auth/models/account_job_status.dart';

void main() {
  group('AccountJobKind', () {
    test('round-trips wire names', () {
      for (final kind in AccountJobKind.values) {
        expect(AccountJobKind.fromWireName(kind.wireName), kind);
      }
    });

    test('rejects unknown wire names', () {
      expect(
        () => AccountJobKind.fromWireName('unknown'),
        throwsA(isA<ArgumentError>()),
      );
    });
  });

  group('AccountJobRunStatus', () {
    test('round-trips wire names', () {
      for (final status in AccountJobRunStatus.values) {
        expect(AccountJobRunStatus.fromWireName(status.wireName), status);
      }
    });

    test('rejects unknown wire names', () {
      expect(
        () => AccountJobRunStatus.fromWireName('unknown'),
        throwsA(isA<ArgumentError>()),
      );
    });
  });

  group('AccountJobStatusSnapshot', () {
    const base = AccountJobStatusSnapshot(
      jobId: 'job-1',
      kind: AccountJobKind.recoveryCleanup,
      status: AccountJobRunStatus.running,
      phase: 'Rewriting ledgers',
      current: 2,
      total: 5,
      retryable: true,
      errorCode: 'permission-denied',
      messageKey: 'cleanupRetry',
      counters: {'groups': 1, 'expenses': 4},
      output: {'oldUid': 'anon-1', 'newUid': 'uid-2'},
    );

    test('serializes to callable-compatible json', () {
      expect(base.toJson(), {
        'jobId': 'job-1',
        'kind': 'recoveryCleanup',
        'status': 'running',
        'phase': 'Rewriting ledgers',
        'current': 2,
        'total': 5,
        'retryable': true,
        'errorCode': 'permission-denied',
        'messageKey': 'cleanupRetry',
        'counters': {'groups': 1, 'expenses': 4},
        'output': {'oldUid': 'anon-1', 'newUid': 'uid-2'},
      });
    });

    test('deserializes json with all optional fields', () {
      final snapshot = AccountJobStatusSnapshot.fromJson(base.toJson());

      expect(snapshot.jobId, 'job-1');
      expect(snapshot.kind, AccountJobKind.recoveryCleanup);
      expect(snapshot.status, AccountJobRunStatus.running);
      expect(snapshot.phase, 'Rewriting ledgers');
      expect(snapshot.current, 2);
      expect(snapshot.total, 5);
      expect(snapshot.retryable, isTrue);
      expect(snapshot.errorCode, 'permission-denied');
      expect(snapshot.messageKey, 'cleanupRetry');
      expect(snapshot.counters, {'groups': 1, 'expenses': 4});
      expect(snapshot.output, {'oldUid': 'anon-1', 'newUid': 'uid-2'});
    });

    test('deserializes json with defaults for optional fields', () {
      final snapshot = AccountJobStatusSnapshot.fromJson({
        'jobId': 'job-2',
        'kind': 'deleteAccount',
        'status': 'idle',
      });

      expect(snapshot.jobId, 'job-2');
      expect(snapshot.kind, AccountJobKind.deleteAccount);
      expect(snapshot.status, AccountJobRunStatus.idle);
      expect(snapshot.phase, isEmpty);
      expect(snapshot.current, isNull);
      expect(snapshot.total, isNull);
      expect(snapshot.retryable, isFalse);
      expect(snapshot.errorCode, isNull);
      expect(snapshot.messageKey, isNull);
      expect(snapshot.counters, isEmpty);
      expect(snapshot.output, isNull);
    });

    test('ignores non-map output values when deserializing', () {
      final snapshot = AccountJobStatusSnapshot.fromJson({
        'jobId': 'job-3',
        'kind': 'cacheWipe',
        'status': 'complete',
        'output': 'done',
      });

      expect(snapshot.kind, AccountJobKind.cacheWipe);
      expect(snapshot.status, AccountJobRunStatus.complete);
      expect(snapshot.output, isNull);
    });

    test('copyWith replaces requested fields and preserves the rest', () {
      final updated = base.copyWith(
        jobId: 'job-4',
        kind: AccountJobKind.deleteAccount,
        status: AccountJobRunStatus.failed,
        phase: 'Auth delete',
        current: 4,
        total: 4,
        retryable: false,
        errorCode: 'internal',
        messageKey: 'deleteRetry',
        counters: {'members': 2},
        output: {'authUserDeleted': false},
      );

      expect(updated.jobId, 'job-4');
      expect(updated.kind, AccountJobKind.deleteAccount);
      expect(updated.status, AccountJobRunStatus.failed);
      expect(updated.phase, 'Auth delete');
      expect(updated.current, 4);
      expect(updated.total, 4);
      expect(updated.retryable, isFalse);
      expect(updated.errorCode, 'internal');
      expect(updated.messageKey, 'deleteRetry');
      expect(updated.counters, {'members': 2});
      expect(updated.output, {'authUserDeleted': false});

      final preserved = base.copyWith();
      expect(preserved.jobId, base.jobId);
      expect(preserved.kind, base.kind);
      expect(preserved.status, base.status);
      expect(preserved.phase, base.phase);
      expect(preserved.current, base.current);
      expect(preserved.total, base.total);
      expect(preserved.retryable, base.retryable);
      expect(preserved.errorCode, base.errorCode);
      expect(preserved.messageKey, base.messageKey);
      expect(preserved.counters, base.counters);
      expect(preserved.output, base.output);
    });

    test('isBlocking tracks running, blocked, and failed statuses', () {
      expect(
        base.copyWith(status: AccountJobRunStatus.running).isBlocking,
        isTrue,
      );
      expect(
        base.copyWith(status: AccountJobRunStatus.blocked).isBlocking,
        isTrue,
      );
      expect(
        base.copyWith(status: AccountJobRunStatus.failed).isBlocking,
        isTrue,
      );
      expect(
        base.copyWith(status: AccountJobRunStatus.idle).isBlocking,
        isFalse,
      );
      expect(
        base.copyWith(status: AccountJobRunStatus.complete).isBlocking,
        isFalse,
      );
    });

    test('hasCountedProgress requires a positive total', () {
      expect(base.hasCountedProgress, isTrue);
      expect(base.copyWith(total: 0).hasCountedProgress, isFalse);
      expect(
        const AccountJobStatusSnapshot(
          jobId: 'job-5',
          kind: AccountJobKind.cacheWipe,
          status: AccountJobRunStatus.running,
          phase: 'Cache wipe',
          total: 3,
        ).hasCountedProgress,
        isFalse,
      );
    });
  });
}
