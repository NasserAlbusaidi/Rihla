import 'package:flutter_test/flutter_test.dart';

// Wave 0 stub: Firestore SubGroupService tests.
// Real implementation added in Plan 04-03 (Logistics Migration).

void main() {
  group('SubGroupService (Firestore)', () {
    group('createSubGroup', () {
      test(
        'writes sub-group document to groups/{groupId}/events/{eventId}/subGroups',
        () {},
        skip: 'Awaiting Plan 04-03: SubGroupService Firestore migration',
      );
    });

    group('watchSubGroups', () {
      test(
        'returns a stream of sub-groups from Firestore subcollection',
        () {},
        skip: 'Awaiting Plan 04-03: SubGroupService Firestore migration',
      );
    });

    group('addMember', () {
      test(
        'writes member document to subGroups/{subGroupId}/members subcollection',
        () {},
        skip: 'Awaiting Plan 04-03: SubGroupService Firestore migration',
      );
    });

    group('removeMember', () {
      test(
        'deletes member document from subGroups/{subGroupId}/members subcollection',
        () {},
        skip: 'Awaiting Plan 04-03: SubGroupService Firestore migration',
      );
    });
  });
}
