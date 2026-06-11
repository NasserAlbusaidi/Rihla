// Screen wiring for the durable-credential gate (#441 PR2).
//
// Both create and join consult durableCredentialGateProvider AFTER form
// validation and BEFORE setDeviceName/the service call; a declined gate
// aborts cleanly. The service-level DurableCredentialRequiredException
// (defense path — UI gate bypassed) maps to the durableCredentialRequired
// snackbar. Harness mirrors notification_prompt_wiring_test.dart.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';
import 'package:safar/core/providers/settings_provider.dart';
import 'package:safar/core/services/notification_prompt.dart';
import 'package:safar/core/theme/app_theme.dart';
import 'package:safar/features/auth/providers/durable_credential_gate_provider.dart';
import 'package:safar/features/auth/services/durable_credential_exception.dart';
import 'package:safar/features/groups/keys/group_keys.dart';
import 'package:safar/features/groups/models/group_model.dart';
import 'package:safar/features/groups/providers/group_provider.dart';
import 'package:safar/features/groups/screens/create_group_screen.dart';
import 'package:safar/features/groups/screens/join_group_screen.dart';
import 'package:safar/l10n/generated/app_localizations.dart';
import 'package:safar/l10n/generated/app_localizations_en.dart';
import 'package:shared_preferences/shared_preferences.dart';

class MockGroupService extends Mock implements GroupService {}

class RecordingPrompt implements NotificationPrompt {
  @override
  Future<void> maybePrompt() async {}
}

class RecordingGate extends DurableCredentialGate {
  RecordingGate(super.ref, {required bool result})
    : super(isAnonymous: () => true, presentSheet: (_) async => result);

  int ensured = 0;

  @override
  Future<bool> ensure(BuildContext context) {
    ensured++;
    return super.ensure(context);
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
  late RecordingGate gate;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    groupService = MockGroupService();
  });

  Widget wrap(SharedPreferences sp, Widget home, String start,
      {required bool gateResult}) {
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
        durableCredentialGateProvider.overrideWith((ref) {
          gate = RecordingGate(ref, result: gateResult);
          return gate;
        }),
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

  /// The override is lazy — materialize it so [gate] is readable even when
  /// the screen never consults the provider (the failing-RED direction).
  void materializeGate(WidgetTester tester) {
    ProviderScope.containerOf(
      tester.element(find.byType(MaterialApp)),
    ).read(durableCredentialGateProvider);
  }

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

    testWidgets('declined gate aborts before createGroup', (tester) async {
      final sp = await prefs();
      await tester.pumpWidget(
        wrap(sp, const CreateGroupScreen(), '/create-group',
            gateResult: false),
      );
      await tester.pumpAndSettle();
      materializeGate(tester);

      await fillAndSubmit(tester);

      expect(gate.ensured, 1);
      verifyNever(
        () => groupService.createGroup(
          name: any(named: 'name'),
          currency: any(named: 'currency'),
        ),
      );
      final container = ProviderScope.containerOf(
        tester.element(find.byKey(GroupKeys.createGroupButton)),
      );
      expect(container.read(groupLoadingProvider), isFalse);
    });

    testWidgets('passed gate proceeds to createGroup', (tester) async {
      when(
        () => groupService.createGroup(
          name: any(named: 'name'),
          currency: any(named: 'currency'),
        ),
      ).thenAnswer((_) async => _group());

      final sp = await prefs();
      await tester.pumpWidget(
        wrap(sp, const CreateGroupScreen(), '/create-group', gateResult: true),
      );
      await tester.pumpAndSettle();
      materializeGate(tester);

      await fillAndSubmit(tester);

      expect(gate.ensured, 1);
      verify(
        () => groupService.createGroup(
          name: 'Family Trip',
          currency: any(named: 'currency'),
        ),
      ).called(1);
    });

    testWidgets(
      'service-level DurableCredentialRequiredException maps to the '
      'durableCredentialRequired snackbar (defense path)',
      (tester) async {
        when(
          () => groupService.createGroup(
            name: any(named: 'name'),
            currency: any(named: 'currency'),
          ),
        ).thenThrow(const DurableCredentialRequiredException());

        final sp = await prefs();
        await tester.pumpWidget(
          wrap(sp, const CreateGroupScreen(), '/create-group',
              gateResult: true),
        );
        await tester.pumpAndSettle();
        materializeGate(tester);

        await fillAndSubmit(tester);

        expect(
          find.text(AppLocalizationsEn().durableCredentialRequired),
          findsOneWidget,
        );
        final container = ProviderScope.containerOf(
          tester.element(find.byKey(GroupKeys.createGroupButton)),
        );
        expect(container.read(groupLoadingProvider), isFalse);
      },
    );
  });

  group('join', () {
    Future<void> typeJoin(WidgetTester tester) async {
      final fields = find.byType(TextField);
      // Name field (0), invite-code field (1).
      await tester.enterText(fields.at(0), 'Tester');
      await tester.pump();
      await tester.enterText(fields.at(1), 'ABCDEF'); // 6th char auto-submits
      await tester.pump(const Duration(milliseconds: 250));
      await tester.pumpAndSettle();
    }

    testWidgets('typing the 6th code char consults the gate; declined gate '
        'blocks joinGroup', (tester) async {
      final sp = await prefs();
      await tester.pumpWidget(
        wrap(sp, const JoinGroupScreen(), '/join', gateResult: false),
      );
      await tester.pumpAndSettle();
      materializeGate(tester);

      await typeJoin(tester);

      expect(gate.ensured, 1);
      verifyNever(
        () => groupService.joinGroup(inviteCode: any(named: 'inviteCode')),
      );
      expect(find.text('group-landing'), findsNothing);
    });

    testWidgets('passed gate proceeds to joinGroup and lands on the group',
        (tester) async {
      when(() => groupService.joinGroup(inviteCode: any(named: 'inviteCode')))
          .thenAnswer((_) async => _group());

      final sp = await prefs();
      await tester.pumpWidget(
        wrap(sp, const JoinGroupScreen(), '/join', gateResult: true),
      );
      await tester.pumpAndSettle();
      materializeGate(tester);

      await typeJoin(tester);

      expect(gate.ensured, 1);
      verify(() => groupService.joinGroup(inviteCode: 'ABCDEF')).called(1);
      expect(find.text('group-landing'), findsOneWidget);
    });

    testWidgets(
      'service-level DurableCredentialRequiredException maps to the '
      'durableCredentialRequired snackbar (defense path)',
      (tester) async {
        when(
          () => groupService.joinGroup(inviteCode: any(named: 'inviteCode')),
        ).thenThrow(const DurableCredentialRequiredException());

        final sp = await prefs();
        await tester.pumpWidget(
          wrap(sp, const JoinGroupScreen(), '/join', gateResult: true),
        );
        await tester.pumpAndSettle();
        materializeGate(tester);

        await typeJoin(tester);

        expect(
          find.text(AppLocalizationsEn().durableCredentialRequired),
          findsOneWidget,
        );
      },
    );
  });
}
