# #1188 — Root back-exit guard + back-event breadcrumbs

**Issue:** #1188 (QA-BUG-03) — Back from group-detail exited the app, once per device (Pixel 9 Pro XL / Android 16 AND SM-G770F), 3-button back, entry via home group-row tap, v1.9.0 build 36.

**Root-cause status — be honest:** every inspectable layer verifies CORRECT (see #1188 for the full citation trail: `group_detail_screen.dart:65-75` guard unconditional; `home_screen.dart:218-221` imperative pushes; Flutter 3.41.5 `navigator.dart:3730-3734` reports `canHandlePop` for a `PopScope(canPop:false)` sole route; `MainActivity : FlutterActivity`). The leading hypothesis is an accidental rapid double-press (pop group→home mid-transition, second press exits from Home = normal Android behavior perceived as a bug); an engine/timing race cannot be excluded. **This spec does NOT claim to fix a diagnosed race.** It ships the two changes that are correct under EVERY hypothesis:

1. **Part A — double-back-to-exit guard at the root shell.** Any pop reaching the root — accidental second press, spurious extra pop event, whatever the cause — becomes a visible, recoverable state ("Press back again to exit") instead of silent app death.
2. **Part B — back-event Sentry breadcrumbs** at the two back chokepoints, so the next real-world occurrence self-documents (breadcrumbs ride along on any later Sentry event; no event spam).

**Rejected alternatives** (decision record):
- *Do nothing / instrumentation only* — leaves the QA-observed symptom reachable; the guard is cheap and standard Android UX.
- *Back on non-home tab → snap to home tab first* — a new navigation semantic, out of scope; not needed to kill the symptom. Tab behavior stays as-is (back on any tab = exit path, now guarded).
- *Speculative race fix in the framework interaction* — no repro, no failing test possible; forbidden by the contract (bug fix requires RED first).

**Accepted trade-off:** `PopScope(canPop:false)` at the root suppresses Android predictive-back's shrink-to-launcher preview animation from the home screen (gesture users see the snackbar on first gesture instead). Exit protection outranks the preview animation. Nested screens (group-detail etc.) are unaffected — their own routes own back while on top.

---

## Part A — design

**File:** `lib/features/home/widgets/bottom_nav_shell.dart` (`_BottomNavShellState.build`, wraps the existing `Scaffold`).

`BottomNavShell` is mounted by `HomeScreen` (`home_screen.dart:64`), the screen of top-level route `/home` (`app_router.dart:188-197`). Its `PopScope` registers with the `/home` `ModalRoute`, so it only receives pop events while `/home` is the top route — pushed routes (group-detail etc.) keep owning their own back, including the `#243` fallback and the `#666` dual-mode contract (the guard lives on the SHELL, never on the tab screens `ProfileScreen`/`CrossGroupActivityScreen`).

Shape (Timer-based, no wall-clock seam — widget-test `pump` controls Timers, not `DateTime.now()`):

```dart
// state
bool _awaitingSecondBack = false;
Timer? _backResetTimer;          // dart:async import

// dispose(): _backResetTimer?.cancel();

// build(): wrap the existing Scaffold:
return PopScope(
  canPop: false,
  onPopInvokedWithResult: (didPop, result) {
    if (didPop) return;
    Sentry.addBreadcrumb(...);                    // Part B, see below
    if (_awaitingSecondBack) {
      SystemNavigator.pop();                      // real exit
      return;
    }
    _awaitingSecondBack = true;
    _backResetTimer?.cancel();
    _backResetTimer = Timer(const Duration(seconds: 2), () {
      if (mounted) setState(() => _awaitingSecondBack = false);
    });
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(context.l10n.backAgainToExit),
      duration: const Duration(seconds: 2),       // no action → no persist trap (#411)
    ));
  },
  child: Scaffold( ... existing ... ),
);
```

Constraints the implementation must honor:
- The handler is **synchronous** — no awaits before the `context` uses (no `use_build_context_synchronously` hazard).
- No `behavior: floating` per-call override — `snackBarTheme` already sets it (#419/#437).
- `SystemNavigator.pop()` is a graceful activity finish — NOT a process-kill path, so the #456 `QueuedWork` drain rule does not apply (do not route this through `MainActivity.restartApp`).
- Do NOT touch `lib/core/router/app_router.dart` or any tab screen.

**l10n:** new key `backAgainToExit` in `lib/l10n/app_en.arb` ("Press back again to exit") and `lib/l10n/app_ar.arb` ("اضغط رجوعًا مرة أخرى للخروج"), with description metadata matching neighboring keys. Commit the regenerated `lib/l10n/generated/` files in the same commit (#245 trap).

## Part B — design

Two breadcrumb sites, both `Sentry.addBreadcrumb` (no-op when Sentry uninitialized — same established property as the `captureException` calls tested in #1160):

1. `group_detail_screen.dart` `onPopInvokedWithResult` (before acting):
   `Breadcrumb(category: 'nav.back', message: 'group-detail back', data: {'routerCanPop': <the canPop value>}, level: SentryLevel.info)`
2. The new shell handler (before branching):
   `Breadcrumb(category: 'nav.back', message: 'root back', data: {'awaitingSecondBack': _awaitingSecondBack})`

Breadcrumbs only — never `captureMessage`/`captureException` here (no telemetry spam; `aborted`-style noise rules stay untouched).

**Diff-coverage floor (the #1187 lesson):** every changed lib line must EXECUTE under tests. Both breadcrumb lines run inside the back handlers the tests below drive, so no dedicated Sentry assertion is needed — but the fixer must confirm via the coverage run, not assume.

## Tests — define done (RED first)

New `test/features/home/bottom_nav_shell_back_test.dart`. Intercept exit via
`tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, ...)` recording `SystemNavigator.pop` method calls; drive system back via `tester.binding.handlePopRoute()`.

1. **First back on shell → no exit, snackbar shown.** Assert zero `SystemNavigator.pop` calls AND `backAgainToExit` text visible. *(RED against current code: the recorded pop call count is 1 — this is the regression test for the symptom class.)*
2. **Second back within window → exits.** Two `handlePopRoute()` in quick succession → exactly one `SystemNavigator.pop` call.
3. **Window expiry resets.** Back once → `tester.pump(const Duration(seconds: 3))` (Timer fires, snackbar auto-dismisses) → back again → still zero pops, snackbar re-shown.
4. **Pushed route unaffected.** With a route pushed on top of `/home` (reuse the `group_detail_navigation_test.dart` harness conventions), system back pops to home, zero `SystemNavigator.pop` calls, no exit snackbar. Guards the #243/#666 non-interference claim.
5. **RTL smoke:** test 1 under `Locale('ar')` — the AR string renders (pins the ARB pair exists).

Test-harness traps (from CLAUDE.md, binding on the fixer): override `sharedPreferencesProvider` in every app-booting test; never `pumpAndSettle` after `pumpRihlaApp`; pump past the 2s reset Timer before teardown or cancel-in-dispose covers it (test 3's pump does); existing shell tests live under `test/features/home/` — follow their boot helper.

Existing suites that must stay green: `test/features/home/`, `test/features/groups/group_detail_navigation_test.dart`, `test/unit/app_router_test.dart`.

## Acceptance
- [ ] First system back on `/home` (any tab) shows "Press back again to exit" and does not exit; second within 2s exits; window resets after 2s.
- [ ] Back on pushed routes (group-detail and deeper) behaves exactly as today (tests 4 + existing nav suites green).
- [ ] `nav.back` breadcrumbs emitted at both chokepoints; app runs with Sentry uninitialized (tests) without error.
- [ ] EN + AR strings shipped with regenerated l10n; RTL smoke green.
- [ ] RED output for test 1 captured pre-fix and pasted in the PR body.
- [ ] `flutter analyze` clean; `tool/check_theme_purity.sh` pass; 90% diff-coverage floor met.

## Verification-principles record (run while authoring)
1. **Callsite classification:** all touched paths INBOUND/UI-only. Breadcrumbs feed Sentry telemetry (external sink), not Firestore — no write path, no schema surface.
2. **Concrete claims re-grepped this session:** `BottomNavShell` mounted at `home_screen.dart:64`; shell has NO existing PopScope/SystemNavigator (grep verified); `/home` top-level `GoRoute` at `app_router.dart:188`; group-detail guard at `group_detail_screen.dart:65-75`; shell tests dir `test/features/home/`; `snackBarTheme` floating set in `app_theme.dart` (#419/#437 note).
3. **Read-path per write-path:** N/A — no persisted data changes. The only new state is in-memory widget state.
4. **Field enumeration:** N/A — no model touched.
5. **Data contracts:** `SystemChannels.platform` method string `SystemNavigator.pop` (test mock matches engine contract); `Breadcrumb(category/message/data)` shape per sentry_flutter 9.x.
6. **Arithmetic decomposition:** N/A.
7. **Orthogonal adversarial axes:** time (Timer window expiry — test 3), locale/RTL (test 5), navigation depth (test 4: guard must not leak into pushed routes), and the named UX trade-off (predictive-back preview loss) surfaced for the Gate reviewers to challenge rather than buried.

## Gate outcome (round 1 — PASSED)

Two fresh-context Opus reviewers (rubric + orthogonal-axis adversary), 2026-07-12: **0 P1 union** (rubric 0 P1/1 P2/3 P3; adversary 0 P1/1 P2/3 P3). Non-blocking findings folded in as binding implementation guidance:

- **[P2, both reviewers] Test 4 must mount the REAL `HomeScreen`/`BottomNavShell` at `/home`**, then push group-detail. The `group_detail_navigation_test.dart` harness stubs `/home` as `Scaffold(body: Text('Home'))` — a test 4 built on that stub cannot exercise the non-interference claim (vacuous). And with the real shell mounted, the tree holds TWO PopScopes — assert via the recorded `SystemNavigator.pop` count + snackbar visibility, NEVER `tester.widget<PopScope>(single-match finder)` ("too many widgets" throw).
- **[P3] Wrap root:** the shell's `build` returns `BottomNavTabScope(child: Scaffold(...))` (`bottom_nav_shell.dart:72-84`) — the new `PopScope` wraps the whole `BottomNavTabScope`, not just the Scaffold.
- **[P3] Imports:** `bottom_nav_shell.dart` needs BOTH `dart:async` (Timer) and `package:sentry_flutter/sentry_flutter.dart` (breadcrumb) — it has neither today. `group_detail_screen.dart` already imports sentry.
- **[P3] Timer hygiene in tests:** every test that shows the exit snackbar must pump past its 2s duration (or drain) before teardown — the ScaffoldMessenger snackbar timer is the "A Timer is still pending" family.
- **[P3, accepted residual] Stale `_awaitingSecondBack` across a sub-2s navigate-out-and-return** (back → tap group → back → back, all inside 2s, exits without a fresh snackbar): requires 4 interactions in <2s, the timer self-clears, and the outcome matches rapid-double-back intent. Documented, not coded around.
- **Existing-suite insulation verified by both reviewers:** the nav suites stub `/home` (no shell PopScope in their trees), and `home_group_row_navigation_test.dart:481`'s singular PopScope finder survives because offstage widgets are skipped by default. Four `test/features/home/` files mount `BottomNavShell` directly and don't drive back — expected green, but run the whole dir.

## Out of scope (named homes)
- Tab-back-to-home-tab rerouting — new decision, file separately if wanted.
- Any change to `app_router.dart`, tab screens, or the group-detail guard beyond the one breadcrumb line.
- Root-cause hunt for the engine race — #1188 stays OPEN (`Refs #1188`, not `Closes`) until the instrumentation confirms or the guard makes the symptom unreachable and we decide to close it deliberately.
