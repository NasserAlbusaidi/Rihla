import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:safar/features/events/models/event_model.dart';
import 'package:safar/features/events/models/event_type_config.dart';
import 'package:safar/features/events/screens/event_command_center.dart';
import 'package:safar/features/gear/providers/gear_provider.dart';
import 'package:safar/features/groups/models/group_model.dart';
import 'package:safar/features/ledger/models/expense_model.dart';
import 'package:safar/features/ledger/providers/expense_provider.dart';
import 'package:safar/features/logistics/providers/sub_group_provider.dart';
import 'package:safar/features/trip/models/trip_model.dart';
import 'package:safar/features/trip/providers/trip_provider.dart';
import 'package:safar/features/vault/providers/document_provider.dart';

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/// Stub group used across tests.
final _testGroup = Group(
  id: 'group-1',
  name: 'Adventure Crew',
  inviteCode: 'ABC123',
  createdBy: 'uid-creator',
  memberIds: const ['uid-creator'],
  currency: 'OMR',
  createdAt: DateTime(2026, 1, 1),
);

/// Creates a minimal test Event with sensible defaults.
Event _makeEvent({
  String id = 'evt-1',
  String name = 'Summer Trip',
  EventType type = EventType.trip,
  EventModules? modules,
}) {
  return Event(
    id: id,
    name: name,
    type: type,
    groupId: 'group-1',
    createdBy: 'uid-creator',
    participantIds: const ['uid-creator'],
    participantNames: const {'uid-creator': 'Alice'},
    modules: modules ?? EventModules.forType(type),
    currency: 'OMR',
    createdAt: DateTime(2026, 3, 1),
    bridgeTripId: id,
  );
}

/// Returns all necessary provider overrides for an EventCommandCenter test.
///
/// These overrides prevent SQLite and Supabase initialization errors by
/// returning empty in-memory values for all data providers.
List<Override> _providerOverrides(String tripId, {List<Expense> expenses = const []}) {
  return [
    // Core expense/balance providers (always watched by EventModuleList)
    tripExpensesProvider(tripId).overrideWith(
      (ref) => Stream.value(expenses),
    ),
    tripBalancesProvider(tripId).overrideWith(
      (ref) async => <UserBalance>[],
    ),
    // currentParticipantProvider is a Provider.family (not StreamProvider)
    // Override it by watching a fixed value.
    currentParticipantProvider(tripId).overrideWith(
      (ref) => null,
    ),
    // Module-specific providers (conditionally watched in EventModuleList
    // based on event.modules, but overriding all prevents init errors)
    tripGearProvider(tripId).overrideWith(
      (ref) => Stream.value(const []),
    ),
    tripSubGroupsProvider(tripId).overrideWith(
      (ref) => Stream.value(const []),
    ),
    tripDocumentsProvider(tripId).overrideWith(
      (ref) => Stream.value(const []),
    ),
  ];
}

/// Wraps [EventCommandCenter] in a minimal ProviderScope+MaterialApp.
Widget _wrapEventHub({
  required Event event,
  required Group group,
  List<Expense> expenses = const [],
}) {
  return ProviderScope(
    overrides: _providerOverrides(event.bridgeTripId, expenses: expenses),
    child: MaterialApp(
      home: EventCommandCenter(event: event, group: group),
    ),
  );
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  group('EventCommandCenter', () {
    testWidgets('shows event name in header', (tester) async {
      final event = _makeEvent(name: 'Desert Camping Weekend');

      await tester.pumpWidget(
        _wrapEventHub(event: event, group: _testGroup),
      );
      await tester.pumpAndSettle();

      expect(find.text('Desert Camping Weekend'), findsOneWidget);
    });

    testWidgets('shows event type label in subtitle', (tester) async {
      final event = _makeEvent(type: EventType.camping);
      final config = EventTypeConfig.forType(EventType.camping);

      await tester.pumpWidget(
        _wrapEventHub(event: event, group: _testGroup),
      );
      await tester.pumpAndSettle();

      // Subtitle combines type label and group name via middle dot
      expect(find.textContaining(config.label), findsAtLeastNWidgets(1));
    });

    testWidgets('shows group name in header subtitle', (tester) async {
      final event = _makeEvent(type: EventType.trip);

      await tester.pumpWidget(
        _wrapEventHub(event: event, group: _testGroup),
      );
      await tester.pumpAndSettle();

      expect(find.textContaining(_testGroup.name), findsAtLeastNWidgets(1));
    });

    testWidgets('shows all 5 module cards for Trip type', (tester) async {
      // Trip type: ledger + gear + logistics + vault + memories
      final event = _makeEvent(type: EventType.trip);

      await tester.pumpWidget(
        _wrapEventHub(event: event, group: _testGroup),
      );
      await tester.pumpAndSettle();

      expect(find.text('Ledger'), findsOneWidget);
      expect(find.text('Gear'), findsOneWidget);
      expect(find.text('Logistics'), findsOneWidget);
      expect(find.text('Vault'), findsOneWidget);
      expect(find.text('Memories'), findsOneWidget);
    });

    testWidgets('shows only Ledger card for Night/Day Out type', (tester) async {
      // Night/Day Out: ledger only — no other modules
      final event = _makeEvent(type: EventType.nightDayOut);

      await tester.pumpWidget(
        _wrapEventHub(event: event, group: _testGroup),
      );
      await tester.pumpAndSettle();

      expect(find.text('Ledger'), findsOneWidget);
      expect(find.text('Gear'), findsNothing);
      expect(find.text('Logistics'), findsNothing);
      expect(find.text('Vault'), findsNothing);
      expect(find.text('Memories'), findsNothing);
    });

    testWidgets(
        'shows Ledger, Gear, Logistics, Memories for Camping type (no Vault)',
        (tester) async {
      // Camping: ledger + gear + logistics + memories, no vault
      final event = _makeEvent(type: EventType.camping);

      await tester.pumpWidget(
        _wrapEventHub(event: event, group: _testGroup),
      );
      await tester.pumpAndSettle();

      expect(find.text('Ledger'), findsOneWidget);
      expect(find.text('Gear'), findsOneWidget);
      expect(find.text('Logistics'), findsOneWidget);
      expect(find.text('Memories'), findsOneWidget);
      expect(find.text('Vault'), findsNothing);
    });

    testWidgets(
        'hides Ledger when event.modules.ledger is false (Custom type toggle)',
        (tester) async {
      // Custom event with ledger explicitly off per D-14
      final event = _makeEvent(
        type: EventType.custom,
        modules: const EventModules(
          ledger: false,
          gear: true,
          logistics: false,
          vault: false,
          memories: false,
        ),
      );

      await tester.pumpWidget(
        _wrapEventHub(event: event, group: _testGroup),
      );
      await tester.pumpAndSettle();

      expect(find.text('Ledger'), findsNothing);
      expect(find.text('Gear'), findsOneWidget);
    });

    testWidgets('FAB is visible on screen', (tester) async {
      final event = _makeEvent();

      await tester.pumpWidget(
        _wrapEventHub(event: event, group: _testGroup),
      );
      await tester.pumpAndSettle();

      expect(find.byType(FloatingActionButton), findsOneWidget);
    });

    testWidgets(
        'expense summary hero renders without error via bridge trip ID',
        (tester) async {
      // Verifies the Trip facade is correctly passed to ExpenseSummaryHero
      // and the widget renders without throwing (providers are wired correctly).
      final event = _makeEvent(id: 'evt-money', name: 'Funded Trip');

      final testExpense = Expense(
        id: 'exp-1',
        tripId: event.bridgeTripId,
        payerParticipantId: 'uid-creator',
        amount: Decimal.parse('50.000'),
        scope: ExpenseScope.global,
        createdAt: DateTime(2026, 3, 1),
      );

      await tester.pumpWidget(
        _wrapEventHub(
          event: event,
          group: _testGroup,
          expenses: [testExpense],
        ),
      );
      // Pump enough frames for the expense stream to emit and UI to build
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));

      // The SPENDING label from ExpenseSummaryHero confirms it rendered
      expect(find.text('SPENDING'), findsOneWidget);
      // Funded Trip name confirms the EventCommandCenter header rendered
      expect(find.text('Funded Trip'), findsOneWidget);
    });
  });
}
