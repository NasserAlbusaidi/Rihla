import 'package:flutter_test/flutter_test.dart';

// Wave 0 stub: Firestore GearService tests.
// Real implementation added in Plan 04-02 (Gear Migration).

void main() {
  group('GearService (Firestore)', () {
    group('addGearItem', () {
      test(
        'writes gear item document to groups/{groupId}/events/{eventId}/gear',
        () {},
        skip: 'Awaiting Plan 04-02: GearService Firestore migration',
      );
    });

    group('watchGearItems', () {
      test(
        'returns a stream of gear items from Firestore subcollection',
        () {},
        skip: 'Awaiting Plan 04-02: GearService Firestore migration',
      );

      test(
        'filters out soft-deleted items (isDeleted=true)',
        () {},
        skip: 'Awaiting Plan 04-02: GearService Firestore migration',
      );
    });

    group('togglePacked', () {
      test(
        'updates isPacked field on Firestore document',
        () {},
        skip: 'Awaiting Plan 04-02: GearService Firestore migration',
      );
    });

    group('deleteGearItem', () {
      test(
        'uses soft-delete pattern (sets isDeleted=true, deletedAt timestamp)',
        () {},
        skip: 'Awaiting Plan 04-02: GearService Firestore migration',
      );
    });
  });
}
