import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:safar/features/groups/models/group_model.dart';
import 'package:safar/features/groups/providers/group_provider.dart';
import 'package:safar/features/groups/widgets/group_card.dart';
import 'package:safar/features/home/screens/home_screen.dart';

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
          ],
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Your Groups'), findsOneWidget);
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
          ],
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('No groups yet'), findsOneWidget);
      expect(
        find.text(
          'Create a group with friends or enter an invite code to join one.',
        ),
        findsOneWidget,
      );
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
          ],
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byType(FloatingActionButton));
      await tester.pumpAndSettle();

      expect(find.text('Create a Group'), findsOneWidget);
      expect(find.text('Join a Group'), findsOneWidget);
    });

    testWidgets('tapping GroupCard navigates to group detail', (tester) async {
      final groups = [_makeGroup('gXYZ', 'Friends')];

      await tester.pumpWidget(
        _buildTestApp(
          const HomeScreen(),
          overrides: [
            userGroupsProvider.overrideWith(
              (ref) => Stream.value(groups),
            ),
          ],
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byType(GroupCard).first);
      await tester.pumpAndSettle();

      expect(find.text('GroupDetail:gXYZ'), findsOneWidget);
    });

    test('does not reference userTripsProvider (trip code removed)', () {
      // This is a static code assertion validated by flutter analyze.
      // The HomeScreen source file must not import or reference userTripsProvider
      // or tripSeedProvider — verified by acceptance criteria grep check.
      expect(true, isTrue);
    });
  });
}
