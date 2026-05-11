import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:safar/core/providers/settings_provider.dart';
import 'package:safar/core/theme/app_theme.dart';
import 'package:safar/features/events/providers/event_provider.dart';
import 'package:safar/features/groups/models/group_activity_log_model.dart';
import 'package:safar/features/groups/providers/group_balance_provider.dart';
import 'package:safar/features/groups/providers/group_provider.dart';
import 'package:safar/features/home/providers/dashboard_providers.dart';
import 'package:safar/features/home/keys/home_keys.dart';
import 'package:safar/features/home/screens/cross_group_activity_screen.dart';
import 'package:safar/features/home/widgets/activity_row.dart';
import 'package:safar/features/home/widgets/bottom_nav_shell.dart';
import 'package:safar/features/home/widgets/weekly_spending_card.dart';
import 'package:safar/features/ledger/models/expense_model.dart';
import 'package:safar/shared/widgets/r_avatar.dart';

void main() {
  late SharedPreferences prefs;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
  });
  // Helper to build a test GroupActivityLog
  GroupActivityLog makeActivity({
    String actorName = 'Alice',
    String description = 'added an expense',
    DateTime? timestamp,
  }) {
    return GroupActivityLog(
      id: 'test-activity-1',
      type: 'expense_added',
      actorId: 'uid-alice',
      actorName: actorName,
      description: description,
      timestamp: timestamp ?? DateTime.now().subtract(const Duration(hours: 2)),
    );
  }

  // Helper to build a 7-day spending list
  List<DailySpending> makeWeekData({bool allZero = false}) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final weekday = today.weekday;
    final startOfWeek = today.subtract(Duration(days: weekday - 1));
    return List.generate(7, (i) {
      final date = startOfWeek.add(Duration(days: i));
      final amount = allZero ? Decimal.zero : Decimal.parse((i + 1).toString());
      return (date: date, amount: amount);
    });
  }

  Widget buildProviderWidget({
    required Widget child,
    List<Override> overrides = const [],
  }) {
    return ProviderScope(
      overrides: overrides,
      child: MaterialApp(
        theme: AppTheme.lightTheme,
        home: Scaffold(body: SingleChildScrollView(child: child)),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // ActivityRow tests
  // ---------------------------------------------------------------------------
  group('ActivityRow', () {
    testWidgets(
      'Test 1: renders actorName, description, groupName, and relative timestamp',
      (tester) async {
        final activity = makeActivity(
          actorName: 'Alice',
          description: 'added an expense',
          timestamp: DateTime.now().subtract(const Duration(hours: 2)),
        );

        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.lightTheme,
            home: Scaffold(
              body: ActivityRow(
                activity: activity,
                groupName: 'Beach Trip',
                groupId: 'group-1',
              ),
            ),
          ),
        );
        await tester.pump();

        expect(
          find.byWidgetPredicate(
            (widget) =>
                widget is Text &&
                (widget.textSpan?.toPlainText().contains('Alice') ?? false),
          ),
          findsOneWidget,
        );
        expect(
          find.byWidgetPredicate(
            (widget) =>
                widget is Text &&
                (widget.textSpan?.toPlainText().contains('added an expense') ??
                    false),
          ),
          findsOneWidget,
        );
        expect(find.text('Beach Trip'), findsOneWidget);
        // Relative timestamp should be there (timeago)
        expect(find.textContaining('ago'), findsOneWidget);
      },
    );

    testWidgets(
      'Test 2: shows colored avatar circle with first letter of actorName',
      (tester) async {
        final activity = makeActivity(actorName: 'Bob');

        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.lightTheme,
            home: Scaffold(
              body: ActivityRow(
                activity: activity,
                groupName: 'Weekend',
                groupId: 'group-2',
              ),
            ),
          ),
        );
        await tester.pump();

        expect(find.byType(RAvatar), findsOneWidget);
        expect(find.text('B'), findsOneWidget);
      },
    );
  });

  // ---------------------------------------------------------------------------
  // WeeklySpendingCard tests
  // ---------------------------------------------------------------------------
  group('WeeklySpendingCard', () {
    testWidgets('Test 3: renders 7 bars and Weekly Spending (OMR) title', (
      tester,
    ) async {
      await tester.pumpWidget(
        buildProviderWidget(
          child: const WeeklySpendingCard(),
          overrides: [
            weeklyGroupSpendingProvider.overrideWith(
              (ref) => AsyncValue.data(makeWeekData()),
            ),
          ],
        ),
      );
      await tester.pump();

      expect(find.text('Weekly Spending (OMR)'), findsOneWidget);
      // Mon through Sun labels should be visible
      expect(find.text('Mon'), findsOneWidget);
      expect(find.text('Sun'), findsOneWidget);
    });

    testWidgets(
      'Test 4: shows No spending this week when all amounts are zero',
      (tester) async {
        await tester.pumpWidget(
          buildProviderWidget(
            child: const WeeklySpendingCard(),
            overrides: [
              weeklyGroupSpendingProvider.overrideWith(
                (ref) => AsyncValue.data(makeWeekData(allZero: true)),
              ),
            ],
          ),
        );
        await tester.pump();

        expect(find.text('No spending this week'), findsOneWidget);
      },
    );

    testWidgets(
      'Test NEW-1: renders amount labels on non-zero bars (CHRT-01)',
      (tester) async {
        await tester.pumpWidget(
          buildProviderWidget(
            child: const WeeklySpendingCard(),
            overrides: [
              weeklyGroupSpendingProvider.overrideWith(
                (ref) => AsyncValue.data(makeWeekData()),
              ),
            ],
          ),
        );
        await tester.pump();

        // makeWeekData produces amounts 1.0 through 7.0
        // Bar labels use toStringAsFixed(1), so '7.0' should appear
        expect(find.text('7.0'), findsOneWidget);
        expect(find.text('1.0'), findsOneWidget);
      },
    );

    testWidgets('Test NEW-2: no amount labels on all-zero chart (CHRT-01)', (
      tester,
    ) async {
      await tester.pumpWidget(
        buildProviderWidget(
          child: const WeeklySpendingCard(),
          overrides: [
            weeklyGroupSpendingProvider.overrideWith(
              (ref) => AsyncValue.data(makeWeekData(allZero: true)),
            ),
          ],
        ),
      );
      await tester.pump();

      // All-zero state shows "No spending this week" — no amount labels
      expect(find.text('0.0'), findsNothing);
    });

    testWidgets('Test 5: shows skeleton when provider is loading', (
      tester,
    ) async {
      await tester.pumpWidget(
        buildProviderWidget(
          child: const WeeklySpendingCard(),
          overrides: [
            weeklyGroupSpendingProvider.overrideWith(
              (ref) => const AsyncValue.loading(),
            ),
          ],
        ),
      );
      await tester.pump();

      // Skeleton is inside the card container — look for loading state content
      // The SkeletonLoader is rendered within the card
      expect(find.byType(WeeklySpendingCard), findsOneWidget);
    });
  });

  // ---------------------------------------------------------------------------
  // BottomNavShell tests
  // ---------------------------------------------------------------------------
  group('BottomNavShell', () {
    /// Minimal overrides for BottomNavShell tests — ProfileScreen (tab 2)
    /// watches settingsProvider, userGroupsProvider, groupEventsProvider,
    /// and groupBalancesProvider via profileStatsProvider.
    List<Override> shellOverrides() => [
      sharedPreferencesProvider.overrideWithValue(prefs),
      userGroupsProvider.overrideWith((ref) => Stream.value([])),
      crossGroupActivityProvider.overrideWith(
        (ref) => const AsyncValue.data([]),
      ),
      groupEventsProvider.overrideWith((ref, groupId) => Stream.value([])),
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

    /// Builds a test app with GoRouter for BottomNavShell — ProfileScreen
    /// requires GoRouter.of(context) for back-button detection.
    Widget buildShellApp(List<Override> overrides) {
      final router = GoRouter(
        initialLocation: '/home',
        routes: [
          GoRoute(
            path: '/home',
            builder: (ctx, state) =>
                const BottomNavShell(child: Text('Dashboard Content')),
          ),
          GoRoute(
            path: '/profile',
            builder: (ctx, state) => const Scaffold(body: Text('ProfileRoute')),
          ),
        ],
      );
      return ProviderScope(
        overrides: overrides,
        child: MaterialApp.router(
          theme: AppTheme.lightTheme,
          routerConfig: router,
        ),
      );
    }

    testWidgets('Test 6: renders 3 tabs: Groups, Activity, Profile', (
      tester,
    ) async {
      await tester.pumpWidget(buildShellApp(shellOverrides()));
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pumpAndSettle();

      final navBar = tester.widget<NavigationBar>(find.byType(NavigationBar));
      expect(navBar.destinations, hasLength(3));
      expect(
        navBar.destinations.map(
          (destination) => (destination as NavigationDestination).label,
        ),
        orderedEquals(['Groups', 'Activity', 'Profile']),
      );
      expect(find.text('Chats'), findsNothing);
    });

    testWidgets(
      'Test 7: shows CrossGroupActivityScreen when tapping Activity tab',
      (tester) async {
        await tester.pumpWidget(buildShellApp(shellOverrides()));
        await tester.pump(const Duration(milliseconds: 500));
        await tester.pumpAndSettle();

        // Tap Activity tab (index 1)
        await tester.tap(find.text('Activity').last);
        await tester.pump();

        expect(find.byType(CrossGroupActivityScreen), findsOneWidget);
        expect(find.text('Coming soon'), findsNothing);
      },
    );

    testWidgets('Test 8: Groups tab shows child content', (tester) async {
      await tester.pumpWidget(buildShellApp(shellOverrides()));
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pumpAndSettle();

      expect(find.text('Dashboard Content'), findsOneWidget);

      // Tap Profile tab — ProfileScreen is shown (Phase 25, not "Coming soon")
      await tester.tap(find.byKey(HomeKeys.bottomNavProfile));
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pumpAndSettle();

      expect(find.text('Coming soon'), findsNothing);

      // Tap back to Groups (use key since 'Groups' also appears in ProfileScreen stat card)
      await tester.tap(find.byKey(HomeKeys.bottomNavGroups));
      await tester.pump();
      expect(find.text('Dashboard Content'), findsOneWidget);
    });
  });
}
