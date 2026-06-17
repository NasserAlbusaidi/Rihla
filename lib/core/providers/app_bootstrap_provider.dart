import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/auth/providers/auth_email_link_bootstrap_provider.dart';
import '../../features/auth/providers/auth_provider.dart';
import '../../features/auth/providers/durable_account_marker_provider.dart';
import '../../features/auth/providers/recovery_outcome_notice_provider.dart';
import '../providers/settings_provider.dart';
import '../services/notification_service.dart';

/// Keeps opt-in services in sync with persisted settings.
final appBootstrapProvider = Provider<void>((ref) {
  ref.watch(authEmailLinkBootstrapProvider);
  // #439: surface the previous process's recovery outcome (one-shot marker).
  ref.watch(recoveryOutcomeNoticeProvider);
  // #469: mark the device "durable account established" whenever a non-anon
  // session is observed, so an anon-shell delete can be gated against silently
  // leaving the durable account intact.
  ref.watch(durableAccountMarkerProvider);

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

  // #480: re-register the FCM token when an anonymous session links a durable
  // credential IN PLACE (same uid) — Settings "Link Google", the home backup
  // nudge, or email-link completion. Those paths neither flip
  // `pushNotificationsEnabled` (so the listener above never re-fires) nor
  // restart the app (so no cold boot re-runs bootstrap), and only the
  // join/create gate re-saved the token. Without this, a push-enabled user who
  // upgrades by any other path keeps a confident-ON toggle that delivers
  // nothing — `_saveToken` skips while anonymous (#441) and nothing re-invokes
  // it after the link. A uid SWAP (recovery restore) is intentionally excluded:
  // that path restarts and re-runs this provider on its own.
  ref.listen<AsyncValue<User?>>(authUserChangesProvider, (previous, next) {
    final before = previous?.valueOrNull;
    final after = next.valueOrNull;
    final upgradedInPlace = before != null &&
        before.isAnonymous &&
        after != null &&
        !after.isAnonymous &&
        before.uid == after.uid;
    if (!upgradedInPlace) return;
    if (ref.read(settingsProvider).pushNotificationsEnabled) {
      unawaited(ref.read(notificationServiceProvider).initialize());
    }
  });

  // #483: re-save the token's stored `locale` when the app language changes, so
  // server-rendered push copy (localized from `fcm_tokens/{uid}.locale`) follows
  // the switch instead of staying frozen at the language present when the token
  // was first written. `refreshTokenLocale` no-ops while push is off /
  // uninitialized and stays a silent skip for anonymous shells, so this only
  // writes for a push-enabled durable user.
  ref.listen<String>(
    settingsProvider.select((value) => value.languageCode),
    (previous, next) {
      if (previous == null || previous == next) return;
      if (ref.read(settingsProvider).pushNotificationsEnabled) {
        unawaited(ref.read(notificationServiceProvider).refreshTokenLocale());
      }
    },
  );
});
