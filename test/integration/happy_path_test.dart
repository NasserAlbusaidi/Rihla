import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:decimal/decimal.dart';
import 'package:mocktail/mocktail.dart';
import 'package:iconsax/iconsax.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:safar/features/auth/providers/auth_provider.dart';
import 'package:safar/features/trip/models/trip_model.dart';
import 'package:safar/features/trip/providers/trip_provider.dart';
import 'package:safar/features/ledger/providers/expense_provider.dart';
import 'package:safar/features/ledger/models/expense_model.dart';
import 'package:safar/core/router/app_router.dart';
import 'package:safar/features/gear/providers/gear_provider.dart';
import 'package:safar/features/logistics/providers/sub_group_provider.dart';
import 'package:safar/features/activity/services/activity_service.dart';
import 'package:safar/features/memories/providers/memory_provider.dart';

class MockUser extends Mock implements User {}

void main() {
  final mockTrip = Trip(
    id: 'trip-123',
    name: 'Integration Test Trip',
    inviteCode: 'TEST24',
    leaderId: 'user-1',
    modules: const TripModules(),
    createdAt: DateTime.now(),
  );

  final mockUser = MockUser();
  when(() => mockUser.id).thenReturn('user-1');
  when(() => mockUser.email).thenReturn('test@example.com');

  testWidgets('Happy Path: Navigate to Ledger and Add Expense', (tester) async {
    // 1. Initialize the app with mocked providers
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          // Bypass splash by providing a logged-in user
          authStateProvider.overrideWith((ref) => Stream.value(mockUser)),
          currentUserProvider.overrideWithValue(mockUser),
          userTripsProvider.overrideWith((ref) => Stream.value([mockTrip])),
          currentTripProvider.overrideWith((ref) => mockTrip),

          // Mock participants and balance
          tripLogisticsParticipantsProvider(mockTrip.id).overrideWith(
            (ref) => Stream.value([
              Participant(
                id: 'p-1',
                tripId: 'trip-123',
                userId: 'user-1',
                role: ParticipantRole.leader,
                joinedAt: DateTime.now(),
                displayName: 'Test User',
              ),
            ]),
          ),
          currentParticipantProvider(mockTrip.id).overrideWith(
            (ref) => Participant(
              id: 'p-1',
              tripId: 'trip-123',
              userId: 'user-1',
              role: ParticipantRole.leader,
              joinedAt: DateTime.now(),
              displayName: 'Test User',
            ),
          ),
          tripBalancesProvider(mockTrip.id).overrideWith(
            (ref) async => [
              UserBalance(
                participantId: 'p-1',
                totalPaid: Decimal.zero,
                totalOwed: Decimal.zero,
                netBalance: Decimal.zero,
              ),
            ],
          ),
          tripGearProvider(mockTrip.id).overrideWith((ref) => Stream.value([])),
          tripSubGroupsProvider(
            mockTrip.id,
          ).overrideWith((ref) => Stream.value([])),
          tripActivityProvider(
            mockTrip.id,
          ).overrideWith((ref) => Stream.value([])),
          tripTransactionActivityProvider(
            mockTrip.id,
          ).overrideWith((ref) => Stream.value([])),
          tripExpensesProvider(
            mockTrip.id,
          ).overrideWith((ref) => Stream.value([])),
          tripSettlementsProvider(
            mockTrip.id,
          ).overrideWith((ref) => Stream.value([])),
          tripMemoriesProvider(
            mockTrip.id,
          ).overrideWith((ref) async => []),
          onboardingCompleteProvider.overrideWith((ref) => true),
        ],
        child: Consumer(
          builder: (context, ref, _) {
            final router = ref.watch(routerProvider);
            return MaterialApp.router(routerConfig: router);
          },
        ),
      ),
    );

    // Wait for splash redirect to Home
    await tester.pumpAndSettle();

    // 2. Locate the trip card on HomeScreen
    final tripCard = find.text('Integration Test Trip', skipOffstage: false);
    expect(tripCard, findsWidgets);

    // Tap the trip card to go to CommandCenter
    await tester.tap(tripCard.first);
    await tester.pumpAndSettle();

    // 3. Verify we are on CommandCenter and locate Ledger
    final ledgerIcon = find.byIcon(Iconsax.wallet_3, skipOffstage: false);
    await tester.ensureVisible(ledgerIcon.first);
    expect(ledgerIcon, findsWidgets);

    // Navigate to Ledger
    await tester.tap(ledgerIcon.first);
    await tester.pumpAndSettle();

    // 4. Verify Ledger Screen
    expect(find.text('Ledger', skipOffstage: false), findsWidgets);
    expect(find.text('ADD EXPENSE', skipOffstage: false), findsWidgets);

    // 5. Add Expense (verify New Expense sheet appears)
    final addBtn = find.text('ADD EXPENSE', skipOffstage: false);
    await tester.tap(addBtn.first);
    await tester.pumpAndSettle();

    expect(find.text('ENTER AMOUNT', skipOffstage: false), findsWidgets);
  });
}
