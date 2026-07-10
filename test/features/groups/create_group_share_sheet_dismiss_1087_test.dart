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
import 'package:safar/features/groups/keys/group_keys.dart';
import 'package:safar/features/groups/models/group_model.dart';
import 'package:safar/features/groups/providers/group_provider.dart';
import 'package:safar/features/groups/screens/create_group_screen.dart';
import 'package:safar/features/groups/widgets/invite_code_display.dart';
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

  setUp(() {
    SharedPreferences.setMockInitialValues({'settings_device_name': 'Tester'});
    groupService = _MockGroupService();
  });

  Widget wrap(SharedPreferences sp) {
    final connectivity = ConnectivityNotifier(startPeriodicChecks: false);
    final router = GoRouter(
      initialLocation: '/create-group',
      routes: [
        GoRoute(
          path: '/create-group',
          builder: (_, _) => const CreateGroupScreen(),
        ),
        GoRoute(
          path: '/group/:groupId',
          builder: (_, state) => Scaffold(
            body: Text('GroupDetail:${state.pathParameters['groupId']}'),
          ),
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
      ],
      child: MaterialApp.router(
        routerConfig: router,
        theme: AppTheme.lightTheme,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
      ),
    );
  }

  Future<void> openShareSheet(WidgetTester tester) async {
    when(
      () => groupService.stageGroup(
        name: any(named: 'name'),
        currency: any(named: 'currency'),
      ),
    ).thenReturn((group: _group(), ack: Future<void>.value()));

    final sp = await SharedPreferences.getInstance();
    await tester.pumpWidget(wrap(sp));
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(GroupKeys.groupNameInput), 'Family Trip');
    await tester.enterText(find.byKey(GroupKeys.deviceNameInput), 'Tester');
    await tester.pump();
    await tester.tap(find.byKey(GroupKeys.createGroupButton));
    await tester.pumpAndSettle();

    expect(find.byType(InviteCodeDisplay), findsOneWidget);
  }

  void expectGroupLanding() {
    expect(find.text('GroupDetail:g1'), findsOneWidget);
    expect(find.byKey(GroupKeys.createScreen), findsNothing);
  }

  testWidgets(
    'barrier-tap dismissal of the post-create share sheet lands on the group (#1087)',
    (tester) async {
      await openShareSheet(tester);

      await tester.tapAt(const Offset(10, 60));
      await tester.pumpAndSettle();

      expectGroupLanding();
    },
  );

  testWidgets('drag-down dismissal lands on the group (#1087)', (tester) async {
    await openShareSheet(tester);

    await tester.drag(find.byType(BottomSheet), const Offset(0, 400));
    await tester.pumpAndSettle();

    expectGroupLanding();
  });

  testWidgets('Done keeps navigating (#1087 regression guard)', (tester) async {
    await openShareSheet(tester);

    await tester.tap(find.widgetWithText(TextButton, 'Done'));
    await tester.pumpAndSettle();

    expectGroupLanding();
  });
}
