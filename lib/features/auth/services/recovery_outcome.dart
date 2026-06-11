import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// PII-safe outcome of a swap that ends in a forced restart (#439).
///
/// The three swap methods (`restoreWithGoogle` / `restoreWithEmailLink` /
/// `signOutCurrentDevice`) restart the process in a `finally`, so neither
/// their success snackbars nor their error rethrows can ever reach the user
/// — and on release builds there is zero Sentry signal. This marker is
/// written BEFORE that restart (mirroring the `markFirestorePersistenceDirty`
/// awaited-pre-restart precedent) and consumed one-shot on the next cold
/// boot, which surfaces the message and emits the authoritative Sentry event.
///
/// PII rules: `code` is ONLY a [FirebaseAuthException.code] or an error
/// runtimeType — never a message, email, UID, oobCode, or link.
@immutable
class RecoveryOutcome {
  const RecoveryOutcome({
    required this.op,
    required this.ok,
    required this.atMillis,
    this.code,
  });

  static const String prefsKey = 'auth.recoveryOutcome';
  static const String opGoogle = 'google';
  static const String opRecover = 'recover';
  static const String opSignOut = 'signout';
  static const int _version = 1;

  final String op;
  final bool ok;
  final String? code;
  final int atMillis;

  Map<String, Object> toJson() => {
        'v': _version,
        'op': op,
        'ok': ok,
        if (code != null) 'code': code!,
        'atMillis': atMillis,
      };
}

/// Guarded — a failed prefs write must never skip the guaranteed restart.
Future<void> writeRecoveryOutcome(
  SharedPreferences prefs, {
  required String op,
  required bool ok,
  String? code,
}) async {
  try {
    final outcome = RecoveryOutcome(
      op: op,
      ok: ok,
      code: code,
      atMillis: DateTime.now().millisecondsSinceEpoch,
    );
    await prefs.setString(RecoveryOutcome.prefsKey, jsonEncode(outcome.toJson()));
  } catch (_) {
    // Losing the marker costs a notice, never the flow.
  }
}

/// One-shot: the marker is removed on read (success or malformed alike),
/// mirroring `CacheUidBarrier.reconcile`'s read-act-clear shape.
RecoveryOutcome? readAndClearRecoveryOutcome(SharedPreferences prefs) {
  try {
    final raw = prefs.getString(RecoveryOutcome.prefsKey);
    if (raw == null) return null;
    // Clear first so a malformed marker can't replay forever.
    prefs.remove(RecoveryOutcome.prefsKey);
    final decoded = jsonDecode(raw);
    if (decoded is! Map<String, dynamic>) return null;
    final op = decoded['op'];
    final ok = decoded['ok'];
    final atMillis = decoded['atMillis'];
    if (op is! String || ok is! bool || atMillis is! int) return null;
    return RecoveryOutcome(
      op: op,
      ok: ok,
      code: decoded['code'] as String?,
      atMillis: atMillis,
    );
  } catch (_) {
    try {
      prefs.remove(RecoveryOutcome.prefsKey);
    } catch (_) {
      // Best-effort cleanup only.
    }
    return null;
  }
}

/// PII-safe error identifier for the marker.
String recoveryOutcomeCodeOf(Object error) =>
    error is FirebaseAuthException ? error.code : error.runtimeType.toString();
