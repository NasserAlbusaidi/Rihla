import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// Prefs key holding the last recovery failure to surface after the forced
/// restart. PII-safe: only a Firebase error `code` + the in-flight `op`.
const String kRecoveryFailureKey = 'auth.recoveryFailure';

/// A persisted recovery failure, consumed once on the next cold boot.
class RecoveryFailureNotice {
  const RecoveryFailureNotice({required this.code, required this.op});

  /// The `FirebaseAuthException.code` (e.g. `invalid-action-code`).
  final String code;

  /// `AuthRecoveryService.opRecover` | `opLink`.
  final String op;
}

/// Persists a recovery failure marker. Awaited at the callsite so it is flushed
/// to disk before the recover path's `System.exit(0)` restart.
Future<void> writeRecoveryFailureNotice(
  SharedPreferences prefs, {
  required String code,
  required String op,
}) =>
    prefs.setString(kRecoveryFailureKey, jsonEncode({'code': code, 'op': op}));

/// Reads the marker WITHOUT clearing it (a failed display must not silently
/// drop it). Returns null on absent or malformed data — never throws.
RecoveryFailureNotice? readRecoveryFailureNotice(SharedPreferences prefs) {
  final raw = prefs.getString(kRecoveryFailureKey);
  if (raw == null || raw.isEmpty) return null;
  try {
    final decoded = jsonDecode(raw);
    if (decoded is! Map) return null;
    final code = decoded['code'];
    final op = decoded['op'];
    if (code is! String || op is! String) return null;
    return RecoveryFailureNotice(code: code, op: op);
  } catch (_) {
    return null;
  }
}

Future<void> clearRecoveryFailureNotice(SharedPreferences prefs) =>
    prefs.remove(kRecoveryFailureKey);
