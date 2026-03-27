import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
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
/// the `_health/ping` document.
///
/// Firestore handles offline writes automatically via its persistence layer,
/// so the offline→online auto-sync trigger is removed — there is no manual
/// upload queue to flush.
class ConnectivityNotifier extends StateNotifier<ConnectivityStatus> {
  Timer? _checkTimer;

  ConnectivityNotifier() : super(ConnectivityStatus.online) {
    _startPeriodicCheck();
  }

  void _startPeriodicCheck() {
    _checkTimer = Timer.periodic(const Duration(seconds: 60), (_) async {
      await checkConnectivity();
    });
  }

  /// Ping Firestore to check connectivity.
  ///
  /// Uses [Source.server] so the SDK attempts a real network request.
  /// A [FirebaseException] with code `unavailable` indicates no network.
  ///
  /// Reads from `inviteCodes` (publicly readable per security rules) rather
  /// than `_health/ping` which is blocked by the default-deny rule.
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
    super.dispose();
  }
}
