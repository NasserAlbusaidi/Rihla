import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/settings_provider.dart';
import '../services/notification_service.dart';

/// Keeps opt-in services in sync with persisted settings.
final appBootstrapProvider = Provider<void>((ref) {
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
      unawaited(syncNotifications());
    },
    fireImmediately: true,
  );
});
