import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

import '../../../core/config/firebase_config.dart';
import '../../../core/providers/settings_provider.dart';
import '../../../core/services/app_messenger.dart';
import '../../../core/services/cache_isolation_controller.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../services/recovery_outcome_notice.dart';
import 'device_name_self_heal_provider.dart';

/// Real (throws-guarded) `currentUid` thunk — overridden in tests so the
/// #839 probe path is reachable without a live Firebase app. Throws
/// `[core/no-app]` when Firebase is absent (it does NOT return null);
/// `surfaceRecoveryOutcome` guards the call.
final recoveryOutcomeCurrentUidProvider = Provider<String? Function()>(
  (ref) => () => FirebaseConfig.currentUser?.uid,
);

/// The #839 data-presence probe — overridable in tests (see
/// [hasAnyGroupMembership] for the real, Source.server-backed default).
final recoveryOutcomeProbeProvider =
    Provider<Future<bool?> Function(String uid)>((ref) => hasAnyGroupMembership);

/// EN-literal fallback copy — used when `appMessengerKey.currentContext` is
/// unavailable or carries no `Localizations` ancestor, so the notice can
/// never crash for want of a BuildContext.
const _fallbackMessages = (
  restoredOk: 'Account restored.',
  restoredEmpty:
      'Signed in, but this account has no groups yet. Restored the wrong '
      'account? Profile → Account → Sign out lets you try another.',
  swapIncomplete: "Account restore didn't complete. Please try again.",
);

/// Resolves the three notice strings via the mounted app's own context
/// (`appMessengerKey.currentContext` → `AppLocalizations.of(ctx)`), falling
/// back to the EN literals when no context / no `Localizations` ancestor is
/// available. Resolved once, synchronously, before the async probe runs —
/// `surfaceRecoveryOutcome` takes pre-resolved copy, not a BuildContext.
RecoveryOutcomeMessages _resolveMessages() {
  final ctx = appMessengerKey.currentContext;
  if (ctx != null) {
    try {
      final l10n = AppLocalizations.of(ctx);
      return (
        restoredOk: l10n.recoveryRestoredOk,
        restoredEmpty: l10n.recoveryRestoredEmpty,
        swapIncomplete: l10n.recoverySwapIncomplete,
      );
    } catch (_) {
      // No Localizations ancestor at this context — fall through to EN.
    }
  }
  return _fallbackMessages;
}

/// Cold-boot consumer of the #439 recovery-outcome marker: shows the snack
/// the pre-restart process could never show, and emits the authoritative
/// Sentry event for release builds. One-shot — the read clears the marker.
final recoveryOutcomeNoticeProvider = Provider<void>((ref) {
  final prefs = ref.watch(sharedPreferencesProvider);
  final currentUid = ref.watch(recoveryOutcomeCurrentUidProvider);
  final hasData = ref.watch(recoveryOutcomeProbeProvider);
  WidgetsBinding.instance.addPostFrameCallback((_) {
    // Never consume the marker mid-swap: engageIsolation invalidates the
    // bootstrap chain, and a re-build here could eat a marker the imminent
    // restart was written to deliver to the NEXT boot.
    if (ref.read(cacheIsolationProvider)) return;
    unawaited(
      surfaceRecoveryOutcome(
        prefs: prefs,
        currentUid: currentUid,
        hasData: hasData,
        messages: _resolveMessages(),
        showSnack: (
          message, {
          bool isError = false,
          Duration duration = const Duration(seconds: 4),
        }) {
          // Gate r1 mid-swap re-check: the marker is cleared-on-read before
          // this async probe runs, so a swap that engages WHILE the probe is
          // in flight must still drop the notice — the outgoing shell is
          // about to be torn down and a stale toast over it is misleading.
          if (ref.read(cacheIsolationProvider)) return;
          final messenger = appMessengerKey.currentState;
          if (messenger == null) return;
          messenger
            ..removeCurrentSnackBar()
            ..showSnackBar(
              SnackBar(
                content: Text(message),
                // design-token-justified: context-less global-messenger error
                // snack — the outgoing shell may be mid-teardown, so there is
                // no reliable themed context.colors here; a fixed Material red
                // keeps the error background theme-resolution-free.
                backgroundColor: isError ? Colors.red.shade700 : null,
                behavior: SnackBarBehavior.floating,
                duration: duration,
              ),
            );
        },
        capture: (message) => unawaited(
          Sentry.captureMessage(message, level: SentryLevel.error),
        ),
      ).whenComplete(() {
        // #990: the verified-success arm may have written the name-seed
        // breadcrumb — bump the revision so the self-heal re-evaluates
        // explicitly instead of relying on a groups emission happening to
        // arrive after this async completion.
        try {
          ref.read(deviceNameSeedRevisionProvider.notifier).state++;
        } catch (_) {
          // Disposed mid-swap — the fresh boot re-evaluates on its own.
        }
      }),
    );
  });
});
