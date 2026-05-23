import 'package:flutter_test/flutter_test.dart';
import 'package:safar/features/auth/models/account_job_status.dart';
import 'package:safar/features/auth/providers/account_job_coordinator_provider.dart';

AccountJobStatusSnapshot _status({
  AccountJobRunStatus status = AccountJobRunStatus.running,
  AccountJobKind kind = AccountJobKind.recoveryCleanup,
  bool retryable = false,
  String jobId = 'job-1',
}) {
  return AccountJobStatusSnapshot(
    jobId: jobId,
    kind: kind,
    status: status,
    phase: status.wireName,
    current: 1,
    total: 2,
    retryable: retryable,
  );
}

void main() {
  test('resumeOnLaunch stores a blocked job without advancing it', () async {
    var advanceCalls = 0;
    var routeHomeCalls = 0;
    final coordinator = AccountJobCoordinator(
      AccountJobDriver(
        resumeProbe: () async => _status(status: AccountJobRunStatus.blocked),
        advance: (status) async {
          advanceCalls += 1;
          return status;
        },
        routeHome: () {
          routeHomeCalls += 1;
        },
      ),
    );
    addTearDown(coordinator.dispose);

    await coordinator.resumeOnLaunch();

    expect(coordinator.state.activeJob?.status, AccountJobRunStatus.blocked);
    expect(coordinator.state.isBlocking, isTrue);
    expect(advanceCalls, 0);
    expect(routeHomeCalls, 0);
  });

  test('resumeOnLaunch advances a running job until complete', () async {
    var advanceCalls = 0;
    var routeHomeCalls = 0;
    final coordinator = AccountJobCoordinator(
      AccountJobDriver(
        resumeProbe: () async => _status(),
        advance: (status) async {
          advanceCalls += 1;
          return advanceCalls == 1
              ? _status(jobId: 'job-2')
              : _status(jobId: 'job-2', status: AccountJobRunStatus.complete);
        },
        routeHome: () {
          routeHomeCalls += 1;
        },
      ),
    );
    addTearDown(coordinator.dispose);

    await coordinator.resumeOnLaunch();

    expect(advanceCalls, 2);
    expect(routeHomeCalls, 1);
    expect(coordinator.state.activeJob, isNull);
    expect(coordinator.state.isBlocking, isFalse);
  });

  test(
    'retryActiveJob advances retryable failed job and routes home',
    () async {
      var advanceCalls = 0;
      var routeHomeCalls = 0;
      final coordinator = AccountJobCoordinator(
        AccountJobDriver(
          resumeProbe: () async => null,
          advance: (status) async {
            advanceCalls += 1;
            return status.copyWith(status: AccountJobRunStatus.complete);
          },
          routeHome: () {
            routeHomeCalls += 1;
          },
        ),
      );
      addTearDown(coordinator.dispose);
      coordinator.setActiveJobForTesting(
        _status(status: AccountJobRunStatus.failed, retryable: true),
      );

      await coordinator.retryActiveJob();

      expect(advanceCalls, 1);
      expect(routeHomeCalls, 1);
      expect(coordinator.state.activeJob, isNull);
    },
  );

  test('retryActiveJob ignores non-retryable or missing jobs', () async {
    var advanceCalls = 0;
    final coordinator = AccountJobCoordinator(
      AccountJobDriver(
        resumeProbe: () async => null,
        advance: (status) async {
          advanceCalls += 1;
          return status;
        },
        routeHome: () {},
      ),
    );
    addTearDown(coordinator.dispose);

    await coordinator.retryActiveJob();
    coordinator.setActiveJobForTesting(
      _status(status: AccountJobRunStatus.failed),
    );
    await coordinator.retryActiveJob();

    expect(advanceCalls, 0);
    expect(coordinator.state.activeJob?.status, AccountJobRunStatus.failed);
  });

  test('deep link notice is only set while a job is blocking', () {
    final coordinator = AccountJobCoordinator(
      AccountJobDriver(
        resumeProbe: () async => null,
        advance: (status) async => status,
        routeHome: () {},
      ),
    );
    addTearDown(coordinator.dispose);

    coordinator.notifyDeepLinkBlocked();
    expect(coordinator.state.blockedDeepLink, isFalse);

    coordinator.setActiveJobForTesting(_status());
    coordinator.notifyDeepLinkBlocked();
    expect(coordinator.state.blockedDeepLink, isTrue);

    coordinator.clearBlockedDeepLinkNotice();
    expect(coordinator.state.blockedDeepLink, isFalse);

    coordinator.clearActiveJobForTesting();
    expect(coordinator.state.activeJob, isNull);
  });
}
