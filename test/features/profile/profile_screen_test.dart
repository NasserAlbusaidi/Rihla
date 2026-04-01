// Widget tests for ProfileScreen — covers IDENT-01, IDENT-02, STATS-01, STATS-02,
// STATS-03. Tests are written first (RED) before implementing the widgets.

import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:safar/core/providers/settings_provider.dart';
import 'package:safar/core/utils/formatters.dart';
import 'package:safar/features/settings/keys/profile_keys.dart';
import 'package:safar/features/settings/providers/profile_stats_provider.dart';
import 'package:safar/features/settings/screens/profile_screen.dart';

// ---------------------------------------------------------------------------
// Test helpers
// ---------------------------------------------------------------------------

Widget _buildTestApp(
  Widget widget, {
  List<Override> overrides = const [],
}) {
  final router = GoRouter(
    initialLocation: '/profile',
    routes: [
      GoRoute(
        path: '/profile',
        builder: (ctx, state) => widget,
      ),
    ],
  );

  return ProviderScope(
    overrides: overrides,
    child: MaterialApp.router(routerConfig: router),
  );
}

/// Build a [ProfileStats] AsyncValue with the given values.
AsyncValue<ProfileStats> _statsData({
  int groupCount = 0,
  int eventCount = 0,
  Decimal? totalSpent,
}) =>
    AsyncValue.data((
      groupCount: groupCount,
      eventCount: eventCount,
      totalSpent: totalSpent ?? Decimal.zero,
    ));

/// Pump the widget tree and advance time enough for all flutter_animate
/// animations to complete (identity section delays up to 200ms + ~300ms).
Future<void> _pumpWithAnimations(WidgetTester tester) async {
  await tester.pump();
  // Advance through animation delays: 100ms + 200ms + buffer
  await tester.pump(const Duration(milliseconds: 500));
  // One more pump to process any final callbacks
  await tester.pump();
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('ProfileScreen — IDENT-01', () {
    testWidgets('shows display name when set', (tester) async {
      SharedPreferences.setMockInitialValues({'settings_device_name': 'Alice'});
      final prefs = await SharedPreferences.getInstance();

      await tester.pumpWidget(
        _buildTestApp(
          const ProfileScreen(),
          overrides: [
            sharedPreferencesProvider.overrideWithValue(prefs),
            profileStatsProvider.overrideWith(
              (ref) => _statsData(),
            ),
          ],
        ),
      );
      await _pumpWithAnimations(tester);

      expect(find.byKey(ProfileKeys.displayName), findsOneWidget);
      expect(find.text('Alice'), findsWidgets);
    });

    testWidgets('shows "Set your name" prompt when deviceName is empty',
        (tester) async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();

      await tester.pumpWidget(
        _buildTestApp(
          const ProfileScreen(),
          overrides: [
            sharedPreferencesProvider.overrideWithValue(prefs),
            profileStatsProvider.overrideWith(
              (ref) => _statsData(),
            ),
          ],
        ),
      );
      await _pumpWithAnimations(tester);

      expect(find.byKey(ProfileKeys.setNamePrompt), findsOneWidget);
      expect(find.text('Set your name'), findsOneWidget);
    });
  });

  group('ProfileScreen — InitialsCircle', () {
    testWidgets('shows correct initials for a single word name', (tester) async {
      SharedPreferences.setMockInitialValues({'settings_device_name': 'Alice'});
      final prefs = await SharedPreferences.getInstance();

      await tester.pumpWidget(
        _buildTestApp(
          const ProfileScreen(),
          overrides: [
            sharedPreferencesProvider.overrideWithValue(prefs),
            profileStatsProvider.overrideWith(
              (ref) => _statsData(),
            ),
          ],
        ),
      );
      await _pumpWithAnimations(tester);

      expect(find.byKey(ProfileKeys.initialsCircle), findsOneWidget);
      expect(find.text('A'), findsOneWidget);
    });
  });

  group('ProfileScreen — IDENT-02', () {
    testWidgets('tapping name row opens edit bottom sheet', (tester) async {
      SharedPreferences.setMockInitialValues({'settings_device_name': 'Alice'});
      final prefs = await SharedPreferences.getInstance();

      await tester.pumpWidget(
        _buildTestApp(
          const ProfileScreen(),
          overrides: [
            sharedPreferencesProvider.overrideWithValue(prefs),
            profileStatsProvider.overrideWith(
              (ref) => _statsData(),
            ),
          ],
        ),
      );
      await _pumpWithAnimations(tester);

      // Tap on the name display row
      await tester.tap(find.byKey(ProfileKeys.displayName));
      await tester.pumpAndSettle();

      // The bottom sheet should show the name text field
      expect(find.byKey(ProfileKeys.nameTextField), findsOneWidget);
    });

    testWidgets('tapping "Set your name" opens edit bottom sheet',
        (tester) async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();

      await tester.pumpWidget(
        _buildTestApp(
          const ProfileScreen(),
          overrides: [
            sharedPreferencesProvider.overrideWithValue(prefs),
            profileStatsProvider.overrideWith(
              (ref) => _statsData(),
            ),
          ],
        ),
      );
      await _pumpWithAnimations(tester);

      await tester.tap(find.byKey(ProfileKeys.setNamePrompt));
      await tester.pumpAndSettle();

      expect(find.byKey(ProfileKeys.nameTextField), findsOneWidget);
    });
  });

  group('ProfileScreen — STATS-01, STATS-02, STATS-03', () {
    testWidgets('shows group count in stat card', (tester) async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();

      await tester.pumpWidget(
        _buildTestApp(
          const ProfileScreen(),
          overrides: [
            sharedPreferencesProvider.overrideWithValue(prefs),
            profileStatsProvider.overrideWith(
              (ref) => _statsData(
                groupCount: 3,
                eventCount: 5,
                totalSpent: Decimal.parse('42.500'),
              ),
            ),
          ],
        ),
      );
      await _pumpWithAnimations(tester);

      // STATS-01: group count
      final groupsStat = find.byKey(ProfileKeys.statGroups);
      expect(groupsStat, findsOneWidget);
      expect(find.descendant(of: groupsStat, matching: find.text('3')),
          findsOneWidget);
    });

    testWidgets('shows event count in stat card', (tester) async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();

      await tester.pumpWidget(
        _buildTestApp(
          const ProfileScreen(),
          overrides: [
            sharedPreferencesProvider.overrideWithValue(prefs),
            profileStatsProvider.overrideWith(
              (ref) => _statsData(
                groupCount: 3,
                eventCount: 5,
                totalSpent: Decimal.parse('42.500'),
              ),
            ),
          ],
        ),
      );
      await _pumpWithAnimations(tester);

      // STATS-02: event count
      final eventsStat = find.byKey(ProfileKeys.statEvents);
      expect(eventsStat, findsOneWidget);
      expect(find.descendant(of: eventsStat, matching: find.text('5')),
          findsOneWidget);
    });

    testWidgets('shows formatted total spending in stat card', (tester) async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();

      final expectedSpending = AppFormatters.formatCurrency(
        Decimal.parse('42.500'),
        'OMR',
      );

      await tester.pumpWidget(
        _buildTestApp(
          const ProfileScreen(),
          overrides: [
            sharedPreferencesProvider.overrideWithValue(prefs),
            profileStatsProvider.overrideWith(
              (ref) => _statsData(
                groupCount: 3,
                eventCount: 5,
                totalSpent: Decimal.parse('42.500'),
              ),
            ),
          ],
        ),
      );
      await _pumpWithAnimations(tester);

      // STATS-03: total spending formatted via AppFormatters
      final spentStat = find.byKey(ProfileKeys.statSpent);
      expect(spentStat, findsOneWidget);
      expect(
        find.descendant(
          of: spentStat,
          matching: find.text(expectedSpending),
        ),
        findsOneWidget,
      );
    });
  });
}
