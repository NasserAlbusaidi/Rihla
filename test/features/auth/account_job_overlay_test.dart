import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:safar/features/auth/models/account_job_status.dart';
import 'package:safar/features/auth/providers/account_job_coordinator_provider.dart';
import 'package:safar/features/auth/widgets/account_job_overlay.dart';

import '../../helpers/pump_rihla_app.dart';

const _runningRecoveryJob = AccountJobStatusSnapshot(
  jobId: 'job-1',
  kind: AccountJobKind.recoveryCleanup,
  status: AccountJobRunStatus.running,
  phase: 'Migrating groups',
  current: 2,
  total: 5,
);

Future<ProviderContainer> _pumpOverlay(
  WidgetTester tester,
  Widget child,
) async {
  SharedPreferences.setMockInitialValues({});
  await pumpRihlaApp(tester, AccountJobOverlay(child: child));
  return ProviderScope.containerOf(
    tester.element(find.byType(AccountJobOverlay)),
  );
}

void main() {
  testWidgets('blocks interaction and shows counted progress while active', (
    tester,
  ) async {
    var taps = 0;
    final container = await _pumpOverlay(
      tester,
      Center(
        child: FilledButton(
          onPressed: () => taps += 1,
          child: const Text('Underlay action'),
        ),
      ),
    );

    container
        .read(accountJobCoordinatorProvider.notifier)
        .setActiveJobForTesting(_runningRecoveryJob);
    await tester.pump();

    expect(find.text('Finishing account restore'), findsOneWidget);
    expect(find.text('Migrating groups - 2 of 5'), findsOneWidget);

    await tester.tap(find.text('Underlay action'), warnIfMissed: false);
    await tester.pump();

    expect(taps, 0);
  });

  testWidgets('shows blocked deep-link notice while job is active', (
    tester,
  ) async {
    final container = await _pumpOverlay(tester, const SizedBox.expand());

    final notifier = container.read(accountJobCoordinatorProvider.notifier);
    notifier.setActiveJobForTesting(_runningRecoveryJob);
    notifier.notifyDeepLinkBlocked();
    await tester.pump();

    expect(
      find.text(
        'Finish this account task before opening invites or recovery links.',
      ),
      findsOneWidget,
    );
  });
}
