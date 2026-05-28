import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart' as firebase_auth;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/config/firebase_config.dart';
import '../../../core/providers/settings_provider.dart';
import '../../../core/services/local_database.dart';
import '../providers/auth_provider.dart';

/// Function the listener calls to wipe the local SQLite cache. Indirected
/// through a provider so tests can override with a fake that records calls.
typedef CacheWipeFn = Future<void> Function();
typedef CacheFileExistsFn = Future<bool> Function();

abstract class CacheOwnerStore {
  String? readOwnerUid();
  Future<void> saveOwnerUid(String? uid);
}

class SharedPreferencesCacheOwnerStore implements CacheOwnerStore {
  SharedPreferencesCacheOwnerStore(this._prefs);

  static const ownerUidKey = 'localCache.ownerUid';

  final SharedPreferences _prefs;

  @override
  String? readOwnerUid() => _prefs.getString(ownerUidKey);

  @override
  Future<void> saveOwnerUid(String? uid) async {
    if (uid == null || uid.isEmpty) {
      await _prefs.remove(ownerUidKey);
      return;
    }
    await _prefs.setString(ownerUidKey, uid);
  }
}

final cacheWipeFnProvider = Provider<CacheWipeFn>((ref) {
  return LocalDatabase.wipeAndReinitialize;
});

final cacheFileExistsProvider = Provider<CacheFileExistsFn>((ref) {
  return LocalDatabase.cacheFileExists;
});

final cacheOwnerStoreProvider = Provider<CacheOwnerStore>((ref) {
  return SharedPreferencesCacheOwnerStore(ref.watch(sharedPreferencesProvider));
});

enum UidCacheBarrierPhase { uninitialized, safe, wiping, failed }

class UidCacheBarrierState {
  const UidCacheBarrierState({
    required this.phase,
    this.safeUid,
    this.observedUid,
    this.previousUid,
    this.error,
    this.stackTrace,
  });

  const UidCacheBarrierState.uninitialized()
    : phase = UidCacheBarrierPhase.uninitialized,
      safeUid = null,
      observedUid = null,
      previousUid = null,
      error = null,
      stackTrace = null;

  final UidCacheBarrierPhase phase;
  final String? safeUid;
  final String? observedUid;
  final String? previousUid;
  final Object? error;
  final StackTrace? stackTrace;

  bool get isBlocking {
    return phase == UidCacheBarrierPhase.wiping ||
        phase == UidCacheBarrierPhase.failed;
  }

  UidCacheBarrierState copyWith({
    UidCacheBarrierPhase? phase,
    String? safeUid,
    String? observedUid,
    String? previousUid,
    Object? error,
    StackTrace? stackTrace,
    bool clearError = false,
  }) {
    return UidCacheBarrierState(
      phase: phase ?? this.phase,
      safeUid: safeUid ?? this.safeUid,
      observedUid: observedUid ?? this.observedUid,
      previousUid: previousUid ?? this.previousUid,
      error: clearError ? null : error ?? this.error,
      stackTrace: clearError ? null : stackTrace ?? this.stackTrace,
    );
  }
}

final uidCacheBarrierProvider =
    StateNotifierProvider<UidCacheBarrierNotifier, UidCacheBarrierState>((ref) {
      final notifier = UidCacheBarrierNotifier(
        wipe: ref.read(cacheWipeFnProvider),
        cacheFileExists: ref.read(cacheFileExistsProvider),
        ownerStore: ref.read(cacheOwnerStoreProvider),
      );
      ref.listen<AsyncValue<firebase_auth.User?>>(authUserChangesProvider, (
        previous,
        next,
      ) {
        if (!next.hasValue) return;
        notifier.observeUid(next.valueOrNull?.uid);
      }, fireImmediately: true);
      return notifier;
    });

/// Current Firebase UID after the local cache is known safe for that UID.
final safeUidProvider = Provider<String?>((ref) {
  return ref.watch(uidCacheBarrierProvider).safeUid;
});

class UidCacheBarrierNotifier extends StateNotifier<UidCacheBarrierState> {
  UidCacheBarrierNotifier({
    required CacheWipeFn wipe,
    required CacheFileExistsFn cacheFileExists,
    required CacheOwnerStore ownerStore,
  }) : _wipe = wipe,
       _cacheFileExists = cacheFileExists,
       _ownerStore = ownerStore,
       super(const UidCacheBarrierState.uninitialized());

  final CacheWipeFn _wipe;
  final CacheFileExistsFn _cacheFileExists;
  final CacheOwnerStore _ownerStore;
  var _seenInitial = false;
  String? _lastObservedUid;
  Future<void>? _wipeInFlight;

  void observeUid(String? uid) {
    if (!_seenInitial) {
      _seenInitial = true;
      _lastObservedUid = uid;
      unawaited(_acceptInitialUid(uid));
      return;
    }

    if (uid == _lastObservedUid) return;

    final previousUid = _lastObservedUid;
    _lastObservedUid = uid;
    FirebaseConfig.log(
      'UidCacheBarrier: uid $previousUid -> $uid; wiping cache',
    );
    _startWipe(previousUid: previousUid, observedUid: uid);
  }

  Future<void> retry() async {
    if (state.phase != UidCacheBarrierPhase.failed) return;
    _startWipe(previousUid: state.previousUid, observedUid: state.observedUid);
    await _wipeInFlight;
  }

  void _startWipe({
    required String? previousUid,
    required String? observedUid,
  }) {
    if (_wipeInFlight != null) return;

    state = UidCacheBarrierState(
      phase: UidCacheBarrierPhase.wiping,
      safeUid: null,
      observedUid: observedUid,
      previousUid: previousUid,
    );
    _wipeInFlight = _wipeForObservedUid(observedUid);
  }

  Future<void> _acceptInitialUid(String? uid) async {
    try {
      final persistedUid = _ownerStore.readOwnerUid();
      final hasCacheFile = await _cacheFileExists();
      final hasOrphanedCache =
          uid != null && persistedUid == null && hasCacheFile;
      final ownerChanged = persistedUid != null && persistedUid != uid;

      if (hasOrphanedCache || ownerChanged) {
        FirebaseConfig.log(
          'UidCacheBarrier: cold-start cache owner $persistedUid -> $uid; wiping cache',
        );
        _startWipe(previousUid: persistedUid, observedUid: uid);
        return;
      }

      await _markSafe(uid);
    } catch (error, stack) {
      FirebaseConfig.log(
        'UidCacheBarrier: cold-start cache ownership check failed',
        error: error,
        stackTrace: stack,
      );
      if (!mounted) return;
      state = UidCacheBarrierState(
        phase: UidCacheBarrierPhase.failed,
        safeUid: null,
        observedUid: uid,
        error: error,
        stackTrace: stack,
      );
    }
  }

  Future<void> _wipeForObservedUid(String? observedUid) async {
    try {
      await _wipe();
      await _markSafe(observedUid);
    } catch (error, stack) {
      FirebaseConfig.log(
        'UidCacheBarrier: cache wipe failed',
        error: error,
        stackTrace: stack,
      );
      if (!mounted) return;
      state = state.copyWith(
        phase: UidCacheBarrierPhase.failed,
        safeUid: null,
        error: error,
        stackTrace: stack,
      );
    } finally {
      _wipeInFlight = null;
    }
  }

  Future<void> _markSafe(String? uid) async {
    await _ownerStore.saveOwnerUid(uid);
    if (!mounted) return;
    state = UidCacheBarrierState(
      phase: UidCacheBarrierPhase.safe,
      safeUid: uid,
      observedUid: uid,
    );
  }
}

/// Activates the local-cache UID barrier.
///
/// Account-recovery spec FR-CACHE-1 / OD-3: `safar_cache.db` is a per-UID
/// hydration of Firestore reads. On any UID swap (sign-out + new anon
/// session, or recovery via email-link) the file must be deleted before
/// providers serve rows from the previous user.
///
/// First emission is compared with the persisted cache owner and any residual
/// cache file before being published as safe. Subsequent emissions with a
/// different UID also trigger the cache wipe. Identical UIDs (e.g.
/// profile/email mutations from `linkWithCredential`) are ignored — the UID
/// is preserved through linking, so cache state remains valid.
final uidChangeListenerProvider = Provider<void>((ref) {
  ref.watch(uidCacheBarrierProvider);
});
