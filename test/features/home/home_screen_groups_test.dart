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

      // #1078: the FAB action lane shortened the dashboard viewport — the
      // group rows start below the fold on the test surface now.
      await tester.drag(find.byType(CustomScrollView), const Offset(0, -300));
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
      expect(find.text('Create group'), findsOneWidget);
    });

    testWidgets(
      'group row labels an AED-only balance AED — honest, '
      'not group.currency (#382 PR-3)',
      (tester) async {
        await tester.pumpWidget(
          _buildTestApp(
            prefs: prefs,
            overrides: [
              ..._overrides([_makeGroup('g1', 'Desert Crew')]),
              homeGroupBalanceProvider.overrideWith(
                (ref, groupId) => AsyncValue.data((
                  userNet: {'AED': Decimal.parse('10.50')},
                  userPerEventNet: const <String, Map<String, Decimal>>{},
                  eventCount: 1,
                  partial: false,
                  fromAggregate: true,
                )),
              ),
            ],
          ),
        );
        await tester.pumpAndSettle();

        // #1078: the FAB action lane shortened the dashboard viewport —
        // bring the row on screen first.
        await tester.drag(find.byType(CustomScrollView), const Offset(0, -400));
        await tester.pumpAndSettle();

        final row = find
            .ancestor(
              of: find.text('Desert Crew'),
              matching: find.byType(InkWell),
            )
            .first;
        expect(
          find.descendant(
            of: row,
            matching: find.textContaining('AED', findRichText: true),
          ),
          findsOneWidget,
        );
        expect(
          find.descendant(
            of: row,
            matching: find.textContaining('10.50', findRichText: true),
          ),
          findsOneWidget,
        );
        expect(
          find.descendant(
            of: row,
            matching: find.textContaining('OMR', findRichText: true),
          ),
          findsNothing,
        );
      },
    );

    testWidgets(
      'group row renders every non-zero currency bucket; mixed signs '
      'omit the tri-state caption (#382 PR-5)',
      (tester) async {
        await tester.pumpWidget(
          _buildTestApp(
            prefs: prefs,
            overrides: [
              ..._overrides([_makeGroup('g1', 'Desert Crew')]),
              homeGroupBalanceProvider.overrideWith(
                (ref, groupId) => AsyncValue.data((
                  userNet: {
                    'OMR': Decimal.parse('5'),
                    'USD': Decimal.parse('-3'),
                  },
                  userPerEventNet: const <String, Map<String, Decimal>>{},
                  eventCount: 1,
                  partial: false,
                  fromAggregate: true,
                )),
              ),
            ],
          ),
        );
        await tester.pumpAndSettle();
        // The two-currency hero pushes the lazily-built groups sliver below
        // the fold — bring the row on screen first.
        await tester.drag(find.byType(CustomScrollView), const Offset(0, -600));
        await tester.pumpAndSettle();

        final row = find
            .ancestor(
              of: find.text('Desert Crew'),
              matching: find.byType(InkWell),
            )
            .first;
        expect(
          find.descendant(
            of: row,
            matching: find.textContaining('OMR', findRichText: true),
          ),
          findsOneWidget,
        );
        expect(
          find.descendant(
            of: row,
            matching: find.textContaining('USD', findRichText: true),
          ),
          findsOneWidget,
        );
        expect(
          find.descendant(of: row, matching: find.text('they owe you')),
          findsNothing,
        );
        expect(
          find.descendant(of: row, matching: find.text('you owe')),
          findsNothing,
        );
        expect(
          find.descendant(of: row, matching: find.text('settled')),
          findsNothing,
        );
      },
    );

    testWidgets(
      'group row keeps the tri-state caption when all non-zero buckets '
      'share one sign (#382 PR-5)',
      (tester) async {
        await tester.pumpWidget(
          _buildTestApp(
            prefs: prefs,
            overrides: [
              ..._overrides([_makeGroup('g1', 'Desert Crew')]),
              homeGroupBalanceProvider.overrideWith(
                (ref, groupId) => AsyncValue.data((
                  userNet: {
                    'OMR': Decimal.parse('5'),
                    'USD': Decimal.parse('3'),
                  },
                  userPerEventNet: const <String, Map<String, Decimal>>{},
                  eventCount: 1,
                  partial: false,
                  fromAggregate: true,
                )),
              ),
            ],
          ),
        );
        await tester.pumpAndSettle();
        await tester.drag(find.byType(CustomScrollView), const Offset(0, -600));
        await tester.pumpAndSettle();

        final row = find
            .ancestor(
              of: find.text('Desert Crew'),
              matching: find.byType(InkWell),
            )
            .first;
        expect(
          find.descendant(
            of: row,
            matching: find.textContaining('USD', findRichText: true),
          ),
          findsOneWidget,
        );
        expect(
          find.descendant(of: row, matching: find.text('they owe you')),
          findsOneWidget,
        );
      },
    );

    testWidgets('group row navigates through GoRouter', (tester) async {
      await tester.pumpWidget(
        _buildTestApp(
          prefs: prefs,
          overrides: _overrides([_makeGroup('gXYZ', 'Friends')]),
        ),
      );
      await tester.pumpAndSettle();

      // #807/#1078: the tap-cue line and the FAB action lane push the row
      // below the fold — scroll it into existence, then fully on-screen.
      await tester.scrollUntilVisible(
        find.text('Friends'),
        120,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.ensureVisible(find.text('Friends'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Friends'));
      await tester.pumpAndSettle();

      expect(find.text('GroupDetail:gXYZ'), findsOneWidget);
    });

    testWidgets('groups header gap is wide enough to disambiguate the '
        'new-group CTA from the first row balance (#161)', (tester) async {
      await tester.pumpWidget(
        _buildTestApp(
          prefs: prefs,
          overrides: _overrides([_makeGroup('g1', 'Desert Crew')]),
        ),
      );
      await tester.pumpAndSettle();

      // #1078: the FAB action lane shortened the dashboard viewport — the
      // groups header gap sits below the fold on the test surface now.
      await tester.drag(find.byType(CustomScrollView), const Offset(0, -300));
      await tester.pumpAndSettle();

      final gap = tester.widget<SizedBox>(
        find.byKey(HomeKeys.groupsHeaderGap),
      );
      expect(gap.height, greaterThanOrEqualTo(12));
    });

    testWidgets('bottom nav has 3 tabs: Groups, History, Profile', (
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
      expect(find.text('History'), findsWidgets);
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
      // #113 lazy-build: tapping Activity mounts CrossGroupActivityScreen for
      // the first time, starting its EmptyStateView entrance ticker. Drain it
      // before teardown or the pending Timer trips '!timersPending'.
      await tester.pumpAndSettle();

      final navBar = tester.widget<NavigationBar>(find.byType(NavigationBar));
      expect(navBar.selectedIndex, 1);
    });
  });
}
