import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:decimal/decimal.dart';
import 'package:safar/features/ledger/providers/expense_provider.dart';
import 'package:safar/features/ledger/models/expense_model.dart';
import 'package:safar/features/ledger/models/settlement_model.dart';
import 'package:safar/features/gear/providers/gear_provider.dart';
import 'package:safar/features/gear/models/gear_item_model.dart';
import 'package:safar/features/trip/providers/trip_provider.dart';
import 'package:safar/features/trip/models/trip_model.dart';
import 'package:safar/features/logistics/providers/sub_group_provider.dart';
import 'package:safar/features/logistics/models/sub_group_model.dart';
import 'package:safar/features/activity/services/activity_service.dart';
import 'package:safar/features/activity/models/activity_log_model.dart';

void main() {
  group('Offline-first providers', () {
    test('tripExpensesProvider can be overridden with mock data', () async {
      final mockExpense = Expense(
        id: 'e-1',
        tripId: 'trip-1',
        payerParticipantId: 'p-1',
        amount: Decimal.parse('25.500'),
        description: 'Fuel',
        scope: ExpenseScope.global,
        createdAt: DateTime(2024),
      );

      final container = ProviderContainer(overrides: [
        tripExpensesProvider('trip-1').overrideWith(
          (ref) => Stream.value([mockExpense]),
        ),
      ]);
      addTearDown(container.dispose);

      final expenses =
          await container.read(tripExpensesProvider('trip-1').future);
      expect(expenses, hasLength(1));
      expect(expenses.first.description, 'Fuel');
      expect(expenses.first.amount, Decimal.parse('25.500'));
    });

    test('tripGearProvider can be overridden with mock data', () async {
      final mockItem = GearItem(
        id: 'g-1',
        tripId: 'trip-1',
        itemName: 'Tent',
        isHighPriority: true,
      );

      final container = ProviderContainer(overrides: [
        tripGearProvider('trip-1').overrideWith(
          (ref) => Stream.value([mockItem]),
        ),
      ]);
      addTearDown(container.dispose);

      final gear = await container.read(tripGearProvider('trip-1').future);
      expect(gear, hasLength(1));
      expect(gear.first.itemName, 'Tent');
      expect(gear.first.isHighPriority, true);
    });

    test('tripSettlementsProvider can be overridden', () async {
      final container = ProviderContainer(overrides: [
        tripSettlementsProvider('trip-1').overrideWith(
          (ref) => Stream.value(<Settlement>[]),
        ),
      ]);
      addTearDown(container.dispose);

      final settlements =
          await container.read(tripSettlementsProvider('trip-1').future);
      expect(settlements, isEmpty);
    });

    test('userTripsProvider can be overridden', () async {
      final mockTrip = Trip(
        id: 'trip-1',
        name: 'Weekend Camping',
        inviteCode: 'ABC123',
        leaderId: 'user-1',
        modules: const TripModules(),
        createdAt: DateTime(2024),
      );

      final container = ProviderContainer(overrides: [
        userTripsProvider.overrideWith(
          (ref) => Stream.value([mockTrip]),
        ),
      ]);
      addTearDown(container.dispose);

      final trips = await container.read(userTripsProvider.future);
      expect(trips, hasLength(1));
      expect(trips.first.name, 'Weekend Camping');
    });

    test('tripLogisticsParticipantsProvider can be overridden', () async {
      final mockParticipant = Participant(
        id: 'p-1',
        tripId: 'trip-1',
        userId: 'user-1',
        role: ParticipantRole.leader,
        displayName: 'Nasser',
        joinedAt: DateTime(2024),
      );

      final container = ProviderContainer(overrides: [
        tripLogisticsParticipantsProvider('trip-1').overrideWith(
          (ref) => Stream.value([mockParticipant]),
        ),
      ]);
      addTearDown(container.dispose);

      final participants = await container
          .read(tripLogisticsParticipantsProvider('trip-1').future);
      expect(participants, hasLength(1));
      expect(participants.first.displayName, 'Nasser');
    });

    test('empty provider overrides return empty lists', () async {
      final container = ProviderContainer(overrides: [
        tripExpensesProvider('empty-trip').overrideWith(
          (ref) => Stream.value(<Expense>[]),
        ),
        tripGearProvider('empty-trip').overrideWith(
          (ref) => Stream.value(<GearItem>[]),
        ),
        tripSubGroupsProvider('empty-trip').overrideWith(
          (ref) => Stream.value(<SubGroup>[]),
        ),
        tripActivityProvider('empty-trip').overrideWith(
          (ref) => Stream.value(<ActivityLog>[]),
        ),
      ]);
      addTearDown(container.dispose);

      final expenses =
          await container.read(tripExpensesProvider('empty-trip').future);
      final gear =
          await container.read(tripGearProvider('empty-trip').future);
      final subGroups =
          await container.read(tripSubGroupsProvider('empty-trip').future);
      final activity =
          await container.read(tripActivityProvider('empty-trip').future);

      expect(expenses, isEmpty);
      expect(gear, isEmpty);
      expect(subGroups, isEmpty);
      expect(activity, isEmpty);
    });
  });
}
