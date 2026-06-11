import 'package:shared_preferences/shared_preferences.dart';

import 'auth_error_humanizer.dart';
import 'recovery_outcome.dart';

/// Surfaces (and clears) a persisted [RecoveryOutcome] on cold boot (#439).
///
/// Pure logic with injected sinks so it unit-tests without Sentry or a
/// messenger; the provider wires the real ones. The capture string is the
/// authoritative release-build signal for a recovery failure — PII-safe by
/// construction (op + code only).
void surfaceRecoveryOutcome({
  required SharedPreferences prefs,
  required void Function(String message, {bool isError}) showSnack,
  required void Function(String message) capture,
}) {
  final outcome = readAndClearRecoveryOutcome(prefs);
  if (outcome == null) return;

  if (!outcome.ok) {
    final code = outcome.code ?? 'unknown';
    showSnack(humanizeAuthErrorCode(code), isError: true);
    capture('recovery_failed op=${outcome.op} code=$code');
    return;
  }

  // A successful sign-out needs no toast — the fresh anonymous home says it.
  if (outcome.op == RecoveryOutcome.opGoogle ||
      outcome.op == RecoveryOutcome.opRecover) {
    showSnack('Account restored.', isError: false);
  }
}
