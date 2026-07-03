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
import 'package:safar/features/settings/screens/profile_screen.dart';
import 'package:safar/features/ledger/models/expense_model.dart';
import 'package:safar/l10n/generated/app_localizations.dart';
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
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
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
        // Relative timestamp is rendered with the compact localized helper.
        expect(find.textContaining('H'), findsOneWidget);
      },
    );

    testWidgets(
      'Test 2: shows colored avatar circle with first letter of actorName',
      (tester) async {
        final activity = makeActivity(actorName: 'Bob');

        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.lightTheme,
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
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
        (ref, groupId) => const AsyncValue.data((
          balances: <String, List<UserBalance>>{},
          totalSpent: <String, Decimal>{},
          eventCount: 0,
          perEventBreakdown: <String, Map<String, Map<String, Decimal>>>{},
          memberNames: <String, String>{},
          memberRawNames: <String, String>{},
        )),
      ),
      currentUserIdProvider.overrideWithValue('test-user-id'),
    ];

    /// Builds a test app with GoRouter for BottomNavShell — ProfileScreen
    /// requires GoRouter.of(context) for back-button detection.
    Widget buildShellApp(List<Override> overrides, {Locale? locale}) {
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
          locale: locale,
          routerConfig: router,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
        ),
      );
    }

    testWidgets('Test 6: renders 3 tabs: Groups, History, Profile', (
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
        orderedEquals(['Groups', 'History', 'Profile']),
      );
      expect(find.text('Chats'), findsNothing);
    });

    testWidgets('renders Arabic tab labels under Locale(ar)', (tester) async {
      await tester.pumpWidget(
        buildShellApp(shellOverrides(), locale: const Locale('ar')),
      );
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pumpAndSettle();

      final navBar = tester.widget<NavigationBar>(find.byType(NavigationBar));
      expect(navBar.destinations, hasLength(3));
      expect(
        navBar.destinations.map(
          (destination) => (destination as NavigationDestination).label,
        ),
        orderedEquals(['المجموعات', 'السجل', 'الملف']),
      );
    });

    testWidgets(
      'Test 7: shows CrossGroupActivityScreen when tapping History tab',
      (tester) async {
        await tester.pumpWidget(buildShellApp(shellOverrides()));
        await tester.pump(const Duration(milliseconds: 500));
        await tester.pumpAndSettle();

        // Tap History tab (index 1)
        await tester.tap(find.text('History').last);
        await tester.pump(const Duration(milliseconds: 500));
        await tester.pumpAndSettle();

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

    testWidgets(
      'lazy-build: unvisited tabs are not mounted until first visit, then stay mounted',
      (tester) async {
        await tester.pumpWidget(buildShellApp(shellOverrides()));
        await tester.pump(const Duration(milliseconds: 500));
        await tester.pumpAndSettle();

        // Groups (index 0) is mounted on first render.
        expect(find.text('Dashboard Content'), findsOneWidget);
        // Activity + Profile tabs are NOT built before they are visited.
        expect(find.byType(CrossGroupActivityScreen), findsNothing);
        expect(find.byType(ProfileScreen), findsNothing);

        // Visit Activity -> it mounts.
        await tester.tap(find.byKey(HomeKeys.bottomNavActivity));
        await tester.pump(const Duration(milliseconds: 500));
        await tester.pumpAndSettle();
        expect(find.byType(CrossGroupActivityScreen), findsOneWidget);

        // Switch back to Groups -> Activity stays mounted (state retained).
        await tester.tap(find.byKey(HomeKeys.bottomNavGroups));
        await tester.pump();
        await tester.pumpAndSettle();
        expect(find.byType(CrossGroupActivityScreen), findsOneWidget);
        expect(find.text('Dashboard Content'), findsOneWidget);
      },
    );
  });
}
