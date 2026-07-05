import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:safar/features/events/keys/event_keys.dart';
import 'package:safar/features/events/models/event_model.dart';
import 'package:safar/features/events/providers/event_provider.dart';
import 'package:safar/features/events/screens/event_command_center.dart';
import 'package:safar/features/groups/models/group_member_model.dart';
import 'package:safar/features/groups/models/group_model.dart';
import 'package:safar/features/groups/providers/group_balance_provider.dart';
import 'package:safar/features/groups/providers/group_provider.dart';
import 'package:safar/features/ledger/providers/expense_provider.dart';
import 'package:safar/features/search/keys/search_keys.dart';
import 'package:safar/features/search/screens/search_screen.dart';
import 'package:safar/features/search/utils/search_match.dart';
import 'package:safar/l10n/generated/app_localizations.dart';
import 'package:safar/core/theme/app_theme.dart';
import 'package:safar/shared/widgets/r_amount.dart';

/// #900 friction #3 — PR-5b Global `/search`. Gate-cleared spec:
/// `docs/plans/2026-07-05-falaj-pr5b-search-spec.md`.
///
/// Covers the full test plan: back-guard (system-back gesture + app-bar
/// button, cold and warm entry), the R1-fix data source (closed events stay
/// findable + carry the `searchEventEnded` badge), the §2 smart-forward
/// contract duplicated on the group row, event-tap routing to a real working
/// hub (closed → Recap available), `?q=` seeding vs the hint/empty states,
/// the case-insensitive match predicate (EN + AR), the visible scope label,
/// the absence of any expense content, and the absence of the bottom-nav
/// shell (this is a pushed top-level route, never a tab).
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

Event _makeEvent({
  required String id,
  required String groupId,
  required String name,
  bool isClosed = false,
  List<String> participantIds = const [_uid],
}) => Event(
  id: id,
  name: name,
  type: EventType.trip,
  groupId: groupId,
  createdBy: _uid,
  participantIds: participantIds,
  participantNames: {for (final p in participantIds) p: 'Traveler'},
  modules: const EventModules(),
  isClosed: isClosed,
  createdAt: DateTime(2026, 1, 2),
);

GroupMember _member(String userId, String groupId, String displayName) =>
    GroupMember(
      id: userId,
      groupId: groupId,
      userId: userId,
      displayName: displayName,
      role: 'CREATOR',
      joinedAt: DateTime(2026, 1, 1),
    );

List<Override> _baseOverrides({
  required List<Group> groups,
  Map<String, List<Event>> eventsByGroup = const {},
  Map<String, Stream<List<Event>>> streamOverridesByGroup = const {},
}) => [
  currentUserIdProvider.overrideWithValue(_uid),
  userGroupsProvider.overrideWith((ref) => Stream.value(groups)),
  for (final group in groups)
    groupEventsProvider(group.id).overrideWith(
      (ref) =>
          streamOverridesByGroup[group.id] ??
          Stream.value(eventsByGroup[group.id] ?? const <Event>[]),
    ),
];

Future<GoRouter> _pumpSearch(
  WidgetTester tester,
  List<Override> overrides, {
  String initialLocation = '/search',
}) async {
  final router = GoRouter(
    initialLocation: initialLocation,
    routes: [
      GoRoute(
        path: '/home',
        builder: (_, _) => const Scaffold(body: Text('Home')),
      ),
      GoRoute(
        path: '/search',
        builder: (_, state) =>
            SearchScreen(query: state.uri.queryParameters['q']),
      ),
      GoRoute(
        path: '/group/:gid',
        builder: (_, state) => Scaffold(
          body: Text('GroupOverview:${state.pathParameters['gid']}'),
        ),
      ),
      GoRoute(
        path: '/group/:gid/event/:eid',
        builder: (_, state) => Scaffold(
          body: Text(
            'EventHub:${state.pathParameters['gid']}/'
            '${state.pathParameters['eid']}',
          ),
        ),
      ),
    ],
  );
  addTearDown(router.dispose);

  await tester.pumpWidget(
    ProviderScope(
      overrides: overrides,
      child: MaterialApp.router(
        theme: AppTheme.lightTheme,
        routerConfig: router,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
      ),
    ),
  );
  await tester.pumpAndSettle();
  return router;
}

void main() {
  group('match predicate (case-insensitive substring, PR-5b spec)', () {
    test('EN: case-insensitive substring matches', () {
      expect(matchesSearchQuery('Desert Crew', 'desert'), isTrue);
      expect(matchesSearchQuery('Desert Crew', 'DESERT'), isTrue);
      expect(matchesSearchQuery('Desert Crew', 'Crew'), isTrue);
      expect(matchesSearchQuery('Desert Crew', 'zzz'), isFalse);
    });

    test('AR: exact substring matches (no diacritic folding in v1)', () {
      expect(matchesSearchQuery('رحلة الصحراء', 'الصحراء'), isTrue);
      expect(matchesSearchQuery('رحلة الصحراء', 'صحراء'), isTrue);
      expect(matchesSearchQuery('رحلة الصحراء', 'جبل'), isFalse);
    });
  });

  group('back-guard (Gate R1 P1 fix — GroupDetailScreen precedent)', () {
    testWidgets(
      'cold entry: system-back gesture (PopScope) lands /home',
      (tester) async {
        await _pumpSearch(
          tester,
          _baseOverrides(groups: const []),
          initialLocation: '/search',
        );

        expect(find.byKey(SearchKeys.screen), findsOneWidget);

        final popScope = tester.widget<PopScope>(
          find.byWidgetPredicate((widget) => widget is PopScope),
        );
        popScope.onPopInvokedWithResult!(false, null);
        await tester.pumpAndSettle();

        expect(find.text('Home'), findsOneWidget);
        expect(find.byKey(SearchKeys.screen), findsNothing);
      },
    );

    testWidgets('cold entry: app-bar back button lands /home', (
      tester,
    ) async {
      await _pumpSearch(
        tester,
        _baseOverrides(groups: const []),
        initialLocation: '/search',
      );

      await tester.tap(find.byTooltip('Back'));
      await tester.pumpAndSettle();

      expect(find.text('Home'), findsOneWidget);
      expect(find.byKey(SearchKeys.screen), findsNothing);
    });

    testWidgets('warm push: back returns to the origin route', (
      tester,
    ) async {
      final router = await _pumpSearch(
        tester,
        _baseOverrides(groups: const []),
        initialLocation: '/home',
      );

      unawaited(router.push('/search'));
      await tester.pumpAndSettle();
      expect(find.byKey(SearchKeys.screen), findsOneWidget);

      await tester.tap(find.byTooltip('Back'));
      await tester.pumpAndSettle();

      expect(find.text('Home'), findsOneWidget);
      expect(find.byKey(SearchKeys.screen), findsNothing);
    });
  });

  group('data source (Gate R1 P1 fix — closed events stay findable)', () {
    testWidgets(
      'a CLOSED event matching q appears in results with the Ended badge',
      (tester) async {
        final group = _makeGroup('g1', 'Desert Crew');
        final closedEvent = _makeEvent(
          id: 'e1',
          groupId: 'g1',
          name: 'Wadi Shab Trip',
          isClosed: true,
        );

        await _pumpSearch(
          tester,
          _baseOverrides(
            groups: [group],
            eventsByGroup: {'g1': [closedEvent]},
          ),
          initialLocation: '/search?q=Wadi',
        );

        expect(find.text('Wadi Shab Trip'), findsOneWidget);
        expect(find.text('Ended'), findsOneWidget);
        // Parent-group subtitle (Gate R2 rubric fix — cross-group
        // disambiguation).
        expect(find.text('Desert Crew'), findsOneWidget);
      },
    );

    testWidgets('an open event matching q renders without the Ended badge', (
      tester,
    ) async {
      final group = _makeGroup('g1', 'Desert Crew');
      final openEvent = _makeEvent(
        id: 'e1',
        groupId: 'g1',
        name: 'Wadi Shab Trip',
      );

      await _pumpSearch(
        tester,
        _baseOverrides(groups: [group], eventsByGroup: {'g1': [openEvent]}),
        initialLocation: '/search?q=Wadi',
      );

      expect(find.text('Wadi Shab Trip'), findsOneWidget);
      expect(find.text('Ended'), findsNothing);
    });
  });

  group('group tap smart-forward contract (#900 §2, duplicated inline)', () {
    testWidgets(
      '(a) exactly one open event → forwards straight to the event hub',
      (tester) async {
        final group = _makeGroup('g1', 'Desert Crew');
        await _pumpSearch(
          tester,
          _baseOverrides(
            groups: [group],
            eventsByGroup: {
              'g1': [_makeEvent(id: 'e1', groupId: 'g1', name: 'Trip')],
            },
          ),
          initialLocation: '/search?q=Desert',
        );

        await tester.tap(find.text('Desert Crew'));
        await tester.pumpAndSettle();

        expect(find.text('EventHub:g1/e1'), findsOneWidget);
        expect(find.text('GroupOverview:g1'), findsNothing);
      },
    );

    testWidgets('(b) two open events → stays on the group overview', (
      tester,
    ) async {
      final group = _makeGroup('g1', 'Desert Crew');
      await _pumpSearch(
        tester,
        _baseOverrides(
          groups: [group],
          eventsByGroup: {
            'g1': [
              _makeEvent(id: 'e1', groupId: 'g1', name: 'Trip 1'),
              _makeEvent(id: 'e2', groupId: 'g1', name: 'Trip 2'),
            ],
          },
        ),
        initialLocation: '/search?q=Desert',
      );

      await tester.tap(find.text('Desert Crew'));
      await tester.pumpAndSettle();

      expect(find.text('GroupOverview:g1'), findsOneWidget);
      expect(find.textContaining('EventHub:'), findsNothing);
    });

    testWidgets('(c) zero open events → stays on the group overview', (
      tester,
    ) async {
      final group = _makeGroup('g1', 'Desert Crew');
      await _pumpSearch(
        tester,
        _baseOverrides(groups: [group], eventsByGroup: {'g1': const []}),
        initialLocation: '/search?q=Desert',
      );

      await tester.tap(find.text('Desert Crew'));
      await tester.pumpAndSettle();

      expect(find.text('GroupOverview:g1'), findsOneWidget);
      expect(find.textContaining('EventHub:'), findsNothing);
    });

    testWidgets(
      '(d) unresolved event stream → fails safe to the group overview',
      (tester) async {
        final group = _makeGroup('g1', 'Desert Crew');
        final neverResolves = StreamController<List<Event>>();
        addTearDown(neverResolves.close);

        await _pumpSearch(
          tester,
          _baseOverrides(
            groups: [group],
            streamOverridesByGroup: {'g1': neverResolves.stream},
          ),
          initialLocation: '/search?q=Desert',
        );

        await tester.tap(find.text('Desert Crew'));
        await tester.pumpAndSettle();

        expect(find.text('GroupOverview:g1'), findsOneWidget);
        expect(find.textContaining('EventHub:'), findsNothing);
      },
    );
  });

  group('event tap lands a working hub (closed → Recap tab available)', () {
    testWidgets(
      'tapping a closed event search result renders the real event hub '
      'with the Recap tab',
      (tester) async {
        const groupId = 'g1';
        const eventId = 'e1';
        final group = _makeGroup(groupId, 'Desert Crew');
        final closedEvent = _makeEvent(
          id: eventId,
          groupId: groupId,
          name: 'Wadi Shab Trip',
          isClosed: true,
        );
        const eventRef = (groupId: groupId, eventId: eventId);

        final router = GoRouter(
          initialLocation: '/search?q=Wadi',
          routes: [
            GoRoute(
              path: '/search',
              builder: (_, state) =>
                  SearchScreen(query: state.uri.queryParameters['q']),
            ),
            GoRoute(
              path: '/group/:gid',
              builder: (_, state) => Scaffold(
                body: Text('GroupOverview:${state.pathParameters['gid']}'),
              ),
              routes: [
                GoRoute(
                  path: 'event/:eid',
                  builder: (_, state) => EventCommandCenter(
                    groupId: state.pathParameters['gid']!,
                    eventId: state.pathParameters['eid']!,
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
              currentUserIdProvider.overrideWithValue(_uid),
              userGroupsProvider.overrideWith((ref) => Stream.value([group])),
              groupEventsProvider(
                groupId,
              ).overrideWith((ref) => Stream.value([closedEvent])),
              eventDetailProvider(
                eventRef,
              ).overrideWith((_) => Stream.value(closedEvent)),
              groupDetailProvider(
                groupId,
              ).overrideWith((_) => Stream.value(group)),
              eventExpensesProvider(
                eventRef,
              ).overrideWith((_) => Stream.value(const [])),
              eventSettlementsProvider(
                eventRef,
              ).overrideWith((_) => Stream.value(const [])),
              groupMembersProvider(groupId).overrideWith(
                (_) => Stream.value([_member(_uid, groupId, 'Traveler')]),
              ),
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

        await tester.tap(find.text('Wadi Shab Trip'));
        await tester.pumpAndSettle();

        expect(find.text('GroupOverview:$groupId'), findsNothing);
        expect(find.byKey(EventKeys.tabRecap), findsOneWidget);
      },
    );
  });

  group('q seeding + hint vs empty states', () {
    testWidgets('?q= seeds the field', (tester) async {
      await _pumpSearch(
        tester,
        _baseOverrides(groups: const []),
        initialLocation: '/search?q=Alps',
      );

      final field = tester.widget<TextField>(find.byKey(SearchKeys.field));
      expect(field.controller!.text, 'Alps');
    });

    testWidgets('absent q → hint state, no empty-state, no scope label', (
      tester,
    ) async {
      await _pumpSearch(
        tester,
        _baseOverrides(groups: const []),
        initialLocation: '/search',
      );

      final field = tester.widget<TextField>(find.byKey(SearchKeys.field));
      expect(field.decoration!.hintText, 'Search groups and events');
      expect(find.byKey(SearchKeys.emptyState), findsNothing);
      expect(find.byKey(SearchKeys.scopeLabel), findsNothing);
    });

    testWidgets('non-empty q with zero matches → searchEmpty (static)', (
      tester,
    ) async {
      final group = _makeGroup('g1', 'Desert Crew');
      await _pumpSearch(
        tester,
        _baseOverrides(groups: [group], eventsByGroup: {'g1': const []}),
        initialLocation: '/search?q=NoSuchThing',
      );

      expect(find.byKey(SearchKeys.emptyState), findsOneWidget);
      expect(find.text('No matches'), findsOneWidget);
      expect(find.byKey(SearchKeys.scopeLabel), findsNothing);
    });
  });

  group('scope label, expense-free scope, no bottom-nav', () {
    testWidgets(
      'results render the scope label, no expense content, no bottom-nav',
      (tester) async {
        final group = _makeGroup('g1', 'Desert Crew');
        await _pumpSearch(
          tester,
          _baseOverrides(
            groups: [group],
            eventsByGroup: {
              'g1': [_makeEvent(id: 'e1', groupId: 'g1', name: 'Trip')],
            },
          ),
          initialLocation: '/search?q=Desert',
        );

        expect(find.byKey(SearchKeys.scopeLabel), findsOneWidget);
        expect(
          find.text('Groups and events, including past events'),
          findsOneWidget,
        );
        // Option-B v1 scope: no expense/settlement content anywhere.
        expect(find.byType(RAmount), findsNothing);
        // Pushed top-level route — never rendered as a BottomNavShell tab.
        expect(find.byType(NavigationBar), findsNothing);
      },
    );

    testWidgets('an Arabic group name matches an Arabic substring query', (
      tester,
    ) async {
      final group = _makeGroup('g1', 'مجموعة الصحراء');
      await _pumpSearch(
        tester,
        _baseOverrides(groups: [group]),
        initialLocation: '/search?q=%D8%A7%D9%84%D8%B5%D8%AD%D8%B1%D8%A7%D8%A1',
      );

      expect(find.text('مجموعة الصحراء'), findsOneWidget);
    });
  });
}
