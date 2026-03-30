import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:safar/features/groups/models/group_activity_log_model.dart';
import 'package:safar/features/groups/models/group_model.dart';
import 'package:safar/features/groups/providers/group_balance_provider.dart';
import 'package:safar/features/groups/providers/group_provider.dart';
import 'package:safar/features/groups/widgets/group_card.dart';
import 'package:safar/features/ledger/models/expense_model.dart';
import 'package:safar/features/home/providers/dashboard_providers.dart';
import 'package:safar/features/home/screens/home_screen.dart';
import 'package:safar/features/home/widgets/balance_hero_card.dart';
import 'package:safar/features/home/widgets/quick_action_tray.dart';
import 'package:safar/features/home/widgets/weekly_spending_card.dart';
import 'package:safar/features/home/widgets/activity_row.dart';

// ---------------------------------------------------------------------------
// Test helpers
// ---------------------------------------------------------------------------

Group _makeGroup(String id, String name, {int memberCount = 2}) => Group(
      id: id,
      name: name,
      inviteCode: 'ABC123',
      createdBy: 'user1',
      memberIds: List.generate(memberCount, (i) => 'uid$i'),
      currency: 'OMR',
      createdAt: DateTime(2026, 1, 1),
    );

GroupActivityLog _makeActivity(String id, String actorName, String description) =>
    GroupActivityLog(
      id: id,
      type: 'event_created',
      actorId: 'uid0',
      actorName: actorName,
      description: description,
      timestamp: DateTime(2026, 3, 28),
    );

Widget _buildTestApp(
  Widget widget, {
  List<Override> overrides = const [],
}) {
  final router = GoRouter(
    initialLocation: '/home',
    routes: [
      GoRoute(
        path: '/home',
        builder: (ctx, state) => widget,
      ),
      GoRoute(
        path: '/create-group',
        builder: (ctx, state) =>
            const Scaffold(body: Text('CreateGroupScreen')),
      ),
      GoRoute(
        path: '/join-group',
        builder: (ctx, state) =>
            const Scaffold(body: Text('JoinGroupScreen')),
      ),
      GoRoute(
        path: '/group/:id',
        builder: (ctx, state) =>
            Scaffold(body: Text('GroupDetail:${state.pathParameters['id']}')),
      ),
    ],
  );

  return ProviderScope(
    overrides: overrides,
    child: MaterialApp.router(routerConfig: router),
  );
}

// ---------------------------------------------------------------------------
// Shared test data
// ---------------------------------------------------------------------------

final _group1 = _makeGroup('g1', 'Desert Crew');
final _group2 = _makeGroup('g2', 'Mountain Pals');

final _testGroups = [_group1, _group2];

final _testActivity1 = _makeActivity('a1', 'Alice', 'added an expense');
final _testActivity2 = _makeActivity('a2', 'Bob', 'joined the group');

CrossGroupActivityEntry _toEntry(GroupActivityLog log, String groupName, String groupId) =>
    (log: log, groupName: groupName, groupId: groupId);

/// Minimal GroupBalances with a known user balance so tests can verify
/// personal balance display.
GroupBalances _testGroupBalances({Decimal? net}) => (
      balances: [
        UserBalance(
          participantId: 'test-user-id',
          displayName: 'Test User',
          totalPaid: Decimal.parse('10.000'),
          totalOwed: Decimal.parse('20.000'),
          netBalance: net ?? Decimal.parse('-5.500'),
        ),
      ],
      totalSpent: Decimal.parse('25.000'),
      eventCount: 1,
      perEventBreakdown: {},
      memberNames: {'test-user-id': 'Test User'},
    );

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  group('HomeScreen dashboard - loaded state', () {
    List<Override> _loadedOverrides() => [
          userGroupsProvider.overrideWith(
            (ref) => Stream.value(_testGroups),
          ),
          crossGroupBalanceProvider.overrideWith(
            (ref) => AsyncValue.data((
              net: Decimal.parse('-5.500'),
              groupCount: 2,
              isLoading: false,
            )),
          ),
          crossGroupActivityProvider.overrideWith(
            (ref) => AsyncValue.data([
              _toEntry(_testActivity1, 'Desert Crew', 'g1'),
              _toEntry(_testActivity2, 'Mountain Pals', 'g2'),
            ]),
          ),
          weeklyGroupSpendingProvider.overrideWith(
            (ref) => AsyncValue.data(
              List.generate(7, (i) {
                final date = DateTime(2026, 3, 24).add(Duration(days: i));
                return (date: date, amount: Decimal.zero);
              }),
            ),
          ),
          groupBalancesProvider.overrideWith(
            (ref, groupId) => AsyncValue.data(_testGroupBalances()),
          ),
          currentUserIdProvider.overrideWithValue('test-user-id'),
        ];

    testWidgets('Test 1: renders BalanceHeroCard widget', (tester) async {
      await tester.pumpWidget(
        _buildTestApp(const HomeScreen(), overrides: _loadedOverrides()),
      );
      await tester.pumpAndSettle();

      expect(find.byType(BalanceHeroCard), findsOneWidget);
    });

    testWidgets('Test 2: renders QuickActionTray widget', (tester) async {
      await tester.pumpWidget(
        _buildTestApp(const HomeScreen(), overrides: _loadedOverrides()),
      );
      await tester.pumpAndSettle();

      expect(find.byType(QuickActionTray), findsOneWidget);
    });

    testWidgets('Test 3: renders WeeklySpendingCard widget', (tester) async {
      await tester.pumpWidget(
        _buildTestApp(const HomeScreen(), overrides: _loadedOverrides()),
      );
      await tester.pumpAndSettle();

      expect(find.byType(WeeklySpendingCard), findsOneWidget);
    });

    testWidgets('Test 4: renders ActivityRow widgets for activity entries',
        (tester) async {
      await tester.pumpWidget(
        _buildTestApp(const HomeScreen(), overrides: _loadedOverrides()),
      );
      await tester.pumpAndSettle();

      expect(find.byType(ActivityRow), findsWidgets);
    });
  });

  group('HomeScreen dashboard - empty state', () {
    List<Override> _emptyOverrides() => [
          userGroupsProvider.overrideWith(
            (ref) => Stream.value([]),
          ),
          crossGroupBalanceProvider.overrideWith(
            (ref) => AsyncValue.data((
              net: Decimal.zero,
              groupCount: 0,
              isLoading: false,
            )),
          ),
          crossGroupActivityProvider.overrideWith(
            (ref) => const AsyncValue.data([]),
          ),
          weeklyGroupSpendingProvider.overrideWith(
            (ref) => AsyncValue.data(
              List.generate(7, (i) {
                final date = DateTime(2026, 3, 24).add(Duration(days: i));
                return (date: date, amount: Decimal.zero);
              }),
            ),
          ),
          groupBalancesProvider.overrideWith(
            (ref, groupId) => const AsyncValue.loading(),
          ),
          currentUserIdProvider.overrideWithValue('test-user-id'),
        ];

    testWidgets('Test 5: shows EmptyStateView with "Create your first group" text',
        (tester) async {
      await tester.pumpWidget(
        _buildTestApp(const HomeScreen(), overrides: _emptyOverrides()),
      );
      await tester.pumpAndSettle();

      expect(find.text('Create your first group'), findsOneWidget);
    });

    testWidgets('Test 6: empty state EmptyStateView has CTA button "Create Group"',
        (tester) async {
      await tester.pumpWidget(
        _buildTestApp(const HomeScreen(), overrides: _emptyOverrides()),
      );
      await tester.pumpAndSettle();

      expect(find.text('Create Group'), findsOneWidget);
    });
  });

  group('HomeScreen dashboard - error state', () {
    List<Override> _errorOverrides() => [
          userGroupsProvider.overrideWith(
            (ref) => Stream.error(Exception('Network error')),
          ),
          crossGroupBalanceProvider.overrideWith(
            (ref) => AsyncValue.data((
              net: Decimal.zero,
              groupCount: 0,
              isLoading: false,
            )),
          ),
          crossGroupActivityProvider.overrideWith(
            (ref) => const AsyncValue.data([]),
          ),
          weeklyGroupSpendingProvider.overrideWith(
            (ref) => AsyncValue.data(
              List.generate(7, (i) {
                final date = DateTime(2026, 3, 24).add(Duration(days: i));
                return (date: date, amount: Decimal.zero);
              }),
            ),
          ),
          groupBalancesProvider.overrideWith(
            (ref, groupId) => const AsyncValue.loading(),
          ),
          currentUserIdProvider.overrideWithValue('test-user-id'),
        ];

    testWidgets('Test 7: error state renders "Something went wrong" heading',
        (tester) async {
      await tester.pumpWidget(
        _buildTestApp(const HomeScreen(), overrides: _errorOverrides()),
      );
      await tester.pumpAndSettle();

      expect(find.text('Something went wrong'), findsOneWidget);
    });

    testWidgets('Test 8: error state has "Retry" CTA button', (tester) async {
      await tester.pumpWidget(
        _buildTestApp(const HomeScreen(), overrides: _errorOverrides()),
      );
      await tester.pumpAndSettle();

      expect(find.text('Retry'), findsOneWidget);
    });
  });

  group('HomeScreen dashboard - bottom navigation', () {
    List<Override> _navOverrides() => [
          userGroupsProvider.overrideWith(
            (ref) => Stream.value([_group1]),
          ),
          crossGroupBalanceProvider.overrideWith(
            (ref) => AsyncValue.data((
              net: Decimal.zero,
              groupCount: 1,
              isLoading: false,
            )),
          ),
          crossGroupActivityProvider.overrideWith(
            (ref) => const AsyncValue.data([]),
          ),
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
            )),
          ),
          currentUserIdProvider.overrideWithValue('test-user-id'),
        ];

    testWidgets('Test 9: bottom nav shows 4 tabs (Groups, Activity, Chats, Profile)',
        (tester) async {
      await tester.pumpWidget(
        _buildTestApp(const HomeScreen(), overrides: _navOverrides()),
      );
      await tester.pumpAndSettle();

      expect(find.text('Groups'), findsOneWidget);
      expect(find.text('Activity'), findsOneWidget);
      expect(find.text('Chats'), findsOneWidget);
      expect(find.text('Profile'), findsOneWidget);
    });

    testWidgets('Test 10: tapping non-Groups tab shows "Coming soon" placeholder',
        (tester) async {
      await tester.pumpWidget(
        _buildTestApp(const HomeScreen(), overrides: _navOverrides()),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Activity'));
      await tester.pumpAndSettle();

      expect(find.text('Coming soon'), findsOneWidget);
    });
  });

  group('HomeScreen dashboard - GroupCard balance display (NAV-04)', () {
    testWidgets(
        'Test 11: GroupCard shows personal balance text ("You owe"), not totalSpent',
        (tester) async {
      final groups = [_makeGroup('g1', 'Desert Crew')];

      await tester.pumpWidget(
        _buildTestApp(
          const HomeScreen(),
          overrides: [
            userGroupsProvider.overrideWith(
              (ref) => Stream.value(groups),
            ),
            crossGroupBalanceProvider.overrideWith(
              (ref) => AsyncValue.data((
                net: Decimal.parse('-5.500'),
                groupCount: 1,
                isLoading: false,
              )),
            ),
            crossGroupActivityProvider.overrideWith(
              (ref) => const AsyncValue.data([]),
            ),
            weeklyGroupSpendingProvider.overrideWith(
              (ref) => AsyncValue.data(
                List.generate(7, (i) {
                  final date = DateTime(2026, 3, 24).add(Duration(days: i));
                  return (date: date, amount: Decimal.zero);
                }),
              ),
            ),
            groupBalancesProvider.overrideWith(
              (ref, groupId) => AsyncValue.data(_testGroupBalances(
                net: Decimal.parse('-10.000'),
              )),
            ),
            currentUserIdProvider.overrideWithValue('test-user-id'),
          ],
        ),
      );
      await tester.pumpAndSettle();

      // Should show "You owe" (personal balance) not the totalSpent amount
      expect(find.textContaining('You owe'), findsOneWidget);
    });

    testWidgets('Test 12: tapping GroupCard navigates to /group/:id (NAV-04 first-tap)',
        (tester) async {
      final groups = [_makeGroup('gABC', 'Friends')];

      await tester.pumpWidget(
        _buildTestApp(
          const HomeScreen(),
          overrides: [
            userGroupsProvider.overrideWith(
              (ref) => Stream.value(groups),
            ),
            crossGroupBalanceProvider.overrideWith(
              (ref) => AsyncValue.data((
                net: Decimal.zero,
                groupCount: 1,
                isLoading: false,
              )),
            ),
            crossGroupActivityProvider.overrideWith(
              (ref) => const AsyncValue.data([]),
            ),
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
              )),
            ),
            currentUserIdProvider.overrideWithValue('test-user-id'),
          ],
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byType(GroupCard).first);
      await tester.pumpAndSettle();

      expect(find.text('GroupDetail:gABC'), findsOneWidget);
    });
  });
}
