import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rihla/features/ledger/models/expense_model.dart';
import 'package:rihla/features/ledger/providers/expense_provider.dart';
import 'package:rihla/features/ledger/screens/ledger_screen.dart';
import 'package:rihla/features/trip/models/trip_model.dart';
import 'package:rihla/features/trip/providers/trip_provider.dart';
import 'package:rihla/features/logistics/models/sub_group_model.dart';
import 'package:rihla/features/logistics/providers/sub_group_provider.dart';
import 'package:rihla/features/activity/services/activity_service.dart';

void main() {
  final mockTrip = Trip(
    id: 'trip-123',
    name: 'Test Trip',
    inviteCode: 'ABCDEF',
    leaderId: 'user-1',
    createdAt: DateTime.now(),
  );

  final mockParticipant = Participant(
    id: 'p-1',
    tripId: 'trip-123',
    userId: 'user-1',
    role: ParticipantRole.leader,
    displayName: 'Test User',
    joinedAt: DateTime.now(),
  );

  final mockExpense = Expense(
    id: 'e-1',
    tripId: 'trip-123',
    payerParticipantId: 'p-1',
    amount: Decimal.parse('10.0'),
    description: 'Pizza',
    scope: ExpenseScope.global,
    createdAt: DateTime.now(),
    payerName: 'Test User',
    categoryName: 'Food',
    categoryIcon: 'food',
  );

  testWidgets('LedgerScreen renders expenses and balances', (WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          tripExpensesProvider(mockTrip.id).overrideWith((ref) => Stream.value([mockExpense])),
          tripSettlementsProvider(mockTrip.id).overrideWith((ref) => Stream.value([])),
          tripLogisticsParticipantsProvider(mockTrip.id).overrideWith((ref) => Stream.value([mockParticipant])),
          tripSubGroupsProvider(mockTrip.id).overrideWith((ref) => Stream.value([])),
          currentParticipantProvider(mockTrip.id).overrideWith((ref) => mockParticipant),
          tripActivityProvider(mockTrip.id).overrideWith((ref) => Stream.value([])),
        ],
        child: MaterialApp(
          home: LedgerScreen(trip: mockTrip),
        ),
      ),
    );

    // Allow animations to settle
    await tester.pumpAndSettle();

    // Verify expense is shown
    expect(find.text('Pizza'), findsOneWidget);
    expect(find.text('10.000'), findsOneWidget); // 3 decimal places
    expect(find.text('OMR'), findsWidgets);

    // Verify balance header
    // Since I paid 10 for a group of 1 (myself), net is 0.
    // Wait, global scope splits among all participants. 1 participant.
    // Paid 10. Owed 10. Net 0.
    // So "You owe others" or "Others owe you" might not appear, or balance is 0.000.

    // Let's add another participant to make it interesting
  });

  testWidgets('LedgerScreen calculates split correctly', (WidgetTester tester) async {
    final mockParticipant2 = Participant(
      id: 'p-2',
      tripId: 'trip-123',
      userId: 'user-2',
      role: ParticipantRole.member,
      displayName: 'Other User',
      joinedAt: DateTime.now(),
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          tripExpensesProvider(mockTrip.id).overrideWith((ref) => Stream.value([mockExpense])),
          tripSettlementsProvider(mockTrip.id).overrideWith((ref) => Stream.value([])),
          tripLogisticsParticipantsProvider(mockTrip.id).overrideWith((ref) => Stream.value([mockParticipant, mockParticipant2])),
          tripSubGroupsProvider(mockTrip.id).overrideWith((ref) => Stream.value([])),
          currentParticipantProvider(mockTrip.id).overrideWith((ref) => mockParticipant),
           tripActivityProvider(mockTrip.id).overrideWith((ref) => Stream.value([])),
        ],
        child: MaterialApp(
          home: LedgerScreen(trip: mockTrip),
        ),
      ),
    );

    await tester.pumpAndSettle();

    // I paid 10. 2 people. Share is 5.
    // Paid 10. Owed 5. Net +5.
    // Should show positive balance.

    expect(find.text('Pizza'), findsOneWidget);
    expect(find.textContaining('5.000'), findsWidgets); // Should find 5.000 in balance header or tooltip
  });
}
