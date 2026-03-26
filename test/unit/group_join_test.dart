import 'package:flutter_test/flutter_test.dart';

void main() {
  group('GroupService join', () {
    test(
      'valid invite code adds user to group memberIds via arrayUnion',
      skip: 'Awaiting Plan 02-01 Task 2: GroupService implementation',
      () {},
    );

    test(
      'valid invite code creates member doc in subcollection with role MEMBER',
      skip: 'Awaiting Plan 02-01 Task 2: GroupService implementation',
      () {},
    );

    test(
      'invalid invite code throws Exception("Invalid invite code")',
      skip: 'Awaiting Plan 02-01 Task 2: GroupService implementation',
      () {},
    );

    test(
      'already a member throws Exception("Already a member")',
      skip: 'Awaiting Plan 02-01 Task 2: GroupService implementation',
      () {},
    );

    test(
      'join uses WriteBatch for atomic member doc + memberIds update',
      skip: 'Awaiting Plan 02-01 Task 2: GroupService implementation',
      () {},
    );

    test(
      'invite code is uppercased before Firestore lookup (D-13)',
      skip: 'Awaiting Plan 02-01 Task 2: GroupService implementation',
      () {},
    );
  });
}
