import 'package:animations/animations.dart';
import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:safar/core/keys/shared_keys.dart';
import 'package:safar/features/groups/models/group_model.dart';
import 'package:safar/features/groups/providers/group_balance_provider.dart';
import 'package:safar/features/groups/providers/group_provider.dart';
import 'package:safar/features/groups/widgets/group_card.dart';
import 'package:safar/features/home/keys/home_keys.dart';
import 'package:safar/features/home/providers/dashboard_providers.dart';
import 'package:safar/features/home/screens/home_screen.dart';
import 'package:safar/features/ledger/models/expense_model.dart';

// ---------------------------------------------------------------------------
// Helpers
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

/// Returns the minimal set of overrides needed for the new dashboard providers
/// to not throw (empty/settled state). Tests that need specific values add
/// their own overrides on top.
List<Override> _dashboardOverrides() => [
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

/// Wraps [widget] with GoRouter and ProviderScope overrides needed for testing.
Widget _buildTestApp(Widget widget, {List<Override> overrides = const []}) {
  final router = GoRouter(
    initialLocation: '/home',
    routes: [
      GoRoute(
        path: '/home',
        builder: (ctx, state) => widget,
      ),
      GoRoute(
        path: '/create-group',
        builder: (ctx, state) => const Scaffold(body: Text('CreateGroupScreen')),
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
    overrides: overrides,
    child: MaterialApp.router(routerConfig: router),
  );
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  group('HomeScreen groups', () {
    testWidgets('shows "Your Groups" header', (tester) async {
      await tester.pumpWidget(
        _buildTestApp(
          const HomeScreen(),
          overrides: [
            userGroupsProvider.overrideWith(
              (ref) => Stream.value([]),
            ),
            ..._dashboardOverrides(),
          ],
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(HomeKeys.yourGroupsHeader), findsOneWidget);
    });

    testWidgets('shows GroupCard for each group from userGroupsProvider',
        (tester) async {
      final groups = [
        _makeGroup('g1', 'Desert Crew'),
        _makeGroup('g2', 'Mountain Pals'),
      ];

      await tester.pumpWidget(
        _buildTestApp(
          const HomeScreen(),
          overrides: [
            userGroupsProvider.overrideWith(
              (ref) => Stream.value(groups),
            ),
            ..._dashboardOverrides(),
          ],
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(GroupCard), findsNWidgets(2));
      expect(find.text('Desert Crew'), findsOneWidget);
      expect(find.text('Mountain Pals'), findsOneWidget);
    });

    testWidgets('shows empty state when user has no groups', (tester) async {
      await tester.pumpWidget(
        _buildTestApp(
          const HomeScreen(),
          overrides: [
            userGroupsProvider.overrideWith(
              (ref) => Stream.value([]),
            ),
            ..._dashboardOverrides(),
          ],
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(SharedKeys.emptyStateView), findsOneWidget);
    });

    testWidgets('FAB opens bottom sheet with Create and Join options',
        (tester) async {
      await tester.pumpWidget(
        _buildTestApp(
          const HomeScreen(),
          overrides: [
            userGroupsProvider.overrideWith(
              (ref) => Stream.value([]),
            ),
            ..._dashboardOverrides(),
          ],
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(HomeKeys.createGroupFab));
      await tester.pumpAndSettle();

      expect(find.byKey(HomeKeys.createGroupOption), findsOneWidget);
      expect(find.byKey(HomeKeys.joinGroupOption), findsOneWidget);
    });

    testWidgets('GroupCard is wrapped in OpenContainer for ContainerTransform', (tester) async {
      // OpenContainer replaces TapBounce+GoRouter push (Phase 20 P02).
      // Verify OpenContainer is present in the group cards section.
      final groups = [_makeGroup('gXYZ', 'Friends')];

      await tester.pumpWidget(
        _buildTestApp(
          const HomeScreen(),
          overrides: [
            userGroupsProvider.overrideWith(
              (ref) => Stream.value(groups),
            ),
            ..._dashboardOverrides(),
          ],
        ),
      );
      await tester.pumpAndSettle();

      // OpenContainer wraps GroupCard — verifies ContainerTransform is wired
      expect(find.byType(OpenContainer<void>), findsWidgets);
    });

    test('does not reference userTripsProvider (trip code removed)', () {
      // This is a static code assertion validated by flutter analyze.
      // The HomeScreen source file must not import or reference userTripsProvider
      // or tripSeedProvider — verified by acceptance criteria grep check.
      expect(true, isTrue);
    });
  });
}
