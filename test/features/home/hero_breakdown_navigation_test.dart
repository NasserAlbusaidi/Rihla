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
import 'package:safar/features/home/widgets/group_balance_breakdown_sheet.dart';
import 'package:safar/features/ledger/models/expense_model.dart';
import 'package:safar/l10n/generated/app_localizations.dart';
import 'package:safar/shared/widgets/r_amount.dart';

/// PR-5 §3 (friction #4) — the balance hero opens a per-group breakdown
/// sheet instead of scrolling to the journeys strip (the #284 dead end).
/// Replaces `home_hero_scroll_to_journeys_test.dart`, deleted whole (its
/// entire assertion was that the hero scrolled — now obsolete).
Group _makeGroup(String id, String name) => Group(
  id: id,
  name: name,
  inviteCode: 'ABC123',
  createdBy: 'test-user-id',
  memberIds: const ['test-user-id', 'uid-2'],
  currency: 'OMR',
  createdAt: DateTime(2026, 1, 1),
);

List<Override> _baseOverrides(List<Group> groups) => [
  currentUserIdProvider.overrideWithValue('test-user-id'),
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
        path: '/group/:gid/settle-up',
        builder: (ctx, state) => Scaffold(
          body: Text(
            'SettleUp:${state.pathParameters['gid']}:'
            '${state.uri.queryParameters['memberId'] ?? 'none'}',
          ),
        ),
      ),
    ],
  );

  return ProviderScope(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      // #285/#428: model a secured, durable user so the account-backup
      // nudge is absent — it would push the hero further down the sliver
      // list and is irrelevant to this test.
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

void main() {
  late SharedPreferences prefs;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
  });

  testWidgets(
    'tapping the balance hero opens the breakdown sheet, no scroll side-effect',
    (tester) async {
      final group = _makeGroup('g1', 'Desert Crew');
      await tester.pumpWidget(
        _buildTestApp(
          prefs: prefs,
          overrides: [
            ..._baseOverrides([group]),
            homeGroupBalanceProvider.overrideWith(
              (ref, groupId) => AsyncValue.data((
                userNet: {'OMR': Decimal.parse('12.500')},
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

      final heroTopBefore = tester
          .getTopLeft(find.byKey(HomeKeys.balanceHeroCard))
          .dy;

      await tester.tap(find.byKey(HomeKeys.balanceHeroCard));
      await tester.pumpAndSettle();

      expect(find.byType(GroupBalanceBreakdownSheet), findsOneWidget);
      expect(find.byKey(HomeKeys.heroBreakdownSheet), findsOneWidget);

      // The sheet is a modal — the home list underneath must not have
      // scrolled (was: the #284 hero tap scrolled to the journeys strip).
      final heroTopAfter = tester
          .getTopLeft(find.byKey(HomeKeys.balanceHeroCard))
          .dy;
      expect(heroTopAfter, heroTopBefore);
    },
  );

  testWidgets(
    'one row per non-zero-net group, per-currency (two-currency group → '
    'two RAmounts, never summed); a fully-settled group renders no row',
    (tester) async {
      final owed = _makeGroup('g1', 'Desert Crew');
      final settled = _makeGroup('g2', 'Mountain Pals');
      await tester.pumpWidget(
        _buildTestApp(
          prefs: prefs,
          overrides: [
            ..._baseOverrides([owed, settled]),
            homeGroupBalanceProvider.overrideWith((ref, groupId) {
              if (groupId == 'g1') {
                return AsyncValue.data((
                  userNet: {
                    'OMR': Decimal.parse('5'),
                    'USD': Decimal.parse('-3'),
                  },
                  userPerEventNet: const <String, Map<String, Decimal>>{},
                  eventCount: 1,
                  partial: false,
                  fromAggregate: true,
                ));
              }
              return AsyncValue.data((
                userNet: {'OMR': Decimal.zero},
                userPerEventNet: const <String, Map<String, Decimal>>{},
                eventCount: 1,
                partial: false,
                fromAggregate: true,
              ));
            }),
          ],
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(HomeKeys.balanceHeroCard));
      await tester.pumpAndSettle();

      final sheet = find.byType(GroupBalanceBreakdownSheet);
      expect(
        find.descendant(of: sheet, matching: find.text('Desert Crew')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: sheet, matching: find.text('Mountain Pals')),
        findsNothing,
      );
      expect(
        find.descendant(of: sheet, matching: find.byType(RAmount)),
        findsNWidgets(2),
      );
    },
  );

  testWidgets(
    'tapping a row pushes /group/:gid/settle-up with no memberId',
    (tester) async {
      final group = _makeGroup('g1', 'Desert Crew');
      await tester.pumpWidget(
        _buildTestApp(
          prefs: prefs,
          overrides: [
            ..._baseOverrides([group]),
            homeGroupBalanceProvider.overrideWith(
              (ref, groupId) => AsyncValue.data((
                userNet: {'OMR': Decimal.parse('12.500')},
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

      await tester.tap(find.byKey(HomeKeys.balanceHeroCard));
      await tester.pumpAndSettle();

      final sheet = find.byType(GroupBalanceBreakdownSheet);
      await tester.tap(
        find.descendant(of: sheet, matching: find.text('Desert Crew')),
      );
      await tester.pumpAndSettle();

      expect(find.text('SettleUp:g1:none'), findsOneWidget);
      expect(find.byType(GroupBalanceBreakdownSheet), findsNothing);
    },
  );

  testWidgets(
    'zero-net user → sheet still opens with the empty state, no crash',
    (tester) async {
      final group = _makeGroup('g1', 'Desert Crew');
      await tester.pumpWidget(
        _buildTestApp(
          prefs: prefs,
          overrides: [
            ..._baseOverrides([group]),
            homeGroupBalanceProvider.overrideWith(
              (ref, groupId) => AsyncValue.data((
                userNet: {'OMR': Decimal.zero},
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

      await tester.tap(find.byKey(HomeKeys.balanceHeroCard));
      await tester.pumpAndSettle();

      expect(find.byType(GroupBalanceBreakdownSheet), findsOneWidget);
      final sheet = find.byType(GroupBalanceBreakdownSheet);
      expect(
        find.descendant(
          of: sheet,
          matching: find.text("You're all settled up"),
        ),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );
}
