import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:safar/core/providers/settings_provider.dart';
import 'package:safar/core/theme/app_theme.dart';
import 'package:safar/features/events/providers/event_provider.dart';
import 'package:safar/features/groups/models/group_model.dart';
import 'package:safar/features/groups/providers/group_balance_provider.dart';
import 'package:safar/features/groups/providers/group_provider.dart';
import 'package:safar/features/home/keys/home_keys.dart';
import 'package:safar/features/home/providers/active_journeys_provider.dart';
import 'package:safar/features/home/providers/dashboard_providers.dart';
import 'package:safar/features/home/screens/home_screen.dart';
import 'package:safar/features/ledger/models/expense_model.dart';
import 'package:safar/l10n/generated/app_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// #284 — tapping the balance hero scrolls the home list down to the active
/// journeys section (the path to per-group settle-up). No new route.
void main() {
  testWidgets('tapping the balance hero scrolls the journeys section into view',
      (tester) async {
    // Small viewport so the journeys section starts below the fold.
    tester.view.physicalSize = const Size(400, 600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();

    final group = Group(
      id: 'g1',
      name: 'Desert Crew',
      inviteCode: 'ABC123',
      createdBy: 'test-user-id',
      memberIds: const ['test-user-id', 'uid-2'],
      currency: 'OMR',
      createdAt: DateTime(2026, 1, 1),
    );

    final router = GoRouter(
      initialLocation: '/home',
      routes: [
        GoRoute(path: '/home', builder: (_, _) => const HomeScreen()),
        GoRoute(
          path: '/activity',
          builder: (_, _) => const Scaffold(body: Text('ActivityScreen')),
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          currentUserIdProvider.overrideWithValue('test-user-id'),
          userGroupsProvider.overrideWith((ref) => Stream.value([group])),
          crossGroupBalanceOnceProvider.overrideWith(
            (ref) => Future.value((
              balance: (
                byCurrency: [
                  (
                    currency: 'OMR',
                    net: Decimal.parse('12.500'),
                    owedToUser: Decimal.parse('12.500'),
                    userOwes: Decimal.zero,
                  ),
                ],
                groupCount: 1,
                isLoading: false,
              ),
              partial: false,
            )),
          ),
          crossGroupActivityProvider.overrideWith(
            (ref) => const AsyncValue.data([]),
          ),
          activeJourneysProvider.overrideWith(
            (ref) => const AsyncValue.data(<ActiveJourneyEntry>[]),
          ),
          groupBalancesProvider.overrideWith(
            (ref, groupId) => AsyncValue.data((
              balances: <UserBalance>[],
              totalSpent: Decimal.zero,
              eventCount: 0,
              perEventBreakdown: <String, Map<String, Decimal>>{},
              memberNames: <String, String>{},
              memberRawNames: <String, String>{},
            )),
          ),
          groupEventsProvider.overrideWith((ref, groupId) => Stream.value([])),
        ],
        child: MaterialApp.router(
          theme: AppTheme.lightTheme,
          routerConfig: router,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
        ),
      ),
    );
    await tester.pumpAndSettle();

    final heroTopBefore = tester
        .getTopLeft(find.byKey(HomeKeys.balanceHeroCard))
        .dy;

    await tester.tap(find.byKey(HomeKeys.balanceHeroCard));
    await tester.pumpAndSettle();

    final heroTopAfter = tester
        .getTopLeft(find.byKey(HomeKeys.balanceHeroCard))
        .dy;

    // The list scrolled down to reveal journeys → the hero moved up.
    expect(
      heroTopAfter,
      lessThan(heroTopBefore),
      reason: 'tapping the hero should scroll the list toward the journeys '
          'section, moving the hero upward',
    );
  });
}
