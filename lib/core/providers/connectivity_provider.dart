import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../config/firebase_config.dart';

/// Connectivity state
enum ConnectivityStatus { online, offline, syncing }

typedef ConnectivityProbe = Future<bool?> Function();

/// Connectivity state provider
final connectivityProvider =
    StateNotifierProvider<ConnectivityNotifier, ConnectivityStatus>((ref) {
      return ConnectivityNotifier();
    });

/// Connectivity state notifier.
///
/// Checks connectivity by attempting a Firestore server-only read against
/// the signed-in user's owner-only FCM token document.
///
/// Firestore handles offline writes automatically via its persistence layer,
/// so the offline→online auto-sync trigger is removed — there is no manual
/// upload queue to flush.
///
/// Pauses the periodic check when the app is backgrounded to avoid
/// wasting Firestore reads while the user isn't looking.
class ConnectivityNotifier extends StateNotifier<ConnectivityStatus>
    with WidgetsBindingObserver {
  Timer? _checkTimer;
  final ConnectivityProbe _connectivityProbe;

  /// [startPeriodicChecks] gates the 60s connectivity timer. Production leaves
  /// it on; widget tests that mount a connectivity-watching screen pass `false`
  /// to get a timer-free notifier, otherwise the periodic timer never settles
  /// and `pumpAndSettle` hangs (the documented ConnectivityNotifier trap).
  ConnectivityNotifier({
    ConnectivityProbe? connectivityProbe,
    bool startPeriodicChecks = true,
  }) : _connectivityProbe = connectivityProbe ?? _defaultConnectivityProbe,
       super(ConnectivityStatus.online) {
    try {
      WidgetsBinding.instance.addObserver(this);
    } catch (_) {
      // No binding in unit tests — lifecycle observation skipped.
    }
    if (startPeriodicChecks) _startPeriodicCheck();
  }

  /// Whether the periodic connectivity timer is currently scheduled.
  @visibleForTesting
  bool get isPeriodicCheckActive => _checkTimer != null;

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

  void _startPeriodicCheck() {
    _checkTimer?.cancel();
    _checkTimer = Timer.periodic(const Duration(seconds: 60), (_) async {
      await checkConnectivity();
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      _checkTimer?.cancel();
      _checkTimer = null;
    } else if (state == AppLifecycleState.resumed) {
      checkConnectivity();
      _startPeriodicCheck();
    }
  }

  /// Ping Firestore to check connectivity.
  ///
  /// Uses [Source.server] so the SDK attempts a real network request.
  /// A [FirebaseException] with code `unavailable` or `deadline-exceeded`
  /// indicates no network. Permission/auth/probe errors are not treated as
  /// offline, because they still mean the server answered.
  ///
  /// Reads the caller's own `fcm_tokens/{uid}` document. A missing document
  /// still proves the server is reachable, while avoiding any broad collection
  /// read permission.
  Future<bool?> _isOnline() => _connectivityProbe();

  /// Check current connectivity and update state.
  ///
  /// Firestore handles offline write replay automatically, so there is no
  /// manual sync trigger needed on the offline→online transition.
  Future<void> checkConnectivity() async {
    final isOnline = await _isOnline();
    if (!mounted) return;

    if (isOnline == true) {
      state = ConnectivityStatus.online;
    } else if (isOnline == false) {
      state = ConnectivityStatus.offline;
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
  /// this is a no-op (the existing success affordance covers it). The periodic
  /// probe resolves `syncing` back to `online`/`offline`, so no timer is added.
  void noteLocalWrite() {
    if (state == ConnectivityStatus.offline) {
      state = ConnectivityStatus.syncing;
    }
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
    _checkTimer?.cancel();
    try {
      WidgetsBinding.instance.removeObserver(this);
    } catch (_) {
      // No binding in unit tests.
    }
    super.dispose();
  }
}
