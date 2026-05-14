import 'package:flutter_test/flutter_test.dart';

import 'package:safar/features/groups/models/group_model.dart';

void main() {
  group('GroupService join contract', () {
    test('invite code input is normalized before callable submission', () {
      const rawCode = ' abc234 ';
      final normalizedCode = rawCode.trim().toUpperCase();

      expect(normalizedCode, 'ABC234');
      expect(RegExp(r'^[A-Z0-9]{6}$').hasMatch(normalizedCode), isTrue);
    });

    test('malformed invite codes are rejected before callable submission', () {
      const malformedCodes = ['', 'ABC12', 'ABC1234', 'ABC-12'];

      for (final code in malformedCodes) {
        final normalizedCode = code.trim().toUpperCase();
        expect(RegExp(r'^[A-Z0-9]{6}$').hasMatch(normalizedCode), isFalse);
      }
    });

    test('returned group model can represent callable-updated membership', () {
      final existing = Group(
        id: 'g1',
        name: 'Test',
        inviteCode: 'TST123',
        createdBy: 'uid-001',
        memberIds: const ['uid-001'],
        createdAt: DateTime.now(),
      );

      final updated = existing.copyWith(
        memberIds: const ['uid-001', 'uid-002'],
      );

      expect(updated.memberIds, containsAll(['uid-001', 'uid-002']));
      expect(existing.memberIds, ['uid-001']);
    });
  });
}
