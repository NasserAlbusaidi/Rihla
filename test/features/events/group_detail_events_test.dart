import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:safar/core/theme/app_theme.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:safar/core/providers/settings_provider.dart';
import 'package:safar/features/events/models/event_model.dart';
import 'package:safar/features/groups/keys/group_keys.dart';
import 'package:safar/features/events/providers/event_provider.dart';
import 'package:safar/features/groups/models/group_member_model.dart';
import 'package:safar/features/groups/models/group_model.dart';
import 'package:safar/features/groups/providers/group_balance_provider.dart';
import 'package:safar/features/groups/providers/group_provider.dart';
import 'package:safar/features/groups/screens/group_detail_screen.dart';
import 'package:safar/features/ledger/models/expense_model.dart';
import 'package:safar/features/ledger/providers/expense_provider.dart';
import 'package:safar/l10n/generated/app_localizations.dart';

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

const _groupId = 'group-test-1';

final _testGroup = Group(
  id: _groupId,
  name: 'Events Test Crew',
  inviteCode: 'EVT123',
  createdBy: 'uid-creator',
  memberIds: const ['uid-creator', 'uid-member'],
  currency: 'OMR',
  createdAt: DateTime(2026, 1, 1),
);

final _testMembers = [
  GroupMember(
    id: 'mem-1',
    groupId: _groupId,
    userId: 'uid-creator',
    displayName: 'Alice',
    role: 'CREATOR',
    joinedAt: DateTime(2026, 1, 1),
  ),
  GroupMember(
    id: 'mem-2',
    groupId: _groupId,
    userId: 'uid-member',
    displayName: 'Bob',
    role: 'MEMBER',
    joinedAt: DateTime(2026, 1, 2),
  ),
];

/// Creates a minimal test Event with sensible defaults.
Event _makeEvent({
  String id = 'evt-1',
  String name = 'Test Trip',
  EventType type = EventType.trip,
  List<String>? participantIds,
  DateTime? startDate,
  DateTime? endDate,
}) {
  return Event(
    id: id,
    name: name,
    type: type,
    groupId: _groupId,
    createdBy: 'uid-creator',
    participantIds: participantIds ?? const ['uid-creator', 'uid-member'],
    participantNames: const {'uid-creator': 'Alice', 'uid-member': 'Bob'},
    modules: EventModules.forType(type),
    startDate: startDate,
    endDate: endDate,
    createdAt: DateTime(2026, 3, 1),
  );
}

/// Returns the EventRef for an event.
EventRef _eventRef(Event event) => (groupId: event.groupId, eventId: event.id);

/// Creates a GoRouter for GroupDetailScreen tests with stub event hub route.
GoRouter _makeRouter({required String groupId}) {
  return GoRouter(
    initialLocation: '/group/$groupId',
    routes: [
      GoRoute(
        path: '/group/:gid',
        builder: (_, state) => const GroupDetailScreen(groupId: _groupId),
        routes: [
          GoRoute(
            path: 'settings',
            builder: (_, state) => Scaffold(
              body: Text('GroupSettings:${state.pathParameters['gid']}'),
            ),
          ),
          GoRoute(
            path: 'settle-up',
            builder: (_, state) => Scaffold(
              body: Text('GroupSettleUp:${state.pathParameters['gid']}'),
            ),
          ),
          GoRoute(
            path: 'activity',
            builder: (_, state) => Scaffold(
              body: Text('GroupActivity:${state.pathParameters['gid']}'),
            ),
          ),
          GoRoute(
            path: 'create-event',
            builder: (_, state) => Scaffold(
              body: Text('CreateEvent:${state.pathParameters['gid']}'),
            ),
          ),
          GoRoute(
            path: 'create-event/:type',
            builder: (_, state) => Scaffold(
              body: Text('CreateEventTyped:${state.pathParameters['type']}'),
            ),
          ),
          GoRoute(
            path: 'event/:eid',
            builder: (_, state) =>
                Scaffold(body: Text('EventHub:${state.pathParameters['eid']}')),
            routes: [
              GoRoute(
                path: 'ledger',
                builder: (_, state) => Scaffold(
                  body: Text('Ledger:${state.pathParameters['eid']}'),
                ),
              ),
            ],
          ),
        ],
      ),
    ],
  );
}

/// Wraps widget in ProviderScope with all required provider overrides.
///
/// Overrides:
/// - [sharedPreferencesProvider] for settings
/// - [currentUserIdProvider] returns the creator UID to avoid Firebase initialization
/// - [groupDetailProvider] returns [_testGroup]
/// - [groupMembersProvider] returns [_testMembers]
/// - [groupEventsProvider] returns the supplied [events]
/// - [eventExpensesProvider] returns an empty list for all event IDs
/// - [groupBalancesProvider] returns zero balances
/// - [groupActivityProvider] returns empty list
Widget _wrap(
  Widget child,
  SharedPreferences prefs, {
  List<Event> events = const [],
  String? currentUserId = 'uid-creator',
}) {
  final router = _makeRouter(groupId: _groupId);
  return ProviderScope(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      currentUserIdProvider.overrideWithValue(currentUserId),
      groupDetailProvider(
        _groupId,
      ).overrideWith((ref) => Stream.value(_testGroup)),
      groupMembersProvider(
        _groupId,
      ).overrideWith((ref) => Stream.value(_testMembers)),
      groupEventsProvider(_groupId).overrideWith((ref) => Stream.value(events)),
      groupBalancesProvider(_groupId).overrideWith(
        (ref) => const AsyncValue.data((
          balances: <String, List<UserBalance>>{},
          totalSpent: <String, Decimal>{},
          eventCount: 0,
          perEventBreakdown: <String, Map<String, Map<String, Decimal>>>{},
          memberNames: <String, String>{},
          memberRawNames: <String, String>{},
        )),
      ),
      groupActivityProvider(
        _groupId,
      ).overrideWith((ref) => Stream.value(const [])),
      // Override eventExpensesProvider for every event so
      // EventCard does not try to open real Firestore.
      for (final event in events)
        eventExpensesProvider(
          _eventRef(event),
        ).overrideWith((ref) => Stream.value(const [])),
    ],
    child: MaterialApp.router(
      theme: AppTheme.lightTheme,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      routerConfig: router,
    ),
  );
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  late SharedPreferences prefs;

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({'device_name': 'Test User'});
    prefs = await SharedPreferences.getInstance();
  });

  group('GroupDetailScreen Events Section', () {
    testWidgets('shows event cards when events exist', (tester) async {
      final events = [
        _makeEvent(id: 'evt-1', name: 'Beach Trip'),
        _makeEvent(id: 'evt-2', name: 'Mountain Hike', type: EventType.camping),
      ];

      await tester.pumpWidget(
        _wrap(
          const GroupDetailScreen(groupId: _groupId),
          prefs,
          events: events,
        ),
      );
      await tester.pumpAndSettle();

      // Both event names should appear in the card list.
      // findsWidgets because the card renders the name in multiple Text widgets.
      expect(find.text('Beach Trip'), findsWidgets);
      expect(find.text('Mountain Hike'), findsWidgets);
    });

    testWidgets('shows empty state when no events', (tester) async {
      await tester.pumpWidget(
        _wrap(const GroupDetailScreen(groupId: _groupId), prefs),
      );
      await tester.pumpAndSettle();

      // Empty state — verified via widget key
      expect(find.byKey(GroupKeys.noEventsEmpty), findsOneWidget);
    });

    testWidgets('events section header has no duplicate New event action', (
      tester,
    ) async {
      final events = [
        _makeEvent(id: 'evt-1', name: 'Trip A'),
        _makeEvent(id: 'evt-2', name: 'Trip B'),
      ];

      await tester.pumpWidget(
        _wrap(
          const GroupDetailScreen(groupId: _groupId),
          prefs,
          events: events,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(GroupKeys.eventsSection), findsOneWidget);
      // #486: the only "New event" is the hero CTA — the section header action
      // was removed to dedupe the two ~40px-apart entries.
      expect(find.text('New event'), findsOneWidget);
      expect(find.byKey(GroupKeys.eventsCountChip), findsNothing);
    });

    testWidgets('does not show count chip when no events', (tester) async {
      await tester.pumpWidget(
        _wrap(const GroupDetailScreen(groupId: _groupId), prefs),
      );
      await tester.pumpAndSettle();

      // No count chip when events list is empty
      // The "Events" section header is still shown
      expect(find.byKey(GroupKeys.eventsSection), findsOneWidget);
      // Count chip only appears when events.isNotEmpty per plan spec
      expect(find.byKey(GroupKeys.eventsCountChip), findsNothing);
    });

    testWidgets('event rows render', (tester) async {
      final events = [
        _makeEvent(id: 'evt-1', name: 'Beach Trip'),
        _makeEvent(id: 'evt-2', name: 'Mountain Hike', type: EventType.camping),
      ];

      await tester.pumpWidget(
        _wrap(
          const GroupDetailScreen(groupId: _groupId),
          prefs,
          events: events,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Beach Trip'), findsWidgets);
      expect(find.text('Mountain Hike'), findsWidgets);
    });

    testWidgets('past events remain visible with their date label', (
      tester,
    ) async {
      // A past event has endDate before today
      final pastEvent = _makeEvent(
        id: 'evt-past',
        name: 'Old Trip',
        endDate: DateTime(2020, 1, 1), // in the past
      );

      await tester.pumpWidget(
        _wrap(
          const GroupDetailScreen(groupId: _groupId),
          prefs,
          events: [pastEvent],
        ),
      );
      await tester.pumpAndSettle();

      // The card still renders (it's tappable behind the opacity).
      // findsWidgets because the card renders the name in multiple Text widgets.
      expect(find.text('Old Trip'), findsWidgets);
      expect(find.text('ends Jan 1'), findsOneWidget);
    });

    testWidgets('shows event creation actions without a FAB', (tester) async {
      await tester.pumpWidget(
        _wrap(const GroupDetailScreen(groupId: _groupId), prefs),
      );
      await tester.pumpAndSettle();

      expect(find.byType(FloatingActionButton), findsNothing);
      expect(find.text('New event'), findsOneWidget);
      expect(find.text('Create event'), findsOneWidget);
    });

    testWidgets('tapping event card navigates to EventHub route', (
      tester,
    ) async {
      final event = _makeEvent(id: 'evt-tap', name: 'Tap Navigation Trip');

      await tester.pumpWidget(
        _wrap(
          const GroupDetailScreen(groupId: _groupId),
          prefs,
          events: [event],
        ),
      );
      await tester.pumpAndSettle();

      await tester.scrollUntilVisible(
        find.text('Tap Navigation Trip').first,
        100,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Tap Navigation Trip'));
      await tester.pumpAndSettle();

      expect(find.text('EventHub:evt-tap'), findsOneWidget);
    });
  });
}
