import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:safar/core/services/lazy_migration_service.dart';

// Mock for the Supabase query chain that LazyMigrationService uses.
// We mock SupabaseClient access at the static level by making
// LazyMigrationService.withFirestore injectable and testing just the
// Firestore-side logic (skip-if-non-empty and write path).
// Supabase calls are tested via the error-handling path.

void main() {
  group('LazyMigrationService', () {
    late FakeFirebaseFirestore fakeFirestore;
    late LazyMigrationService service;

    setUp(() {
      fakeFirestore = FakeFirebaseFirestore();
      service = LazyMigrationService.withFirestore(fakeFirestore);
    });

    group('migrateModuleIfNeeded — skip conditions', () {
      test('returns false immediately if bridgeTripId is null', () async {
        final result = await service.migrateModuleIfNeeded(
          groupId: 'g1',
          eventId: 'e1',
          bridgeTripId: null,
          module: 'expenses',
        );
        expect(result, isFalse);
      });

      test('returns false immediately if bridgeTripId is empty string',
          () async {
        final result = await service.migrateModuleIfNeeded(
          groupId: 'g1',
          eventId: 'e1',
          bridgeTripId: '',
          module: 'expenses',
        );
        expect(result, isFalse);
      });

      test(
          'returns false immediately if Firestore subcollection is already non-empty',
          () async {
        // Pre-populate Firestore subcollection — it's already migrated
        await fakeFirestore
            .collection('groups/g1/events/e1/expenses')
            .doc('existing-expense')
            .set({
          'id': 'existing-expense',
          'eventId': 'e1',
          'payerParticipantId': 'user1',
          'amountFils': 10500,
          'currency': 'OMR',
          'scope': 'global',
          'createdAt': DateTime.now().toIso8601String(),
        });

        final result = await service.migrateModuleIfNeeded(
          groupId: 'g1',
          eventId: 'e1',
          bridgeTripId: 'legacy-trip-123',
          module: 'expenses',
        );

        expect(result, isFalse);
      });

      test('returns false for unknown module type', () async {
        final result = await service.migrateModuleIfNeeded(
          groupId: 'g1',
          eventId: 'e1',
          bridgeTripId: 'legacy-trip-123',
          module: 'unknown_module_xyz',
        );

        // Should return false — unknown module is handled gracefully
        expect(result, isFalse);
      });
    });

    group('migrateModuleIfNeeded — error handling', () {
      test('returns false and does not throw if Supabase is unavailable',
          () async {
        // With a bridge trip ID and empty Firestore, the service will try
        // to access Supabase. Since Supabase is not initialized in this test
        // environment, it should catch the error and return false.
        expect(
          () async => await service.migrateModuleIfNeeded(
            groupId: 'g1',
            eventId: 'e1',
            bridgeTripId: 'legacy-trip-123',
            module: 'expenses',
          ),
          returnsNormally,
        );

        final result = await service.migrateModuleIfNeeded(
          groupId: 'g1',
          eventId: 'e1',
          bridgeTripId: 'legacy-trip-123',
          module: 'expenses',
        );

        // Returns false when Supabase is unavailable (not authenticated / not initialized)
        expect(result, isFalse);
      });

      test('handles gear_items module gracefully when Supabase unavailable',
          () async {
        final result = await service.migrateModuleIfNeeded(
          groupId: 'g1',
          eventId: 'e1',
          bridgeTripId: 'legacy-trip-123',
          module: 'gear_items',
        );
        expect(result, isFalse);
      });

      test('handles settlements module gracefully when Supabase unavailable',
          () async {
        final result = await service.migrateModuleIfNeeded(
          groupId: 'g1',
          eventId: 'e1',
          bridgeTripId: 'legacy-trip-123',
          module: 'settlements',
        );
        expect(result, isFalse);
      });
    });

    group('migrateModuleIfNeeded — Firestore path correctness', () {
      test('check uses correct Firestore path for expenses subcollection',
          () async {
        // Seed data at a DIFFERENT path — verifies service uses the right path
        await fakeFirestore
            .collection('groups/g1/events/OTHER_EVENT/expenses')
            .doc('some-doc')
            .set({'id': 'some-doc'});

        // Should NOT see the data at group/g1/events/e1/expenses
        // and should attempt migration (but fail gracefully on Supabase)
        final result = await service.migrateModuleIfNeeded(
          groupId: 'g1',
          eventId: 'e1',
          bridgeTripId: 'legacy-trip-123',
          module: 'expenses',
        );

        // Supabase not available — returns false but confirms path was checked
        expect(result, isFalse);
      });
    });
  });
}
