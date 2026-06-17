import 'package:shared_preferences/shared_preferences.dart';

/// #469: device-local marker that a durable (Google/email) account was
/// established on this device.
///
/// Set by *observing* the auth state — any non-anonymous session marks it
/// (in-place link, restore swap, or a durable session at cold boot) — so there
/// is no enumerated-establish-event path to miss. Cleared only when the durable
/// account is actually deleted. Read at delete time to gate an anon-shell delete
/// that would otherwise silently leave the durable account + its data intact
/// under a different uid.
///
/// Device-local prefs: an app reinstall wipes it, falling back to the #546
/// disclosure dialog (never a silent wrong-delete).
const String kDurableAccountEstablishedKey = 'auth.durableAccountEstablished';

bool durableAccountEstablished(SharedPreferences prefs) =>
    prefs.getBool(kDurableAccountEstablishedKey) ?? false;

/// Idempotent + guarded: a no-op when already set (so the per-emission
/// fire-and-forget call on every `userChanges` tick costs nothing for a durable
/// session), and never throws — losing the marker only falls back to the #546
/// disclosure, it must never crash an auth flow.
Future<void> markDurableAccountEstablished(SharedPreferences prefs) async {
  try {
    if (prefs.getBool(kDurableAccountEstablishedKey) == true) return;
    await prefs.setBool(kDurableAccountEstablishedKey, true);
  } catch (_) {
    // Best-effort only.
  }
}

Future<void> clearDurableAccountEstablished(SharedPreferences prefs) async {
  try {
    await prefs.remove(kDurableAccountEstablishedKey);
  } catch (_) {
    // Best-effort only.
  }
}
