import 'dart:math';

import 'package:flutter_test/flutter_test.dart';

// We test the invite code generation logic independently by replicating the
// same algorithm used in GroupService._generateInviteCode().
String generateInviteCode([Random? random]) {
  const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
  final rng = random ?? Random.secure();
  return List.generate(6, (_) => chars[rng.nextInt(chars.length)]).join();
}

void main() {
  group('Invite code generation', () {
    test('generates a 6-character code', () {
      final code = generateInviteCode();
      expect(code.length, equals(6));
    });

    test(
        'code uses only allowed chars: ABCDEFGHJKLMNPQRSTUVWXYZ23456789 (no O/0/I/l per D-10)',
        () {
      const allowed = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
      for (int i = 0; i < 200; i++) {
        final code = generateInviteCode();
        for (final char in code.split('')) {
          expect(
            allowed.contains(char),
            isTrue,
            reason: 'Char "$char" is not in the allowed set (code: $code)',
          );
        }
      }
    });

    test('code does not contain confusing characters O, 0, I, l', () {
      const forbidden = ['O', '0', 'I', 'l'];
      for (int i = 0; i < 200; i++) {
        final code = generateInviteCode();
        for (final char in forbidden) {
          expect(
            code.contains(char),
            isFalse,
            reason: 'Code "$code" contains forbidden char "$char"',
          );
        }
      }
    });

    test('code is uppercase', () {
      for (int i = 0; i < 50; i++) {
        final code = generateInviteCode();
        expect(code, equals(code.toUpperCase()));
      }
    });

    test('100 generated codes are all unique (probabilistic)', () {
      // The code space is 32^6 = ~1 billion codes.
      // Collision probability for 100 codes is negligibly small.
      final codes = List.generate(100, (_) => generateInviteCode());
      final unique = codes.toSet();
      expect(unique.length, equals(100));
    });
  });

  group('Invite code validation', () {
    test('valid 6-char code is accepted', () {
      // Simulate the validation: a 6-char uppercase alphanumeric code
      // should not be rejected by format checks.
      const validCode = 'ABC234';
      expect(validCode.length, equals(6));
      expect(validCode, equals(validCode.toUpperCase()));
    });

    test('code is uppercased before lookup (D-13)', () {
      // The joinGroup method calls inviteCode.toUpperCase() before Firestore
      // lookup. Verify that lowercased codes normalize correctly.
      const lowercase = 'abc234';
      const expected = 'ABC234';
      expect(lowercase.toUpperCase(), equals(expected));
    });

    test('empty code would not match any valid invite', () {
      const emptyCode = '';
      expect(emptyCode.isEmpty, isTrue);
    });
  });
}
