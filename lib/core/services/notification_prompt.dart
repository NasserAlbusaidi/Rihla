import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/settings_provider.dart';
import 'notification_service.dart';

/// Coordinates the one-time, natural-moment request for OS notification
/// permission (#288).
///
/// `pushNotificationsEnabled` defaults off, and the bootstrap only requests
/// permission when it's already on — so the Android 13+ system dialog never
/// appears for a casual joiner. This asks once, the first time the user gains a
/// stake in a group (a successful join or group creation), then never nags.
final notificationPromptProvider = Provider<NotificationPrompt>(
  NotificationPrompt.new,
);

class NotificationPrompt {
  NotificationPrompt(this._ref);

  final Ref _ref;
  bool _inFlight = false;

  /// Requests OS notification permission once. No-op if it's already been shown
  /// or push is already enabled. On grant, persists `pushNotificationsEnabled`
  /// so future launches re-sync the token via the bootstrap. Safe to call
  /// fire-and-forget from a UI success handler.
  Future<void> maybePrompt() async {
    if (_inFlight) return;
    final settings = _ref.read(settingsProvider);
    if (settings.notificationPromptSeen) return;

    _inFlight = true;
    try {
      final notifier = _ref.read(settingsProvider.notifier);
      // Mark seen up front so a crash/abandon mid-prompt doesn't re-nag.
      await notifier.setNotificationPromptSeen(true);

      // Already opted in elsewhere (e.g. the Settings toggle) — nothing to ask.
      if (settings.pushNotificationsEnabled) return;

      final granted = await _ref.read(notificationServiceProvider).initialize();
      if (granted) {
        await notifier.setPushNotificationsEnabled(true);
      }
    } finally {
      _inFlight = false;
    }
  }
}
