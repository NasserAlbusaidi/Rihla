import 'dart:async';

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

// ---------------------------------------------------------------------------
// #1017 — the loading-state skeleton renders two stub `Group(id: 'sk1'/'sk2')`
// rows through the real `_buildLoaded`/`_GroupRow` path. Before the fix each
// stub row called `ref.watch(homeGroupBalanceProvider(group.id))`, and because
// that provider is a keyed family it INSTANTIATED an element for the fake gid
// — opening a real `groups/sk1/aggregates/balance` server listen that always
// fails PERMISSION_DENIED and (non-autoDispose) persists for the session.
//
// This pins the fix: placeholder rows must never instantiate the balance
// facade for their sentinel ids. We spy on the family's create fn — in the
// skeleton state it must never be called with 'sk1' or 'sk2'.
// ---------------------------------------------------------------------------

void main() {
  late SharedPreferences prefs;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
  });

  testWidgets(
    'loading skeleton never instantiates homeGroupBalanceProvider for sk1/sk2',
    (tester) async {
      // Tall viewport so both stub rows lay out on-screen (the default 600px
      // height leaves the group list below the fold, so only sk1 would build).
      tester.view.physicalSize = const Size(1200, 3000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      // A never-emitting groups stream keeps userGroupsProvider in loading —
      // exactly the state that renders `_buildSkeleton`.
      final groupsController = StreamController<List<Group>>();
      addTearDown(groupsController.close);

      final watchedGids = <String>[];

      final router = GoRouter(
        initialLocation: '/home',
        routes: [
          GoRoute(path: '/home', builder: (ctx, state) => const HomeScreen()),
        ],
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            sharedPreferencesProvider.overrideWithValue(prefs),
            linkedEmailProvider.overrideWithValue('secured@example.com'),
            isDurableUserProvider.overrideWithValue(true),
            userGroupsProvider.overrideWith((ref) => groupsController.stream),
            crossGroupActivityProvider.overrideWith(
              (ref) => const AsyncValue.data([]),
            ),
            groupBalancesProvider.overrideWith(
              (ref, groupId) => const AsyncValue.data((
                balances: <String, List<UserBalance>>{},
                totalSpent: <String, Decimal>{},
                eventCount: 0,
                perEventBreakdown:
                    <String, Map<String, Map<String, Decimal>>>{},
                memberNames: <String, String>{},
                memberRawNames: <String, String>{},
              )),
            ),
            groupEventsProvider.overrideWith((ref, groupId) => Stream.value([])),
            currentUserIdProvider.overrideWithValue('test-user-id'),
            // Spy: record every gid the balance facade is instantiated for.
            homeGroupBalanceProvider.overrideWith((ref, groupId) {
              watchedGids.add(groupId);
              return const AsyncValue<HomeGroupBalance>.loading();
            }),
          ],
          child: MaterialApp.router(
            theme: AppTheme.lightTheme,
            routerConfig: router,
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
          ),
        ),
      );

      // The skeleton shimmers via a repeating Skeletonizer animation, so
      // pumpAndSettle would never terminate — pump a bounded number of frames.
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }

      // Fix-independent proof we are on the skeleton path: both stub rows
      // render the loading trailing (a placeholder row is `isLoading`, so it
      // shows the same balance-skeleton the fix preserves).
      expect(
        find.byKey(HomeKeys.groupRowBalanceSkeleton),
        findsNWidgets(2),
        reason: 'expected two skeleton stub rows to render',
      );

      // The leak is closed: no listen was opened for the sentinel ids.
      expect(
        watchedGids,
        isNot(anyElement(anyOf(equals('sk1'), equals('sk2')))),
        reason:
            'skeleton stub rows must not watch homeGroupBalanceProvider for '
            'their fake gids — that opens real permission-denied listens '
            '(#1017). Observed: $watchedGids',
      );
    },
  );
}
