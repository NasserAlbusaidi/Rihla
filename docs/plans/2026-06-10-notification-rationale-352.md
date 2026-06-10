# Plan — #352 soft in-app rationale before the OS push prompt

**Issue:** #352 (P2, Post-launch hardening). Builds on shipped #288 (`NotificationPrompt`).
**Gate:** EXEMPT — no money math, no `firestore.rules`, no `functions/**`, no `lib/core/router/**` *modified*, no `**/models/**`. Client-only UI + l10n + a service seam.

## Problem

`NotificationPrompt.maybePrompt()` (`lib/core/services/notification_prompt.dart`) fires at the
first natural moment (successful join/create, #288) and goes **straight to the OS permission
dialog** (`notificationService.initialize()`) with zero context. Best practice is a soft in-app
rationale first: explain the value, offer [Not now] / [Turn on], and only call the OS prompt on
opt-in.

## Architecture constraint (verified)

- `maybePrompt()` is a **context-free service method**, fire-and-forget from the join/create
  success handlers (`join_group_screen.dart:127`, `create_group_screen.dart:107`). It survives the
  screens' `pushReplacement` to `/group/:id` precisely because it holds no `BuildContext`.
- A rationale **sheet needs a Navigator**. `appMessengerKey` sits *above* the Navigator
  (it's the `ScaffoldMessenger`) → unusable for a modal.
- The create flow's share sheet `onNavigate` does `pushReplacement`, so the create screen's
  `context` may be dead by the time the prompt fires → a callsite-context sheet is fragile.
- **Solution:** show the sheet via the **root navigator context**, reached through
  `routerProvider.routerDelegate.navigatorKey.currentContext`. Verified: go_router **13.2.5**
  exposes `GoRouterDelegate.navigatorKey` (delegate.dart:166), and a throwaway spike confirmed
  `showModalBottomSheet(context: navKey.currentContext!)` works after a `go()` navigation.
- This keeps `maybePrompt()` parameterless (callsites + wiring tests unchanged, #288's
  fire-and-forget intact) and lands the rationale on the **destination** screen (payoff-first),
  **without modifying `app_router.dart`** (Gate-exempt).

## Changes

### New: `lib/core/services/notification_rationale_sheet.dart`
- `Future<bool> showNotificationRationaleSheet(BuildContext context)` — modal bottom sheet styled
  like `legal_links_sheet.dart` (SafeArea → cardSurface container, `radiusLarge`, drag handle,
  `AppTypography`, `Iconsax.notification`). Returns `true` on [Turn on], `false` on [Not now] /
  barrier-dismiss (`showModalBottomSheet` returns `null` on dismiss → coalesce to `false`).
- **Tri-state** seam provider so the service stays unit-testable without a widget tree AND can tell
  "user declined" apart from "couldn't present" (`null`):
  ```dart
  typedef NotificationRationaleGate = Future<bool?> Function();
  final notificationRationaleGateProvider = Provider<NotificationRationaleGate>((ref) {
    return () async {
      final context =
          ref.read(routerProvider).routerDelegate.navigatorKey.currentContext;
      if (context == null || !context.mounted) return null; // couldn't show → retry later
      return showNotificationRationaleSheet(context);        // true/false = user decision
    };
  });
  ```
  Root-navigator context: the sheet is correct because `routerDelegate.navigatorKey` is the **root**
  navigator (stable across `pushReplacement`; the modal stacks above whatever page is current) — NOT
  because of any guarantee about which screen is mounted when the fire-and-forget microtask runs.

### Modified: `lib/core/services/notification_prompt.dart`
**`_inFlight` (set synchronously) is the re-entrancy guard; `notificationPromptSeen` is the
once-only persistence guard.** Per the Gate review (both reviewers, P1): do **not** mark seen until
the rationale was actually presented — otherwise a transient null root-context silently consumes the
single lifetime ask and never retries.
```dart
if (_inFlight) return;
final settings = _ref.read(settingsProvider);
if (settings.notificationPromptSeen) return;
_inFlight = true;
try {
  final notifier = _ref.read(settingsProvider.notifier);
  // Opted in elsewhere (Settings toggle) — nothing to ask; mark seen, no UI needed.
  if (settings.pushNotificationsEnabled) {
    await notifier.setNotificationPromptSeen(true);
    return;
  }
  final optedIn = await _ref.read(notificationRationaleGateProvider)();
  if (optedIn == null) return;                  // couldn't present → stay unseen, retry next moment
  await notifier.setNotificationPromptSeen(true); // user saw it → never nag again
  if (!optedIn) return;                          // [Not now]
  final granted = await _ref.read(notificationServiceProvider).initialize();
  if (granted) await notifier.setPushNotificationsEnabled(true);
} finally {
  _inFlight = false;
}
```

### Modified: `lib/l10n/app_en.arb` + `app_ar.arb` (4 keys)
- `notificationRationaleTitle` — "Stay in the loop" / "ابقَ على اطّلاع"
- `notificationRationaleBody` — "Get notified when someone adds an expense or settles up." /
  "نُنبّهك عندما يضيف أحدهم مصروفًا أو يسوّي حسابًا."
- `notificationRationaleNotNow` — "Not now" / "ليس الآن"
- `notificationRationaleTurnOn` — "Turn on" / "تفعيل"

### Callsites: UNCHANGED. Wiring tests: UNCHANGED (`maybePrompt()` stays parameterless).

## Tests (TDD: RED first)

1. **NEW `test/unit/notification_rationale_sheet_test.dart`** (widget) — covers AC "EN + AR copy;
   both branches":
   - EN: title/body/[Not now]/[Turn on] render.
   - Tap [Turn on] → future resolves `true`. Tap [Not now] → `false`. Barrier dismiss → `false`.
   - AR locale: title/body render in Arabic.
2. **`test/unit/notification_prompt_test.dart`** — add
   `notificationRationaleGateProvider` override to `makeContainer` (default returns `true`, so the
   existing 7 tests keep their meaning: granted → initialize → enable). Add:
   - `unseen + disabled + rationale DECLINED (false) → marks seen, never initializes, push stays off`.
   - `unseen + disabled + rationale ACCEPTED (true) + granted → initializes, enables` (explicit).
   - **`unseen + disabled + gate could-not-show (null) → never initializes, stays UNSEEN, retries`**
     (the P1 regression: `verifyNever(initialize)` + `notificationPromptSeen == false`, then a second
     `maybePrompt()` invokes the gate again — pin via a counting gate).

## Acceptance criteria → coverage

- [x] Soft rationale sheet shown before the OS dialog; [Not now] sets `notificationPromptSeen` and
  never nags → gate inserted before `initialize()`; seen set up front; declined-test pins it.
- [x] [Turn on] proceeds to `notificationService.initialize()` → accepted-test pins it.
- [x] EN + AR copy; test covers both branches → sheet widget test (EN+AR, both buttons) + prompt
  unit tests (accepted/declined).

## Verify
`flutter analyze` clean; `flutter test test/unit/notification_prompt_test.dart
test/unit/notification_rationale_sheet_test.dart test/features/groups/notification_prompt_wiring_test.dart
test/features/groups/create_join_group_test.dart` green; then full suite.
