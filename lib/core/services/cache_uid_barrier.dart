import 'package:shared_preferences/shared_preferences.dart';

import 'firestore_cache_gate.dart';

/// The UID the on-device Firestore cache currently belongs to.
const String kLastActiveUidKey = 'auth.lastActiveUid';

/// Set true by an in-session UID swap (recovery / sign-out / deletion) BEFORE
/// the auth change; cleared by the barrier after a successful clear. Durable
/// crash-safety net: a process death between set-dirty and restart still
/// clears on the next launch.
const String kFirestorePersistenceDirtyKey = 'auth.firestorePersistenceDirty';

/// Pure decision: should the on-device Firestore cache be cleared on this boot?
///
/// - `forceClear`: a UID swap demonstrably happened on THIS boot (e.g. the
///   internal-error restored-session retry minted a fresh anon UID). Clears even
///   when no marker exists yet — closes the upgrade-first-boot swap leak.
/// - A bare null marker (first install / the upgrade that ships this key) does
///   NOT clear: clearing would drop every existing user's same-UID un-synced
///   offline writes.
bool shouldClearCache({
  required String? lastActiveUid,
  required String currentUid,
  required bool dirty,
  required bool forceClear,
}) =>
    forceClear || dirty || (lastActiveUid != null && lastActiveUid != currentUid);

/// Cold-start cache barrier: the single site that clears Firestore persistence.
///
/// Runs inside `FirebaseConfig.ensureAnonymousSession` after the session settles
/// and before `SafarApp` renders, so the clear precedes the first Firestore read.
class CacheUidBarrier {
  CacheUidBarrier({
    required SharedPreferences prefs,
    required FirestoreCacheGate cacheGate,
  })  : _prefs = prefs,
        _cacheGate = cacheGate;

  final SharedPreferences _prefs;
  final FirestoreCacheGate _cacheGate;

  Future<void> reconcile(String currentUid, {bool forceClear = false}) async {
    final lastActiveUid = _prefs.getString(kLastActiveUidKey);
    final dirty = _prefs.getBool(kFirestorePersistenceDirtyKey) ?? false;

    if (shouldClearCache(
      lastActiveUid: lastActiveUid,
      currentUid: currentUid,
      dirty: dirty,
      forceClear: forceClear,
    )) {
      await _cacheGate.clearPersistence();
      await _prefs.setBool(kFirestorePersistenceDirtyKey, false);
    }
    await _prefs.setString(kLastActiveUidKey, currentUid);
  }
}
