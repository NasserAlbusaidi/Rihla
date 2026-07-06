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
// #997 — home row showed "0 events · settled" for a group whose balance
// facade (`homeGroupBalanceProvider`) was loading or errored, not settled.
// `_GroupRow` used to collapse every non-data AsyncValue to its defaults via
// `.valueOrNull` — this pins the fix: loading/error must never render a
// false event count or "settled" caption, and a resolved-but-partial balance
// must keep showing its numbers plus an incomplete-data affordance.
//
// This is display-layer hardening ONLY (Refs #997, not Closes) — the
// on-device mechanism that put the provider in a non-data state on the
// reporting device is a separate, still-open investigation.
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

List<Override> _overrides(
  List<Group> groups,
  AsyncValue<HomeGroupBalance> balance,
) => [
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
  homeGroupBalanceProvider.overrideWith((ref, groupId) => balance),
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
      linkedEmailProvider.overrideWithValue('secured@example.com'),
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

Finder _rowFor(String groupName) => find
    .ancestor(of: find.text(groupName), matching: find.byType(InkWell))
    .first;

void main() {
  late SharedPreferences prefs;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
  });

  group('_GroupRow balance-facade states (#997)', () {
    testWidgets(
      'loading facade renders a skeleton, never "0 events" or "settled"',
      (tester) async {
        await tester.pumpWidget(
          _buildTestApp(
            prefs: prefs,
            overrides: _overrides(
              [_makeGroup('g1', 'Desert Crew')],
              const AsyncValue.loading(),
            ),
          ),
        );
        // The loading trailing column shimmers via a repeating animation
        // (Skeletonizer) — pumpAndSettle would never terminate. Pump a
        // bounded number of frames instead so the Stream-backed group/event
        // providers still get to deliver their first value.
        for (var i = 0; i < 6; i++) {
          await tester.pump(const Duration(milliseconds: 16));
        }

        expect(find.text('Desert Crew'), findsOneWidget);
        expect(
          find.byKey(HomeKeys.groupRowBalanceSkeleton),
          findsOneWidget,
        );
        expect(find.text('settled'), findsNothing);
        expect(find.textContaining('0 events'), findsNothing);
        expect(find.byKey(HomeKeys.groupRowBalanceError), findsNothing);
      },
    );

    testWidgets(
      'errored facade suppresses numbers and never silently shows "settled"',
      (tester) async {
        await tester.pumpWidget(
          _buildTestApp(
            prefs: prefs,
            overrides: _overrides(
              [_makeGroup('g1', 'Desert Crew')],
              AsyncValue.error(Exception('denied'), StackTrace.empty),
            ),
          ),
        );
        await tester.pumpAndSettle();

        final row = _rowFor('Desert Crew');
        expect(find.text('settled'), findsNothing);
        expect(find.textContaining('0 events'), findsNothing);
        expect(
          find.descendant(
            of: row,
            matching: find.byKey(HomeKeys.groupRowBalanceError),
          ),
          findsOneWidget,
        );
        expect(
          find.descendant(of: row, matching: find.byType(RichText)),
          findsWidgets,
        );
      },
    );

    testWidgets(
      'partial data keeps the available numbers and shows an incomplete '
      'indicator',
      (tester) async {
        await tester.pumpWidget(
          _buildTestApp(
            prefs: prefs,
            overrides: _overrides(
              [_makeGroup('g1', 'Desert Crew')],
              AsyncValue.data((
                userNet: {'OMR': Decimal.parse('-5')},
                userPerEventNet: const <String, Map<String, Decimal>>{},
                eventCount: 1,
                partial: true,
                fromAggregate: false,
              )),
            ),
          ),
        );
        await tester.pumpAndSettle();

        final row = _rowFor('Desert Crew');
        expect(
          find.descendant(of: row, matching: find.text('you owe')),
          findsOneWidget,
        );
        expect(
          find.descendant(
            of: row,
            matching: find.byKey(HomeKeys.groupRowBalanceIncomplete),
          ),
          findsOneWidget,
        );
      },
    );
  });
}
