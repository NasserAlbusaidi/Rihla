import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:safar/core/providers/settings_provider.dart';
import 'package:safar/core/theme/app_theme.dart';
import 'package:safar/features/events/providers/event_provider.dart';
import 'package:safar/features/groups/models/group_model.dart';
import 'package:safar/features/groups/providers/group_balance_provider.dart';
import 'package:safar/features/groups/providers/group_provider.dart';
import 'package:safar/features/home/keys/home_keys.dart';
import 'package:safar/features/home/providers/dashboard_providers.dart';
import 'package:safar/features/home/screens/home_screen.dart';
import 'package:safar/features/ledger/models/expense_model.dart';

Group _makeGroup(String id, String name) => Group(
  id: id,
  name: name,
  inviteCode: 'ABC123',
  createdBy: 'user1',
  memberIds: const ['uid0', 'uid1'],
  currency: 'OMR',
  createdAt: DateTime(2026, 1, 1),
);

List<Override> _baseOverrides(List<Group> groups) => [
  userGroupsProvider.overrideWith((ref) => Stream.value(groups)),
  crossGroupBalanceProvider.overrideWith(
    (ref) => AsyncValue.data((
      net: Decimal.zero,
      groupCount: groups.length,
      isLoading: false,
    )),
  ),
  crossGroupActivityProvider.overrideWith((ref) => const AsyncValue.data([])),
  weeklyGroupSpendingProvider.overrideWith(
    (ref) => AsyncValue.data(
      List.generate(7, (i) {
        final date = DateTime(2026, 3, 24).add(Duration(days: i));
        return (date: date, amount: Decimal.zero);
      }),
    ),
  ),
  groupBalancesProvider.overrideWith(
    (ref, groupId) => AsyncValue.data((
      balances: <UserBalance>[],
      totalSpent: Decimal.zero,
      eventCount: 0,
      perEventBreakdown: <String, Map<String, Decimal>>{},
      memberNames: <String, String>{},
      memberRawNames: <String, String>{},
    )),
  ),
  groupEventsProvider.overrideWith((ref, groupId) => Stream.value([])),
  currentUserIdProvider.overrideWithValue('test-user-id'),
];

Widget _buildTestApp({
  required List<Override> overrides,
  required SharedPreferences prefs,
}) {
  final router = GoRouter(
    initialLocation: '/home',
    routes: [
      GoRoute(path: '/home', builder: (ctx, state) => const HomeScreen()),
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
      GoRoute(
        path: '/activity',
        builder: (ctx, state) => const Scaffold(body: Text('ActivityScreen')),
      ),
      GoRoute(
        path: '/profile',
        builder: (ctx, state) => const Scaffold(body: Text('ProfileScreen')),
      ),
    ],
  );

  return ProviderScope(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      ...overrides,
    ],
    child: MaterialApp.router(theme: AppTheme.lightTheme, routerConfig: router),
  );
}

void main() {
  late SharedPreferences prefs;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
  });

  group('HomeScreen action wiring', () {
    testWidgets('empty-state Create Group CTA routes to create-group', (
      tester,
    ) async {
      await tester.pumpWidget(
        _buildTestApp(overrides: _baseOverrides([]), prefs: prefs),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Create Group'));
      await tester.pumpAndSettle();

      expect(find.text('CreateGroupScreen'), findsOneWidget);
    });

    testWidgets('empty-state Join Group CTA routes to join-group', (
      tester,
    ) async {
      await tester.pumpWidget(
        _buildTestApp(overrides: _baseOverrides([]), prefs: prefs),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Join Group'));
      await tester.pumpAndSettle();

      expect(find.text('JoinGroupScreen'), findsOneWidget);
    });

    testWidgets('New group action opens create/join sheet', (tester) async {
      await tester.pumpWidget(
        _buildTestApp(
          overrides: _baseOverrides([_makeGroup('g1', 'Desert Crew')]),
          prefs: prefs,
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(HomeKeys.createGroupFab));
      await tester.pumpAndSettle();

      expect(find.byKey(HomeKeys.createGroupOption), findsOneWidget);
      expect(find.byKey(HomeKeys.joinGroupOption), findsOneWidget);
    });

    testWidgets('Create sheet option routes to create-group', (tester) async {
      await tester.pumpWidget(
        _buildTestApp(
          overrides: _baseOverrides([_makeGroup('g1', 'Desert Crew')]),
          prefs: prefs,
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(HomeKeys.createGroupFab));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(HomeKeys.createGroupOption));
      await tester.pumpAndSettle();

      expect(find.text('CreateGroupScreen'), findsOneWidget);
    });

    testWidgets('Join sheet option routes to join-group', (tester) async {
      await tester.pumpWidget(
        _buildTestApp(
          overrides: _baseOverrides([_makeGroup('g1', 'Desert Crew')]),
          prefs: prefs,
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(HomeKeys.createGroupFab));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(HomeKeys.joinGroupOption));
      await tester.pumpAndSettle();

      expect(find.text('JoinGroupScreen'), findsOneWidget);
    });

    testWidgets('group row routes to group detail', (tester) async {
      await tester.pumpWidget(
        _buildTestApp(
          overrides: _baseOverrides([_makeGroup('g1', 'Desert Crew')]),
          prefs: prefs,
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Desert Crew'));
      await tester.pumpAndSettle();

      expect(find.text('GroupDetail:g1'), findsOneWidget);
    });

    testWidgets('Activity bottom tab selects the activity tab', (tester) async {
      await tester.pumpWidget(
        _buildTestApp(
          overrides: _baseOverrides([_makeGroup('g1', 'Desert Crew')]),
          prefs: prefs,
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(HomeKeys.bottomNavActivity));
      await tester.pump(const Duration(milliseconds: 250));

      final navBar = tester.widget<NavigationBar>(find.byType(NavigationBar));
      expect(navBar.selectedIndex, 1);
    });

    testWidgets('profile avatar routes to profile', (tester) async {
      await tester.pumpWidget(
        _buildTestApp(
          overrides: _baseOverrides([_makeGroup('g1', 'Desert Crew')]),
          prefs: prefs,
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(HomeKeys.profileAvatar));
      await tester.pumpAndSettle();

      expect(find.text('ProfileScreen'), findsOneWidget);
    });
  });
}
