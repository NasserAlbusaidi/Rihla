import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:safar/core/providers/settings_provider.dart';
import 'package:safar/core/theme/app_theme.dart';
import 'package:safar/features/auth/providers/auth_provider.dart';
import 'package:safar/features/events/providers/event_provider.dart';
import 'package:safar/features/groups/models/group_model.dart';
import 'package:safar/features/groups/providers/group_balance_provider.dart';
import 'package:safar/features/groups/providers/group_provider.dart';
import 'package:safar/features/home/keys/home_keys.dart';
import 'package:safar/features/home/providers/dashboard_providers.dart';
import 'package:safar/features/home/screens/home_screen.dart';
import 'package:safar/features/ledger/models/expense_model.dart';
import 'package:safar/l10n/generated/app_localizations.dart';

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
  crossGroupHomeBalanceProvider.overrideWith(
    (ref) => AsyncValue.data((
      balance: (
        byCurrency: const <CurrencyBalance>[],
        groupCount: groups.length,
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
      // #285: model an email-secured user so the one-time account-backup nudge
      // is absent; its appearance is covered by account_backup_nudge_test.dart.
      linkedEmailProvider.overrideWithValue('secured@example.com'),
      // #428: the backup nudge now gates on durability, not linked email.
      isDurableUserProvider.overrideWithValue(true),
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

  group('HomeScreen action wiring', () {
    testWidgets('empty-state Create Group CTA routes to create-group', (
      tester,
    ) async {
      await tester.pumpWidget(
        _buildTestApp(overrides: _baseOverrides([]), prefs: prefs),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Create group'));
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

      await tester.tap(find.text('Join group'));
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

      // #1078: the FAB action lane shortened the dashboard viewport — the
      // groups header (which carries the New-group action) sits below the
      // fold on the test surface now.
      await tester.scrollUntilVisible(
        find.byKey(HomeKeys.createGroupFab),
        120,
        scrollable: find.byType(Scrollable).first,
      );
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

      // #1078: see above — the New-group action needs a scroll first.
      await tester.scrollUntilVisible(
        find.byKey(HomeKeys.createGroupFab),
        120,
        scrollable: find.byType(Scrollable).first,
      );
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

      // #1078: see above — the New-group action needs a scroll first.
      await tester.scrollUntilVisible(
        find.byKey(HomeKeys.createGroupFab),
        120,
        scrollable: find.byType(Scrollable).first,
      );
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

      // #807/#1077/#1078: the tap-cue line, 44dp header action, and FAB lane
      // push the row below the fold — scroll it into existence first.
      await tester.scrollUntilVisible(
        find.text('Desert Crew'),
        120,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.ensureVisible(find.text('Desert Crew'));
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
      // #113 lazy-build: tapping Activity mounts CrossGroupActivityScreen for
      // the first time, starting its EmptyStateView entrance ticker. Drain it
      // before teardown or the pending Timer trips '!timersPending'.
      await tester.pumpAndSettle();

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
