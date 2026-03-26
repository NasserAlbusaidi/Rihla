import 'package:flutter_test/flutter_test.dart';

void main() {
  group('GroupService', () {
    group('createGroup', () {
      test(
        'creates group doc, inviteCode doc, and member doc atomically via WriteBatch',
        skip: 'Awaiting Plan 02-01 Task 2: GroupService implementation',
        () {},
      );

      test(
        'creator is added as member with role CREATOR (D-09)',
        skip: 'Awaiting Plan 02-01 Task 2: GroupService implementation',
        () {},
      );

      test(
        'generated invite code is stored in both group doc and inviteCodes collection',
        skip: 'Awaiting Plan 02-01 Task 2: GroupService implementation',
        () {},
      );

      test(
        'memberIds array contains creator UID after creation',
        skip: 'Awaiting Plan 02-01 Task 2: GroupService implementation',
        () {},
      );

      test(
        'throws if user is not authenticated (uid is null)',
        skip: 'Awaiting Plan 02-01 Task 2: GroupService implementation',
        () {},
      );
    });

    group('updateGroup', () {
      test(
        'updates group name in Firestore',
        skip: 'Awaiting Plan 02-01 Task 2: GroupService implementation',
        () {},
      );

      test(
        'updates currency in Firestore',
        skip: 'Awaiting Plan 02-01 Task 2: GroupService implementation',
        () {},
      );

      test(
        'only updates provided fields (partial update)',
        skip: 'Awaiting Plan 02-01 Task 2: GroupService implementation',
        () {},
      );
    });

    group('updateMemberDisplayName', () {
      test(
        'updates displayName field on member subcollection document (D-07)',
        skip: 'Awaiting Plan 02-01 Task 2: GroupService implementation',
        () {},
      );
    });
  });
}
