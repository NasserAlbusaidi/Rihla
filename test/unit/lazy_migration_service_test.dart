import 'package:flutter_test/flutter_test.dart';

// Wave 0 stub: LazyMigrationService tests.
// Real implementation added in Plan 04-01 (Ledger Migration).

void main() {
  group('LazyMigrationService', () {
    group('migrateExpensesIfNeeded', () {
      test(
        'skips migration if Firestore subcollection is non-empty',
        () {},
        skip: 'Awaiting Plan 04-01: LazyMigrationService implementation',
      );

      test(
        'fetches expenses from Supabase if Firestore subcollection is empty',
        () {},
        skip: 'Awaiting Plan 04-01: LazyMigrationService implementation',
      );

      test(
        'migration handles Supabase errors gracefully (does not throw)',
        () {},
        skip: 'Awaiting Plan 04-01: LazyMigrationService implementation',
      );
    });
  });
}
