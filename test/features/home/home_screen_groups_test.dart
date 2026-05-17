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

Group _makeGroup(String id, String name, {int memberCount = 2}) => Group(
  id: id,
  name: name,
  inviteCode: 'ABC123',
  createdBy: 'user1',
  memberIds: List.generate(memberCount, (i) => 'uid$i'),
  currency: 'OMR',
  createdAt: DateTime(2026, 1, 1),
);

List<Override> _overrides(List<Group> groups) => [
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

  group('HomeScreen groups', () {
    testWidgets('shows greeting strip when groups are loaded', (tester) async {
      await tester.pumpWidget(
        _buildTestApp(
          prefs: prefs,
          overrides: _overrides([_makeGroup('g1', 'Desert Crew')]),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(HomeKeys.yourGroupsHeader), findsOneWidget);
    });

    testWidgets('shows one row for each group from userGroupsProvider', (
      tester,
    ) async {
      await tester.pumpWidget(
        _buildTestApp(
          prefs: prefs,
          overrides: _overrides([
            _makeGroup('g1', 'Desert Crew'),
            _makeGroup('g2', 'Mountain Pals'),
          ]),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Desert Crew'), findsOneWidget);
      await tester.drag(find.byType(CustomScrollView), const Offset(0, -500));
      await tester.pumpAndSettle();
      expect(find.text('Mountain Pals'), findsOneWidget);
    });

    testWidgets('shows empty state when user has no groups', (tester) async {
      await tester.pumpWidget(
        _buildTestApp(prefs: prefs, overrides: _overrides([])),
      );
      await tester.pumpAndSettle();

      expect(find.text('Start your first group'), findsOneWidget);
      expect(find.text('Create Group'), findsOneWidget);
    });

    testWidgets('group row navigates through GoRouter', (tester) async {
      await tester.pumpWidget(
        _buildTestApp(
          prefs: prefs,
          overrides: _overrides([_makeGroup('gXYZ', 'Friends')]),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Friends'));
      await tester.pumpAndSettle();

      expect(find.text('GroupDetail:gXYZ'), findsOneWidget);
    });

    testWidgets('bottom nav has 3 tabs: Groups, Activity, Profile', (
      tester,
    ) async {
      await tester.pumpWidget(
        _buildTestApp(
          prefs: prefs,
          overrides: _overrides([_makeGroup('g1', 'Desert Crew')]),
        ),
      );
      await tester.pumpAndSettle();

      final navBar = tester.widget<NavigationBar>(find.byType(NavigationBar));
      expect(navBar.destinations, hasLength(3));
      expect(find.text('Groups'), findsWidgets);
      expect(find.text('Activity'), findsWidgets);
      expect(find.text('Profile'), findsWidgets);
      expect(find.text('Chats'), findsNothing);
    });

    testWidgets('Activity tab updates selected index', (tester) async {
      await tester.pumpWidget(
        _buildTestApp(
          prefs: prefs,
          overrides: _overrides([_makeGroup('g1', 'Desert Crew')]),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(HomeKeys.bottomNavActivity));
      await tester.pump(const Duration(milliseconds: 250));

      final navBar = tester.widget<NavigationBar>(find.byType(NavigationBar));
      expect(navBar.selectedIndex, 1);
    });
  });
}
