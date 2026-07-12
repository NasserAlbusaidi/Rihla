import 'dart:async';

import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:safar/core/providers/settings_provider.dart';
import 'package:safar/core/theme/app_theme.dart';
import 'package:safar/features/auth/providers/auth_provider.dart';
import 'package:safar/features/events/providers/event_provider.dart';
import 'package:safar/features/groups/keys/group_keys.dart';
import 'package:safar/features/groups/models/group_member_model.dart';
import 'package:safar/features/groups/models/group_model.dart';
import 'package:safar/features/groups/providers/group_balance_provider.dart';
import 'package:safar/features/groups/providers/group_provider.dart';
import 'package:safar/features/groups/screens/group_detail_screen.dart';
import 'package:safar/features/home/providers/dashboard_providers.dart';
import 'package:safar/features/home/screens/home_screen.dart';
import 'package:safar/features/home/widgets/bottom_nav_shell.dart';
import 'package:safar/features/ledger/models/expense_model.dart';
import 'package:safar/l10n/generated/app_localizations.dart';

/// #1188 — dual-channel root back-exit guard on [BottomNavShell] + `nav.back`
/// breadcrumbs.
///
/// Drive note (round 3): the primary drive is `tester.binding.handlePopRoute()`
/// — the REAL engine entry point. It exercises the full chain (binding → Router
/// → RootBackButtonDispatcher → BackButtonListener / go_router `popRoute`) and
/// is exactly the path the go_router 13.2.5 hole lives on: `popRoute()` guards
/// `maybePop()` behind `state.canPop()`, so on a SOLE `/home` route a
/// `PopScope`-only guard is never consulted and the app exits via
/// `SystemNavigator.pop()`. A test that hand-mirrors `maybePop`'s disposition
/// switch would go green while the guard is dead on device — that masking is
/// what round 1 shipped and this file removes. Assertions read the recorded
/// `SystemNavigator.pop` calls + the exit snackbar, never a singular `PopScope`
/// finder (the real tree holds two PopScopes).
///
/// Test 6 additionally drives `NavigatorState.maybePop()` directly to pin the
/// PopScope layer (the maybePop/predictive channel) and channel exclusivity —
/// exactly one guard effect per press, never both channels on one press.
const _uid = 'test-user-id';
const _groupId = 'g1';

Group _group() => Group(
  id: _groupId,
  name: 'Desert Crew',
  inviteCode: 'ABC123',
  createdBy: _uid,
  memberIds: const [_uid],
  currency: 'OMR',
  createdAt: DateTime(2026, 1, 1),
);

List<GroupMember> _members() => [
  GroupMember(
    id: 'member-1',
    groupId: _groupId,
    userId: _uid,
    displayName: 'Traveler',
    role: 'CREATOR',
    joinedAt: DateTime(2026, 1, 1),
  ),
];

List<Override> _overrides(SharedPreferences prefs) => [
  sharedPreferencesProvider.overrideWithValue(prefs),
  currentUserIdProvider.overrideWithValue(_uid),
  linkedEmailProvider.overrideWithValue('secured@example.com'),
  isDurableUserProvider.overrideWithValue(true),
  userGroupsProvider.overrideWith((ref) => Stream.value([_group()])),
  crossGroupHomeBalanceProvider.overrideWith(
    (ref) => const AsyncValue.data((
      balance: (
        byCurrency: <CurrencyBalance>[],
        groupCount: 1,
        isLoading: false,
      ),
      partial: false,
    )),
  ),
  crossGroupActivityProvider.overrideWith((ref) => const AsyncValue.data([])),
  groupBalancesProvider.overrideWith(
    (ref, groupId) => const AsyncValue.data((
      balances: <String, List<UserBalance>>{},
      totalSpent: <String, Decimal>{},
      eventCount: 0,
      perEventBreakdown: <String, Map<String, Map<String, Decimal>>>{},
      memberNames: <String, String>{},
      memberRawNames: <String, String>{},
    )),
  ),
  groupEventsProvider(_groupId).overrideWith((ref) => Stream.value(const [])),
  groupDetailProvider(_groupId).overrideWith((ref) => Stream.value(_group())),
  groupMembersProvider(_groupId).overrideWith((ref) => Stream.value(_members())),
  groupActivityProvider(_groupId).overrideWith((ref) => Stream.value(const [])),
];

GoRouter _router() => GoRouter(
  initialLocation: '/home',
  routes: [
    GoRoute(path: '/home', builder: (_, _) => const HomeScreen()),
    GoRoute(
      path: '/group/:gid',
      builder: (_, state) =>
          GroupDetailScreen(groupId: state.pathParameters['gid']!),
    ),
  ],
);

/// Mount the real home shell at `/home`, returning the list that records every
/// `SystemNavigator.pop` platform call (the exit signal) and the live router.
Future<(List<MethodCall> popCalls, GoRouter router)> _pumpHome(
  WidgetTester tester, {
  Locale? locale,
}) async {
  SharedPreferences.setMockInitialValues({'device_name': 'Traveler'});
  final prefs = await SharedPreferences.getInstance();

  final popCalls = <MethodCall>[];
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
    SystemChannels.platform,
    (call) async {
      if (call.method == 'SystemNavigator.pop') popCalls.add(call);
      return null;
    },
  );
  addTearDown(
    () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      null,
    ),
  );

  final router = _router();
  addTearDown(router.dispose);

  await tester.pumpWidget(
    ProviderScope(
      overrides: _overrides(prefs),
      child: MaterialApp.router(
        theme: AppTheme.lightTheme,
        locale: locale,
        routerConfig: router,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
      ),
    ),
  );
  await tester.pumpAndSettle();
  return (popCalls, router);
}

/// The exit-snackbar text in the currently-mounted locale.
String _exitCopy(WidgetTester tester) => AppLocalizations.of(
  tester.element(find.byType(HomeScreen)),
).backAgainToExit;

/// Drive a system back through the REAL engine entry point — the exact chain
/// (binding → Router → RootBackButtonDispatcher → BackButtonListener /
/// go_router `popRoute`) the go_router 13.2.5 hole lives on. NOT a hand-mirrored
/// disposition switch (that masks a guard dead on device).
Future<void> _handlePopRoute(WidgetTester tester) async {
  await tester.binding.handlePopRoute();
  await tester.pumpAndSettle();
}

void main() {
  group('#1188 dual-channel root back-exit guard', () {
    testWidgets(
      'test 1 — first back (popRoute channel): no exit, exit hint shown',
      (tester) async {
        final (popCalls, _) = await _pumpHome(tester);

        await _handlePopRoute(tester);

        expect(popCalls, isEmpty, reason: 'first back must NOT exit the app');
        expect(find.text(_exitCopy(tester)), findsOneWidget);

        // Drain the 2s snackbar + reset timers before teardown.
        await tester.pump(const Duration(seconds: 3));
      },
    );

    testWidgets('test 2 — second back within the window exits exactly once', (
      tester,
    ) async {
      final (popCalls, _) = await _pumpHome(tester);

      await _handlePopRoute(tester);
      expect(popCalls, isEmpty);
      await _handlePopRoute(tester);

      expect(
        popCalls,
        hasLength(1),
        reason: 'second back within 2s exits exactly once',
      );

      await tester.pump(const Duration(seconds: 3));
    });

    testWidgets('test 3 — window expiry resets the guard', (tester) async {
      final (popCalls, _) = await _pumpHome(tester);

      await _handlePopRoute(tester);
      expect(popCalls, isEmpty);
      expect(find.text(_exitCopy(tester)), findsOneWidget);

      // Let the 2s window (and its snackbar) expire — the reset Timer fires.
      await tester.pump(const Duration(seconds: 3));

      await _handlePopRoute(tester);
      expect(
        popCalls,
        isEmpty,
        reason: 'after the window resets, back is a first-press again',
      );
      expect(find.text(_exitCopy(tester)), findsOneWidget);

      await tester.pump(const Duration(seconds: 3));
    });

    testWidgets(
      'test 4 — pushed route keeps its own back (no shell interference)',
      (tester) async {
        final (popCalls, router) = await _pumpHome(tester);

        unawaited(router.push('/group/$_groupId'));
        await tester.pumpAndSettle();
        expect(find.byKey(GroupKeys.detailScreen), findsOneWidget);

        // System back on the pushed group-detail: the shell's BackButtonListener
        // defers (its `/home` route is not current), so go_router pops the
        // pushed route back to home — never the shell's exit guard.
        await _handlePopRoute(tester);

        expect(popCalls, isEmpty, reason: 'pushed-route back must not exit');
        expect(find.byKey(GroupKeys.detailScreen), findsNothing);
        expect(find.byType(HomeScreen), findsOneWidget);
        expect(
          find.text(_exitCopy(tester)),
          findsNothing,
          reason: 'shell guard must not fire while a route is on top',
        );

        // Back on home again re-arms the shell guard (guard active again).
        await _handlePopRoute(tester);
        expect(popCalls, isEmpty);
        expect(find.text(_exitCopy(tester)), findsOneWidget);

        await tester.pump(const Duration(seconds: 3));
      },
    );

    testWidgets('test 5 — RTL smoke: Arabic exit hint renders', (tester) async {
      final (popCalls, _) = await _pumpHome(tester, locale: const Locale('ar'));

      await _handlePopRoute(tester);

      expect(popCalls, isEmpty);
      final arCopy = _exitCopy(tester);
      expect(arCopy, 'اضغط رجوعًا مرة أخرى للخروج');
      expect(find.text(arCopy), findsOneWidget);

      await tester.pump(const Duration(seconds: 3));
    });

    testWidgets(
      'test 6 — maybePop channel parity: one press, one snackbar, no exit',
      (tester) async {
        final (popCalls, _) = await _pumpHome(tester);

        // Drive the maybePop/predictive channel directly (the PopScope layer),
        // never the BackButtonListener. First-press parity + exclusivity: the
        // two channels must never both fire on a single press.
        await tester
            .state<NavigatorState>(find.byType(Navigator).first)
            .maybePop();
        await tester.pumpAndSettle();

        expect(
          popCalls,
          isEmpty,
          reason: 'maybePop first press must not exit',
        );
        expect(
          find.text(_exitCopy(tester)),
          findsOneWidget,
          reason: 'exactly one exit snackbar — channels do not both fire',
        );

        await tester.pump(const Duration(seconds: 3));
      },
    );
  });
}
