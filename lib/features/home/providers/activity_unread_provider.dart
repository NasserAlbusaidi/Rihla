import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/providers/settings_provider.dart';
import 'dashboard_providers.dart';

/// SharedPreferences key holding the last time the Activity tab was seen (UTC
/// ISO-8601 string). Absent until the user first opens the tab.
const String kActivityLastSeenKey = 'activityLastSeenIso';

/// Holds the last-seen Activity timestamp, seeded from SharedPreferences.
///
/// A plain `prefs.getString` read cannot drive the unread dot reactively — a
/// write does not notify Riverpod — so the value lives in a notifier that both
/// persists and updates state on [markSeenNow].
class ActivitySeenNotifier extends StateNotifier<String?> {
  ActivitySeenNotifier(this._prefs) : super(_prefs.getString(kActivityLastSeenKey));

  final SharedPreferences _prefs;

  /// Stamp "seen" at the current instant (UTC ISO-8601) and persist it.
  Future<void> markSeenNow() async {
    final iso = DateTime.now().toUtc().toIso8601String();
    state = iso;
    await _prefs.setString(kActivityLastSeenKey, iso);
  }
}

final activitySeenProvider =
    StateNotifierProvider<ActivitySeenNotifier, String?>(
      (ref) => ActivitySeenNotifier(ref.watch(sharedPreferencesProvider)),
    );

/// Whether the Activity tab has entries newer than the last time it was seen
/// (#808 PR2, D-PR2-2). Drives the bottom-nav dot.
///
/// Reads the still-live [crossGroupActivityProvider] (untouched by PR2) for the
/// newest timestamp. An empty feed is never unread; a non-empty feed with no
/// recorded last-seen IS unread.
final activityUnreadProvider = Provider<bool>((ref) {
  final entries =
      ref.watch(crossGroupActivityProvider).valueOrNull ??
      const <CrossGroupActivityEntry>[];
  if (entries.isEmpty) return false;

  // The provider sorts newest-first, but fold defensively rather than assume.
  final newest = entries
      .map((e) => e.log.timestamp)
      .reduce((a, b) => a.isAfter(b) ? a : b);

  final lastSeenIso = ref.watch(activitySeenProvider);
  if (lastSeenIso == null) return true;
  final lastSeen = DateTime.tryParse(lastSeenIso);
  if (lastSeen == null) return true;
  return newest.isAfter(lastSeen);
});
