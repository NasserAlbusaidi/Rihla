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

/// #1188 — double-back-to-exit guard on the root [BottomNavShell] + `nav.back`
/// breadcrumbs.
///
/// Drive note: a system back is dispatched by mirroring the framework's own
/// [NavigatorState.maybePop] `popDisposition` switch — `doNotPop` routes the
/// back to the current route's `onPopInvokedWithResult` (which fans out to a
/// registered [PopScope]); `bubble` finishes the activity via
/// `SystemNavigator.pop` (the real exit). This is device-faithful: modern
/// Android predictive-back consults `popDisposition` exactly this way. We do
/// NOT use `tester.binding.handlePopRoute()` — go_router's legacy `popRoute()`
/// returns `handled: false` for a *first/root* route even when its
/// `popDisposition` is `doNotPop` (proven), so that path can't exercise a
/// root-shell guard. Assertions are on the recorded `SystemNavigator.pop`
/// calls + the exit snackbar, never a singular `PopScope` finder.
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

/// The `popDisposition` the framework reads for the current top route
/// (anchored on a widget that lives in that route's subtree). `doNotPop` means
/// a guard will intercept the system back on device.
RoutePopDisposition _disposition(WidgetTester tester, Finder inCurrentRoute) =>
    ModalRoute.of(inCurrentRoute.evaluate().first)!.popDisposition;

/// Dispatch a system back exactly as [NavigatorState.maybePop] does: the
/// current route's `popDisposition` decides whether a guard intercepts
/// (`doNotPop`), the navigator pops (`pop`), or the OS finishes the activity
/// (`bubble` → `SystemNavigator.pop`). [inCurrentRoute] anchors the top route;
/// defaults to the home shell.
Future<void> _systemBack(
  WidgetTester tester, {
  Finder? inCurrentRoute,
}) async {
  final anchor = (inCurrentRoute ?? find.byType(BottomNavTabScope))
      .evaluate()
      .first;
  final route = ModalRoute.of(anchor)!;
  switch (route.popDisposition) {
    case RoutePopDisposition.doNotPop:
      route.onPopInvokedWithResult(false, null);
    case RoutePopDisposition.pop:
      route.navigator!.pop();
    case RoutePopDisposition.bubble:
      await SystemNavigator.pop();
  }
  await tester.pumpAndSettle();
}

void main() {
  group('#1188 double-back-to-exit guard', () {
    testWidgets('first back on shell shows the exit hint and does not exit', (
      tester,
    ) async {
      final (popCalls, _) = await _pumpHome(tester);

      await _systemBack(tester);

      expect(popCalls, isEmpty, reason: 'first back must NOT exit the app');
      expect(find.text(_exitCopy(tester)), findsOneWidget);
      // Device-faithful pin: the framework routes the system back into the
      // guard (route reports doNotPop) rather than finishing the activity.
      expect(
        _disposition(tester, find.byType(BottomNavTabScope)),
        RoutePopDisposition.doNotPop,
      );

      // Drain the 2s snackbar + reset timers before teardown.
      await tester.pump(const Duration(seconds: 3));
    });

    testWidgets('second back within the window exits the app', (tester) async {
      final (popCalls, _) = await _pumpHome(tester);

      await _systemBack(tester);
      expect(popCalls, isEmpty);
      await _systemBack(tester);

      expect(
        popCalls,
        hasLength(1),
        reason: 'second back within 2s exits exactly once',
      );

      await tester.pump(const Duration(seconds: 3));
    });

    testWidgets('window expiry resets the guard', (tester) async {
      final (popCalls, _) = await _pumpHome(tester);

      await _systemBack(tester);
      expect(popCalls, isEmpty);
      expect(find.text(_exitCopy(tester)), findsOneWidget);

      // Let the 2s window (and its snackbar) expire.
      await tester.pump(const Duration(seconds: 3));

      await _systemBack(tester);
      expect(
        popCalls,
        isEmpty,
        reason: 'after the window resets, back is a first-press again',
      );
      expect(find.text(_exitCopy(tester)), findsOneWidget);

      await tester.pump(const Duration(seconds: 3));
    });

    testWidgets('pushed route keeps its own back (no shell interference)', (
      tester,
    ) async {
      final (popCalls, router) = await _pumpHome(tester);

      unawaited(router.push('/group/$_groupId'));
      await tester.pumpAndSettle();
      expect(find.byKey(GroupKeys.detailScreen), findsOneWidget);

      // System back on the pushed group-detail follows ITS OWN PopScope
      // (pop back to home), never the shell's exit guard.
      await _systemBack(tester, inCurrentRoute: find.byKey(GroupKeys.detailScreen));

      expect(popCalls, isEmpty, reason: 'pushed-route back must not exit');
      expect(find.byKey(GroupKeys.detailScreen), findsNothing);
      expect(find.byType(HomeScreen), findsOneWidget);
      expect(find.text(_exitCopy(tester)), findsNothing);
    });

    testWidgets('RTL smoke — Arabic exit hint renders', (tester) async {
      final (popCalls, _) = await _pumpHome(tester, locale: const Locale('ar'));

      await _systemBack(tester);

      expect(popCalls, isEmpty);
      final arCopy = _exitCopy(tester);
      expect(arCopy, 'اضغط رجوعًا مرة أخرى للخروج');
      expect(find.text(arCopy), findsOneWidget);

      await tester.pump(const Duration(seconds: 3));
    });
  });
}
