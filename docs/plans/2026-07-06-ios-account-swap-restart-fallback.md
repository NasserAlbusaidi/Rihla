# iOS Account-Swap Restart Fallback (#946) Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** On iOS, replace the cache-isolation overlay's dead-end "Try again" (which re-invokes a MethodChannel that has no iOS handler and can never succeed) with designed, outcome-neutral manual-restart copy and no futile retry affordance — Android behavior unchanged.

**Architecture:** Pure Dart/UI change. `_CacheIsolationApp` (lib/main.dart) platform-gates the failed-restart branch: on iOS it renders a new `SplashScreen` manual-restart mode (new l10n copy, no button); on Android it keeps the existing retry affordance. No native code is added (Decision D1 below). No money/rules/routing/schema surface is touched.

**Tech Stack:** Flutter, Riverpod 2.x, gen-l10n (ARB en+ar), `debugDefaultTargetPlatformOverride` for platform-gated widget tests.

---

## Decision D1: option (a) designed manual-restart copy — option (b) native `exit(0)` handler REJECTED

**Chosen (a):** iOS shows permanent, outcome-neutral copy instructing the user to close Rihla from the App Switcher and reopen it. The retry button is suppressed on iOS because `restart()` there always throws `MissingPluginException` — the retry can never succeed and re-tapping it is the dead-end #946 describes.

**Rejected (b): native iOS `exit(0)`-after-flush handler.**
- Apple QA1561 / HIG: apps must not terminate themselves programmatically; a self-exit "may appear to the user as a crash." App Review rejection risk sits exactly on the account-recovery path we need to be most reliable, at iOS launch time when we have zero review history.
- `exit(0)` still cannot relaunch the app — iOS has no launch-Intent equivalent. The user must tap the icon anyway, so (b) buys only "skip the App Switcher swipe" at the cost of review risk plus an NSUserDefaults-flush analysis (#456-equivalent for cfprefsd) that we cannot verify on-device until Apple enrollment completes.
- (b) remains revisitable post-launch with RD-QA device evidence; nothing in (a) blocks a later (b).

**Why the data is already safe (verified, not assumed):** every swap flow persists `markFirestorePersistenceDirty` + `writeRecoveryOutcome` (awaited) BEFORE the swap and the `finally` restart (`auth_recovery_service.dart:321-346`, `:423`, `:490-503`; `data_deletion_service.dart:83-97`). On iOS, FirebaseAuth persists the current user in the Keychain (not SharedPreferences — the #456 QueuedWork hazard is Android-specific), and the awaited SharedPreferences writes have reached cfprefsd long before any user-initiated force-quit. The cold boot after a manual relaunch runs the same `CacheUidBarrier`/`FirestoreCacheGate` path as an Android process restart — `clearPersistence()` is platform-neutral Dart.

**Why the overlay copy must be outcome-neutral:** the same overlay covers all four swap flows — Google restore, email-link restore, sign-out, deletion — and covers both success AND failure of the swap (the `finally` restarts unconditionally; `writeRecoveryOutcome` records `ok:false` on failure). The overlay does not know the outcome; the post-restart boot notice (`recovery_outcome_notice_provider.dart`, gated off while `cacheIsolationProvider` is true) is what reports success/failure with `expectedUid` verification. Copy like "Your account is restored!" would lie on the failure path — the copy says only "close and reopen to finish."

## Control-flow facts the implementation relies on (verified against code)

1. `PlatformCacheIsolationController.restart()` catches ALL errors, logs, flips `cacheIsolationRestartFailedProvider = true`, and RESOLVES (never rethrows) — `cache_isolation_controller_provider.dart:50-67`. On iOS the `MissingPluginException` is immediate, so the flag flips within the same frame; the 6s `_restartWatchdog` (`main.dart:303`) is a second net, not the primary path.
2. Because `restart()` resolves, on iOS the code AFTER each `finally` continues in-process (on Android the process is dead). All post-restart UI is covered: `cacheIsolationProvider` is already `true` (set by `engageIsolation()` before the swap), `SafarApp` short-circuits to `_CacheIsolationApp` before the router builds (`main.dart:256`), and `recovery_outcome_notice_provider.dart:71,87` early-returns while isolated.
3. `SplashScreen` call sites (exhaustive, verified): `main.dart:174` (boot loading), `main.dart:190` (#838 boot error, `onRetry: _retry` non-null), `main.dart:332` (isolation overlay — the ONLY site this plan changes), `app_router.dart:184` (splash route, loading). The #838 boot-error path must render byte-identically after this change.
4. The overlay renders pre-theme with `AppColorTokens.light` on purpose (`splash_screen.dart:10-11,30`); reuse `_ErrorBody`'s existing structure/tokens — no new colors (theme-purity CI).
5. Platform gate: `defaultTargetPlatform == TargetPlatform.iOS` (from `package:flutter/foundation.dart`), overridable in tests via `debugDefaultTargetPlatformOverride`. Do NOT use `dart:io` `Platform.isIOS` — not overridable in widget tests and throws on web.

## Data contract (exact — principle 5)

`SplashScreen` gains one parameter:

```dart
/// When true (and [hasError] is true), renders the manual-restart copy
/// (splashManualRestartTitle/Body) and hides the retry button entirely.
/// Used by the iOS cache-isolation overlay, where a native restart is
/// impossible (#946). Default false — all existing call sites unchanged.
final bool manualRestartRequired;
```

- `manualRestartRequired: true` ⇒ `_ErrorBody` shows `l10n.splashManualRestartTitle` / `l10n.splashManualRestartBody`, and does NOT render the `ElevatedButton` (regardless of `onRetry`).
- `manualRestartRequired: false` (default) ⇒ behavior byte-identical to today, including the disabled-button-when-`onRetry`-null edge.
- Icon in manual mode: reuse the existing `_IconBox` but with `Icons.refresh_rounded` in `colors.primary` / `colors.saffronSoft` (both existing tokens) instead of the error X — this is an instruction, not an error.

New l10n keys (both `lib/l10n/app_en.arb` and `lib/l10n/app_ar.arb`; regenerate with `flutter gen-l10n`):

```json
"splashManualRestartTitle": "One last step",
"@splashManualRestartTitle": {
  "description": "Cache-isolation overlay title on iOS after an account swap; the app cannot restart itself (#946)"
},
"splashManualRestartBody": "To finish switching accounts, close Rihla from the App Switcher (swipe up and hold, then swipe Rihla away), then open it again.",
"@splashManualRestartBody": {
  "description": "Instructs the user to force-quit and relaunch; outcome-neutral because the overlay covers success and failure of all four swap flows"
}
```

Arabic:

```json
"splashManualRestartTitle": "خطوة أخيرة",
"splashManualRestartBody": "لإكمال تبديل الحساب، أغلق «رحلة» من مبدّل التطبيقات (اسحب للأعلى مع الاستمرار ثم اسحب «رحلة» بعيدًا)، ثم افتحه من جديد."
```

`_CacheIsolationAppState.build` change (exact):

```dart
final restartFailed = ref.watch(cacheIsolationRestartFailedProvider);
final showManualRestart = restartFailed || _watchdogElapsed;
final iosManualRestart =
    showManualRestart && defaultTargetPlatform == TargetPlatform.iOS;
```

- `iosManualRestart` ⇒ `SplashScreen(key: Key('cache-isolation-manual-restart'), hasError: true, manualRestartRequired: true)` — no `onRetry`.
- else `showManualRestart` ⇒ existing retry branch, unchanged (Android + any non-iOS platform keeps retry: a transient native throw there is recoverable).

## Verification principles (run while writing this spec, reported per the Operating Contract)

1. **Callsite classification:** every touched surface is INBOUND/display-only — overlay branch selection, splash copy, l10n keys. Grepped: no write path reads `cacheIsolationRestartFailedProvider` (`grep -rn cacheIsolationRestartFailed lib` → main.dart overlay + controller + definition only). No Firestore/prefs write is added, moved, or reordered.
2. **Concrete claims re-verified:** channel name `com.safar.safar/cache_isolation` (`cache_isolation_controller_provider.dart:16-18`); no iOS handler (`ios/Runner/AppDelegate.swift` — stock 16 lines, grepped for `MethodChannel`: absent); catch-and-flag behavior (`:50-67`); overlay branch (`main.dart:324-343`); splash error copy keys `splashErrorTitle/Body`, `splashRetry` (`app_en.arb:2174-2183`); all four `restart()` sites (`auth_recovery_service.dart:344,423,500`; `data_deletion_service.dart:95`).
3. **Read-path per write-path:** no data-shape write. The one state write (`cacheIsolationRestartFailedProvider = true`) has a named reader: `_CacheIsolationAppState.build` (`main.dart:324`).
4. **Fields enumerated from the type:** `SplashScreen` carries `hasError`, `error`, `onRetry` (+ new `manualRestartRequired`). All four call sites enumerated above; three are untouched and compile unchanged because the new param defaults to `false`.
5. **Data contracts spelled out:** exact param name, exact l10n keys, exact widget keys (`cache-isolation-manual-restart` new; `cache-isolation-restart` retained on the Android retry branch; `cache-isolation-overlay` untouched).
6. **Arithmetic decomposition:** N/A — no money math touched (nearest money surface is the recovery-outcome notice, which this plan does not modify).
7. **Orthogonal-axis adversarial pass (identity + time axis):** worked example — iOS user taps "Restore with Google," swap succeeds server-side, then merely BACKGROUNDS the app instead of force-quitting, and returns. In-process: overlay still mounted (correct — Firestore instance still holds the old UID's cache), copy still instructs closing. FirebaseAuth in-memory user is already the NEW uid, but nothing can render stale financial UI because the router never built and `recovery_outcome_notice` is isolation-gated. If iOS jetsams the suspended process, next open is the cold boot — identical to force-quit. Failure path (swap threw): outcome `ok:false` persisted; same copy; cold boot shows the failure notice. No path renders old-UID financials, and no path loses the swap. Second example (time axis): user leaves the overlay up for an hour, then force-quits — dirty flag and outcome were persisted before the overlay appeared; staleness changes nothing.

## Out of scope (bounded on purpose)

- No native iOS handler (D1). No change to `MainActivity.kt`, `AppDelegate.swift`, or the channel protocol.
- No change to the four swap flows' ordering, `engageIsolation()`, or persistence — the #414/#647/#648 data-loss class lives there; this plan deliberately never touches those lines.
- No change to the #838 boot-error splash or the router splash route.
- RD-QA on a real device (does jetsam reliably cold-boot? does the App Switcher copy read well on-device?) is enrollment-gated → tracked under #951, noted in the PR as the remainder.

---

### Task 1: Failing widget tests (RED)

**Files:**
- Modify: `test/features/auth/cache_isolation_overlay_test.dart`

**Step 1: Write the failing tests** — extend the existing file (it already has `_RecordingController` and `drainWatchdog`):

```dart
testWidgets(
  'iOS: failed restart shows manual-restart copy with NO retry button (#946)',
  (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    final controller = _RecordingController();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          cacheIsolationProvider.overrideWith((ref) => true),
          cacheIsolationRestartFailedProvider.overrideWith((ref) => true),
          cacheIsolationControllerProvider.overrideWithValue(controller),
        ],
        child: const SafarApp(),
      ),
    );
    await tester.pump();

    expect(
      find.byKey(const Key('cache-isolation-manual-restart')),
      findsOneWidget,
    );
    expect(find.byType(ElevatedButton), findsNothing);
    // Outcome-neutral instruction copy, not the generic error copy.
    expect(find.text('One last step'), findsOneWidget);
    expect(find.text("Something's off"), findsNothing);

    await drainWatchdog(tester);
  },
);

testWidgets(
  'Android: failed restart keeps the retry affordance (#946 regression pin)',
  (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    final controller = _RecordingController();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          cacheIsolationProvider.overrideWith((ref) => true),
          cacheIsolationRestartFailedProvider.overrideWith((ref) => true),
          cacheIsolationControllerProvider.overrideWithValue(controller),
        ],
        child: const SafarApp(),
      ),
    );
    await tester.pump();

    expect(find.byKey(const Key('cache-isolation-restart')), findsOneWidget);
    await tester.tap(find.byType(ElevatedButton));
    expect(controller.restarts, 1);

    await drainWatchdog(tester);
  },
);
```

(Import `package:flutter/foundation.dart` if not already imported.)

**Step 2: Run to verify RED**

Run: `flutter test test/features/auth/cache_isolation_overlay_test.dart`
Expected: iOS test FAILS — `cache-isolation-manual-restart` key not found (current code renders `cache-isolation-restart` + retry button on every platform). Android test may already pass (it pins existing behavior). Paste the failing output into the PR body (RED evidence).

### Task 2: l10n keys

**Files:**
- Modify: `lib/l10n/app_en.arb`, `lib/l10n/app_ar.arb`

**Step 1:** Add the two keys + `@`-descriptions to both ARB files (exact strings from the Data contract section — en keys carry the `@` metadata, ar carries values only, matching the files' existing convention).
**Step 2:** Run `flutter gen-l10n` (or `flutter pub get` which triggers `generate: true`). Expected: `lib/l10n/generated` gains both getters; `flutter analyze` clean.

### Task 3: SplashScreen manual-restart mode

**Files:**
- Modify: `lib/core/screens/splash_screen.dart`

**Step 1:** Add `manualRestartRequired` (final bool, default false) to `SplashScreen`; thread it into `_ErrorBody` as a `manualRestart` flag. In `_ErrorBody.build`: when `manualRestart` — `title = l10n.splashManualRestartTitle`, `body = l10n.splashManualRestartBody`, icon becomes `Icon(Icons.refresh_rounded, size: 42, color: colors.primary)` inside `_IconBox(borderColor: colors.primary, backgroundColor: colors.saffronSoft, …)`, and the `ElevatedButton` subtree (and its preceding `SizedBox(height: 28)`) is omitted. All existing paths byte-identical.
**Step 2:** `flutter analyze` — clean (watch `prefer_const_constructors`).

### Task 4: Platform-gate the overlay branch

**Files:**
- Modify: `lib/main.dart` (`_CacheIsolationAppState.build`, ~:322-344)

**Step 1:** Apply the exact change from the Data contract section (import `package:flutter/foundation.dart` for `defaultTargetPlatform` if `material.dart`'s re-export isn't already in scope — `material.dart` re-exports foundation, so no new import is expected).
**Step 2:** Run: `flutter test test/features/auth/cache_isolation_overlay_test.dart` — all tests GREEN, including the two pre-existing ones (they run under the test-default platform, Android, and must be untouched).

### Task 5: Full verification + commit

**Step 1:** `flutter analyze` — clean.
**Step 2:** `flutter test` — full suite green (l10n surface tests must see the new keys as live: they're referenced from `splash_screen.dart`).
**Step 3:** `bash tool/check_theme_purity.sh` — no new violations (no new hex colors; tokens only).
**Step 4:** Commit: `feat(auth): iOS manual-restart fallback for the cache-isolation overlay (#946)` — body carries `Closes #946` (full delivery of the (a) decision; RD-QA device pass is #951's box, named in the PR as remainder).
