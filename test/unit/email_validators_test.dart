import 'package:flutter_test/flutter_test.dart';
import 'package:safar/core/utils/email_validators.dart';

void main() {
  group('isValidEmailFormat', () {
    test('accepts a basic well-formed address', () {
      expect(isValidEmailFormat('foo@example.com'), isTrue);
    });

    test('accepts addresses with plus aliases and dots', () {
      expect(isValidEmailFormat('foo.bar+baz@example.co.uk'), isTrue);
    });

    test('accepts uncommon TLDs', () {
      expect(isValidEmailFormat('user@something.museum'), isTrue);
      expect(isValidEmailFormat('user@example.app'), isTrue);
    });

    test('rejects empty / whitespace input', () {
      expect(isValidEmailFormat(''), isFalse);
      expect(isValidEmailFormat('   '), isFalse);
    });

    test('rejects addresses missing the @ or the dot', () {
      expect(isValidEmailFormat('foo.example.com'), isFalse);
      expect(isValidEmailFormat('foo@example'), isFalse);
    });

    test('rejects addresses containing whitespace', () {
      expect(isValidEmailFormat('foo bar@example.com'), isFalse);
      expect(isValidEmailFormat('foo@exa mple.com'), isFalse);
    });

    test('rejects addresses longer than the RFC cap', () {
      final tooLong = '${'a' * 250}@x.io';
      expect(isValidEmailFormat(tooLong), isFalse);
    });
  });

  group('validateEmail', () {
    test('returns null for a valid address', () {
      expect(validateEmail('foo@example.com'), isNull);
    });

    test('returns the empty-input message when blank', () {
      expect(validateEmail(''), 'Enter your email.');
      expect(validateEmail('   '), 'Enter your email.');
      expect(validateEmail(null), 'Enter your email.');
    });

    test('returns the format message for malformed input', () {
      expect(
        validateEmail('not-an-email'),
        "That doesn't look like an email.",
      );
    });
  });

  group('normalizeEmail', () {
    test('trims whitespace and lower-cases the entire address', () {
      expect(normalizeEmail('  Foo@Example.COM '), 'foo@example.com');
    });
  });
}
