import 'package:flutter_riverpod/flutter_riverpod.dart';

/// True once an in-session UID swap (recovery / sign-out / deletion) has
/// engaged cache isolation. In-memory only — never reset in-process, because a
/// swap is always followed by a true process restart (the cold boot clears it).
///
/// `SafarApp.build` reads this FIRST and short-circuits to an opaque overlay,
/// so no cached financials from the outgoing UID can render during the swap →
/// restart window (#45 §3.7).
final cacheIsolationProvider = StateProvider<bool>((ref) => false);

/// Set true when [CacheIsolationController.restart] cannot complete the native
/// process restart — the channel is absent or threw. The isolation overlay
/// watches this to immediately surface a manual restart affordance, so a failed
/// `restart()` can never leave the user stranded on an opaque cover with no
/// escape (#45 §6.3). The dirty flag is already persisted before the swap, so
/// any cold boot (including a user-forced relaunch) still clears the outgoing
/// UID's cache regardless of how the restart resolves.
final cacheIsolationRestartFailedProvider = StateProvider<bool>((ref) => false);

/// Seam over the in-session cache-isolation window.
///
/// Services depend on this abstraction (not the concrete Riverpod/MethodChannel
/// wiring) so the swap flows can be unit-tested with a recording fake. The
/// concrete [PlatformCacheIsolationController] lives in the provider layer
/// (`features/auth/providers/cache_isolation_controller_provider.dart`) because
/// it needs a long-lived `Ref` to flip [cacheIsolationProvider] and tear down
/// the leaf subscription providers.
abstract class CacheIsolationController {
  /// Synchronously flips [cacheIsolationProvider] true (covering all cached UI)
  /// and disposes the live subscription holders, BEFORE any auth change.
  void engageIsolation();

  /// Performs a TRUE process restart (not a `flutter_phoenix` widget rebirth):
  /// the cold boot yields an un-started Firestore instance so the boot barrier
  /// may legally call `clearPersistence()`. Device-validated (#45 §6.1).
  Future<void> restart();
}
