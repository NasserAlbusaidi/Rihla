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
/// Drive note (round 4, post go_router 14.8.1 — #1192/#1197): tests 1-5 drive
/// `tester.binding.handlePopRoute()` — the REAL engine entry point (binding →
/// Router → `RootBackButtonDispatcher` → child-dispatcher priority →
/// [BackButtonListener]). Verified against
/// `package:flutter/src/widgets/router.dart`: a mounted [BackButtonListener]
/// registers a *priority* `ChildBackButtonDispatcher` on the root dispatcher
/// (`takePriority()`), so `RootBackButtonDispatcher.invokeCallback` always
/// tries that child FIRST and falls through to go_router's own
/// `GoRouterDelegate.popRoute()` only when the child's callback returns
/// `false`. This shell's [BackButtonListener] returns `true` whenever `/home`
/// is the current route, so `handlePopRoute()` reaches it and never falls
/// through to go_router's `popRoute()`/[PopScope] path in that case — a
/// Flutter dispatch-priority fact, not a go_router-version one: it held on
/// go_router 13.2.5 and still holds on 14.8.1. Tests 1-5 pin exactly this
/// channel; hand-mirroring `maybePop`'s disposition switch (what round 1
/// shipped) would go green even if [BackButtonListener] regressed, since it
/// never drives the real dispatcher chain — that masking is what this file
/// removes.
///
/// STALE CLAIM CORRECTED (true on go_router 13.2.5, false since the #1192
/// upgrade to 14.8.1): "`popRoute()` guards `maybePop()` behind `canPop()`, so
/// a `PopScope`-only guard is never consulted on a sole route" — that hole was
/// the reason this shell also carries [BackButtonListener] as a second
/// channel (see `group_detail_back_navigation_test.dart` for the still-live
/// version of that bug on a `PopScope`-only screen). `GoRouterDelegate.popRoute()`
/// now calls `state.maybePop()` unconditionally, so the `PopScope` channel is
/// independently correct too — but on THIS shell that channel can only be
/// observed by bypassing [BackButtonListener], which never happens while
/// `/home` is current. Proven empirically: flipping the shell's
/// `PopScope(canPop: false)` to `true` locally leaves tests 1-5 GREEN
/// ([BackButtonListener] is untouched by that flip) and only test 6 goes RED —
/// so test 6, not the `handlePopRoute()` tests, is what pins the
/// go_router-14.8.1-dependent contract for this shell. Assertions read the
/// recorded `SystemNavigator.pop` calls + the exit snackbar, never a singular
/// `PopScope` finder (the real tree holds two).
///
/// Test 6 drives `NavigatorState.maybePop()` directly on BOTH presses
/// (mirroring tests 1+2) to pin the `PopScope`/predictive-back layer
/// end-to-end and channel exclusivity — exactly one guard effect per press,
/// never both channels on one press.
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
      'test 6 — maybePop channel: full guard round-trip, channel exclusivity',
      (tester) async {
        final (popCalls, _) = await _pumpHome(tester);

        // Drive the maybePop/predictive channel directly (the PopScope layer),
        // never the BackButtonListener — this is the ONLY channel that
        // regresses when the shell's `PopScope(canPop: false)` flips to
        // `true` without touching BackButtonListener (see file header).
        final navigator = tester.state<NavigatorState>(
          find.byType(Navigator).first,
        );

        await navigator.maybePop();
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

        // Second press within the window: exactly one exit, same as the
        // popRoute channel's round-trip in test 2 — proves the PopScope
        // channel completes the guard, not just arms it.
        await navigator.maybePop();
        await tester.pump();

        expect(
          popCalls,
          hasLength(1),
          reason: 'second maybePop within the window exits exactly once',
        );

        await tester.pump(const Duration(seconds: 3));
      },
    );
  });
}
