import 'dart:async';

import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:iconsax/iconsax.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:safar/core/providers/settings_provider.dart';
import 'package:safar/core/theme/app_theme.dart';
import 'package:safar/features/auth/providers/auth_provider.dart';
import 'package:safar/features/events/models/event_model.dart';
import 'package:safar/features/events/providers/event_provider.dart';
import 'package:safar/features/groups/models/group_activity_log_model.dart';
import 'package:safar/features/groups/models/group_model.dart';
import 'package:safar/features/groups/providers/group_balance_provider.dart';
import 'package:safar/features/groups/providers/group_provider.dart';
import 'package:safar/features/home/keys/home_keys.dart';
import 'package:safar/features/home/providers/dashboard_providers.dart';
import 'package:safar/features/home/screens/cross_group_activity_screen.dart';
import 'package:safar/features/home/screens/home_screen.dart';
import 'package:safar/features/ledger/models/expense_model.dart';
import 'package:safar/l10n/generated/app_localizations.dart';

/// #818 Wave 5.2: the bell and the journeys "View history" action select the
/// History tab in place (`BottomNavTabScope.selectTab(1)`) instead of pushing
/// the `/activity` route. Coverage: (a) the bell lands on the tab with no
/// back affordance and never pushes `/activity`; (b) a bell tap clears the
/// unread dot exactly like a direct nav-bar tap; (c) the journeys action
/// converts identically. `/activity` itself stays registered for deep links
/// (pinned separately by `test/unit/app_router_test.dart`) — its stub route
/// here exists only so a regression that still pushes it is visible.
///
/// #840 PR-4: the bell also carries its own unread badge
/// (`HomeKeys.bellUnreadBadge` — never `activityUnreadBadge`, which the
/// NavigationBar destination already owns) and its glyph is `Iconsax.activity`
/// (matching the History tab's own inactive icon), not `Iconsax.notification`.

Group _makeGroup(String id, String name) => Group(
  id: id,
  name: name,
  inviteCode: 'ABC123',
  createdBy: 'user1',
  memberIds: const ['test-user-id'],
  currency: 'OMR',
  createdAt: DateTime(2026, 1, 1),
);

Event _makeEvent(String id, String name) => Event(
  id: id,
  name: name,
  type: EventType.camping,
  groupId: 'g1',
  createdBy: 'test-user-id',
  participantIds: const ['test-user-id'],
  participantNames: const {'test-user-id': 'Test User'},
  modules: EventModules.forType(EventType.camping),
  createdAt: DateTime.now().subtract(const Duration(days: 2)),
);

GroupActivityLog _activityLog(String id, DateTime at) => GroupActivityLog(
  id: id,
  type: 'expense_added',
  actorId: 'u',
  actorName: 'A',
  description: 'd',
  timestamp: at,
);

CrossGroupActivityEntry _entry(String id, DateTime at) => (
  log: _activityLog(id, at),
  groupName: 'Desert Crew',
  groupId: 'g1',
  currency: 'OMR',
);

GroupBalances _emptyGroupBalances() => (
  balances: const <String, List<UserBalance>>{},
  totalSpent: const <String, Decimal>{},
  eventCount: 0,
  perEventBreakdown: const <String, Map<String, Map<String, Decimal>>>{},
  memberNames: const <String, String>{},
  memberRawNames: const <String, String>{},
);

/// Base overrides: one group with one event (so the journeys "View history"
/// action is offered) and an empty activity feed (no unread dot). Individual
/// tests layer `crossGroupActivityProvider` on top to seed unread state.
List<Override> _baseOverrides() => [
  linkedEmailProvider.overrideWithValue('secured@example.com'),
  isDurableUserProvider.overrideWithValue(true),
  userGroupsProvider.overrideWith((ref) => Stream.value([_makeGroup('g1', 'Desert Crew')])),
  groupEventsProvider.overrideWith(
    (ref, groupId) => Stream.value([_makeEvent('e1', 'Camping Trip')]),
  ),
  groupBalancesProvider.overrideWith(
    (ref, groupId) => AsyncValue.data(_emptyGroupBalances()),
  ),
  groupBalancesOnceProvider.overrideWith(
    (ref, gid) => ref.watch(groupBalancesProvider(gid)).maybeWhen(
      data: (d) => (balances: d, failedEventIds: const <String>{}),
      orElse: () => Completer<GroupBalancesOnce>().future,
    ),
  ),
  crossGroupHomeBalanceProvider.overrideWith(
    (ref) => const AsyncValue.data((
      balance: (byCurrency: <CurrencyBalance>[], groupCount: 1, isLoading: false),
      partial: false,
    )),
  ),
  crossGroupActivityProvider.overrideWith((ref) => const AsyncValue.data([])),
  currentUserIdProvider.overrideWithValue('test-user-id'),
];

Widget _buildTestApp(SharedPreferences prefs, List<Override> overrides) {
  final router = GoRouter(
    initialLocation: '/home',
    routes: [
      GoRoute(path: '/home', builder: (ctx, state) => const HomeScreen()),
      GoRoute(
        path: '/activity',
        builder: (ctx, state) => const Scaffold(body: Text('ActivityScreen')),
      ),
      GoRoute(
        path: '/profile',
        builder: (ctx, state) => const Scaffold(body: Text('ProfileScreen')),
      ),
      GoRoute(
        path: '/create-group',
        builder: (ctx, state) =>
            const Scaffold(body: Text('CreateGroupScreen')),
      ),
      GoRoute(
        path: '/join-group',
        builder: (ctx, state) => const Scaffold(body: Text('JoinGroupScreen')),
      ),
      GoRoute(
        path: '/group/:id',
        builder: (ctx, state) =>
            Scaffold(body: Text('GroupDetail:${state.pathParameters['id']}')),
      ),
    ],
  );

  return ProviderScope(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      ...overrides,
    ],
    child: MaterialApp.router(
      theme: AppTheme.lightTheme,
      routerConfig: router,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
    ),
  );
}

void main() {
  late SharedPreferences prefs;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
  });

  group('Home bell selects the History tab (#818 Wave 5.2)', () {
    testWidgets(
      'bell selects the Activity tab: no route push, no back affordance',
      (tester) async {
        await tester.pumpWidget(_buildTestApp(prefs, _baseOverrides()));
        await tester.pumpAndSettle();

        expect(find.byKey(HomeKeys.activityBell), findsOneWidget);

        await tester.tap(find.byKey(HomeKeys.activityBell));
        // Drains the Activity tab's EmptyStateView entrance ticker.
        await tester.pumpAndSettle();

        final navBar = tester.widget<NavigationBar>(find.byType(NavigationBar));
        expect(navBar.selectedIndex, 1);
        expect(find.byType(CrossGroupActivityScreen), findsOneWidget);
        // The bell must select the tab, never push the /activity route.
        expect(find.text('ActivityScreen'), findsNothing);
        // Tab mode: no back affordance (showBack stays false).
        expect(find.byTooltip('Back'), findsNothing);
      },
    );

    testWidgets('bell tap clears the unread dot', (tester) async {
      await tester.pumpWidget(
        _buildTestApp(prefs, [
          ..._baseOverrides(),
          crossGroupActivityProvider.overrideWith(
            (ref) => AsyncValue.data([_entry('a', DateTime.utc(2026, 3, 1))]),
          ),
        ]),
      );
      await tester.pumpAndSettle();

      final badge = tester.widget<Badge>(
        find.byKey(HomeKeys.activityUnreadBadge),
      );
      expect(badge.isLabelVisible, isTrue);
      final bellBadge = tester.widget<Badge>(
        find.byKey(HomeKeys.bellUnreadBadge),
      );
      expect(bellBadge.isLabelVisible, isTrue);

      await tester.tap(find.byKey(HomeKeys.activityBell));
      await tester.pumpAndSettle();

      // #840 PR-4: the bell lives on the Groups tab, which AnimatedOpacity/
      // IgnorePointer keeps MOUNTED (just invisible) while Activity is
      // selected — so its own badge is readable immediately, no back-to-
      // Groups dance needed (unlike the NavigationBar badge below, which the
      // selectedIcon swap removes from the tree entirely).
      final bellCleared = tester.widget<Badge>(
        find.byKey(HomeKeys.bellUnreadBadge),
      );
      expect(bellCleared.isLabelVisible, isFalse);

      // While Activity is selected, NavigationBar renders selectedIcon (no
      // Badge) — switch back to Groups before reading the badge, mirroring
      // activity_unread_test.dart's back-to-Groups dance.
      await tester.tap(find.byKey(HomeKeys.bottomNavGroups));
      await tester.pumpAndSettle();

      final cleared = tester.widget<Badge>(
        find.byKey(HomeKeys.activityUnreadBadge),
      );
      expect(cleared.isLabelVisible, isFalse);
    });

    testWidgets('bell badge hidden with an empty activity feed', (
      tester,
    ) async {
      await tester.pumpWidget(_buildTestApp(prefs, _baseOverrides()));
      await tester.pumpAndSettle();

      final bellBadge = tester.widget<Badge>(
        find.byKey(HomeKeys.bellUnreadBadge),
      );
      expect(bellBadge.isLabelVisible, isFalse);
    });

    testWidgets('bell renders the activity glyph, not the notification bell', (
      tester,
    ) async {
      await tester.pumpWidget(_buildTestApp(prefs, _baseOverrides()));
      await tester.pumpAndSettle();

      expect(
        find.descendant(
          of: find.byKey(HomeKeys.activityBell),
          matching: find.byIcon(Iconsax.activity),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byKey(HomeKeys.activityBell),
          matching: find.byIcon(Iconsax.notification),
        ),
        findsNothing,
      );
    });

    testWidgets('journeys View-history action selects the tab', (
      tester,
    ) async {
      await tester.pumpWidget(_buildTestApp(prefs, _baseOverrides()));
      await tester.pumpAndSettle();

      expect(find.text('View history'), findsOneWidget);

      await tester.tap(find.text('View history'));
      await tester.pumpAndSettle();

      final navBar = tester.widget<NavigationBar>(find.byType(NavigationBar));
      expect(navBar.selectedIndex, 1);
      expect(find.byType(CrossGroupActivityScreen), findsOneWidget);
      expect(find.text('ActivityScreen'), findsNothing);
    });
  });
}

