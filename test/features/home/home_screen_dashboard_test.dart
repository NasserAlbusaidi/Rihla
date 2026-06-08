import 'dart:async';

import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:safar/core/theme/app_theme.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:safar/core/providers/settings_provider.dart';
import 'package:safar/features/events/models/event_model.dart';
import 'package:safar/features/events/providers/event_provider.dart';
import 'package:safar/features/groups/models/group_activity_log_model.dart';
import 'package:safar/features/groups/models/group_model.dart';
import 'package:safar/features/groups/providers/group_balance_provider.dart';
import 'package:safar/features/groups/providers/group_provider.dart';
import 'package:safar/features/ledger/models/expense_model.dart';
import 'package:safar/features/home/keys/home_keys.dart';
import 'package:safar/features/home/providers/dashboard_providers.dart';
import 'package:safar/features/home/screens/home_screen.dart';
import 'package:safar/features/home/widgets/balance_hero_card.dart';
import 'package:safar/features/home/widgets/activity_row.dart';
import 'package:safar/features/home/widgets/journey_ticket_card.dart';
import 'package:safar/l10n/generated/app_localizations.dart';

// ---------------------------------------------------------------------------
// Test helpers
// ---------------------------------------------------------------------------

/// #261: single-OMR-currency [CrossGroupBalance] from a net string (owed/owes
/// derived; zero net → empty byCurrency = all-settled).
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

Event _makeEvent(
  String id,
  String name,
  EventType type, {
  DateTime? createdAt,
}) => Event(
  id: id,
  name: name,
  type: type,
  groupId: 'g1',
  createdBy: 'uid0',
  participantIds: ['uid0'],
  participantNames: {'uid0': 'Alice'},
  modules: EventModules.forType(type),
  createdAt: createdAt ?? DateTime.now().subtract(const Duration(days: 2)),
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

Widget _buildTestApp(
  Widget widget, {
  List<Override> overrides = const [],
  required SharedPreferences prefs,
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
      ...overrides,
      // #104: the home dashboard now reads the one-shot balance variants.
      // Bridge them to whatever the live providers were overridden to, so the
      // existing per-test data/loading overrides keep driving the UI. A
      // never-completing future preserves the loading-state assertions.
      // #244: once-providers now yield wrapper records; bridge as non-partial.
      crossGroupBalanceOnceProvider.overrideWith(
        (ref) => ref.watch(crossGroupBalanceProvider).maybeWhen(
              data: (d) => (balance: d, partial: false),
              orElse: () => Completer<CrossGroupBalanceOnce>().future,
            ),
      ),
      groupBalancesOnceProvider.overrideWith(
        (ref, gid) => ref.watch(groupBalancesProvider(gid)).maybeWhen(
              data: (d) => (balances: d, failedEventIds: const <String>{}),
              orElse: () => Completer<GroupBalancesOnce>().future,
            ),
      ),
    ],
    child: MaterialApp.router(
      theme: AppTheme.lightTheme,
      routerConfig: router,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
    ),
  );
}

// ---------------------------------------------------------------------------
// Shared test data
// ---------------------------------------------------------------------------

final _group1 = _makeGroup('g1', 'Desert Crew');
final _group2 = _makeGroup('g2', 'Mountain Pals');

final _testGroups = [_group1, _group2];

final _testActivity1 = _makeActivity('a1', 'Alice', 'added an expense');
final _testActivity2 = _makeActivity('a2', 'Bob', 'joined the group');

CrossGroupActivityEntry _toEntry(
  GroupActivityLog log,
  String groupName,
  String groupId,
) => (log: log, groupName: groupName, groupId: groupId, currency: 'OMR');

/// Minimal GroupBalances with a known user balance so tests can verify
/// personal balance display.
GroupBalances _testGroupBalances({Decimal? net}) => (
  balances: [
    UserBalance(
      participantId: 'test-user-id',
      displayName: 'Test User',
      totalPaid: Decimal.parse('10.000'),
      totalOwed: Decimal.parse('20.000'),
      netBalance: net ?? Decimal.parse('-5.500'),
    ),
  ],
  totalSpent: Decimal.parse('25.000'),
  eventCount: 1,
  perEventBreakdown: {},
  memberNames: {'test-user-id': 'Test User'},
  memberRawNames: <String, String>{},
);

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

List<Override> _loadedOverrides() => [
  userGroupsProvider.overrideWith((ref) => Stream.value(_testGroups)),
  crossGroupBalanceProvider.overrideWith(
    (ref) => AsyncValue.data(_omr('-5.500', groupCount: 2)),
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

  group('HomeScreen dashboard - loaded state', () {
    testWidgets('Test 1: renders BalanceHeroCard widget', (tester) async {
      await tester.pumpWidget(
        _buildTestApp(
          const HomeScreen(),
          overrides: _loadedOverrides(),
          prefs: prefs,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(BalanceHeroCard), findsOneWidget);
    });

    testWidgets('Test 2: renders active JourneyTicketCard widgets', (
      tester,
    ) async {
      await tester.pumpWidget(
        _buildTestApp(
          const HomeScreen(),
          overrides: _loadedOverrides(),
          prefs: prefs,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(JourneyTicketCard), findsNWidgets(2));
      expect(find.text('Camping Trip'), findsWidgets);
    });

    testWidgets('Test 3: renders inline group rows from userGroupsProvider', (
      tester,
    ) async {
      await tester.pumpWidget(
        _buildTestApp(
          const HomeScreen(),
          overrides: _loadedOverrides(),
          prefs: prefs,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Groups'), findsOneWidget);
      expect(find.text('Desert Crew'), findsOneWidget);
      expect(find.text('Mountain Pals'), findsOneWidget);
    });

    testWidgets('Test 4: renders ActivityRow widgets for activity entries', (
      tester,
    ) async {
      await tester.pumpWidget(
        _buildTestApp(
          const HomeScreen(),
          overrides: _loadedOverrides(),
          prefs: prefs,
        ),
      );
      await tester.pumpAndSettle();

      await tester.drag(find.byType(CustomScrollView), const Offset(0, -600));
      await tester.pumpAndSettle();

      expect(find.byType(ActivityRow), findsWidgets);
    });
  });

  group('HomeScreen dashboard - empty state', () {
    List<Override> emptyOverrides() => [
      userGroupsProvider.overrideWith((ref) => Stream.value([])),
      crossGroupBalanceProvider.overrideWith(
        (ref) => AsyncValue.data(_omr('0', groupCount: 0)),
      ),
      crossGroupActivityProvider.overrideWith(
        (ref) => const AsyncValue.data([]),
      ),
      groupBalancesProvider.overrideWith(
        (ref, groupId) => const AsyncValue.loading(),
      ),
      groupEventsProvider.overrideWith((ref, groupId) => Stream.value([])),
      currentUserIdProvider.overrideWithValue('test-user-id'),
    ];

    testWidgets(
      'Test 5: shows EmptyStateView with "Start your first group" text',
      (tester) async {
        await tester.pumpWidget(
          _buildTestApp(
            const HomeScreen(),
            overrides: emptyOverrides(),
            prefs: prefs,
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('Start your first group'), findsOneWidget);
      },
    );

    testWidgets(
      'Test 6: empty state EmptyStateView has CTA button "Create Group"',
      (tester) async {
        await tester.pumpWidget(
          _buildTestApp(
            const HomeScreen(),
            overrides: emptyOverrides(),
            prefs: prefs,
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('Create Group'), findsOneWidget);
      },
    );
  });

  group('HomeScreen dashboard - error state', () {
    List<Override> errorOverrides() => [
      userGroupsProvider.overrideWith(
        (ref) => Stream.error(Exception('Network error')),
      ),
      crossGroupBalanceProvider.overrideWith(
        (ref) => AsyncValue.data(_omr('0', groupCount: 0)),
      ),
      crossGroupActivityProvider.overrideWith(
        (ref) => const AsyncValue.data([]),
      ),
      groupBalancesProvider.overrideWith(
        (ref, groupId) => const AsyncValue.loading(),
      ),
      groupEventsProvider.overrideWith((ref, groupId) => Stream.value([])),
      currentUserIdProvider.overrideWithValue('test-user-id'),
    ];

    testWidgets('Test 7: error state renders "Something went wrong" heading', (
      tester,
    ) async {
      await tester.pumpWidget(
        _buildTestApp(
          const HomeScreen(),
          overrides: errorOverrides(),
          prefs: prefs,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Something went wrong'), findsOneWidget);
    });

    testWidgets('Test 8: error state has "Retry" CTA button', (tester) async {
      await tester.pumpWidget(
        _buildTestApp(
          const HomeScreen(),
          overrides: errorOverrides(),
          prefs: prefs,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Retry'), findsOneWidget);
    });
  });

  group('HomeScreen dashboard - bottom navigation', () {
    List<Override> navOverrides() => [
      userGroupsProvider.overrideWith((ref) => Stream.value([_group1])),
      crossGroupBalanceProvider.overrideWith(
        (ref) => AsyncValue.data(_omr('0', groupCount: 1)),
      ),
      crossGroupActivityProvider.overrideWith(
        (ref) => const AsyncValue.data([]),
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
      currentUserIdProvider.overrideWithValue('test-user-id'),
    ];

    testWidgets('Test 9: bottom nav shows 3 tabs (Groups, Activity, Profile)', (
      tester,
    ) async {
      await tester.pumpWidget(
        _buildTestApp(
          const HomeScreen(),
          overrides: navOverrides(),
          prefs: prefs,
        ),
      );
      await tester.pumpAndSettle();

      final navBar = tester.widget<NavigationBar>(find.byType(NavigationBar));
      expect(navBar.destinations, hasLength(3));
      expect(find.text('Groups'), findsWidgets);
      expect(find.text('Activity'), findsWidgets);
      expect(find.text('Profile'), findsWidgets);
      expect(find.text('Chats'), findsNothing);
    });

    testWidgets('Test 10: tapping Profile tab shows ProfileScreen (Phase 25)', (
      tester,
    ) async {
      await tester.pumpWidget(
        _buildTestApp(
          const HomeScreen(),
          overrides: navOverrides(),
          prefs: prefs,
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(HomeKeys.bottomNavProfile));
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pumpAndSettle();

      final navBar = tester.widget<NavigationBar>(find.byType(NavigationBar));
      expect(navBar.selectedIndex, 2);
      expect(find.text('Coming soon'), findsNothing);
    });
  });

  group('HomeScreen dashboard - group row balance display (NAV-04)', () {
    testWidgets(
      'Test 11: group row shows personal balance text, not totalSpent',
      (tester) async {
        final groups = [_makeGroup('g1', 'Desert Crew')];

        await tester.pumpWidget(
          _buildTestApp(
            const HomeScreen(),
            prefs: prefs,
            overrides: [
              userGroupsProvider.overrideWith((ref) => Stream.value(groups)),
              crossGroupBalanceProvider.overrideWith(
                (ref) => AsyncValue.data(_omr('-5.500', groupCount: 1)),
              ),
              crossGroupActivityProvider.overrideWith(
                (ref) => const AsyncValue.data([]),
              ),
              groupBalancesProvider.overrideWith(
                (ref, groupId) => AsyncValue.data(
                  _testGroupBalances(net: Decimal.parse('-10.000')),
                ),
              ),
              groupEventsProvider.overrideWith(
                (ref, groupId) => Stream.value([]),
              ),
              currentUserIdProvider.overrideWithValue('test-user-id'),
            ],
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('you owe'), findsAtLeastNWidgets(1));
      },
    );

    testWidgets('Test 12: group row navigates via GoRouter (NAV-04)', (
      tester,
    ) async {
      final groups = [_makeGroup('gABC', 'Friends')];

      await tester.pumpWidget(
        _buildTestApp(
          const HomeScreen(),
          prefs: prefs,
          overrides: [
            userGroupsProvider.overrideWith((ref) => Stream.value(groups)),
            crossGroupBalanceProvider.overrideWith(
              (ref) => AsyncValue.data(_omr('0', groupCount: 1)),
            ),
            crossGroupActivityProvider.overrideWith(
              (ref) => const AsyncValue.data([]),
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
            groupEventsProvider.overrideWith(
              (ref, groupId) => Stream.value([]),
            ),
            currentUserIdProvider.overrideWithValue('test-user-id'),
          ],
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Friends'));
      await tester.pumpAndSettle();

      expect(find.text('GroupDetail:gABC'), findsOneWidget);
    });
  });

  group('HomeScreen dashboard - section header (Phase 24)', () {
    testWidgets(
      'Test NEW-3: "Groups" section header renders above group rows',
      (tester) async {
        // _loadedOverrides() provides 2 groups
        await tester.pumpWidget(
          _buildTestApp(
            const HomeScreen(),
            overrides: _loadedOverrides(),
            prefs: prefs,
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('Groups'), findsOneWidget);
      },
    );
  });

  group('HomeScreen dashboard - journey and group enrichment', () {
    List<Override> enrichmentOverrides({List<Event>? events}) => [
      userGroupsProvider.overrideWith(
        (ref) => Stream.value([_makeGroup('g1', 'Desert Crew')]),
      ),
      crossGroupBalanceProvider.overrideWith(
        (ref) => AsyncValue.data(_omr('0', groupCount: 1)),
      ),
      crossGroupActivityProvider.overrideWith(
        (ref) => const AsyncValue.data([]),
      ),
      groupBalancesProvider.overrideWith(
        (ref, groupId) => AsyncValue.data(_testGroupBalances()),
      ),
      groupEventsProvider.overrideWith(
        (ref, groupId) => Stream.value(events ?? []),
      ),
      currentUserIdProvider.overrideWithValue('test-user-id'),
    ];

    testWidgets('Test A: active journey ticket renders latest event name', (
      tester,
    ) async {
      await tester.pumpWidget(
        _buildTestApp(
          const HomeScreen(),
          prefs: prefs,
          overrides: enrichmentOverrides(
            events: [_makeEvent('e1', 'Camping Trip', EventType.camping)],
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(JourneyTicketCard), findsOneWidget);
      expect(find.text('Camping Trip'), findsOneWidget);
    });

    testWidgets('Test C: group row shows event count from group balances', (
      tester,
    ) async {
      await tester.pumpWidget(
        _buildTestApp(
          const HomeScreen(),
          prefs: prefs,
          overrides: enrichmentOverrides(
            events: [_makeEvent('e1', 'Camping Trip', EventType.camping)],
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.drag(find.byType(CustomScrollView), const Offset(0, -500));
      await tester.pumpAndSettle();

      expect(find.textContaining('1 event'), findsOneWidget);
    });

    testWidgets('Test D: active journey ticket routes to the event hub', (
      tester,
    ) async {
      await tester.pumpWidget(
        _buildTestApp(
          const HomeScreen(),
          prefs: prefs,
          overrides: enrichmentOverrides(
            events: [
              _makeEvent(
                'e1',
                'Beach Day',
                EventType.nightDayOut,
                createdAt: DateTime.now().subtract(const Duration(hours: 3)),
              ),
            ],
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byType(JourneyTicketCard));
      await tester.pumpAndSettle();

      expect(find.text('EventHub:e1'), findsOneWidget);
    });

    testWidgets('Test E: no active events shows empty journey strip copy', (
      tester,
    ) async {
      await tester.pumpWidget(
        _buildTestApp(
          const HomeScreen(),
          prefs: prefs,
          overrides: enrichmentOverrides(events: []),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('No upcoming or active journeys'), findsOneWidget);
    });

    testWidgets('Test F: empty events still keep the group row visible', (
      tester,
    ) async {
      await tester.pumpWidget(
        _buildTestApp(
          const HomeScreen(),
          prefs: prefs,
          overrides: enrichmentOverrides(),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Desert Crew'), findsOneWidget);
      expect(find.textContaining('1 event'), findsOneWidget);
    });
  });

  group('HomeScreen dashboard - settings subscription (#107)', () {
    testWidgets(
      'greeting reacts to deviceName change (.select targets the right field)',
      (tester) async {
        await tester.pumpWidget(
          _buildTestApp(
            const HomeScreen(),
            overrides: _loadedOverrides(),
            prefs: prefs,
          ),
        );
        await tester.pumpAndSettle();

        // Empty prefs => blank deviceName => greeting uses the fallback name.
        expect(find.textContaining('RUA'), findsNothing);

        final container = ProviderScope.containerOf(
          tester.element(find.byType(HomeScreen)),
        );
        await container.read(settingsProvider.notifier).setDeviceName('Rua');
        await tester.pumpAndSettle();

        // settingsProvider.select((s) => s.deviceName) must still rebuild the
        // greeting when deviceName changes — guards against selecting the
        // wrong field while narrowing the subscription.
        expect(find.textContaining('RUA'), findsOneWidget);
      },
    );
  });
}
