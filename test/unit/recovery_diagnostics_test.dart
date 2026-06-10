import 'package:flutter_test/flutter_test.dart';
import 'package:safar/features/auth/services/recovery_diagnostics.dart';

void main() {
  group('RecoveryDiagnostics.fingerprint', () {
    test('is 8 lowercase hex chars regardless of input length', () {
      final fp = RecoveryDiagnostics.fingerprint('abc');
      expect(fp, matches(RegExp(r'^[0-9a-f]{8}$')));
      // A realistic 28-char Firebase UID still compresses to 8 hex chars.
      const uid = 'aZ9bQ1cR2dS3eT4fU5gV6hW7iX8j';
      expect(RecoveryDiagnostics.fingerprint(uid), matches(RegExp(r'^[0-9a-f]{8}$')));
    });

    test('is deterministic for the same input', () {
      const uid = 'aZ9bQ1cR2dS3eT4fU5gV6hW7iX8j';
      expect(
        RecoveryDiagnostics.fingerprint(uid),
        RecoveryDiagnostics.fingerprint(uid),
      );
    });

    test('differs for different inputs and is never the raw uid', () {
      const uid = 'aZ9bQ1cR2dS3eT4fU5gV6hW7iX8j';
      expect(
        RecoveryDiagnostics.fingerprint('a'),
        isNot(RecoveryDiagnostics.fingerprint('b')),
      );
      expect(RecoveryDiagnostics.fingerprint(uid), isNot(uid));
    });
  });

  group('SentryRecoveryDiagnostics', () {
    test('breadcrumb and captureFailure are safe no-ops without Sentry init', () {
      const diag = SentryRecoveryDiagnostics();
      // Sentry is not initialized in unit tests; these must not throw.
      expect(
        () => diag.breadcrumb('phase.test', data: {'k': 'v'}),
        returnsNormally,
      );
      expect(
        () => diag.captureFailure('phase.test', code: 'invalid-action-code'),
        returnsNormally,
      );
    });
  });
}
