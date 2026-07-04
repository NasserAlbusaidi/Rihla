import 'package:shared_preferences/shared_preferences.dart';

/// One-release cleanup for the prefs marker written by the removed auth-intent
/// replay flow (#825).
///
/// The marker was only best-effort create-form prefill. This intentionally does
/// not replay or decode it; it only prevents stale upgrade state from lingering
/// after the replay/prefill machinery has been retired.
///
/// Errors intentionally bubble to the cold-start coordinator guard, which
/// reports them through `onStepError` while continuing boot.
abstract final class LegacyAuthMarkerCleanup {
  static const String legacyPrefsKey = 'auth.pendingGateIntent';

  static Future<void> clear(SharedPreferences prefs) async {
    await prefs.remove(legacyPrefsKey);
  }
}
