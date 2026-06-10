import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/settings_provider.dart';
import 'notification_rationale_sheet.dart';
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

  /// Requests OS notification permission once, behind a soft in-app rationale
  /// sheet (#352). No-op if it's already been shown or push is already enabled.
  ///
  /// `_inFlight` (set synchronously) guards re-entrancy; `notificationPromptSeen`
  /// is the once-only persistence guard. The seen flag is set only once the
  /// rationale has actually been **presented** — a `null` gate result means the
  /// sheet could not be shown (no root navigator yet), so we stay unseen and
  /// retry at the next natural moment rather than silently burning the single
  /// lifetime ask. On opt-in we proceed to the OS dialog; on grant we persist
  /// `pushNotificationsEnabled` so future launches re-sync the token via the
  /// bootstrap. Safe to call fire-and-forget from a UI success handler.
  Future<void> maybePrompt() async {
    if (_inFlight) return;
    final settings = _ref.read(settingsProvider);
    if (settings.notificationPromptSeen) return;

    _inFlight = true;
    try {
      final notifier = _ref.read(settingsProvider.notifier);

      // Already opted in elsewhere (e.g. the Settings toggle) — nothing to ask;
      // mark seen so the natural-moment prompt never fires. No UI needed.
      if (settings.pushNotificationsEnabled) {
        await notifier.setNotificationPromptSeen(true);
        return;
      }

      // Soft in-app rationale before the OS dialog. null = couldn't present.
      final optedIn = await _ref.read(notificationRationaleGateProvider)();
      if (optedIn == null) return; // stay unseen → retry next natural moment

      // The user saw the rationale and decided — never nag again.
      await notifier.setNotificationPromptSeen(true);
      if (!optedIn) return; // [Not now]

      final granted = await _ref.read(notificationServiceProvider).initialize();
      if (granted) {
        await notifier.setPushNotificationsEnabled(true);
      }
    } finally {
      _inFlight = false;
    }
  }
}
