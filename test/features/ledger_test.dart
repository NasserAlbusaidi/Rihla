import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:safar/core/types/event_ref.dart';
import 'package:safar/features/events/models/event_model.dart';
import 'package:safar/features/events/providers/event_provider.dart';
import 'package:safar/features/ledger/keys/ledger_keys.dart';
import 'package:safar/features/ledger/models/expense_model.dart';
import 'package:safar/features/ledger/models/settlement_model.dart';
import 'package:safar/features/ledger/models/transaction_model.dart';
import 'package:safar/features/ledger/providers/expense_provider.dart';
import 'package:safar/features/ledger/providers/ledger_provider.dart';
import 'package:safar/features/ledger/screens/ledger_screen.dart';
import 'package:safar/features/logistics/models/sub_group_model.dart';
import 'package:safar/features/logistics/providers/sub_group_provider.dart';

// ---------------------------------------------------------------------------
// Shared test helpers
// ---------------------------------------------------------------------------

const _mockGroupId = 'group-1';
const _mockEventId = 'evt-123';
const EventRef _eventRef = (groupId: _mockGroupId, eventId: _mockEventId);

final _mockEvent = Event(
  id: _mockEventId,
  name: 'Test Event',
  type: EventType.trip,
  groupId: _mockGroupId,
  createdBy: 'uid-creator',
  participantIds: const ['uid-creator'],
  participantNames: const {'uid-creator': 'Test User'},
  modules: EventModules.forType(EventType.trip),
  currency: 'OMR',
  createdAt: DateTime(2026, 1, 1),
);

/// Builds a ProviderScope wrapper for LedgerScreen with standard overrides.
Widget _wrapLedger({
  required Event event,
  List<Expense> expenses = const [],
  List<Settlement> settlements = const [],
  List<SubGroup> subGroups = const [],
}) {
  return ProviderScope(
    overrides: [
      eventDetailProvider(_eventRef).overrideWith(
        (ref) => Stream.value(event),
      ),
      eventExpensesProvider(_eventRef).overrideWith(
        (ref) => Stream.value(expenses),
      ),
      eventSettlementsProvider(_eventRef).overrideWith(
        (ref) => Stream.value(settlements),
      ),
      eventSubGroupsProvider(_eventRef).overrideWith(
        (ref) => Stream.value(subGroups),
      ),
      eventUnifiedLedgerProvider(_eventRef).overrideWith(
        (ref) => const AsyncValue.data(<Transaction>[]),
      ),
    ],
    child: MaterialApp(
      home: LedgerScreen(
        groupId: _mockGroupId,
        eventId: _mockEventId,
      ),
    ),
  );
}

void main() {
  final mockEvent = Event(
    id: 'evt-123',
    name: 'Test Event',
    type: EventType.trip,
    groupId: 'group-1',
    createdBy: 'uid-creator',
    participantIds: const ['uid-creator'],
    participantNames: const {'uid-creator': 'Test User'},
    modules: EventModules.forType(EventType.trip),
    currency: 'OMR',
    createdAt: DateTime(2026, 1, 1),
  );

  final EventRef eventRef = (groupId: 'group-1', eventId: 'evt-123');

  final mockExpense = Expense(
    id: 'e-1',
    tripId: 'evt-123',
    payerParticipantId: 'uid-creator',
    amount: Decimal.parse('10.0'),
    description: 'Pizza',
    scope: ExpenseScope.global,
    createdAt: DateTime.now(),
    payerName: 'Test User',
    categoryName: 'Food',
    categoryIcon: 'food',
  );

  testWidgets('LedgerScreen renders expenses and balances', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          eventDetailProvider(eventRef).overrideWith(
            (ref) => Stream.value(mockEvent),
          ),
          eventExpensesProvider(eventRef).overrideWith(
            (ref) => Stream.value([mockExpense]),
          ),
          eventSettlementsProvider(eventRef).overrideWith(
            (ref) => Stream.value(const <Settlement>[]),
          ),
          eventSubGroupsProvider(eventRef).overrideWith(
            (ref) => Stream.value(const <SubGroup>[]),
          ),
          eventUnifiedLedgerProvider(eventRef).overrideWith(
            (ref) => const AsyncValue.data(<Transaction>[]),
          ),
        ],
        child: MaterialApp(
          home: LedgerScreen(groupId: 'group-1', eventId: 'evt-123'),
        ),
      ),
    );

    // Allow streams and animations to settle
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();

    // Verify expense is shown (rendered via unified ledger as transaction card)
    // Items may be below the viewport in CustomScrollView, so use skipOffstage
    expect(find.text('Pizza', skipOffstage: false), findsOneWidget);
    expect(find.textContaining('10.000', skipOffstage: false), findsWidgets); // 3 decimal places
  });

  testWidgets('LedgerScreen calculates split correctly', (
    WidgetTester tester,
  ) async {
    // Two participants: uid-creator (payer) and uid-member
    final mockEvent2 = Event(
      id: 'evt-123',
      name: 'Test Event',
      type: EventType.trip,
      groupId: 'group-1',
      createdBy: 'uid-creator',
      participantIds: const ['uid-creator', 'uid-member'],
      participantNames: const {
        'uid-creator': 'Test User',
        'uid-member': 'Other User',
      },
      modules: EventModules.forType(EventType.trip),
      currency: 'OMR',
      createdAt: DateTime(2026, 1, 1),
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          eventDetailProvider(eventRef).overrideWith(
            (ref) => Stream.value(mockEvent2),
          ),
          eventExpensesProvider(eventRef).overrideWith(
            (ref) => Stream.value([mockExpense]),
          ),
          eventSettlementsProvider(eventRef).overrideWith(
            (ref) => Stream.value(const <Settlement>[]),
          ),
          eventSubGroupsProvider(eventRef).overrideWith(
            (ref) => Stream.value(const <SubGroup>[]),
          ),
          eventUnifiedLedgerProvider(eventRef).overrideWith(
            (ref) => const AsyncValue.data(<Transaction>[]),
          ),
        ],
        child: MaterialApp(
          home: LedgerScreen(groupId: 'group-1', eventId: 'evt-123'),
        ),
      ),
    );

    // Allow streams and animations to settle
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();

    // I paid 10. 2 people. Share is 5.
    // Paid 10. Owed 5. Net +5.
    // Should show positive balance.

    expect(find.text('Pizza', skipOffstage: false), findsOneWidget);
    expect(
      find.textContaining('5.000', skipOffstage: false),
      findsWidgets,
    ); // Should find 5.000 in balance header or tooltip
  });

  // ---------------------------------------------------------------------------
  // Additional widget tests (Plan 04 — filling audit gaps from 06-01)
  // ---------------------------------------------------------------------------

  testWidgets('LedgerScreen shows empty state with no expenses', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      _wrapLedger(event: _mockEvent, expenses: const []),
    );

    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();

    // With no expenses, the balance header should show 0.000
    expect(find.textContaining('0.000', skipOffstage: false), findsWidgets);
  });

  testWidgets('LedgerScreen renders event name in ModuleHeader as subtitle', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      _wrapLedger(event: _mockEvent, expenses: const []),
    );

    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();

    // Event name appears as uppercase subtitle in the ModuleHeader
    // (widget.event.name.toUpperCase() per ledger_screen.dart line 737)
    expect(find.text('TEST EVENT'), findsWidgets);
  });

  testWidgets('LedgerScreen shows OMR amounts with 3 decimal places', (
    WidgetTester tester,
  ) async {
    final precisionExpense = Expense(
      id: 'e-prec',
      tripId: _mockEventId,
      payerParticipantId: 'uid-creator',
      amount: Decimal.parse('7.500'),
      description: 'Juice',
      scope: ExpenseScope.global,
      createdAt: DateTime.now(),
    );

    await tester.pumpWidget(
      _wrapLedger(event: _mockEvent, expenses: [precisionExpense]),
    );

    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();

    // OMR amounts formatted with 3 decimal places
    expect(
      find.textContaining('7.500', skipOffstage: false),
      findsWidgets,
      reason: 'OMR amount must display with 3 decimal places',
    );
  });

  testWidgets('LedgerScreen shows SPENDING label in balance header', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          eventDetailProvider(eventRef).overrideWith(
            (ref) => Stream.value(mockEvent),
          ),
          eventExpensesProvider(eventRef).overrideWith(
            (ref) => Stream.value([mockExpense]),
          ),
          eventSettlementsProvider(eventRef).overrideWith(
            (ref) => Stream.value(const <Settlement>[]),
          ),
          eventSubGroupsProvider(eventRef).overrideWith(
            (ref) => Stream.value(const <SubGroup>[]),
          ),
          eventUnifiedLedgerProvider(eventRef).overrideWith(
            (ref) => const AsyncValue.data(<Transaction>[]),
          ),
        ],
        child: MaterialApp(
          home: LedgerScreen(groupId: 'group-1', eventId: 'evt-123'),
        ),
      ),
    );

    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();

    // SPENDING label from balance header confirms render
    expect(find.byKey(LedgerKeys.spendingLabel), findsOneWidget);
  });
}
