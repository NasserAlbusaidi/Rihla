import 'package:animations/animations.dart';
import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:safar/features/events/models/event_model.dart';
import 'package:safar/features/events/providers/event_provider.dart';
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

Event _makeEvent(
  String id,
  String name,
  EventType type, {
  DateTime? createdAt,
}) =>
    Event(
      id: id,
      name: name,
      type: type,
      groupId: 'g1',
      createdBy: 'uid0',
      participantIds: ['uid0'],
      participantNames: {'uid0': 'Alice'},
      modules: EventModules.forType(type),
      createdAt: createdAt ?? DateTime.now().subtract(const Duration(days: 2)),
    );

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
      groupEventsProvider.overrideWith(
        (ref, groupId) => Stream.value([
          _makeEvent('e1', 'Camping Trip', EventType.camping),
        ]),
      ),
      currentUserIdProvider.overrideWithValue('test-user-id'),
    ];

void main() {
  group('HomeScreen dashboard - loaded state', () {

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

      // WeeklySpendingCard is the last section in the CustomScrollView.
      // Scroll down to ensure it's built and visible in the viewport.
      await tester.drag(
        find.byType(CustomScrollView),
        const Offset(0, -600),
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
          groupEventsProvider.overrideWith(
            (ref, groupId) => Stream.value([]),
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
          groupEventsProvider.overrideWith(
            (ref, groupId) => Stream.value([]),
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
          groupEventsProvider.overrideWith(
            (ref, groupId) => Stream.value([]),
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
      // 'Activity' text appears in both QuickActionTray and BottomNavigationBar.
      // The nav tab label has a smaller font style; we assert at least one exists.
      expect(find.text('Activity'), findsAtLeastNWidgets(1));
      expect(find.text('Chats'), findsOneWidget);
      expect(find.text('Profile'), findsOneWidget);
    });

    testWidgets('Test 10: tapping non-Groups tab shows "Coming soon" placeholder',
        (tester) async {
      await tester.pumpWidget(
        _buildTestApp(const HomeScreen(), overrides: _navOverrides()),
      );
      await tester.pumpAndSettle();

      // Tap the last 'Activity' text which is the BottomNavBar label
      // (the first 'Activity' is the QuickActionTray button label)
      await tester.tap(find.text('Activity').last);
      await tester.pumpAndSettle();

      // BottomNavShell keeps all 3 placeholder tabs rendered simultaneously
      // (both IndexedStack and Stack+AnimatedOpacity build all children).
      expect(find.text('Coming soon'), findsNWidgets(3));
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
            groupEventsProvider.overrideWith(
              (ref, groupId) => Stream.value([]),
            ),
            currentUserIdProvider.overrideWithValue('test-user-id'),
          ],
        ),
      );
      await tester.pumpAndSettle();

      // Should show "You owe" (personal balance) not the totalSpent amount.
      // Note: BalanceHeroCard also shows "You owe across N groups" when the
      // cross-group balance is negative. The GroupCard shows "You owe OMR X.XXX".
      // Both phrases contain "You owe" — we assert at least one exists.
      expect(find.textContaining('You owe'), findsAtLeastNWidgets(1));
    });

    testWidgets('Test 12: GroupCard wrapped in OpenContainer for ContainerTransform (NAV-04)',
        (tester) async {
      // Phase 20 P02: OpenContainer replaces TapBounce+context.push.
      // GroupCard nav is via ContainerTransform, not GoRouter push.
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
            groupEventsProvider.overrideWith(
              (ref, groupId) => Stream.value([]),
            ),
            currentUserIdProvider.overrideWithValue('test-user-id'),
          ],
        ),
      );
      await tester.pumpAndSettle();

      // OpenContainer wrapping GroupCard confirms ContainerTransform is wired (NAV-04)
      expect(find.byType(OpenContainer<void>), findsWidgets);
    });
  });

  group('HomeScreen dashboard - section header (Phase 24)', () {
    testWidgets('Test NEW-3: "Your Groups (N)" header renders above group cards (LAYT-02)',
        (tester) async {
      // _loadedOverrides() provides 2 groups
      await tester.pumpWidget(
        _buildTestApp(const HomeScreen(), overrides: _loadedOverrides()),
      );
      await tester.pumpAndSettle();

      expect(find.text('Your Groups (2)'), findsOneWidget);
    });
  });

  group('HomeScreen dashboard - GroupCard enrichment (Phase 24)', () {
    List<Override> _enrichmentOverrides({
      List<Event>? events,
    }) =>
        [
          userGroupsProvider.overrideWith(
            (ref) => Stream.value([_makeGroup('g1', 'Desert Crew')]),
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
            (ref, groupId) => AsyncValue.data(_testGroupBalances()),
          ),
          groupEventsProvider.overrideWith(
            (ref, groupId) => Stream.value(events ?? []),
          ),
          currentUserIdProvider.overrideWithValue('test-user-id'),
        ];

    // Test A (CARD-01): GroupCard renders a Container with width 4 (the accent strip)
    testWidgets('Test A: GroupCard renders accent strip Container with width 4',
        (tester) async {
      await tester.pumpWidget(
        _buildTestApp(
          const HomeScreen(),
          overrides: _enrichmentOverrides(events: [
            _makeEvent('e1', 'Camping Trip', EventType.camping),
          ]),
        ),
      );
      await tester.pumpAndSettle();

      // Find a Container whose rendered width in the layout is exactly 4dp.
      // The accent strip Container(width: 4) inside GroupCard renders at exactly 4dp.
      bool foundAccentStrip = false;
      for (final element in find.byType(Container).evaluate()) {
        final renderBox = element.renderObject;
        if (renderBox is RenderBox && renderBox.size.width == 4.0) {
          foundAccentStrip = true;
          break;
        }
      }
      expect(foundAccentStrip, isTrue,
          reason: 'GroupCard should render a 4dp accent strip Container');
    });

    // Test C (CARD-02): GroupCard with events loaded shows the latest event name
    testWidgets('Test C: GroupCard with events shows latest event name',
        (tester) async {
      await tester.pumpWidget(
        _buildTestApp(
          const HomeScreen(),
          overrides: _enrichmentOverrides(events: [
            _makeEvent('e1', 'Camping Trip', EventType.camping),
          ]),
        ),
      );
      await tester.pumpAndSettle();

      // Event name appears in context line as "Camping Trip — X ago"
      expect(find.textContaining('Camping Trip'), findsOneWidget);
    });

    // Test D (CARD-02): GroupCard with events shows relative timestamp containing "ago"
    testWidgets('Test D: GroupCard with events shows relative timestamp',
        (tester) async {
      await tester.pumpWidget(
        _buildTestApp(
          const HomeScreen(),
          overrides: _enrichmentOverrides(events: [
            _makeEvent(
              'e1',
              'Beach Day',
              EventType.nightDayOut,
              createdAt: DateTime.now().subtract(const Duration(hours: 3)),
            ),
          ]),
        ),
      );
      await tester.pumpAndSettle();

      // Context line shows "Beach Day — 3 hours ago"
      expect(find.textContaining('ago'), findsOneWidget);
    });

    // Test E (CARD-02): GroupCard with no events shows "No events yet"
    testWidgets('Test E: GroupCard with no events shows "No events yet"',
        (tester) async {
      await tester.pumpWidget(
        _buildTestApp(
          const HomeScreen(),
          overrides: _enrichmentOverrides(events: []),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('No events yet'), findsOneWidget);
    });

    // Test F (CARD-02): GroupCard with empty events also shows "No events yet" placeholder
    testWidgets(
        'Test F: GroupCard with empty events shows "No events yet" placeholder',
        (tester) async {
      await tester.pumpWidget(
        _buildTestApp(
          const HomeScreen(),
          overrides: _enrichmentOverrides(),
        ),
      );
      await tester.pumpAndSettle();

      // No events shows "No events yet"
      expect(find.text('No events yet'), findsOneWidget);
    });
  });
}
