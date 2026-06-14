// #520: offline createGroup must be treated as queued-success, not a loud
// false error. The write future acks only on SERVER ack (#412); offline it
// stays pending, so the old createGroup().timeout(15s) fired a TimeoutException
// → groupErrorProvider + Sentry + groupCreateError snackbar, even though the
// group was applied to the local cache and will replay. The fix stages the
// write and races the ack with skipWait when offline.
//
// FakeFirebaseFirestore acks instantly and would prove nothing about offline,
// so this models offline with a never-completing Completer through a mocked
// GroupService (the *_offline_412_test.dart precedent).

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:safar/core/providers/connectivity_provider.dart';
import 'package:safar/core/providers/settings_provider.dart';
import 'package:safar/core/services/notification_prompt.dart';
import 'package:safar/core/theme/app_theme.dart';
import 'package:safar/features/auth/providers/durable_credential_gate_provider.dart';
import 'package:safar/features/groups/keys/group_keys.dart';
import 'package:safar/features/groups/models/group_model.dart';
import 'package:safar/features/groups/providers/group_provider.dart';
import 'package:safar/features/groups/screens/create_group_screen.dart';
import 'package:safar/l10n/generated/app_localizations.dart';

class _MockGroupService extends Mock implements GroupService {}

class _RecordingPrompt implements NotificationPrompt {
  @override
  Future<void> maybePrompt() async {}
}

Group _group() => Group(
  id: 'g1',
  name: 'Trip',
  inviteCode: 'ABCDEF',
  createdBy: 'u1',
  memberIds: const ['u1'],
  currency: 'OMR',
  createdAt: DateTime(2026, 1, 1),
);

void main() {
  late _MockGroupService groupService;
  late ConnectivityNotifier connectivity;

  setUp(() {
    SharedPreferences.setMockInitialValues({'settings_device_name': 'Tester'});
    groupService = _MockGroupService();
  });

  Widget wrap(SharedPreferences sp) {
    connectivity = ConnectivityNotifier(startPeriodicChecks: false)..setOffline();
    final router = GoRouter(
      initialLocation: '/create-group',
      routes: [
        GoRoute(
          path: '/create-group',
          builder: (_, _) => const CreateGroupScreen(),
        ),
        GoRoute(
          path: '/group/:id',
          builder: (_, _) => const Scaffold(body: Text('group-landing')),
        ),
        GoRoute(
          path: '/home',
          builder: (_, _) => const Scaffold(body: Text('home')),
        ),
      ],
    );
    return ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(sp),
        deviceLocalesProvider.overrideWithValue(const [Locale('en')]),
        groupServiceProvider.overrideWithValue(groupService),
        notificationPromptProvider.overrideWithValue(_RecordingPrompt()),
        connectivityProvider.overrideWith((ref) => connectivity),
        // Durable (non-anonymous) user → the gate passes without presenting a
        // sheet, so the create path runs straight through to the write.
        durableCredentialGateProvider.overrideWith(
          (ref) => DurableCredentialGate(
            ref,
            isAnonymous: () => false,
            presentSheet: (_, {intent}) async => true,
          ),
        ),
      ],
      child: MaterialApp.router(
        routerConfig: router,
        theme: AppTheme.lightTheme,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
      ),
    );
  }

  testWidgets(
    'offline create is treated as queued-success, not a false error (#520)',
    (tester) async {
      // Post-fix offline: stageGroup returns the local Group immediately with a
      // never-acking ack (server confirms only on reconnect).
      when(
        () => groupService.stageGroup(
          name: any(named: 'name'),
          currency: any(named: 'currency'),
        ),
      ).thenReturn((group: _group(), ack: Completer<void>().future));
      // Pre-fix offline: the screen awaits createGroup().timeout(15s); the raw
      // write never acks → TimeoutException → the false error. (Unused once the
      // screen switches to stageGroup; harmless to stub both — *_offline_412
      // precedent.)
      when(
        () => groupService.createGroup(
          name: any(named: 'name'),
          currency: any(named: 'currency'),
        ),
      ).thenAnswer((_) => Completer<Group>().future);

      final sp = await SharedPreferences.getInstance();
      await tester.pumpWidget(wrap(sp));
      await tester.pump();

      await tester.enterText(find.byKey(GroupKeys.groupNameInput), 'Family Trip');
      await tester.enterText(find.byKey(GroupKeys.deviceNameInput), 'Tester');
      await tester.pump();
      await tester.tap(find.byKey(GroupKeys.createGroupButton));
      // FIXED pumps only — pumpAndSettle would hang on the never-acking ack.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 120));

      final container = ProviderScope.containerOf(
        tester.element(find.byKey(GroupKeys.createGroupButton)),
      );

      // Queued-success affordances appear immediately (skipWait short-circuit),
      // within the snackbar's lifetime. Pre-fix the screen is still hanging on
      // createGroup so none of these are present → RED.
      expect(find.text('ABCDEF'), findsOneWidget); // share sheet invite code
      expect(
        find.text('Group created — will sync when online.'),
        findsOneWidget,
      );
      expect(container.read(connectivityProvider), ConnectivityStatus.syncing);

      // Advance past the old 15s timeout to prove NO false error ever fires.
      // Pre-fix, the timeout sets groupErrorProvider here → RED.
      await tester.pump(const Duration(seconds: 16));
      expect(container.read(groupErrorProvider), isNull);
    },
  );
}
