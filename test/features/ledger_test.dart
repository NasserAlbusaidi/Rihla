import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:safar/core/types/event_ref.dart';
import 'package:safar/features/events/models/event_model.dart';
import 'package:safar/features/groups/models/group_model.dart';
import 'package:safar/features/ledger/models/expense_model.dart';
import 'package:safar/features/ledger/models/settlement_model.dart';
import 'package:safar/features/ledger/providers/expense_provider.dart';
import 'package:safar/features/ledger/screens/ledger_screen.dart';
import 'package:safar/features/logistics/models/sub_group_model.dart';
import 'package:safar/features/logistics/providers/sub_group_provider.dart';

void main() {
  final mockGroup = Group(
    id: 'group-1',
    name: 'Test Group',
    inviteCode: 'ABCDEF',
    createdBy: 'uid-creator',
    memberIds: const ['uid-creator', 'uid-member'],
    currency: 'OMR',
    createdAt: DateTime(2026, 1, 1),
  );

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
          eventExpensesProvider(eventRef).overrideWith(
            (ref) => Stream.value([mockExpense]),
          ),
          eventSettlementsProvider(eventRef).overrideWith(
            (ref) => Stream.value(const <Settlement>[]),
          ),
          eventSubGroupsProvider(eventRef).overrideWith(
            (ref) => Stream.value(const <SubGroup>[]),
          ),
        ],
        child: MaterialApp(home: LedgerScreen(event: mockEvent, group: mockGroup)),
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
          eventExpensesProvider(eventRef).overrideWith(
            (ref) => Stream.value([mockExpense]),
          ),
          eventSettlementsProvider(eventRef).overrideWith(
            (ref) => Stream.value(const <Settlement>[]),
          ),
          eventSubGroupsProvider(eventRef).overrideWith(
            (ref) => Stream.value(const <SubGroup>[]),
          ),
        ],
        child: MaterialApp(home: LedgerScreen(event: mockEvent2, group: mockGroup)),
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
}
