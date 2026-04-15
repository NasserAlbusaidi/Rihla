import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../config/firebase_config.dart';

/// Connectivity state
enum ConnectivityStatus { online, offline, syncing }

/// Connectivity state provider
final connectivityProvider =
    StateNotifierProvider<ConnectivityNotifier, ConnectivityStatus>((ref) {
      return ConnectivityNotifier();
    });

/// Connectivity state notifier.
///
/// Checks connectivity by attempting a Firestore server-only read against
/// the `inviteCodes` collection.
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

  ConnectivityNotifier() : super(ConnectivityStatus.online) {
    try {
      WidgetsBinding.instance.addObserver(this);
    } catch (_) {
      // No binding in unit tests — lifecycle observation skipped.
    }
    _startPeriodicCheck();
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
  /// A [FirebaseException] with code `unavailable` indicates no network.
  ///
  /// Reads from `inviteCodes` (requires auth — anonymous session must be
  /// established before this runs).
  Future<bool> _isOnline() async {
    try {
      await FirebaseConfig.firestore
          .collection('inviteCodes')
          .limit(1)
          .get(const GetOptions(source: Source.server));
      return true;
    } catch (e) {
      return false;
    }
  }

  /// Check current connectivity and update state.
  ///
  /// Firestore handles offline write replay automatically, so there is no
  /// manual sync trigger needed on the offline→online transition.
  Future<void> checkConnectivity() async {
    final isOnline = await _isOnline();
    if (!mounted) return;

    if (isOnline) {
      if (state != ConnectivityStatus.online) {
        debugPrint('Connectivity restored (Firestore reachable)');
      }
      state = ConnectivityStatus.online;
    } else {
      state = ConnectivityStatus.offline;
    }
  }

  /// Set syncing state
  void setSyncing() {
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
    _checkTimer?.cancel();
    try {
      WidgetsBinding.instance.removeObserver(this);
    } catch (_) {
      // No binding in unit tests.
    }
    super.dispose();
  }
}
