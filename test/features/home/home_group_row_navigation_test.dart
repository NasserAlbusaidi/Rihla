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
import 'package:safar/features/events/models/event_model.dart';
import 'package:safar/features/events/providers/event_provider.dart';
import 'package:safar/features/groups/keys/group_keys.dart';
import 'package:safar/features/groups/models/group_member_model.dart';
import 'package:safar/features/groups/models/group_model.dart';
import 'package:safar/features/groups/providers/group_balance_provider.dart';
import 'package:safar/features/groups/providers/group_provider.dart';
import 'package:safar/features/groups/screens/group_detail_screen.dart';
import 'package:safar/features/home/providers/dashboard_providers.dart';
import 'package:safar/features/home/screens/home_screen.dart';
import 'package:safar/features/ledger/models/expense_model.dart';
import 'package:safar/l10n/generated/app_localizations.dart';

const _uid = 'test-user-id';

Group _makeGroup(String id, String name) => Group(
  id: id,
  name: name,
  inviteCode: 'ABC123',
  createdBy: _uid,
  memberIds: const [_uid],
  currency: 'OMR',
  createdAt: DateTime(2026, 1, 1),
);

Event _makeEvent({required String id, required String groupId}) => Event(
  id: id,
  name: 'Event $id',
  type: EventType.trip,
  groupId: groupId,
  createdBy: _uid,
  participantIds: const [_uid],
  participantNames: const {_uid: 'Traveler'},
  modules: const EventModules(),
  isClosed: false,
  createdAt: DateTime(2026, 1, 2),
);

List<Override> _baseOverrides({
  required SharedPreferences prefs,
  required List<Group> groups,
}) => [
  sharedPreferencesProvider.overrideWithValue(prefs),
  currentUserIdProvider.overrideWithValue(_uid),
  linkedEmailProvider.overrideWithValue('secured@example.com'),
  isDurableUserProvider.overrideWithValue(true),
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
];

GoRouter _flatRouter() {
  return GoRouter(
    initialLocation: '/home',
    routes: [
      GoRoute(path: '/home', builder: (_, _) => const HomeScreen()),
      GoRoute(
        path: '/create-group',
        builder: (_, _) => const Scaffold(body: Text('CreateGroupRoute')),
      ),
      GoRoute(
        path: '/join-group',
        builder: (_, _) => const Scaffold(body: Text('JoinGroupRoute')),
      ),
      GoRoute(
        path: '/group/:gid',
        builder: (_, state) =>
            Scaffold(body: Text('GroupOverview:${state.pathParameters['gid']}')),
      ),
      GoRoute(
        path: '/group/:gid/event/:eid',
        builder: (_, state) => Scaffold(
          body: Text(
            'EventHub:${state.pathParameters['gid']}/${state.pathParameters['eid']}',
          ),
        ),
      ),
      GoRoute(
        path: '/activity',
        builder: (_, _) => const Scaffold(body: Text('ActivityRoute')),
      ),
      GoRoute(
        path: '/profile',
        builder: (_, _) => const Scaffold(body: Text('ProfileRoute')),
      ),
    ],
  );

}

Widget _buildApp(List<Override> overrides, {GoRouter? router}) {
  return ProviderScope(
    overrides: overrides,
    child: MaterialApp.router(
      theme: AppTheme.lightTheme,
      routerConfig: router ?? _flatRouter(),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
    ),
  );
}

Future<void> _tapGroupRow(WidgetTester tester, String name) async {
  final finder = find.text(name);
  // The active-journeys strip pushes the groups sliver below the fold when
  // an open event exists — scroll the lazily-built SliverList into view
  // rather than assuming a fixed drag distance (#807-style).
  await tester.scrollUntilVisible(
    finder,
    260,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

void main() {
  late SharedPreferences prefs;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
  });

  group('HomeScreen group row smart-forward (PR-5 §2, #900)', () {
    testWidgets(
      '(a) exactly one open event → row push forwards straight to the '
      'event hub',
      (tester) async {
        final group = _makeGroup('g1', 'Desert Crew');
        await tester.pumpWidget(
          _buildApp([
            ..._baseOverrides(prefs: prefs, groups: [group]),
            groupEventsProvider(
              'g1',
            ).overrideWith((ref) => Stream.value([_makeEvent(id: 'e1', groupId: 'g1')])),
          ]),
        );
        await tester.pumpAndSettle();

        await _tapGroupRow(tester, 'Desert Crew');

        expect(find.text('EventHub:g1/e1'), findsOneWidget);
        expect(find.text('GroupOverview:g1'), findsNothing);
      },
    );

    testWidgets(
      '(b) two open events → row push stays on the group overview',
      (tester) async {
        final group = _makeGroup('g1', 'Desert Crew');
        await tester.pumpWidget(
          _buildApp([
            ..._baseOverrides(prefs: prefs, groups: [group]),
            groupEventsProvider('g1').overrideWith(
              (ref) => Stream.value([
                _makeEvent(id: 'e1', groupId: 'g1'),
                _makeEvent(id: 'e2', groupId: 'g1'),
              ]),
            ),
          ]),
        );
        await tester.pumpAndSettle();

        await _tapGroupRow(tester, 'Desert Crew');

        expect(find.text('GroupOverview:g1'), findsOneWidget);
        expect(find.textContaining('EventHub:'), findsNothing);
      },
    );

    testWidgets(
      '(c) zero open events → row push stays on the group overview',
      (tester) async {
        final group = _makeGroup('g1', 'Desert Crew');
        await tester.pumpWidget(
          _buildApp([
            ..._baseOverrides(prefs: prefs, groups: [group]),
            groupEventsProvider('g1').overrideWith((ref) => Stream.value(const [])),
          ]),
        );
        await tester.pumpAndSettle();

        await _tapGroupRow(tester, 'Desert Crew');

        expect(find.text('GroupOverview:g1'), findsOneWidget);
        expect(find.textContaining('EventHub:'), findsNothing);
      },
    );

    testWidgets(
      '(d) unresolved event stream → fails safe to the group overview, '
      'never forwards on partial data',
      (tester) async {
        final group = _makeGroup('g1', 'Desert Crew');
        final neverResolves = StreamController<List<Event>>();
        addTearDown(neverResolves.close);
        await tester.pumpWidget(
          _buildApp([
            ..._baseOverrides(prefs: prefs, groups: [group]),
            groupEventsProvider('g1').overrideWith((ref) => neverResolves.stream),
          ]),
        );
        await tester.pumpAndSettle();

        await _tapGroupRow(tester, 'Desert Crew');

        expect(find.text('GroupOverview:g1'), findsOneWidget);
        expect(find.textContaining('EventHub:'), findsNothing);
      },
    );

    testWidgets(
      '(e) sole-open-event forward → one Back lands the group overview, '
      'a second Back returns home (#996)',
      (tester) async {
        final group = _makeGroup('g1', 'Desert Crew');
        final router = _flatRouter();
        addTearDown(router.dispose);
        await tester.pumpWidget(
          _buildApp([
            ..._baseOverrides(prefs: prefs, groups: [group]),
            groupEventsProvider('g1').overrideWith(
              (ref) => Stream.value([_makeEvent(id: 'e1', groupId: 'g1')]),
            ),
          ], router: router),
        );
        await tester.pumpAndSettle();

        await _tapGroupRow(tester, 'Desert Crew');
        expect(find.text('EventHub:g1/e1'), findsOneWidget);

        router.pop();
        await tester.pumpAndSettle();
        expect(find.text('GroupOverview:g1'), findsOneWidget);
        expect(find.textContaining('EventHub:'), findsNothing);

        router.pop();
        await tester.pumpAndSettle();
        expect(find.text('GroupOverview:g1'), findsNothing);
        expect(find.byType(HomeScreen), findsOneWidget);
      },
    );

    testWidgets(
      '(f) two-open-events tap stacks NOTHING beneath the overview — one '
      'Back returns straight home (#996 else-branch guard)',
      (tester) async {
        final group = _makeGroup('g1', 'Desert Crew');
        final router = _flatRouter();
        addTearDown(router.dispose);
        await tester.pumpWidget(
          _buildApp([
            ..._baseOverrides(prefs: prefs, groups: [group]),
            groupEventsProvider('g1').overrideWith(
              (ref) => Stream.value([
                _makeEvent(id: 'e1', groupId: 'g1'),
                _makeEvent(id: 'e2', groupId: 'g1'),
              ]),
            ),
          ], router: router),
        );
        await tester.pumpAndSettle();

        await _tapGroupRow(tester, 'Desert Crew');
        expect(find.text('GroupOverview:g1'), findsOneWidget);

        router.pop();
        await tester.pumpAndSettle();
        expect(find.text('GroupOverview:g1'), findsNothing);
        expect(find.byType(HomeScreen), findsOneWidget);
      },
    );

    testWidgets(
      '(g) NESTED route tree — the forward composes to exactly '
      '[home, overview, hub]; two Backs walk hub → overview → home (#996 '
      'defense-in-depth: proves no duplicate ancestor materializes)',
      (tester) async {
        final group = _makeGroup('g1', 'Desert Crew');
        final router = GoRouter(
          initialLocation: '/home',
          routes: [
            GoRoute(path: '/home', builder: (_, _) => const HomeScreen()),
            GoRoute(
              path: '/group/:gid',
              builder: (_, state) => Scaffold(
                body: Text('GroupOverview:${state.pathParameters['gid']}'),
              ),
              routes: [
                GoRoute(
                  path: 'event/:eid',
                  builder: (_, state) => Scaffold(
                    body: Text(
                      'EventHub:${state.pathParameters['gid']}/'
                      '${state.pathParameters['eid']}',
                    ),
                  ),
                ),
              ],
            ),
          ],
        );
        addTearDown(router.dispose);
        await tester.pumpWidget(
          _buildApp([
            ..._baseOverrides(prefs: prefs, groups: [group]),
            groupEventsProvider('g1').overrideWith(
              (ref) => Stream.value([_makeEvent(id: 'e1', groupId: 'g1')]),
            ),
          ], router: router),
        );
        await tester.pumpAndSettle();

        await _tapGroupRow(tester, 'Desert Crew');
        expect(find.text('EventHub:g1/e1'), findsOneWidget);

        router.pop();
        await tester.pumpAndSettle();
        expect(find.text('GroupOverview:g1'), findsOneWidget);
        expect(find.textContaining('EventHub:'), findsNothing);

        router.pop();
        await tester.pumpAndSettle();
        expect(find.text('GroupOverview:g1'), findsNothing);
        expect(find.byType(HomeScreen), findsOneWidget);
      },
    );
  });

  group('Cold deep-link to /group/:gid regression (PR-5 §2, #900)', () {
    // Regression: smart-forwarding is a HOME-ROW tap decision only, never a
    // router redirect. A cold deep-link to /group/:gid must still render the
    // overview — even for a group whose sole event WOULD forward from the
    // home row — and the existing #243 back-guard must be untouched.
    testWidgets(
      'still renders the overview for a sole-open-event group and honors '
      'the PopScope→/home back guard',
      (tester) async {
        const groupId = 'group-1';
        SharedPreferences.setMockInitialValues({'device_name': 'Alice'});
        final directPrefs = await SharedPreferences.getInstance();

        final testGroup = Group(
          id: groupId,
          name: 'Adventure Crew',
          inviteCode: 'ABC123',
          createdBy: 'uid-creator',
          memberIds: const ['uid-creator'],
          createdAt: DateTime(2026, 1, 1),
        );
        final members = [
          GroupMember(
            id: 'member-1',
            groupId: groupId,
            userId: 'uid-creator',
            displayName: 'Alice',
            role: 'CREATOR',
            joinedAt: DateTime(2026, 1, 1),
          ),
        ];
        final soleOpenEvent = _makeEvent(id: 'event-1', groupId: groupId);
        final balances = (
          balances: <String, List<UserBalance>>{},
          totalSpent: <String, Decimal>{},
          eventCount: 1,
          perEventBreakdown: <String, Map<String, Map<String, Decimal>>>{},
          memberNames: <String, String>{'uid-creator': 'Alice'},
          memberRawNames: <String, String>{},
        );

        final router = GoRouter(
          initialLocation: '/group/$groupId',
          routes: [
            GoRoute(
              path: '/home',
              builder: (_, _) => const Scaffold(body: Text('Home')),
            ),
            GoRoute(
              path: '/group/:gid',
              builder: (_, state) =>
                  GroupDetailScreen(groupId: state.pathParameters['gid']!),
              routes: [
                GoRoute(
                  path: 'event/:eid',
                  builder: (_, state) => Scaffold(
                    body: Text(
                      'EventHub:${state.pathParameters['gid']}/'
                      '${state.pathParameters['eid']}',
                    ),
                  ),
                ),
              ],
            ),
          ],
        );
        addTearDown(router.dispose);

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              sharedPreferencesProvider.overrideWithValue(directPrefs),
              currentUserIdProvider.overrideWithValue('uid-creator'),
              groupDetailProvider(
                groupId,
              ).overrideWith((ref) => Stream.value(testGroup)),
              groupMembersProvider(
                groupId,
              ).overrideWith((ref) => Stream.value(members)),
              groupEventsProvider(
                groupId,
              ).overrideWith((ref) => Stream.value([soleOpenEvent])),
              groupBalancesProvider(
                groupId,
              ).overrideWith((ref) => AsyncValue.data(balances)),
              groupActivityProvider(
                groupId,
              ).overrideWith((ref) => Stream.value(const [])),
            ],
            child: MaterialApp.router(
              theme: AppTheme.lightTheme,
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              routerConfig: router,
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.byKey(GroupKeys.detailScreen), findsOneWidget);
        expect(find.textContaining('EventHub:'), findsNothing);

        final popScope = tester.widget<PopScope>(
          find.byWidgetPredicate((widget) => widget is PopScope),
        );
        popScope.onPopInvokedWithResult!(false, null);
        await tester.pumpAndSettle();

        expect(find.text('Home'), findsOneWidget);
        expect(find.byKey(GroupKeys.detailScreen), findsNothing);
      },
    );
  });
}
