// #818: the #441 durable-credential create-time gate is REMOVED. This file
// used to pin the gated create-screen wiring (declined gate aborts, gate
// receives an in-flight intent, passed gate proceeds, and the
// DurableCredentialRequiredException defense path). All four are obsolete —
// stageGroup no longer consults anonymity at all, and durableCredentialGateProvider
// no longer exists — so they're replaced by ONE pin: an anonymous user taps
// Create and stageGroup is invoked directly, with no sheet ever presented.
//
// The join group (join never consulted the gate, #648) is UNRELATED to this
// removal and survives — relocated to create_join_group_test.dart per the
// #818 spec so create-gate coverage can be deleted without losing it.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';
import 'package:safar/core/providers/connectivity_provider.dart';
import 'package:safar/core/providers/settings_provider.dart';
import 'package:safar/core/services/notification_prompt.dart';
import 'package:safar/core/theme/app_theme.dart';
import 'package:safar/features/groups/keys/group_keys.dart';
import 'package:safar/features/groups/models/group_model.dart';
import 'package:safar/features/groups/providers/group_provider.dart';
import 'package:safar/features/groups/screens/create_group_screen.dart';
import 'package:safar/l10n/generated/app_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

class MockGroupService extends Mock implements GroupService {}

class RecordingPrompt implements NotificationPrompt {
  @override
  Future<void> maybePrompt() async {}
}

Group _group() => Group(
  id: 'g1',
  name: 'Trip',
  inviteCode: 'ABCDEF',
  createdBy: 'u1',
  memberIds: const ['u1'],
  createdAt: DateTime(2026, 1, 1),
);

void main() {
  late MockGroupService groupService;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    groupService = MockGroupService();
  });

  Widget wrap(SharedPreferences sp, Widget home, String start) {
    final router = GoRouter(
      initialLocation: start,
      routes: [
        GoRoute(path: start, builder: (_, _) => home),
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
        notificationPromptProvider.overrideWithValue(RecordingPrompt()),
        // The create path reads connectivityProvider (#520); use a timer-free
        // notifier so pumpAndSettle doesn't hang/leak the 60s periodic timer.
        connectivityProvider.overrideWith(
          (ref) => ConnectivityNotifier(startPeriodicChecks: false),
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

  Future<SharedPreferences> prefs() => SharedPreferences.getInstance();

  group('create', () {
    Future<void> fillAndSubmit(WidgetTester tester) async {
      await tester.enterText(
        find.byKey(GroupKeys.groupNameInput),
        'Family Trip',
      );
      await tester.enterText(find.byKey(GroupKeys.deviceNameInput), 'Tester');
      await tester.pump();
      await tester.tap(find.byKey(GroupKeys.createGroupButton));
      await tester.pumpAndSettle();
    }

    testWidgets(
      '#818: anonymous user taps Create → stageGroup invoked directly, '
      'no durable-credential sheet',
      (tester) async {
        when(
          () => groupService.stageGroup(
            name: any(named: 'name'),
            currency: any(named: 'currency'),
          ),
        ).thenReturn((group: _group(), ack: Future<void>.value()));

        final sp = await prefs();
        await tester.pumpWidget(wrap(sp, const CreateGroupScreen(), '/create-group'));
        await tester.pumpAndSettle();

        await fillAndSubmit(tester);

        verify(
          () => groupService.stageGroup(
            name: 'Family Trip',
            currency: any(named: 'currency'),
          ),
        ).called(1);
        // The #441 gate sheet ("Keep your money safe") never appears — there is
        // no gate left to present it.
        expect(find.text('Keep your money safe'), findsNothing);
      },
    );
  });
}
