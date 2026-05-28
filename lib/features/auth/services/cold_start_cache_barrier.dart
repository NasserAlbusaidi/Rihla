import 'package:sentry_flutter/sentry_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/config/firebase_config.dart';

/// SharedPreferences key recording the most-recently-confirmed safe Firebase
/// UID. Read on cold start by [runColdStartCacheBarrier], rewritten on every
/// confirmed-safe UID transition by `uidChangeListenerProvider`.
const String lastObservedUidPrefsKey = 'auth.lastObservedUid';

/// Drops the SQLite cache on cold start when the previously-observed UID does
/// not match the settled session UID, or when a cache file exists with no
/// recorded UID (legacy v1.1 install hitting v1.2 for the first time).
///
/// Issue #45 — cross-UID cache leak fix. MUST run before any provider reads
/// or writes the cache; enforced by chaining into `_AuthGate._bootSequence`
/// so `SafarApp` does not render until this returns.
///
/// Wipe-before-persist ordering is load-bearing. If [wipe] throws the barrier
/// rethrows, leaving prefs stale so the next cold start retries. If the
/// process dies between wipe success and the prefs write, the next launch
/// re-detects identity drift and re-wipes a now-empty file (no-op via sqflite
/// `deleteDatabase` swallowing missing-file errors).
Future<void> runColdStartCacheBarrier({
  required SharedPreferences prefs,
  required String? currentUid,
  required Future<bool> Function() cacheFileExists,
  required Future<void> Function() wipe,
}) async {
  if (currentUid == null) return;

  final persistedUid = prefs.getString(lastObservedUidPrefsKey);

  String? wipeCause;
  if (persistedUid != null && persistedUid != currentUid) {
    wipeCause = 'identity_drift';
  } else if (persistedUid == null && await cacheFileExists()) {
    wipeCause = 'residual_cache';
  }

  if (wipeCause != null) {
    try {
      await wipe();
    } catch (error, stack) {
      Sentry.captureException(error, stackTrace: stack);
      rethrow;
    }
    FirebaseConfig.log(
      'cold_start_wipe cause=$wipeCause persisted=${persistedUid != null}',
    );
    Sentry.addBreadcrumb(
      Breadcrumb(
        category: 'auth.cache',
        message: 'cold_start_wipe',
        data: {'cause': wipeCause},
      ),
    );
  }

  await prefs.setString(lastObservedUidPrefsKey, currentUid);
}
