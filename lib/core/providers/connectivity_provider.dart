import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../config/firebase_config.dart';

/// Connectivity state
enum ConnectivityStatus { online, offline, syncing }

/// One-shot reachability probe (init + app-resume backstop): returns true when
/// the server answered, false on a network error, null when inconclusive.
typedef ConnectivityProbe = Future<bool?> Function();

/// Live "is this snapshot from cache?" signal from the Firestore metadata
/// listener — `true` = served from cache (offline / not-yet-replayed),
/// `false` = served from the server (online). Injected in tests via a
/// `StreamController` so offline transitions are driven without a live Firebase
/// instance (`FakeFirebaseFirestore` acks instantly and can't model this).
typedef ConnectivitySyncSignals = Stream<bool> Function();

/// Connectivity state provider
final connectivityProvider =
    StateNotifierProvider<ConnectivityNotifier, ConnectivityStatus>((ref) {
      return ConnectivityNotifier();
    });

/// Connectivity state notifier — event-driven (#633).
///
/// Connectivity is derived from the Firestore SDK's own signals rather than a
/// wall-clock forced read:
///
/// * A persistent metadata listener on the caller's owner-only
///   `fcm_tokens/{uid}` document (`snapshots(includeMetadataChanges: true)`)
///   flips state on `metadata.isFromCache`: a server snapshot (`false`) means
///   online and **resolves the transient `syncing` state on the actual
///   reconnect/replay** (previously this lagged up to 60s — #682). A
///   cache snapshot (`true`) means offline, but only once a server snapshot has
///   been seen in this subscription, so the cold-start cache-first emission
///   never false-flips to offline.
/// * A one-shot [ConnectivityProbe] fires on construct and on app-resume as a
///   backstop for prompt offline detection before the first write / before the
///   listener has seen the server. There is **no** periodic forced read.
///
/// Firestore replays offline writes automatically via its persistence layer, so
/// there is no manual upload queue to flush. The listener is cancelled while the
/// app is backgrounded to avoid waking the radio.
class ConnectivityNotifier extends StateNotifier<ConnectivityStatus>
    with WidgetsBindingObserver {
  final ConnectivityProbe _connectivityProbe;
  final ConnectivitySyncSignals _syncSignals;
  StreamSubscription<bool>? _syncSub;

  /// Whether a server snapshot has been observed since the current
  /// subscription started. Guards against treating the cold-start cache-first
  /// emission as an offline transition. Reset on every (re-)subscribe.
  bool _sawServer = false;

  /// [startPeriodicChecks] gates the live connectivity mechanism (metadata
  /// listener + init probe). Production leaves it on; widget tests that mount a
  /// connectivity-watching screen pass `false` to get a listener-free notifier,
  /// otherwise the never-ending stream keeps `pumpAndSettle` from settling (the
  /// documented ConnectivityNotifier trap). Name kept for test compatibility.
  ConnectivityNotifier({
    ConnectivityProbe? connectivityProbe,
    ConnectivitySyncSignals? syncSignals,
    bool startPeriodicChecks = true,
  }) : _connectivityProbe = connectivityProbe ?? _defaultConnectivityProbe,
       _syncSignals = syncSignals ?? _defaultSyncSignals,
       super(ConnectivityStatus.online) {
    try {
      WidgetsBinding.instance.addObserver(this);
    } catch (_) {
      // No binding in unit tests — lifecycle observation skipped.
    }
    if (startPeriodicChecks) _startLiveChecks();
  }

  /// Whether the live connectivity subscription is currently active.
  @visibleForTesting
  bool get isLiveCheckActive => _syncSub != null;

  /// Default one-shot probe: a server-source read of `fcm_tokens/{uid}`.
  static Future<bool?> _defaultConnectivityProbe() async {
    try {
      final uid = FirebaseConfig.currentUser?.uid;
      if (uid == null) return null;
      await FirebaseConfig.firestore
          .collection('fcm_tokens')
          .doc(uid)
          .get(const GetOptions(source: Source.server));
      return true;
    } on FirebaseException catch (e) {
      if (e.code == 'unavailable' || e.code == 'deadline-exceeded') {
        return false;
      }
      return true;
    } catch (_) {
      return null;
    }
  }

  /// Default live signal: the `fcm_tokens/{uid}` metadata listener mapped to
  /// `metadata.isFromCache`. Returns an empty stream when there is no signed-in
  /// user so the subscription never targets `.doc(null)`. `FirebaseConfig`
  /// access throws `[core/no-app]` in unit tests without a Firebase app; the
  /// caller ([_subscribeSyncSignals]) catches that and fails open.
  static Stream<bool> _defaultSyncSignals() {
    final uid = FirebaseConfig.currentUser?.uid;
    if (uid == null) return const Stream<bool>.empty();
    return FirebaseConfig.firestore
        .collection('fcm_tokens')
        .doc(uid)
        .snapshots(includeMetadataChanges: true)
        .map((snap) => snap.metadata.isFromCache);
  }

  void _startLiveChecks() {
    _subscribeSyncSignals();
    unawaited(checkConnectivity());
  }

  void _subscribeSyncSignals() {
    _syncSub?.cancel();
    _sawServer = false;
    try {
      _syncSub = _syncSignals().listen(
        _onSyncSignal,
        // Async Firestore errors (permission-denied, transient) bypass a
        // synchronous try/catch — fail open, keep the current state.
        onError: (Object _) {},
      );
    } catch (_) {
      // No Firebase app / stream-build throw — fail open, no live subscription.
      _syncSub = null;
    }
  }

  /// Maps a live cache/server signal to a state transition.
  void _onSyncSignal(bool isFromCache) {
    if (!mounted) return;
    if (!isFromCache) {
      // Server answered — online, and this resolves `syncing` on the actual
      // reconnect/replay (#682 fix).
      _sawServer = true;
      state = ConnectivityStatus.online;
    } else if (_sawServer) {
      // Dropped back to cache after having reached the server — offline.
      state = ConnectivityStatus.offline;
    }
    // else: cold-start cache-first emission before any server contact — ignore
    // (the init/resume probe or a write-timeout drives offline instead).
  }

  Future<bool?> _isOnline() => _connectivityProbe();

  /// One-shot connectivity check (init + app-resume backstop).
  ///
  /// Uses [Source.server] via the probe so the SDK attempts a real network
  /// request. A null result is inconclusive and leaves state unchanged.
  Future<void> checkConnectivity() async {
    final isOnline = await _isOnline();
    if (!mounted) return;

    if (isOnline == true) {
      state = ConnectivityStatus.online;
    } else if (isOnline == false) {
      state = ConnectivityStatus.offline;
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      _syncSub?.cancel();
      _syncSub = null;
    } else if (state == AppLifecycleState.resumed) {
      _subscribeSyncSignals();
      unawaited(checkConnectivity());
    }
  }

  /// Set syncing state
  void setSyncing() {
    state = ConnectivityStatus.syncing;
  }

  /// Note that a write was just accepted locally by the Firestore SDK.
  ///
  /// Surfaces the transient `syncing` ("Saved — will sync") state **only when
  /// currently offline** — the SDK has queued the write and will replay it on
  /// reconnect (#357). When already online the write commits immediately, so
  /// this is a no-op. The metadata listener resolves `syncing` back to
  /// `online`/`offline` on the actual reconnect.
  void noteLocalWrite() {
    if (state == ConnectivityStatus.offline) {
      state = ConnectivityStatus.syncing;
    }
  }

  /// Note that a write TIMED OUT waiting for the server ack (#412).
  ///
  /// Unlike [noteLocalWrite], this is unconditional: a timed-out write is
  /// strong evidence of being offline. The SDK has the write queued; surface
  /// "Saved — will sync" regardless. The metadata listener resolves `syncing`
  /// back to `online`/`offline` on the actual reconnect.
  void noteQueuedWrite() {
    state = ConnectivityStatus.syncing;
  }

  /// Set online state
  void setOnline() {
    state = ConnectivityStatus.online;
  }

  /// Set offline state
  void setOffline() {
    state = ConnectivityStatus.offline;
  }

  @override
  void dispose() {
    _syncSub?.cancel();
    try {
      WidgetsBinding.instance.removeObserver(this);
    } catch (_) {
      // No binding in unit tests.
    }
    super.dispose();
  }
}
