import 'package:flutter_test/flutter_test.dart';

// Wave 0 stub: Firestore SettlementService tests.
// Real implementation added in Plan 04-01 (Ledger Migration).

void main() {
  group('SettlementService (Firestore)', () {
    group('addSettlement', () {
      test(
        'writes settlement document to groups/{groupId}/events/{eventId}/settlements',
        () {},
        skip: 'Awaiting Plan 04-01: SettlementService Firestore migration',
      );

      test(
        'uses MoneySerializer.toSubunits to store amountFils',
        () {},
        skip: 'Awaiting Plan 04-01: SettlementService Firestore migration',
      );
    });

    group('watchSettlements', () {
      test(
        'returns a stream of settlements from Firestore subcollection',
        () {},
        skip: 'Awaiting Plan 04-01: SettlementService Firestore migration',
      );
    });

    group('deleteSettlement', () {
      test(
        'uses soft-delete pattern (sets isDeleted=true, deletedAt timestamp)',
        () {},
        skip: 'Awaiting Plan 04-01: SettlementService Firestore migration',
      );
    });
  });
}
