import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/auth/providers/auth_email_link_bootstrap_provider.dart';
import '../../features/auth/providers/recovery_outcome_notice_provider.dart';
import '../providers/settings_provider.dart';
import '../services/notification_service.dart';

/// Keeps opt-in services in sync with persisted settings.
final appBootstrapProvider = Provider<void>((ref) {
  ref.watch(authEmailLinkBootstrapProvider);
  // #439: surface the previous process's recovery outcome (one-shot marker).
  ref.watch(recoveryOutcomeNoticeProvider);

  Future<void> syncNotifications() async {
    final settings = ref.read(settingsProvider);
    final notificationService = ref.read(notificationServiceProvider);

    if (!settings.pushNotificationsEnabled) {
      await notificationService.removeToken();
      return;
    }

    // Attempt to engage the OS permission + token. The boolean result is
    // intentionally ignored: `pushNotificationsEnabled` is the user's intent and
    // must survive a denial (#470), while OS reality is reflected by
    // `notificationStatusProvider` (set inside `initialize()`). Resetting the
    // pref here overwrote the opt-in and made the Settings toggle a dead control.
    await notificationService.initialize();
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
