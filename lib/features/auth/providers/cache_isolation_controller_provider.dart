import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/firebase_config.dart';
import '../../../core/providers/app_bootstrap_provider.dart';
import '../../../core/providers/balance_aggregate_freshness_provider.dart';
import '../../../core/providers/connectivity_provider.dart';
import '../../../core/services/cache_isolation_controller.dart';
import '../../../core/services/notification_service.dart';
import 'auth_email_link_bootstrap_provider.dart';

/// Platform channel that triggers a true Android process restart. The native
/// handler (MainActivity.kt) relaunches via the launch Intent then calls
/// `Runtime.getRuntime().exit(0)`, so the next launch is a genuine cold boot
/// with an un-started Firestore instance (#45 §6.1).
const MethodChannel kCacheIsolationChannel = MethodChannel(
  'com.safar.safar/cache_isolation',
);

/// Production [CacheIsolationController].
///
/// Holds the long-lived `Ref` of [cacheIsolationControllerProvider] (a provider
/// that is never invalidated), so [engageIsolation] can safely invalidate OTHER
/// providers without disposing the ref it runs on.
class PlatformCacheIsolationController implements CacheIsolationController {
  PlatformCacheIsolationController({required Ref ref, MethodChannel? channel})
    : _ref = ref,
      _channel = channel ?? kCacheIsolationChannel;

  final Ref _ref;
  final MethodChannel _channel;

  @override
  void engageIsolation() {
    _ref.read(cacheIsolationProvider.notifier).state = true;
    // Tear down the live subscription holders BEFORE the swap so their
    // uriLinkStream / onTokenRefresh listeners and the `fcm_tokens/{uid}` write
    // don't run cross-UID during the up-to-70s recovery window. These are plain
    // (non-autoDispose) providers, so invalidating only the parent
    // appBootstrapProvider would NOT dispose them — invalidate the leaves
    // directly (#45 §3.7 / R5 P2-1).
    _ref.invalidate(authEmailLinkBootstrapProvider);
    _ref.invalidate(balanceAggregateFreshnessProvider);
    _ref.invalidate(connectivityProvider);
    _ref.invalidate(notificationServiceProvider);
    _ref.invalidate(appBootstrapProvider);
  }

  @override
  Future<void> restart() async {
    try {
      await _channel.invokeMethod<void>('restart');
    } catch (error, stackTrace) {
      // The native restart channel is absent (iOS / a build without the
      // handler) or threw. Do NOT rethrow — a propagating restart() leaves the
      // isolation overlay mounted with no escape. Flip the failed flag so the
      // overlay surfaces a manual restart affordance instead. The dirty flag is
      // already set before the swap, so any cold boot still clears the outgoing
      // UID's cache (#45 §6.3 / codex re-gate [P1]).
      FirebaseConfig.log(
        'Cache isolation: native restart failed (${error.runtimeType}) — '
        'surfacing manual restart affordance',
        stackTrace: stackTrace,
      );
      _ref.read(cacheIsolationRestartFailedProvider.notifier).state = true;
    }
  }
}

final cacheIsolationControllerProvider = Provider<CacheIsolationController>((
  ref,
) {
  return PlatformCacheIsolationController(ref: ref);
});
