import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/auth/providers/auth_email_link_bootstrap_provider.dart';
import '../../features/auth/providers/recovery_failure_surface.dart';
import '../providers/settings_provider.dart';
import '../services/notification_service.dart';

/// Keeps opt-in services in sync with persisted settings.
final appBootstrapProvider = Provider<void>((ref) {
  ref.watch(authEmailLinkBootstrapProvider);

  // A recovery failure (e.g. an expired link) restarts the process before its
  // error SnackBar can render, so the reason was persisted pre-restart. Surface
  // it once now, after the first frame (the root ScaffoldMessenger is mounted).
  WidgetsBinding.instance.addPostFrameCallback((_) {
    unawaited(
      surfaceRecoveryFailureNotice(
        prefs: ref.read(sharedPreferencesProvider),
        diagnostics: ref.read(recoveryDiagnosticsProvider),
      ),
    );
  });

  Future<void> syncNotifications() async {
    final settings = ref.read(settingsProvider);
    final notificationService = ref.read(notificationServiceProvider);

    if (!settings.pushNotificationsEnabled) {
      await notificationService.removeToken();
      return;
    }

    final enabled = await notificationService.initialize();
    if (!enabled && ref.read(settingsProvider).pushNotificationsEnabled) {
      await ref
          .read(settingsProvider.notifier)
          .setPushNotificationsEnabled(false);
    }
  }

  ref.listen<bool>(
    settingsProvider.select((value) => value.pushNotificationsEnabled),
    (previous, next) {
      if (previous == null && !next) return;
      unawaited(syncNotifications());
    },
    fireImmediately: true,
  );
});
