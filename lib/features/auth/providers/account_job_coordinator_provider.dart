import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/firebase_config.dart';
import '../models/account_job_status.dart';
import 'auth_provider.dart';

typedef AccountJobResumeProbe = Future<AccountJobStatusSnapshot?> Function();
typedef AccountJobAdvance =
    Future<AccountJobStatusSnapshot> Function(AccountJobStatusSnapshot status);
typedef AccountJobRouteHome = void Function();

class AccountJobCoordinatorState {
  const AccountJobCoordinatorState({
    this.activeJob,
    this.blockedDeepLink = false,
  });

  final AccountJobStatusSnapshot? activeJob;
  final bool blockedDeepLink;

  bool get isBlocking => activeJob?.isBlocking ?? false;

  AccountJobCoordinatorState copyWith({
    AccountJobStatusSnapshot? activeJob,
    bool clearActiveJob = false,
    bool? blockedDeepLink,
  }) {
    return AccountJobCoordinatorState(
      activeJob: clearActiveJob ? null : activeJob ?? this.activeJob,
      blockedDeepLink: blockedDeepLink ?? this.blockedDeepLink,
    );
  }
}

class AccountJobDriver {
  const AccountJobDriver({
    required this.resumeProbe,
    required this.advance,
    required this.routeHome,
  });

  final AccountJobResumeProbe resumeProbe;
  final AccountJobAdvance advance;
  final AccountJobRouteHome routeHome;
}

final accountJobDriverProvider = Provider<AccountJobDriver>((ref) {
  return AccountJobDriver(
    resumeProbe: () =>
        ref.read(authRecoveryServiceProvider).resumePendingRecoveryCleanup(),
    advance: (status) =>
        ref.read(authRecoveryServiceProvider).advanceAccountJob(status),
    routeHome: () {},
  );
});

final accountJobCoordinatorProvider =
    StateNotifierProvider<AccountJobCoordinator, AccountJobCoordinatorState>((
      ref,
    ) {
      return AccountJobCoordinator(ref.read(accountJobDriverProvider));
    });

class AccountJobCoordinator extends StateNotifier<AccountJobCoordinatorState> {
  AccountJobCoordinator(this._driver)
    : super(const AccountJobCoordinatorState());

  final AccountJobDriver _driver;
  var _resumeInFlight = false;
  var _advanceInFlight = false;

  bool get isBlocking => state.isBlocking;

  Future<void> resumeOnLaunch() => _resume('launch');

  Future<void> resumeOnAppResume() => _resume('appResume');

  void setActiveJobForTesting(AccountJobStatusSnapshot status) {
    state = state.copyWith(activeJob: status, blockedDeepLink: false);
  }

  void clearActiveJobForTesting() {
    state = state.copyWith(clearActiveJob: true, blockedDeepLink: false);
  }

  void notifyDeepLinkBlocked() {
    if (!state.isBlocking) return;
    state = state.copyWith(blockedDeepLink: true);
  }

  void clearBlockedDeepLinkNotice() {
    state = state.copyWith(blockedDeepLink: false);
  }

  Future<void> retryActiveJob() async {
    final active = state.activeJob;
    if (active == null || !active.retryable || _advanceInFlight) return;
    await _advance(active);
  }

  Future<void> _resume(String reason) async {
    if (_resumeInFlight || state.isBlocking) return;
    _resumeInFlight = true;
    try {
      final status = await _driver.resumeProbe();
      if (status == null) return;
      state = state.copyWith(activeJob: status, blockedDeepLink: false);
      if (status.status == AccountJobRunStatus.running) {
        await _advance(status);
      }
    } catch (error, stackTrace) {
      FirebaseConfig.log(
        'AccountJobCoordinator: resume failed ($reason)',
        error: error,
        stackTrace: stackTrace,
      );
    } finally {
      _resumeInFlight = false;
    }
  }

  Future<void> _advance(AccountJobStatusSnapshot status) async {
    if (_advanceInFlight) return;
    _advanceInFlight = true;
    try {
      var next = status;
      while (mounted && next.status == AccountJobRunStatus.running) {
        next = await _driver.advance(next);
        state = state.copyWith(activeJob: next, blockedDeepLink: false);
      }
      if (!mounted) return;
      if (next.status == AccountJobRunStatus.complete) {
        state = state.copyWith(clearActiveJob: true, blockedDeepLink: false);
        _driver.routeHome();
      }
    } catch (error, stackTrace) {
      FirebaseConfig.log(
        'AccountJobCoordinator: advance failed',
        error: error,
        stackTrace: stackTrace,
      );
      state = state.copyWith(
        activeJob: status.copyWith(
          status: AccountJobRunStatus.failed,
          retryable: true,
          errorCode: error.runtimeType.toString(),
        ),
      );
    } finally {
      _advanceInFlight = false;
    }
  }
}

class AccountJobLifecycleObserver extends WidgetsBindingObserver {
  AccountJobLifecycleObserver(this._onResume);

  final Future<void> Function() _onResume;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_onResume());
    }
  }
}
