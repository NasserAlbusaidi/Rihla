import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:safar/core/providers/settings_provider.dart';
import 'package:safar/features/events/models/event_model.dart';
import 'package:safar/features/events/providers/event_provider.dart';
import 'package:safar/features/groups/models/group_member_model.dart';
import 'package:safar/features/groups/models/group_model.dart';
import 'package:safar/features/groups/providers/group_provider.dart';
import 'package:safar/features/groups/screens/group_detail_screen.dart';
import 'package:safar/features/ledger/models/expense_model.dart';
import 'package:safar/features/ledger/providers/expense_provider.dart';

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
    participantNames: const {
      'uid-creator': 'Alice',
      'uid-member': 'Bob',
    },
    modules: EventModules.forType(type),
    startDate: startDate,
    endDate: endDate,
    currency: 'OMR',
    createdAt: DateTime(2026, 3, 1),
    bridgeTripId: id, // same as id for simplicity
  );
}

/// Wraps widget in ProviderScope with all required provider overrides.
///
/// Overrides:
/// - [sharedPreferencesProvider] for settings
/// - [groupDetailProvider] returns [_testGroup]
/// - [groupMembersProvider] returns [_testMembers]
/// - [groupEventsProvider] returns the supplied [events]
/// - [tripExpensesProvider] returns an empty list for all trip IDs
Widget _wrap(
  Widget child,
  SharedPreferences prefs, {
  List<Event> events = const [],
}) {
  return ProviderScope(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      groupDetailProvider(_groupId).overrideWith(
        (ref) => Stream.value(_testGroup),
      ),
      groupMembersProvider(_groupId).overrideWith(
        (ref) => Stream.value(_testMembers),
      ),
      groupEventsProvider(_groupId).overrideWith(
        (ref) => Stream.value(events),
      ),
      // Override tripExpensesProvider for every event's bridgeTripId so
      // EventCard does not try to open real SQLite (offlineRepositoryProvider).
      for (final event in events)
        tripExpensesProvider(event.bridgeTripId).overrideWith(
          (ref) => Stream.value(const []),
        ),
    ],
    child: MaterialApp(home: child),
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

      // Both event names should appear in the card list
      expect(find.text('Beach Trip'), findsOneWidget);
      expect(find.text('Mountain Hike'), findsOneWidget);
    });

    testWidgets('shows empty state when no events', (tester) async {
      await tester.pumpWidget(
        _wrap(const GroupDetailScreen(groupId: _groupId), prefs),
      );
      await tester.pumpAndSettle();

      // Empty state matching Copywriting Contract
      expect(find.text('No events yet'), findsOneWidget);
      expect(
        find.text(
          'Tap the + button to create the first event for this group.',
        ),
        findsOneWidget,
      );
    });

    testWidgets('shows event count chip when events exist', (tester) async {
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

      // Count chip shows the integer count of events
      expect(find.text('2'), findsOneWidget);
    });

    testWidgets('does not show count chip when no events', (tester) async {
      await tester.pumpWidget(
        _wrap(const GroupDetailScreen(groupId: _groupId), prefs),
      );
      await tester.pumpAndSettle();

      // No count chip when events list is empty
      // The "Events" section header is still shown
      expect(find.text('Events'), findsOneWidget);
      // But no count chip with numeric text like '0' next to it
      // (chip only appears when events.isNotEmpty per plan spec)
      expect(find.text('0'), findsNothing);
    });

    testWidgets('dims past events with 0.6 opacity', (tester) async {
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

      // The card still renders (it's tappable behind the opacity)
      expect(find.text('Old Trip'), findsOneWidget);

      // Verify Opacity widget with 0.6 is present in the tree
      final opacityWidgets = tester.widgetList<Opacity>(find.byType(Opacity));
      expect(
        opacityWidgets.any((o) => o.opacity == 0.6),
        isTrue,
        reason: 'Past event should be wrapped in Opacity(0.6)',
      );
    });

    testWidgets('shows FAB for creating events', (tester) async {
      await tester.pumpWidget(
        _wrap(const GroupDetailScreen(groupId: _groupId), prefs),
      );
      await tester.pumpAndSettle();

      // FAB should be visible
      expect(find.byType(FloatingActionButton), findsOneWidget);
    });

    test(
      'tapping event card navigates to EventCommandCenter',
      () {},
      skip: 'Awaiting Plan 03-04: EventCard navigation',
    );
  });

  group('EventCard financial total', () {
    testWidgets('shows total spent from bridge trip expenses', (tester) async {
      final event = _makeEvent(id: 'evt-money', name: 'Expensive Trip');

      // Override tripExpensesProvider for this specific event to return expenses
      final testExpense = Expense(
        id: 'exp-1',
        tripId: event.bridgeTripId,
        payerParticipantId: 'uid-creator',
        amount: Decimal.parse('25.500'),
        scope: ExpenseScope.global,
        createdAt: DateTime(2026, 3, 1),
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            sharedPreferencesProvider.overrideWithValue(prefs),
            groupDetailProvider(_groupId).overrideWith(
              (ref) => Stream.value(_testGroup),
            ),
            groupMembersProvider(_groupId).overrideWith(
              (ref) => Stream.value(_testMembers),
            ),
            groupEventsProvider(_groupId).overrideWith(
              (ref) => Stream.value([event]),
            ),
            tripExpensesProvider(event.bridgeTripId).overrideWith(
              (ref) => Stream.value([testExpense]),
            ),
          ],
          child: MaterialApp(home: const GroupDetailScreen(groupId: _groupId)),
        ),
      );
      await tester.pumpAndSettle();

      // Total spent should be formatted with 3 decimal places and currency
      expect(find.text('25.500 OMR'), findsOneWidget);
    });

    testWidgets('shows 0.000 OMR when bridge trip has no expenses',
        (tester) async {
      final event = _makeEvent(id: 'evt-zero', name: 'Free Trip');

      await tester.pumpWidget(
        _wrap(
          const GroupDetailScreen(groupId: _groupId),
          prefs,
          events: [event],
        ),
      );
      await tester.pumpAndSettle();

      // Zero total with correct formatting
      expect(find.text('0.000 OMR'), findsOneWidget);
    });
  });
}
