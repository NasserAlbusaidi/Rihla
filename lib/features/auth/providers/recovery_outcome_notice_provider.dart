import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

import '../../../core/config/firebase_config.dart';
import '../../../core/providers/settings_provider.dart';
import '../../../core/services/app_messenger.dart';
import '../../../core/services/cache_isolation_controller.dart';
import '../services/recovery_outcome_notice.dart';

/// Cold-boot consumer of the #439 recovery-outcome marker: shows the snack
/// the pre-restart process could never show, and emits the authoritative
/// Sentry event for release builds. One-shot — the read clears the marker.
final recoveryOutcomeNoticeProvider = Provider<void>((ref) {
  final prefs = ref.watch(sharedPreferencesProvider);
  WidgetsBinding.instance.addPostFrameCallback((_) {
    // Never consume the marker mid-swap: engageIsolation invalidates the
    // bootstrap chain, and a re-build here could eat a marker the imminent
    // restart was written to deliver to the NEXT boot.
    if (ref.read(cacheIsolationProvider)) return;
    surfaceRecoveryOutcome(
      prefs: prefs,
      // Throws [core/no-app] when Firebase is absent (it does NOT return
      // null) — surfaceRecoveryOutcome guards the call.
      currentUid: () => FirebaseConfig.currentUser?.uid,
      showSnack: (message, {bool isError = false}) {
        final messenger = appMessengerKey.currentState;
        if (messenger == null) return;
        messenger
          ..removeCurrentSnackBar()
          ..showSnackBar(
            SnackBar(
              content: Text(message),
              backgroundColor: isError ? Colors.red.shade700 : null,
              behavior: SnackBarBehavior.floating,
              duration: const Duration(seconds: 4),
            ),
          );
      },
      capture: (message) => unawaited(
        Sentry.captureMessage(message, level: SentryLevel.error),
      ),
    );
  });
});
