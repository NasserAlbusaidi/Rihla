import 'dart:async';

import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:iconsax/iconsax.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:safar/core/providers/settings_provider.dart';
import 'package:safar/core/theme/app_theme.dart';
import 'package:safar/features/auth/providers/auth_provider.dart';
import 'package:safar/features/groups/models/group_model.dart';
import 'package:safar/features/groups/providers/group_balance_provider.dart';
import 'package:safar/features/groups/providers/group_provider.dart';
import 'package:safar/features/home/keys/home_keys.dart';
import 'package:safar/features/home/providers/dashboard_providers.dart';
import 'package:safar/features/home/screens/home_screen.dart';
import 'package:safar/features/ledger/models/expense_model.dart';
import 'package:safar/l10n/generated/app_localizations.dart';

/// #900 friction #3 — PR-5b: the home top-bar search entry point (spec §
/// "Entry point"). Sibling coverage to `bell_tab_select_test.dart` — pins
/// that the new `_IconCircle` doesn't collide with the bell's Badge key
/// (each instance now carries its own `badgeKey`) and that the icon pushes
/// `/search` with the right semantics/glyph.

List<Override> _baseOverrides() => [
  linkedEmailProvider.overrideWithValue('secured@example.com'),
  isDurableUserProvider.overrideWithValue(true),
  userGroupsProvider.overrideWith((ref) => Stream.value(const <Group>[])),
  crossGroupHomeBalanceProvider.overrideWith(
    (ref) => const AsyncValue.data((
      balance: (byCurrency: <CurrencyBalance>[], groupCount: 0, isLoading: false),
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
  currentUserIdProvider.overrideWithValue('test-user-id'),
];

Widget _buildTestApp(SharedPreferences prefs, List<Override> overrides) {
  final router = GoRouter(
    initialLocation: '/home',
    routes: [
      GoRoute(path: '/home', builder: (ctx, state) => const HomeScreen()),
      GoRoute(
        path: '/search',
        builder: (ctx, state) => Scaffold(
          body: Text('SearchScreen:${state.uri.queryParameters['q'] ?? ''}'),
        ),
      ),
      GoRoute(
        path: '/activity',
        builder: (ctx, state) => const Scaffold(body: Text('ActivityScreen')),
      ),
      GoRoute(
        path: '/profile',
        builder: (ctx, state) => const Scaffold(body: Text('ProfileScreen')),
      ),
      GoRoute(
        path: '/create-group',
        builder: (ctx, state) =>
            const Scaffold(body: Text('CreateGroupScreen')),
      ),
      GoRoute(
        path: '/join-group',
        builder: (ctx, state) => const Scaffold(body: Text('JoinGroupScreen')),
      ),
    ],
  );

  return ProviderScope(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
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

  group('Home top-bar search entry point (#900 friction #3, PR-5b)', () {
    testWidgets('search icon pushes /search', (tester) async {
      await tester.pumpWidget(_buildTestApp(prefs, _baseOverrides()));
      await tester.pumpAndSettle();

      expect(find.byKey(HomeKeys.searchButton), findsOneWidget);

      await tester.tap(find.byKey(HomeKeys.searchButton));
      await tester.pumpAndSettle();

      expect(find.textContaining('SearchScreen:'), findsOneWidget);
    });

    testWidgets('search icon renders the search glyph, no RTL flip', (
      tester,
    ) async {
      await tester.pumpWidget(_buildTestApp(prefs, _baseOverrides()));
      await tester.pumpAndSettle();

      expect(
        find.descendant(
          of: find.byKey(HomeKeys.searchButton),
          matching: find.byIcon(Iconsax.search_normal),
        ),
        findsOneWidget,
      );
    });

    testWidgets(
      'search and bell icons carry distinct Badge keys (no collision)',
      (tester) async {
        await tester.pumpWidget(_buildTestApp(prefs, _baseOverrides()));
        await tester.pumpAndSettle();

        // Both badges must be independently locatable — a shared key would
        // make either `find.byKey` ambiguous (two widgets) or throw.
        expect(find.byKey(HomeKeys.searchButtonBadge), findsOneWidget);
        expect(find.byKey(HomeKeys.bellUnreadBadge), findsOneWidget);

        final searchBadge = tester.widget<Badge>(
          find.byKey(HomeKeys.searchButtonBadge),
        );
        expect(searchBadge.isLabelVisible, isFalse);
      },
    );

    testWidgets('semantic label matches searchTitle', (tester) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(_buildTestApp(prefs, _baseOverrides()));
      await tester.pumpAndSettle();

      expect(find.bySemanticsLabel('Search'), findsOneWidget);
      handle.dispose();
    });
  });
}
