import 'package:shared_preferences/shared_preferences.dart';

import 'auth_recovery_service.dart';
import 'pending_gate_intent.dart';

/// Cold-boot replay for a [PendingGateIntent] (#428): navigates back into the
/// create flow the gate-conflict restart interrupted. Navigation only — the
/// CreateGroupScreen prefills from the marker and clears it, so a boot that
/// never reaches the screen leaves the marker for the next one (until TTL).
abstract final class GateIntentReplay {
  /// [go] is `GoRouter.go` — injected as a plain callback for testability.
  ///
  /// Skipped while an email-restore op is pending: that bootstrap ends in
  /// another forced restart, which would destroy the replayed form again.
  /// The marker survives untouched and replays on the boot after.
  static void maybeReplay(SharedPreferences prefs, void Function(String) go) {
    final pendingOp = prefs.getString(AuthRecoveryService.inFlightOpPrefsKey);
    if (pendingOp == AuthRecoveryService.opRecover) return;

    final intent = PendingGateIntent.read(prefs);
    if (intent == null || intent.type != PendingGateIntent.typeCreate) return;
    go('/create-group');
  }
}
