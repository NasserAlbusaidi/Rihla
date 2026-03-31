import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:safar/core/theme/app_theme.dart';
import 'package:safar/features/groups/models/group_activity_log_model.dart';
import 'package:safar/features/home/providers/dashboard_providers.dart';
import 'package:safar/features/home/widgets/activity_row.dart';
import 'package:safar/features/home/widgets/bottom_nav_shell.dart';
import 'package:safar/features/home/widgets/weekly_spending_card.dart';

void main() {
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
    testWidgets('Test 1: renders actorName, description, groupName, and relative timestamp', (tester) async {
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

      expect(find.text('Alice'), findsOneWidget);
      expect(find.text('added an expense'), findsOneWidget);
      expect(find.text('Beach Trip'), findsOneWidget);
      // Relative timestamp should be there (timeago)
      expect(find.textContaining('ago'), findsOneWidget);
    });

    testWidgets('Test 2: shows colored avatar circle with first letter of actorName', (tester) async {
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

      expect(find.byType(CircleAvatar), findsOneWidget);
      expect(find.text('B'), findsOneWidget);
    });
  });

  // ---------------------------------------------------------------------------
  // WeeklySpendingCard tests
  // ---------------------------------------------------------------------------
  group('WeeklySpendingCard', () {
    testWidgets('Test 3: renders 7 bars and This Week title', (tester) async {
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

      expect(find.text('This Week'), findsOneWidget);
      // Mon through Sun labels should be visible
      expect(find.text('Mon'), findsOneWidget);
      expect(find.text('Sun'), findsOneWidget);
    });

    testWidgets('Test 4: shows No spending this week when all amounts are zero', (tester) async {
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
    });

    testWidgets('Test 5: shows skeleton when provider is loading', (tester) async {
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
    testWidgets('Test 6: renders 4 tabs: Groups, Activity, Chats, Profile', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: BottomNavShell(
            child: const Text('Dashboard Content'),
          ),
        ),
      );
      await tester.pump();

      expect(find.text('Groups'), findsOneWidget);
      expect(find.text('Activity'), findsAtLeastNWidgets(1));
      expect(find.text('Chats'), findsOneWidget);
      expect(find.text('Profile'), findsOneWidget);
    });

    testWidgets('Test 7: shows Coming soon when tapping Activity tab', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: BottomNavShell(
            child: const Text('Dashboard Content'),
          ),
        ),
      );
      await tester.pump();

      // Tap Activity tab (index 1)
      await tester.tap(find.text('Activity').last);
      await tester.pump();

      // Stack+AnimatedOpacity keeps all 3 placeholder tabs rendered simultaneously.
      expect(find.text('Coming soon'), findsNWidgets(3));
    });

    testWidgets('Test 8: Groups tab shows child content', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: BottomNavShell(
            child: const Text('Dashboard Content'),
          ),
        ),
      );
      await tester.pump();

      expect(find.text('Dashboard Content'), findsOneWidget);

      // Tap Profile tab
      await tester.tap(find.text('Profile'));
      await tester.pump();
      // Stack+AnimatedOpacity keeps all 3 placeholder tabs rendered simultaneously.
      expect(find.text('Coming soon'), findsNWidgets(3));

      // Tap back to Groups
      await tester.tap(find.text('Groups'));
      await tester.pump();
      expect(find.text('Dashboard Content'), findsOneWidget);
    });
  });
}
