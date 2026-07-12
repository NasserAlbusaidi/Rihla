import 'dart:async';

import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:safar/core/providers/settings_provider.dart';
import 'package:safar/core/theme/app_theme.dart';
import 'package:safar/features/events/providers/event_provider.dart';
import 'package:safar/features/groups/models/group_member_model.dart';
import 'package:safar/features/groups/models/group_model.dart';
import 'package:safar/features/groups/providers/group_balance_provider.dart';
import 'package:safar/features/groups/providers/group_provider.dart';
import 'package:safar/features/groups/screens/group_detail_screen.dart';
import 'package:safar/features/ledger/models/expense_model.dart';
import 'package:safar/l10n/generated/app_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

// #1192: go_router 13.2.5's GoRouterDelegate.popRoute() nulls the root
// navigator when the current match stack can't pop (a sole route), so it
// returns `false` before ever consulting the mounted PopScope. WidgetsBinding
// then falls through to SystemNavigator.pop() and the app exits — the #243
// cold-entry back guard on GroupDetailScreen (PopScope(canPop:false) ->
// go('/home')) never fires on the real device back-button channel.
//
// This pins that contract end-to-end. The mount below is load-bearing:
// tester.binding.handlePopRoute() reaches GoRouterDelegate.popRoute() only
// through the RootBackButtonDispatcher that MaterialApp.router(routerConfig:)
// installs — a bare Navigator would let handlePopRoute consult the PopScope
// directly and go green on 13.2.5 too (a vacuous RED).
void main() {
  const groupId = 'g1';

  final testGroup = Group(
    id: groupId,
    name: 'Adventure Crew',
    inviteCode: 'ABC123',
    createdBy: 'uid-creator',
    memberIds: const ['uid-creator', 'uid-member'],
    createdAt: DateTime(2026, 1, 1),
  );

  final members = [
    GroupMember(
      id: 'member-1',
      groupId: groupId,
      userId: 'uid-creator',
      displayName: 'Alice',
      role: 'CREATOR',
      joinedAt: DateTime(2026, 1, 1),
    ),
    GroupMember(
      id: 'member-2',
      groupId: groupId,
      userId: 'uid-member',
      displayName: 'Bob',
      role: 'MEMBER',
      joinedAt: DateTime(2026, 1, 2),
    ),
  ];

  final balances = (
    balances: <String, List<UserBalance>>{
      'OMR': [
        UserBalance(
          participantId: 'uid-creator',
          displayName: 'Alice',
          totalPaid: Decimal.zero,
          totalOwed: Decimal.zero,
          netBalance: Decimal.zero,
        ),
        UserBalance(
          participantId: 'uid-member',
          displayName: 'Bob',
          totalPaid: Decimal.zero,
          totalOwed: Decimal.zero,
          netBalance: Decimal.zero,
        ),
      ],
    },
    totalSpent: <String, Decimal>{'OMR': Decimal.zero},
    eventCount: 0,
    perEventBreakdown: <String, Map<String, Map<String, Decimal>>>{},
    memberNames: <String, String>{'uid-creator': 'Alice', 'uid-member': 'Bob'},
    memberRawNames: <String, String>{},
  );

  List<Override> overridesFor() => [
    groupDetailProvider(groupId).overrideWith((ref) => Stream.value(testGroup)),
    groupMembersProvider(groupId).overrideWith((ref) => Stream.value(members)),
    groupEventsProvider(groupId).overrideWith((ref) => Stream.value(const [])),
    groupBalancesProvider(
      groupId,
    ).overrideWith((ref) => AsyncValue.data(balances)),
    groupActivityProvider(
      groupId,
    ).overrideWith((ref) => Stream.value(const [])),
    currentUserIdProvider.overrideWithValue('uid-creator'),
  ];

  group('GroupDetailScreen back-navigation (#1192 popRoute channel)', () {
    testWidgets(
      'sole-route cold entry: device back lands on /home, never exits',
      (tester) async {
        SharedPreferences.setMockInitialValues({'device_name': 'Alice'});
        final prefs = await SharedPreferences.getInstance();

        final router = GoRouter(
          initialLocation: '/group/$groupId',
          routes: [
            GoRoute(
              path: '/home',
              builder: (_, _) => const Scaffold(body: Text('Home')),
            ),
            GoRoute(
              path: '/group/:gid',
              builder: (_, state) =>
                  GroupDetailScreen(groupId: state.pathParameters['gid']!),
            ),
          ],
        );
        addTearDown(router.dispose);

        final popCalls = <MethodCall>[];
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(SystemChannels.platform, (call) async {
              if (call.method == 'SystemNavigator.pop') {
                popCalls.add(call);
              }
              return null;
            });
        addTearDown(
          () => TestDefaultBinaryMessengerBinding.instance
              .defaultBinaryMessenger
              .setMockMethodCallHandler(SystemChannels.platform, null),
        );

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              sharedPreferencesProvider.overrideWithValue(prefs),
              ...overridesFor(),
            ],
            child: MaterialApp.router(
              theme: AppTheme.lightTheme,
              routerConfig: router,
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
            ),
          ),
        );
        await tester.pumpAndSettle();

        // The real device back-button channel — NOT a hand-called PopScope
        // handler and NOT an imperative router.pop()/router.pop() call.
        await tester.binding.handlePopRoute();
        await tester.pumpAndSettle();

        // #1192 contract: the guard must win — no exit, back lands on /home.
        expect(popCalls, isEmpty);
        expect(
          router.routerDelegate.currentConfiguration.uri.path,
          '/home',
        );
      },
    );

    testWidgets(
      'pushed stack control: device back pops to /home, no exit (unchanged)',
      (tester) async {
        SharedPreferences.setMockInitialValues({'device_name': 'Alice'});
        final prefs = await SharedPreferences.getInstance();

        final router = GoRouter(
          initialLocation: '/home',
          routes: [
            GoRoute(
              path: '/home',
              builder: (_, _) => const Scaffold(body: Text('Home')),
            ),
            GoRoute(
              path: '/group/:gid',
              builder: (_, state) =>
                  GroupDetailScreen(groupId: state.pathParameters['gid']!),
            ),
          ],
        );
        addTearDown(router.dispose);

        final popCalls = <MethodCall>[];
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(SystemChannels.platform, (call) async {
              if (call.method == 'SystemNavigator.pop') {
                popCalls.add(call);
              }
              return null;
            });
        addTearDown(
          () => TestDefaultBinaryMessengerBinding.instance
              .defaultBinaryMessenger
              .setMockMethodCallHandler(SystemChannels.platform, null),
        );

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              sharedPreferencesProvider.overrideWithValue(prefs),
              ...overridesFor(),
            ],
            child: MaterialApp.router(
              theme: AppTheme.lightTheme,
              routerConfig: router,
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
            ),
          ),
        );
        await tester.pumpAndSettle();

        // #1192 trap: GoRouter.push()'s returned Future resolves only when
        // the pushed route is later POPPED, not when the push transition
        // completes — awaiting it here would block forever (established
        // idiom: group_detail_navigation_test.dart:276,296).
        unawaited(router.push('/group/$groupId'));
        await tester.pumpAndSettle();

        await tester.binding.handlePopRoute();
        await tester.pumpAndSettle();

        expect(popCalls, isEmpty);
        expect(
          router.routerDelegate.currentConfiguration.uri.path,
          '/home',
        );
      },
    );
  });
}
