import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/cache_service.dart';
import '../services/sync_service.dart';

/// Connectivity state
enum ConnectivityStatus { online, offline, syncing }

/// Connectivity state provider
final connectivityProvider =
    StateNotifierProvider<ConnectivityNotifier, ConnectivityStatus>((ref) {
      return ConnectivityNotifier();
    });

/// Pending sync count provider
final pendingSyncCountProvider = FutureProvider<int>((ref) async {
  return await CacheService.getSyncQueueCount();
});

/// Connectivity state notifier
class ConnectivityNotifier extends StateNotifier<ConnectivityStatus> {
  Timer? _checkTimer;

  ConnectivityNotifier() : super(ConnectivityStatus.online) {
    _startPeriodicCheck();
  }

  void _startPeriodicCheck() {
    _checkTimer = Timer.periodic(const Duration(seconds: 30), (_) async {
      await checkConnectivity();
    });
  }

  /// Check current connectivity
  Future<void> checkConnectivity() async {
    final isOnline = await SyncService.isOnline();
    state = isOnline ? ConnectivityStatus.online : ConnectivityStatus.offline;
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

/// Sync provider for triggering syncs
final syncProvider = Provider<SyncController>((ref) {
  return SyncController(ref);
});

/// Sync controller
class SyncController {
  final Ref _ref;

  SyncController(this._ref);

  /// Trigger a full sync
  Future<SyncResult> fullSync(String userId) async {
    _ref.read(connectivityProvider.notifier).setSyncing();

    try {
      final result = await SyncService.fullSync(userId);
      _ref.read(connectivityProvider.notifier).setOnline();
      _ref.invalidate(pendingSyncCountProvider);
      return result;
    } catch (e) {
      _ref.read(connectivityProvider.notifier).setOffline();
      rethrow;
    }
  }

  /// Sync pending changes only
  Future<SyncResult> syncPending() async {
    _ref.read(connectivityProvider.notifier).setSyncing();

    try {
      final result = await SyncService.syncPendingChanges();
      _ref.read(connectivityProvider.notifier).setOnline();
      _ref.invalidate(pendingSyncCountProvider);
      return result;
    } catch (e) {
      _ref.read(connectivityProvider.notifier).setOffline();
      rethrow;
    }
  }
}
