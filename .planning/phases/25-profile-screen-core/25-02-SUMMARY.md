---
phase: 25-profile-screen-core
plan: "02"
subsystem: navigation, profile
tags: [navigation, profile, router, home-screen, bottom-nav]
dependency_graph:
  requires:
    - lib/features/settings/screens/profile_screen.dart
    - lib/shared/widgets/initials_circle.dart
    - lib/core/providers/settings_provider.dart
    - lib/features/settings/keys/profile_keys.dart
    - lib/core/router/app_router.dart
    - lib/features/home/screens/home_screen.dart
    - lib/features/home/widgets/bottom_nav_shell.dart
  provides:
    - AppRoutes.profile (/profile route)
    - ProfileScreen accessible from home header avatar
    - ProfileScreen accessible from bottom nav tab 3
    - .planning/phases/25-profile-screen-core/phase-26-handoff.md
  affects:
    - lib/core/router/app_router.dart (routes updated)
    - lib/features/home/screens/home_screen.dart (initials avatar added)
    - lib/features/home/widgets/bottom_nav_shell.dart (profile tab wired)
    - lib/features/home/keys/home_keys.dart (new profileAvatar key)
tech_stack:
  added: []
  patterns:
    - GestureDetector with Semantics(button: true) for accessible tap targets
    - InitialsCircle at 32dp in header alongside FAB
    - ProfileScreen embedded in BottomNavShell Stack (always built, opacity-switched)
    - sharedPreferencesProvider override required in all HomeScreen widget tests
    - GoRouter required in BottomNavShell tests (ProfileScreen calls GoRouter.of)
key_files:
  created:
    - .planning/phases/25-profile-screen-core/phase-26-handoff.md
  modified:
    - lib/core/router/app_router.dart (AppRoutes.settings → AppRoutes.profile, /profile route)
    - lib/features/home/screens/home_screen.dart (32px InitialsCircle header avatar)
    - lib/features/home/widgets/bottom_nav_shell.dart (ProfileScreen at tab 3)
    - lib/features/home/keys/home_keys.dart (profileAvatar key added)
    - test/helpers/test_router.dart (/settings → /profile stub)
    - test/features/home/home_screen_dashboard_test.dart (sharedPreferencesProvider, /profile route, updated assertions)
    - test/features/home/home_screen_quick_actions_test.dart (sharedPreferencesProvider, /profile route)
    - test/features/home/home_screen_groups_test.dart (sharedPreferencesProvider, /profile route)
    - test/features/home/widgets_test.dart (sharedPreferencesProvider, GoRouter, updated assertions)
  deleted:
    - lib/features/settings/screens/settings_screen.dart (replaced by profile_screen.dart)
decisions:
  - "Deleted settings_screen.dart and preserved all patterns in phase-26-handoff.md — Phase 26 rebuilds preferences/about sections inside ProfileScreen"
  - "GoRouter required in BottomNavShell widget tests — ProfileScreen.build() calls GoRouter.of(context).canPop()"
  - "sharedPreferencesProvider must be overridden in ALL HomeScreen widget tests — header now watches settingsProvider for deviceName"
  - "Groups/Events bottom nav labels now appear N+1 times in tests (ProfileScreen stat card adds one more) — assertions updated to findsAtLeastNWidgets(1)"
metrics:
  duration: "~15m"
  completed_date: "2026-04-01"
  tasks: 2
  files_created: 1
  files_modified: 9
  files_deleted: 1
  tests_added: 0
  tests_modified: 5
  tests_total: 804
---

# Phase 25 Plan 02: Navigation Wiring — Summary

## One-liner

/settings replaced by /profile, InitialsCircle avatar added to home header navigating to /profile, ProfileScreen wired into bottom nav tab 3, settings_screen.dart deleted with Phase 26 patterns preserved.

## What Was Built

### Task 1: Router update, settings_screen deletion, Phase 26 handoff

**AppRoutes.settings → AppRoutes.profile** — `app_router.dart` import replaced (`settings_screen.dart` → `profile_screen.dart`), route constant renamed, GoRoute `path`/`child` updated. `_slideRightTransition` preserved (D-12).

**settings_screen.dart deleted** — The old screen is gone. `phase-26-handoff.md` captures all patterns Phase 26 will need: section header pattern, 36px leading icon container, notification SwitchListTile, currency/language/theme dialogs, privacy policy/terms dialogs, version display, section card container pattern, and required imports.

**test_router.dart updated** — `/settings` stub replaced with `/profile` stub.

**home_screen_dashboard_test.dart updated** — Added `/profile` route to test router, added `sharedPreferencesProvider` override support, updated Test 10 (Profile tab now shows ProfileScreen not "Coming soon").

### Task 2: Home header avatar and bottom nav Profile tab

**HomeKeys.profileAvatar** — New semantic key for the 48×48 tap target wrapping the 32dp InitialsCircle in the home header.

**Home header update** — FAB is now wrapped in a `Row` alongside an `InitialsCircle(size: 32)` that reads from `ref.watch(settingsProvider).deviceName`. Tap triggers `HapticService.lightClick()` then `context.push('/profile')`. `Semantics(label: 'Open profile', button: true)` wraps the detector.

**BottomNavShell tab 3** — `const _PlaceholderTab()` at index 3 replaced with `const ProfileScreen()`. Stack+AnimatedOpacity pattern unchanged — ProfileScreen is always built, invisible when not active. GoRouter context is required for ProfileScreen to render.

**5 test files updated (Rule 1 fix)** — HomeScreen header now watches `settingsProvider`, which requires `sharedPreferencesProvider`. All HomeScreen widget tests updated with `setUp` blocks and `sharedPreferencesProvider.overrideWithValue(prefs)`. BottomNavShell tests migrated from `MaterialApp` to `MaterialApp.router` (GoRouter required for ProfileScreen). "Coming soon" count assertions corrected from 3 to 2 (Profile tab is now ProfileScreen, not placeholder). Text ambiguity fixes for "Groups" label appearing in both bottom nav and ProfileScreen stat card.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Test suite failures after HomeScreen settingsProvider dependency added**
- **Found during:** Task 2 verification
- **Issue:** `home_screen_quick_actions_test.dart`, `home_screen_groups_test.dart`, and `widgets_test.dart` all rendered `HomeScreen` or `BottomNavShell` without `sharedPreferencesProvider` override. The new `InitialsCircle` in the header triggers `ref.watch(settingsProvider)` which reads `sharedPreferencesProvider`, causing `UnimplementedError` in tests.
- **Fix:** Added `setUp` blocks with `SharedPreferences.setMockInitialValues({})` and `sharedPreferencesProvider.overrideWithValue(prefs)` to all three test files. Migrated `BottomNavShell` tests to `MaterialApp.router` (GoRouter required for `GoRouter.of(context)` call in ProfileScreen). Fixed text-ambiguity issues (`find.text('Groups')`, `find.text('Coming soon')` counts).
- **Files modified:** `test/features/home/home_screen_quick_actions_test.dart`, `test/features/home/home_screen_groups_test.dart`, `test/features/home/widgets_test.dart`
- **Commit:** e81b923

## Known Stubs

None. Navigation is fully wired. Profile is accessible from both entry points (header avatar and bottom nav tab).

## Self-Check: PASSED

- FOUND: commit 6c874e3 (Task 1 — router update)
- FOUND: commit 0542e8a (Task 2 — home header + bottom nav)
- FOUND: commit e81b923 (Task 2 fix — test suite updates)
- FOUND: .planning/phases/25-profile-screen-core/25-02-SUMMARY.md
- FOUND: .planning/phases/25-profile-screen-core/phase-26-handoff.md
- PASS: settings_screen.dart deleted
- PASS: AppRoutes.profile exists in app_router.dart
