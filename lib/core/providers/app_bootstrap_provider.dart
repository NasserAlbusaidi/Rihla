import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/auth/providers/auth_email_link_bootstrap_provider.dart';
import '../../features/auth/providers/auth_provider.dart';
import '../../features/auth/providers/durable_account_marker_provider.dart';
import '../../features/auth/providers/recovery_outcome_notice_provider.dart';
import '../models/app_settings_model.dart';
import '../providers/settings_provider.dart';
import '../services/notification_service.dart';

/// Single source of the push-token reconciliation. Mirrors persisted intent to
/// the OS/FCM side effect: opted-out → drop the token; opted-in → engage the OS
/// permission + (re)register. The boolean result of `initialize()` is
/// intentionally ignored: `pushNotificationsEnabled` is the user's intent and
/// must survive a denial (#470), while OS reality is reflected by
/// `notificationStatusProvider` (set inside `initialize()`). Resetting the pref
/// here overwrote the opt-in and made the Settings toggle a dead control.
Future<void> _syncNotifications(
  AppSettings settings,
  NotificationService notificationService,
  bool handleInitialMessage,
) async {
  if (!settings.pushNotificationsEnabled) {
    await notificationService.removeToken();
    return;
  }
  await notificationService.initialize(
    handleInitialMessage: handleInitialMessage,
  );
}

/// #635: the eager boot-time notification sync, deferred off the first-frame
/// build turn. Called once from a post-first-frame callback in
/// [SafarApp.initState] instead of via `fireImmediately` on the pref-listener,
/// so `notificationService.initialize()` (OS permission platform-channel +
/// FCM `getToken()` network + a Firestore token write + stream `.listen()`s)
/// no longer contends for the platform channel / main isolate during the most
/// contended cold-start window (router build + first home reads).
///
/// Behaviour is identical to the old initial `fireImmediately` fire under its
/// `if (previous == null && !next) return;` guard: an enabled user still gets
/// `initialize()`; a disabled fresh user is a no-op (NO `removeToken()` on
/// initial boot — that only fires on a later off-toggle via the listener).
void kickInitialNotificationSync(
  WidgetRef ref, {
  bool handleInitialMessage = true,
}) {
  runInitialNotificationSync(
    ref.read(settingsProvider),
    () => ref.read(notificationServiceProvider),
    handleInitialMessage: handleInitialMessage,
  );
}

/// Testable core of [kickInitialNotificationSync]; `serviceFactory` is read
/// lazily so a disabled fresh user never even resolves the notification service.
void runInitialNotificationSync(
  AppSettings settings,
  NotificationService Function() serviceFactory, {
  bool handleInitialMessage = true,
}) {
  if (!settings.pushNotificationsEnabled) return;
  unawaited(
    _syncNotifications(settings, serviceFactory(), handleInitialMessage),
  );
}

/// Keeps opt-in services in sync with persisted settings.
final appBootstrapProvider = Provider<void>((ref) {
  ref.watch(authEmailLinkBootstrapProvider);
  // #439: surface the previous process's recovery outcome (one-shot marker).
  ref.watch(recoveryOutcomeNoticeProvider);
  // #469: mark the device "durable account established" whenever a non-anon
  // session is observed, so an anon-shell delete can be gated against silently
  // leaving the durable account intact.
  ref.watch(durableAccountMarkerProvider);

  // #635: the INITIAL eager sync is deferred to a post-first-frame callback in
  // SafarApp.initState (kickInitialNotificationSync) — NOT fired here — so it
  // doesn't contend during cold start. `fireImmediately: false` so only LATER
  // toggles flow through this listener.
  ref.listen<bool>(
    settingsProvider.select((value) => value.pushNotificationsEnabled),
    (previous, next) {
      if (previous == null && !next) return;
      unawaited(
        _syncNotifications(
          ref.read(settingsProvider),
          ref.read(notificationServiceProvider),
          true,
        ),
      );
    },
    fireImmediately: false,
  );

  // #480: re-register the FCM token when an anonymous session links a durable
  // credential IN PLACE (same uid) — Settings "Link Google", the home backup
  // nudge, create-screen account link, or email-link completion. Those paths
  // neither flip `pushNotificationsEnabled` (so the listener above never
  // re-fires) nor restart the app (so no cold boot re-runs bootstrap). Without
  // this, a push-enabled user who upgrades keeps a confident-ON toggle that
  // delivers nothing — `_saveToken` skips while anonymous (#441) and nothing
  // re-invokes it after the link. A uid SWAP (recovery restore) is intentionally
  // excluded: that path restarts and re-runs this provider on its own.
  ref.listen<AsyncValue<User?>>(authUserChangesProvider, (previous, next) {
    final before = previous?.valueOrNull;
    final after = next.valueOrNull;
    final upgradedInPlace =
        before != null &&
        before.isAnonymous &&
        after != null &&
        !after.isAnonymous &&
        before.uid == after.uid;
    if (!upgradedInPlace) return;
    if (ref.read(settingsProvider).pushNotificationsEnabled) {
      unawaited(
        ref
            .read(notificationServiceProvider)
            .initialize(handleInitialMessage: true),
      );
    }
  });

  // #483: re-save the token's stored `locale` when the app language changes, so
  // server-rendered push copy (localized from `fcm_tokens/{uid}.locale`) follows
  // the switch instead of staying frozen at the language present when the token
  // was first written. `refreshTokenLocale` no-ops while push is off /
  // uninitialized and stays a silent skip for anonymous shells, so this only
  // writes for a push-enabled durable user.
  ref.listen<String>(settingsProvider.select((value) => value.languageCode), (
    previous,
    next,
  ) {
    if (previous == null || previous == next) return;
    if (ref.read(settingsProvider).pushNotificationsEnabled) {
      unawaited(ref.read(notificationServiceProvider).refreshTokenLocale());
    }
  });
});
