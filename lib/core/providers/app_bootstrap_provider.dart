import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../features/auth/providers/auth_provider.dart';
import '../providers/settings_provider.dart';
import '../services/notification_service.dart';

/// Keeps opt-in services in sync with auth and persisted settings.
final appBootstrapProvider = Provider<void>((ref) {
  Future<void> syncNotifications() async {
    final user = ref.read(currentUserProvider);
    final settings = ref.read(settingsProvider);
    final notificationService = ref.read(notificationServiceProvider);

    if (user == null) {
      notificationService.markSignedOut();
      return;
    }

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

  ref.listen<User?>(currentUserProvider, (previous, next) {
    unawaited(syncNotifications());
  }, fireImmediately: true);

  ref.listen<bool>(
    settingsProvider.select((value) => value.pushNotificationsEnabled),
    (previous, next) {
      unawaited(syncNotifications());
    },
  );
});
