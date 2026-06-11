import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:safar/features/auth/services/recovery_outcome.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late SharedPreferences prefs;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
  });

  group('writeRecoveryOutcome / readAndClearRecoveryOutcome', () {
    test('failure outcome round-trips', () async {
      await writeRecoveryOutcome(
        prefs,
        op: RecoveryOutcome.opRecover,
        ok: false,
        code: 'invalid-action-code',
      );

      final outcome = readAndClearRecoveryOutcome(prefs);
      expect(outcome, isNotNull);
      expect(outcome!.op, 'recover');
      expect(outcome.ok, isFalse);
      expect(outcome.code, 'invalid-action-code');
    });

    test('success outcome round-trips with null code', () async {
      await writeRecoveryOutcome(
        prefs,
        op: RecoveryOutcome.opGoogle,
        ok: true,
      );

      final outcome = readAndClearRecoveryOutcome(prefs);
      expect(outcome!.ok, isTrue);
      expect(outcome.code, isNull);
    });

    test('read is one-shot: second read returns null', () async {
      await writeRecoveryOutcome(
        prefs,
        op: RecoveryOutcome.opSignOut,
        ok: true,
      );

      expect(readAndClearRecoveryOutcome(prefs), isNotNull);
      expect(readAndClearRecoveryOutcome(prefs), isNull);
      expect(prefs.containsKey(RecoveryOutcome.prefsKey), isFalse);
    });

    test('missing marker → null', () {
      expect(readAndClearRecoveryOutcome(prefs), isNull);
    });

    test('malformed marker → null and cleared', () async {
      await prefs.setString(RecoveryOutcome.prefsKey, '{nope');
      expect(readAndClearRecoveryOutcome(prefs), isNull);
      expect(prefs.containsKey(RecoveryOutcome.prefsKey), isFalse);
    });

    test('round-trips expectedUid (#458)', () async {
      await writeRecoveryOutcome(
        prefs,
        op: RecoveryOutcome.opGoogle,
        ok: true,
        expectedUid: 'durable-uid-1',
      );

      final outcome = readAndClearRecoveryOutcome(prefs);
      expect(outcome!.expectedUid, 'durable-uid-1');
    });

    test('legacy marker without expectedUid reads as null (#458)', () async {
      await writeRecoveryOutcome(prefs, op: RecoveryOutcome.opGoogle, ok: true);

      final outcome = readAndClearRecoveryOutcome(prefs);
      expect(outcome!.ok, isTrue);
      expect(outcome.expectedUid, isNull);
    });

    test('overwrite keeps only the latest outcome', () async {
      await writeRecoveryOutcome(
        prefs,
        op: RecoveryOutcome.opGoogle,
        ok: false,
        code: 'network-request-failed',
      );
      await writeRecoveryOutcome(
        prefs,
        op: RecoveryOutcome.opGoogle,
        ok: true,
      );

      final outcome = readAndClearRecoveryOutcome(prefs);
      expect(outcome!.ok, isTrue);
    });
  });

  group('recoveryOutcomeCodeOf', () {
    test('FirebaseAuthException → its code (never the message)', () {
      final code = recoveryOutcomeCodeOf(
        FirebaseAuthException(
          code: 'invalid-action-code',
          message: 'user@secret.com leaked',
        ),
      );
      expect(code, 'invalid-action-code');
      expect(code.contains('secret'), isFalse);
    });

    test('other errors → runtimeType only (PII-safe)', () {
      expect(
        recoveryOutcomeCodeOf(StateError('email: x@y.com')),
        'StateError',
      );
    });
  });
}
