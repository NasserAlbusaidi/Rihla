// #278 PR2: a group creator can seed placeholder ("shadow") members by name at
// create time. Names are local UI state until Create; on Create the screen
// awaits the stageGroup ack, then fans out one addShadowMember callable per
// chip. The chips field is connectivity-gated (the callable is online-only),
// while the group itself still creates offline with just the creator.
//
// The whole GroupService is mocked (the offline-412 precedent), so stageGroup
// and the new addShadowMember wrapper are both stubbed — no Firebase, no
// network. Offline is modelled with a never-acking Completer ack.

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
    // Group create acks instantly online unless a test overrides it.
    when(
      () => groupService.stageGroup(
        name: any(named: 'name'),
        currency: any(named: 'currency'),
      ),
    ).thenReturn((group: _group(), ack: Future<void>.value()));
  });

  Widget wrap(SharedPreferences sp, {required ConnectivityStatus status}) {
    connectivity = ConnectivityNotifier(startPeriodicChecks: false);
    if (status == ConnectivityStatus.offline) {
      connectivity.setOffline();
    }
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

  // Types a shadow name into the chips field and submits it (becomes a chip).
  Future<void> addChip(WidgetTester tester, String name) async {
    await tester.enterText(find.byKey(GroupKeys.shadowMemberInput), name);
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
  }

  testWidgets(
    'online: 2 shadow chips → Create fans out addShadowMember twice (#278)',
    (tester) async {
      when(
        () => groupService.addShadowMember(
          groupId: any(named: 'groupId'),
          displayName: any(named: 'displayName'),
        ),
      ).thenAnswer((_) async => 'm-generated');

      final sp = await SharedPreferences.getInstance();
      await tester.pumpWidget(wrap(sp, status: ConnectivityStatus.online));
      await tester.pump();

      await tester.enterText(
        find.byKey(GroupKeys.groupNameInput),
        'Family Trip',
      );
      await tester.enterText(find.byKey(GroupKeys.deviceNameInput), 'Tester');
      await addChip(tester, 'Sara');
      await addChip(tester, 'Khalid');
      await tester.pump();

      // Both chips render.
      expect(find.text('Sara'), findsOneWidget);
      expect(find.text('Khalid'), findsOneWidget);

      await tester.tap(find.byKey(GroupKeys.createGroupButton));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 120));

      // The group was created and each chip got an addShadowMember call.
      verify(
        () => groupService.stageGroup(
          name: 'Family Trip',
          currency: any(named: 'currency'),
        ),
      ).called(1);
      verify(
        () => groupService.addShadowMember(groupId: 'g1', displayName: 'Sara'),
      ).called(1);
      verify(
        () =>
            groupService.addShadowMember(groupId: 'g1', displayName: 'Khalid'),
      ).called(1);
    },
  );

  testWidgets(
    'offline: chips input disabled + hint; Create still makes the group with '
    'zero addShadowMember calls (#278)',
    (tester) async {
      // never-acking ack models offline queued-success.
      when(
        () => groupService.stageGroup(
          name: any(named: 'name'),
          currency: any(named: 'currency'),
        ),
      ).thenReturn((group: _group(), ack: Completer<void>().future));

      final sp = await SharedPreferences.getInstance();
      await tester.pumpWidget(wrap(sp, status: ConnectivityStatus.offline));
      await tester.pump();

      // Offline hint visible, input is disabled (not editable).
      expect(find.text('Connect to add names'), findsOneWidget);
      final field = tester.widget<TextField>(
        find.byKey(GroupKeys.shadowMemberInput),
      );
      expect(field.enabled, isFalse);

      await tester.enterText(
        find.byKey(GroupKeys.groupNameInput),
        'Family Trip',
      );
      await tester.enterText(find.byKey(GroupKeys.deviceNameInput), 'Tester');
      await tester.pump();

      await tester.tap(find.byKey(GroupKeys.createGroupButton));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 120));

      // Group still created; the share sheet shows the invite code.
      expect(find.text('ABCDEF'), findsOneWidget);
      verify(
        () => groupService.stageGroup(
          name: 'Family Trip',
          currency: any(named: 'currency'),
        ),
      ).called(1);
      verifyNever(
        () => groupService.addShadowMember(
          groupId: any(named: 'groupId'),
          displayName: any(named: 'displayName'),
        ),
      );
    },
  );

  testWidgets(
    'already-exists for one chip → that name surfaces as taken; group still '
    'created; the other chip still proceeds (#278)',
    (tester) async {
      when(
        () => groupService.addShadowMember(
          groupId: any(named: 'groupId'),
          displayName: 'Sara',
        ),
      ).thenThrow(const ShadowMemberNameTakenException('Sara'));
      when(
        () => groupService.addShadowMember(
          groupId: any(named: 'groupId'),
          displayName: 'Khalid',
        ),
      ).thenAnswer((_) async => 'm-khalid');

      final sp = await SharedPreferences.getInstance();
      await tester.pumpWidget(wrap(sp, status: ConnectivityStatus.online));
      await tester.pump();

      await tester.enterText(
        find.byKey(GroupKeys.groupNameInput),
        'Family Trip',
      );
      await tester.enterText(find.byKey(GroupKeys.deviceNameInput), 'Tester');
      await addChip(tester, 'Sara');
      await addChip(tester, 'Khalid');
      await tester.pump();

      await tester.tap(find.byKey(GroupKeys.createGroupButton));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 120));

      // The group was created (share sheet shows the code).
      expect(find.text('ABCDEF'), findsOneWidget);
      // Sara surfaced as taken.
      expect(find.textContaining('Sara'), findsWidgets);
      expect(find.textContaining('already used in this group'), findsOneWidget);
      // Khalid still got its call.
      verify(
        () =>
            groupService.addShadowMember(groupId: 'g1', displayName: 'Khalid'),
      ).called(1);
    },
  );

  testWidgets(
    'generic addShadowMember failure surfaces that typed names were not added '
    '(#649)',
    (tester) async {
      when(
        () => groupService.addShadowMember(
          groupId: any(named: 'groupId'),
          displayName: 'Sara',
        ),
      ).thenThrow(Exception('network failed'));
      when(
        () => groupService.addShadowMember(
          groupId: any(named: 'groupId'),
          displayName: 'Khalid',
        ),
      ).thenAnswer((_) async => 'm-khalid');

      final sp = await SharedPreferences.getInstance();
      await tester.pumpWidget(wrap(sp, status: ConnectivityStatus.online));
      await tester.pump();

      await tester.enterText(
        find.byKey(GroupKeys.groupNameInput),
        'Family Trip',
      );
      await tester.enterText(find.byKey(GroupKeys.deviceNameInput), 'Tester');
      await addChip(tester, 'Sara');
      await addChip(tester, 'Khalid');
      await tester.pump();

      await tester.tap(find.byKey(GroupKeys.createGroupButton));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 120));

      // The group was created, but the failed chip is not silently lost.
      expect(find.text('ABCDEF'), findsOneWidget);
      expect(
        find.text(
          'Some names could not be added. You can add them from the group later.',
        ),
        findsOneWidget,
      );
      verify(
        () =>
            groupService.addShadowMember(groupId: 'g1', displayName: 'Khalid'),
      ).called(1);
    },
  );
}
