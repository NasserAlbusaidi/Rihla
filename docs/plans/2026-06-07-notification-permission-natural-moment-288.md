# #288 — Request push permission at a natural moment

**Branch:** `fix/288-push-permission-natural-moment` · worktree `../Rihla-288`
**Issue:** #288 (P2 bug) — `pushNotificationsEnabled` defaults false, so `syncNotifications` never calls `initialize()`/`requestPermission()`; the Android 13+ `POST_NOTIFICATIONS` dialog never appears. A default-off toggle behind Profile→Preferences→Notifications means a casual joiner gets zero pushes and never learns why.

## Root cause (verified on `main` e30e38f)

- `app_settings_model.dart:21` — `pushNotificationsEnabled` defaults `false`.
- `app_bootstrap_provider.dart:17-20` — `syncNotifications` early-returns (removeToken) when the toggle is off; `initialize()` (which calls `requestPermission`) is only reached when the toggle is already on.
- `notification_service.dart:119` — `requestPermission` lives inside `initialize()`.
- Net: the OS permission dialog is gated behind a setting the target cohort never opens.

## Decision

Request the OS permission **once, at the first natural moment the user gains a stake in a group** — a successful **join** or **group creation**. The issue names "right after a successful join" (joiner cohort) as primary; group creation is the symmetric owner moment and the same one-line mechanism, so both are wired. A new persisted `notificationPromptSeen` flag ensures we prompt exactly once and never nag.

`initialize()` is reused as-is (it already requests permission, wires listeners, saves the token, sets status). On grant we persist `pushNotificationsEnabled = true` so future launches re-sync via the bootstrap. We call `initialize()` directly and flip the toggle only on grant — NOT "flip toggle → let bootstrap self-heal" — to avoid a transient true→false flicker on denial and to keep the flow deterministically unit-testable.

Not Gate-category: the new field is a local SharedPreferences preference (no Firestore schema, no money, no rules/auth, no routing).

## Changes

1. **`app_settings_model.dart`** — add `bool notificationPromptSeen` (default `false`) to ctor + `copyWith`.
2. **`settings_service.dart`** — key `settings_notification_prompt_seen`; load (default false) + `saveNotificationPromptSeen`.
3. **`settings_provider.dart`** — `setNotificationPromptSeen(bool)` on `SettingsNotifier`.
4. **`lib/core/services/notification_prompt.dart`** (new) — `NotificationPrompt` + `notificationPromptProvider`:
   - `maybePrompt()`: no-op if `notificationPromptSeen`; if push already enabled → mark seen + return; else mark seen FIRST (+ in-memory re-entrancy guard), call `initialize()`, and on grant set `pushNotificationsEnabled = true`.
5. **`join_group_screen.dart`** — after a successful join (post-`HapticService.success`), `unawaited(ref.read(notificationPromptProvider).maybePrompt())`.
6. **`create_group_screen.dart`** — after `_showSharePrompt` returns, `unawaited(ref.read(notificationPromptProvider).maybePrompt())` (placed after the sheet so it doesn't fight the modal).

## Tests (RED first)

- `test/unit/notification_prompt_test.dart` (new):
  - unseen + disabled + granted → `initialize` ×1, push true, seen true.
  - unseen + disabled + denied → `initialize` ×1, push false, seen true.
  - already seen → `initialize` never called, no change.
  - already enabled → `initialize` never called, seen true.
  - persistence: seen survives a fresh container (SharedPreferences).
  - re-entrant double `maybePrompt` → `initialize` ≤1.
- `settings_notifier_test.dart` — `setNotificationPromptSeen` persists; default false.
- `create_join_group_test.dart` — join success fires `maybePrompt` (override `notificationPromptProvider` with a recorder); create success fires `maybePrompt`.

## Verify

- `flutter analyze` clean.
- `flutter test test/unit/notification_prompt_test.dart test/unit/settings_notifier_test.dart test/unit/notification_service_test.dart test/core/providers/app_bootstrap_wiring_test.dart test/features/groups/create_join_group_test.dart`
- Full `flutter test`.
