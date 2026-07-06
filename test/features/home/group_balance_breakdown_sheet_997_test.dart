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

// ---------------------------------------------------------------------------
// #997 — the breakdown sheet used to filter on `.valueOrNull?.userNet ?? {}`,
// so a group whose balance facade was loading/errored produced empty lines
// and was silently dropped — indistinguishable from a genuinely settled
// group. This pins the fix: an unresolved group must not vanish; the sheet
// says so instead of presenting a false "you're all settled up".
// ---------------------------------------------------------------------------

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
        builder: (ctx, state) =>
            Scaffold(body: Text('SettleUp:${state.pathParameters['gid']}')),
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

/// The home groups list renders `_GroupRow`'s loading skeleton via a
/// repeating shimmer animation whenever any group's balance is loading —
/// `pumpAndSettle` never terminates against a repeating animation, so this
/// test pumps a bounded number of frames instead (long enough for the
/// stream-backed providers to emit and the sheet's entrance transition to
/// finish).
Future<void> _pumpFrames(WidgetTester tester, {int times = 24}) async {
  for (var i = 0; i < times; i++) {
    await tester.pump(const Duration(milliseconds: 16));
  }
}

void main() {
  late SharedPreferences prefs;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
  });

  testWidgets(
    'a loading group is not presented as settled — sheet shows loading, '
    'not the empty state',
    (tester) async {
      final group = _makeGroup('g1', 'Desert Crew');
      await tester.pumpWidget(
        _buildTestApp(
          prefs: prefs,
          overrides: [
            ..._baseOverrides([group]),
            homeGroupBalanceProvider.overrideWith(
              (ref, groupId) => const AsyncValue.loading(),
            ),
          ],
        ),
      );
      await _pumpFrames(tester);

      await tester.tap(find.byKey(HomeKeys.balanceHeroCard));
      await _pumpFrames(tester);

      final sheet = find.byType(GroupBalanceBreakdownSheet);
      expect(
        find.descendant(
          of: sheet,
          matching: find.text('You\'re all settled up'),
        ),
        findsNothing,
        reason: 'unresolved balance must not read as settled',
      );
      expect(
        find.descendant(of: sheet, matching: find.byType(CircularProgressIndicator)),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'one resolved group + one errored group → resolved row shows, plus an '
    'incomplete-data footer (errored group not silently dropped as settled)',
    (tester) async {
      final owed = _makeGroup('g1', 'Desert Crew');
      final unresolved = _makeGroup('g2', 'Mountain Pals');
      await tester.pumpWidget(
        _buildTestApp(
          prefs: prefs,
          overrides: [
            ..._baseOverrides([owed, unresolved]),
            homeGroupBalanceProvider.overrideWith((ref, groupId) {
              if (groupId == 'g1') {
                return AsyncValue.data((
                  userNet: {'OMR': Decimal.parse('5')},
                  userPerEventNet: const <String, Map<String, Decimal>>{},
                  eventCount: 1,
                  partial: false,
                  fromAggregate: true,
                ));
              }
              return AsyncValue.error(Exception('denied'), StackTrace.empty);
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
        reason: 'the resolved group must still render its row',
      );
      expect(
        find.descendant(of: sheet, matching: find.text('Mountain Pals')),
        findsNothing,
        reason: 'the errored group has no known lines to render as a row',
      );
      expect(
        find.descendant(
          of: sheet,
          matching: find.byKey(HomeKeys.heroBreakdownIncompleteNotice),
        ),
        findsOneWidget,
        reason: 'the errored group must not silently read as settled',
      );
    },
  );
}
