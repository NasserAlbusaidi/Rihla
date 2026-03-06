import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:decimal/decimal.dart';
import 'package:safar/features/home/screens/command_center.dart';
import 'package:safar/features/trip/models/trip_model.dart';
import 'package:safar/features/trip/providers/trip_provider.dart';
import 'package:safar/features/ledger/providers/expense_provider.dart';
import 'package:safar/features/ledger/models/expense_model.dart';
import 'package:safar/features/auth/providers/auth_provider.dart';
import 'package:safar/features/memories/providers/memory_provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:mocktail/mocktail.dart';

class MockUser extends Mock implements User {}

void main() {
  final mockTrip = Trip(
    id: 'trip-123',
    name: 'Test Adventure',
    inviteCode: 'TRIP12',
    leaderId: 'user-1',
    modules: const TripModules(),
    createdAt: DateTime(2023),
  );

  final mockUser = MockUser();
  when(() => mockUser.id).thenReturn('user-1');
  when(() => mockUser.email).thenReturn('test@example.com');

  testWidgets('CommandCenter shows expense summary and navigation modules', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          currentUserProvider.overrideWithValue(mockUser),
          userTripsProvider.overrideWith((ref) => Stream.value([mockTrip])),
          currentTripProvider.overrideWith((ref) => mockTrip),
          tripExpensesProvider(
            mockTrip.id,
          ).overrideWith((ref) => Stream.value([])),
          tripBalancesProvider(mockTrip.id).overrideWith(
            (ref) async => [
              UserBalance(
                participantId: 'user-1',
                totalPaid: Decimal.zero,
                totalOwed: Decimal.zero,
                netBalance: Decimal.zero,
              ),
            ],
          ),
          tripMemoriesProvider(mockTrip.id).overrideWith((ref) async => []),
        ],
        child: const MaterialApp(home: CommandCenter()),
      ),
    );

    await tester.pumpAndSettle();

    // Verify trip name is visible (Upper case in UI)
    expect(find.text('TEST ADVENTURE'), findsWidgets);

    // Verify Expense Summary card is visible
    expect(find.text('TREASURY'), findsOneWidget);

    // Verify Navigation Modules are visible
    expect(find.text('Ledger'), findsOneWidget);
    expect(find.text('Logistics'), findsOneWidget);
    expect(find.text('Vault'), findsOneWidget);

    // Verify Floating Action Button is visible
    expect(find.byType(FloatingActionButton), findsOneWidget);
  });

  testWidgets('CommandCenter shows empty state when no trips available', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          currentUserProvider.overrideWithValue(mockUser),
          userTripsProvider.overrideWith((ref) => Stream.value([])),
          currentTripProvider.overrideWith((ref) => null),
        ],
        child: const MaterialApp(home: CommandCenter()),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('No Trips Yet'), findsOneWidget);
    expect(find.byType(FloatingActionButton), findsNothing);
  });
}
