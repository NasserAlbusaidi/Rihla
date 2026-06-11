import 'package:shared_preferences/shared_preferences.dart';

import 'auth_error_humanizer.dart';
import 'recovery_outcome.dart';

/// Surfaces (and clears) a persisted [RecoveryOutcome] on cold boot (#439).
///
/// Pure logic with injected sinks so it unit-tests without Sentry or a
/// messenger; the provider wires the real ones. The capture string is the
/// authoritative release-build signal for a recovery failure — PII-safe by
/// construction (op + code only, never a UID).
///
/// A success marker naming an [RecoveryOutcome.expectedUid] is verified
/// against [currentUid] before the success notice shows (#458) — `ok` only
/// proves the auth API call succeeded BEFORE the forced restart; the swap is
/// real only if it survived the process kill.
void surfaceRecoveryOutcome({
  required SharedPreferences prefs,
  required String? Function() currentUid,
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
  if (outcome.op != RecoveryOutcome.opGoogle &&
      outcome.op != RecoveryOutcome.opRecover) {
    return;
  }

  final expected = outcome.expectedUid;
  if (expected != null) {
    bool verified;
    String? uid;
    try {
      uid = currentUid();
      verified = true;
    } catch (_) {
      // Auth unreadable (no Firebase app) — trust the claim rather than
      // false-alarm on something we cannot verify.
      verified = false;
    }
    if (verified && uid != expected) {
      showSnack(
        "Account restore didn't complete. Please try again.",
        isError: true,
      );
      capture('recovery_swap_not_durable op=${outcome.op}');
      return;
    }
  }

  showSnack('Account restored.', isError: false);
}
