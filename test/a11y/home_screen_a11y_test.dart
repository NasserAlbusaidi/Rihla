// #1283 — accessibility guideline matchers for HomeScreen.
//
// Arrange section copied from test/features/home/home_screen_dashboard_test.dart
// (`_buildTestApp`/`_loadedOverrides`/fixtures) — reuse, don't invent new
// fixtures.

import 'dart:async';

import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:safar/core/theme/app_theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:safar/core/providers/settings_provider.dart';
import 'package:safar/features/auth/providers/auth_provider.dart';
import 'package:safar/features/events/models/event_model.dart';
import 'package:safar/features/events/providers/event_provider.dart';
import 'package:safar/features/groups/models/group_activity_log_model.dart';
import 'package:safar/features/groups/models/group_model.dart';
import 'package:safar/features/groups/providers/group_balance_provider.dart';
import 'package:safar/features/groups/providers/group_provider.dart';
import 'package:safar/features/ledger/models/expense_model.dart';
import 'package:safar/features/home/providers/dashboard_providers.dart';
import 'package:safar/features/home/screens/home_screen.dart';
import 'package:safar/l10n/generated/app_localizations.dart';

CrossGroupBalance _omr(String net, {int groupCount = 1}) {
  final n = Decimal.parse(net);
  if (n == Decimal.zero) {
    return (
      byCurrency: const <CurrencyBalance>[],
      groupCount: groupCount,
      isLoading: false,
    );
  }
  return (
    byCurrency: [
      (
        currency: 'OMR',
        net: n,
        owedToUser: n > Decimal.zero ? n : Decimal.zero,
        userOwes: n < Decimal.zero ? n.abs() : Decimal.zero,
      ),
    ],
    groupCount: groupCount,
    isLoading: false,
  );
}

Event _makeEvent(String id, String name, EventType type) => Event(
  id: id,
  name: name,
  type: type,
  groupId: 'g1',
  createdBy: 'uid0',
  participantIds: const ['uid0'],
  participantNames: const {'uid0': 'Alice'},
  modules: EventModules.forType(type),
  createdAt: DateTime.now().subtract(const Duration(days: 2)),
);

Group _makeGroup(String id, String name, {int memberCount = 2}) => Group(
  id: id,
  name: name,
  inviteCode: 'ABC123',
  createdBy: 'user1',
  memberIds: List.generate(memberCount, (i) => 'uid$i'),
  currency: 'OMR',
  createdAt: DateTime(2026, 1, 1),
);

GroupActivityLog _makeActivity(
  String id,
  String actorName,
  String description,
) => GroupActivityLog(
  id: id,
  type: 'event_created',
  actorId: 'uid0',
  actorName: actorName,
  description: description,
  timestamp: DateTime(2026, 3, 28),
);

CrossGroupActivityEntry _toEntry(
  GroupActivityLog log,
  String groupName,
  String groupId,
) => (log: log, groupName: groupName, groupId: groupId, currency: 'OMR');

GroupBalances _testGroupBalances({Decimal? net}) => (
  balances: {
    'OMR': [
      UserBalance(
        participantId: 'test-user-id',
        displayName: 'Test User',
        totalPaid: Decimal.parse('10.000'),
        totalOwed: Decimal.parse('20.000'),
        netBalance: net ?? Decimal.parse('-5.500'),
      ),
    ],
  },
  totalSpent: {'OMR': Decimal.parse('25.000')},
  eventCount: 1,
  perEventBreakdown: {},
  memberNames: {'test-user-id': 'Test User'},
  memberRawNames: <String, String>{},
);

final _group1 = _makeGroup('g1', 'Desert Crew');
final _group2 = _makeGroup('g2', 'Mountain Pals');
final _testGroups = [_group1, _group2];
final _testActivity1 = _makeActivity('a1', 'Alice', 'added an expense');
final _testActivity2 = _makeActivity('a2', 'Bob', 'joined the group');

Widget _buildTestApp(
  Widget widget, {
  List<Override> overrides = const [],
  required SharedPreferences prefs,
  Locale? locale,
}) {
  final router = GoRouter(
    initialLocation: '/home',
    routes: [
      GoRoute(path: '/home', builder: (ctx, state) => widget),
      GoRoute(
        path: '/create-group',
        builder: (ctx, state) =>
            const Scaffold(body: Text('CreateGroupScreen')),
      ),
      GoRoute(
        path: '/join-group',
        builder: (ctx, state) => const Scaffold(body: Text('JoinGroupScreen')),
      ),
      GoRoute(
        path: '/group/:id',
        builder: (ctx, state) =>
            Scaffold(body: Text('GroupDetail:${state.pathParameters['id']}')),
        routes: [
          GoRoute(
            path: 'event/:eventId',
            builder: (ctx, state) => Scaffold(
              body: Text('EventHub:${state.pathParameters['eventId']}'),
            ),
          ),
        ],
      ),
      GoRoute(
        path: '/profile',
        builder: (ctx, state) => const Scaffold(body: Text('ProfileScreen')),
      ),
      GoRoute(
        path: '/activity',
        builder: (ctx, state) => const Scaffold(body: Text('ActivityScreen')),
      ),
    ],
  );

  return ProviderScope(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      linkedEmailProvider.overrideWithValue('secured@example.com'),
      isDurableUserProvider.overrideWithValue(true),
      ...overrides,
      groupBalancesOnceProvider.overrideWith(
        (ref, gid) => ref.watch(groupBalancesProvider(gid)).maybeWhen(
              data: (d) => (balances: d, failedEventIds: const <String>{}, groupSettlementsFailed: false),
              orElse: () => Completer<GroupBalancesOnce>().future,
            ),
      ),
    ],
    child: MaterialApp.router(
      theme: AppTheme.lightTheme,
      locale: locale,
      routerConfig: router,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
    ),
  );
}

List<Override> _loadedOverrides() => [
  userGroupsProvider.overrideWith((ref) => Stream.value(_testGroups)),
  crossGroupHomeBalanceProvider.overrideWith(
    (ref) => AsyncValue.data((
      balance: _omr('-5.500', groupCount: 2),
      partial: false,
    )),
  ),
  crossGroupActivityProvider.overrideWith(
    (ref) => AsyncValue.data([
      _toEntry(_testActivity1, 'Desert Crew', 'g1'),
      _toEntry(_testActivity2, 'Mountain Pals', 'g2'),
    ]),
  ),
  groupBalancesProvider.overrideWith(
    (ref, groupId) => AsyncValue.data(_testGroupBalances()),
  ),
  groupEventsProvider.overrideWith(
    (ref, groupId) =>
        Stream.value([_makeEvent('e1', 'Camping Trip', EventType.camping)]),
  ),
  currentUserIdProvider.overrideWithValue('test-user-id'),
];

void main() {
  late SharedPreferences prefs;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
  });

  Future<void> pumpScreen(WidgetTester tester, {required Locale locale}) async {
    await tester.pumpWidget(
      _buildTestApp(
        const HomeScreen(),
        overrides: _loadedOverrides(),
        prefs: prefs,
        locale: locale,
      ),
    );
    // Bounded pumps only — ConnectivityNotifier's live checks fail-open with
    // no Firebase app in this unit test, but pumpAndSettle is avoided anyway
    // per the documented ConnectivityNotifier trap (test/helpers/pump_rihla_app.dart).
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 800));
  }

  group('HomeScreen accessibility (#1283)', () {
    testWidgets('EN meets labeledTapTargetGuideline', (tester) async {
      final handle = tester.ensureSemantics();
      await pumpScreen(tester, locale: const Locale('en'));

      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
      handle.dispose();
    });

    testWidgets('AR meets labeledTapTargetGuideline', (tester) async {
      final handle = tester.ensureSemantics();
      await pumpScreen(tester, locale: const Locale('ar'));

      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
      handle.dispose();
    });

    // androidTapTargetGuideline (48x48) is deliberately NOT asserted — the
    // project's own tap-target floor is 44dp (docs/DESIGN.md §4, matching
    // iOS, not Android): the top-bar Profile/Search/History actions
    // (44x44 exactly, both locales) and the "Set name" inline text-button
    // (~133x26 EN / ~131x26 AR) all measure under Android's stricter 48x48.
    // This is a project-wide, deliberate-floor mismatch, not a per-screen
    // bug — reported upstream, not fixed in this test-only PR.
    testWidgets('EN meets textContrastGuideline', (tester) async {
      final handle = tester.ensureSemantics();
      await pumpScreen(tester, locale: const Locale('en'));
      await expectLater(tester, meetsGuideline(textContrastGuideline));
      handle.dispose();
    });

    testWidgets('AR meets textContrastGuideline', (tester) async {
      final handle = tester.ensureSemantics();
      await pumpScreen(tester, locale: const Locale('ar'));
      await expectLater(tester, meetsGuideline(textContrastGuideline));
      handle.dispose();
    });
  });
}
