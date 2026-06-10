import 'package:flutter_test/flutter_test.dart';
import 'package:safar/features/auth/providers/auth_email_link_bootstrap_provider.dart';

void main() {
  group('humanizeAuthErrorCode', () {
    test('maps expired/invalid action codes to the resend message', () {
      const resend = 'This link has expired or was already used. Send a new one.';
      expect(humanizeAuthErrorCode('expired-action-code'), resend);
      expect(humanizeAuthErrorCode('invalid-action-code'), resend);
    });

    test('maps a network failure to an offline message', () {
      expect(
        humanizeAuthErrorCode('network-request-failed'),
        "No connection. Try again when you're online.",
      );
    });

    test('maps an already-in-use email to the restore-instead message', () {
      expect(
        humanizeAuthErrorCode('email-already-in-use'),
        contains('already linked'),
      );
    });

    test('falls back with the raw code for unknown codes', () {
      expect(humanizeAuthErrorCode('weird-code'), contains('weird-code'));
    });
  });
}
