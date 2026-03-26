import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Invite code generation', () {
    test(
      'generates a 6-character code',
      skip: 'Awaiting Plan 02-01 Task 2: GroupService._generateInviteCode',
      () {},
    );

    test(
      'code uses only allowed chars: ABCDEFGHJKLMNPQRSTUVWXYZ23456789 (no O/0/I/l per D-10)',
      skip: 'Awaiting Plan 02-01 Task 2: GroupService._generateInviteCode',
      () {},
    );

    test(
      'code is uppercase',
      skip: 'Awaiting Plan 02-01 Task 2: GroupService._generateInviteCode',
      () {},
    );

    test(
      '100 generated codes are all unique (probabilistic)',
      skip: 'Awaiting Plan 02-01 Task 2: GroupService._generateInviteCode',
      () {},
    );
  });

  group('Invite code validation', () {
    test(
      'valid 6-char code is accepted',
      skip: 'Awaiting Plan 02-01 Task 2: joinGroup validation',
      () {},
    );

    test(
      'invalid code throws Exception with "Invalid invite code" message',
      skip: 'Awaiting Plan 02-01 Task 2: joinGroup validation',
      () {},
    );

    test(
      'code is uppercased before lookup (D-13)',
      skip: 'Awaiting Plan 02-01 Task 2: joinGroup validation',
      () {},
    );
  });
}
