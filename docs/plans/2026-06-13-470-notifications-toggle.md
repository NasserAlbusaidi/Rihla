# Fix #470 — Notifications toggle won't latch (force-reset + dead control)

**Branch:** `fix/notifications-toggle-470` · **Gate:** not required (client-only; no money/rules/routing/schema surface) · **Deploy:** none

## Problem

Settings → Notifications toggle turns ON then snaps back OFF and goes dead once OS
permission has been denied. The user's opt-in is silently discarded and there is no
in-app recovery path (Android 13+ never re-shows the system dialog after a denial).

## Root cause (verified against code 2026-06-13)

1. **Forced pref reset.** `lib/core/providers/app_bootstrap_provider.dart:25-30` —
   `syncNotifications()` awaits `notificationService.initialize()`; on permission denial
   `initialize()` returns `false` (`notification_service.dart:161-163`) and the listener
   force-resets `pushNotificationsEnabled` back to `false`. User intent is overwritten.
2. **Dead control.** `profile_screen.dart:715-739` — `isPermissionDenied` disables the
   row (`onChanged: null`, InkWell `onTap: null`). The displayed value
   `notificationsOn = pushNotificationsEnabled && !isPermissionDenied` renders OFF. So
   even without the reset the control cannot be re-engaged from inside the app.

No test pins the reset as intended (`app_bootstrap_wiring_test.dart` only asserts
`initialize()` fires on the true transition), so removing it breaks no contract.

## Design

- **`pushNotificationsEnabled` = user intent** (persisted, never auto-mutated).
- **`notificationStatusProvider` = live OS reality** (the only thing that flips on denial).
- **Denied state is actionable, not dead:** tapping the row/switch deep-links to the OS
  app-notification settings (`AppSettings.openAppSettings(type: notification)` — the
  `app_settings` 7.0.0 dep is already in `pubspec.yaml`, currently unused). The switch
  stays visually OFF (honest: the OS is blocking), subtitle stays
  `profileNotificationsDisabledHint` ("Enable in device Settings") — now truthful.
- **Recovery:** with intent preserved, the next cold boot's `syncNotifications()` re-runs
  `initialize()`; if the user granted permission in OS settings it latches to `enabled`.
  Recoverable across restart per the acceptance box. (For **durable** Google/email-linked
  users it also re-registers the FCM token; anonymous users never get a token by design —
  `notification_service.dart:184` `_saveToken` skips anon shells per the #441 contract, so
  the toggle can read ON for an anon user yet deliver no pushes. That is pre-existing and
  out of #470's scope — see follow-up below.)

`openAppSettings` is wrapped in an injectable provider (matches the
`notificationRationaleGateProvider` DI pattern) so widget tests assert the call without a
platform channel.

## Out of scope (follow-up, not bundled)

- **In-session live refresh** — re-running `initialize()` on `AppLifecycleState.resumed` so
  the toggle updates without a restart. Acceptance only requires *recoverable*, which
  cold-boot re-sync satisfies. Adding a lifecycle observer is a separate concern (#470
  follow-up).
- **Anon users get no pushes** — `_saveToken` skips anonymous shells (#441), so an anon user
  can enable notifications (toggle ON) and still receive nothing; the switch over-promises.
  Pre-existing, orthogonal to the dead-control bug. Worth a separate issue (gate the toggle
  on a durable identity, or surface a "link an account to receive notifications" hint).

## Files

- `lib/core/providers/app_bootstrap_provider.dart` — drop the force-reset; keep calling
  `initialize()` so status still reflects OS reality.
- `lib/core/services/notification_settings_launcher.dart` (new) — `openNotificationSettingsProvider`.
- `lib/features/settings/screens/profile_screen.dart` — `_PreferencesCard` wiring +
  `_NotificationPrefRow` (denied → open settings instead of dead).

## TDD (RED first)

1. **Bootstrap intent survives denial** (`app_bootstrap_wiring_test.dart`): stub
   `initialize()` → `false`, set pref true, activate bootstrap, pump; assert
   `settingsProvider.pushNotificationsEnabled` stays `true`. RED today (reset to false).
2. **Denied toggle opens OS settings** (`profile_screen_test.dart`, replaces the obsolete
   NOTIF-01 "disabled state … onChanged isNull" assertion): override
   `openNotificationSettingsProvider` with a spy; with `permissionDenied`, tap the tile;
   assert the spy fired and the persisted pref is untouched. RED today (provider absent,
   onChanged null).

## Acceptance (from #470)

- [ ] RED regression test written first, then GREEN
- [ ] Toggling on with permission denied no longer resets the persisted pref
- [ ] Permanently-denied state routes the user to OS settings (recoverable)
- [ ] `flutter analyze` clean; settings/bootstrap tests pass
