// Wiring tests for #288: a successful group join (and create) fires the
// natural-moment notification-permission prompt exactly once. The prompt's
// own logic is unit-tested in test/unit/notification_prompt_test.dart; here we
// only prove the call sites invoke it.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';
import 'package:safar/core/theme/app_theme.dart';
import 'package:safar/core/providers/connectivity_provider.dart';
import 'package:safar/core/providers/settings_provider.dart';
import 'package:safar/core/services/notification_prompt.dart';
import 'package:safar/features/groups/keys/group_keys.dart';
import 'package:safar/features/groups/models/group_model.dart';
import 'package:safar/features/groups/providers/group_provider.dart';
import 'package:safar/features/groups/screens/create_group_screen.dart';
import 'package:safar/features/groups/screens/join_group_screen.dart';
import 'package:safar/l10n/generated/app_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

class MockGroupService extends Mock implements GroupService {}

/// Records calls without touching FirebaseMessaging.
class RecordingPrompt implements NotificationPrompt {
  int calls = 0;

  @override
  Future<void> maybePrompt() async {
    calls++;
  }
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
  late RecordingPrompt prompt;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    groupService = MockGroupService();
    prompt = RecordingPrompt();
  });

  Future<SharedPreferences> prefs() => SharedPreferences.getInstance();

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
        notificationPromptProvider.overrideWithValue(prompt),
        // The create path reads connectivityProvider (#520); timer-free notifier.
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

  testWidgets('successful join fires the notification prompt once',
      (tester) async {
    when(() => groupService.joinGroup(inviteCode: any(named: 'inviteCode')))
        .thenAnswer((_) async => _group());

    final sp = await prefs();
    await tester.pumpWidget(wrap(sp, const JoinGroupScreen(), '/join'));
    await tester.pumpAndSettle();

    final fields = find.byType(TextField);
    // Name field (0), invite-code field (1).
    await tester.enterText(fields.at(0), 'Tester');
    await tester.pump();
    await tester.enterText(fields.at(1), 'ABCDEF'); // 6th char auto-submits
    await tester.pump(const Duration(milliseconds: 250)); // drain haptic timer
    await tester.pumpAndSettle();

    verify(() => groupService.joinGroup(inviteCode: 'ABCDEF')).called(1);
    expect(prompt.calls, 1);
    expect(find.text('group-landing'), findsOneWidget);
  });

  testWidgets('successful create fires the notification prompt once after the '
      'share sheet is dismissed', (tester) async {
    when(
      () => groupService.stageGroup(
        name: any(named: 'name'),
        currency: any(named: 'currency'),
      ),
    ).thenReturn((group: _group(), ack: Future<void>.value()));

    final sp = await prefs();
    await tester
        .pumpWidget(wrap(sp, const CreateGroupScreen(), '/create-group'));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(GroupKeys.groupNameInput),
      'Family Trip',
    );
    await tester.enterText(find.byKey(GroupKeys.deviceNameInput), 'Tester');
    await tester.pump();

    await tester.tap(find.byKey(GroupKeys.createGroupButton));
    await tester.pumpAndSettle(); // create resolves → share sheet appears

    // Prompt must NOT fire while the share sheet is still up.
    expect(prompt.calls, 0);

    await tester.tap(find.text('Done')); // onNavigate → pops sheet + navigates
    await tester.pumpAndSettle();

    verify(
      () => groupService.stageGroup(
        name: 'Family Trip',
        currency: any(named: 'currency'),
      ),
    ).called(1);
    expect(prompt.calls, 1);
    expect(find.text('group-landing'), findsOneWidget);
  });
}
