---
phase: 21-module-screens-redesign
plan: "06"
subsystem: onboarding-splash
tags: [onboarding, splash, earthy-palette, terracotta, warm-sand, D-29, D-30]
dependency_graph:
  requires: [21-01]
  provides: [SCRN-06]
  affects: [first-run-experience, brand-first-impression]
tech_stack:
  added: []
  patterns:
    - DotStepIndicator for page dots (no checkmarks — onboarding has no complete state)
    - Earthy gradient circles: terracotta/olive/dusty-teal per page
    - Warm sand splash: Color(0xFFF2E8D6) hard-coded per D-30 (not an AppColors token)
key_files:
  created: []
  modified:
    - lib/features/onboarding/screens/onboarding_screen.dart
    - lib/core/router/app_router.dart
decisions:
  - id: D-29
    summary: "Onboarding uses white background with warm gradient icon circles and terracotta dots — terracotta CTA locked to final page only, not teal"
  - id: D-30
    summary: "Splash warm sand (#F2E8D6) is a hard-coded one-off — not added to AppColors since it's splash-specific and not reused elsewhere"
metrics:
  duration_seconds: 178
  completed_date: "2026-03-30"
  tasks_completed: 2
  files_modified: 2
---

# Phase 21 Plan 06: Onboarding + Splash Redesign Summary

**One-liner:** White-background onboarding with earthy gradient circles, terracotta DotStepIndicator, terracotta Get Started CTA, and minimal warm sand splash screen.

## What Was Built

### Task 1: Onboarding Screen Redesign (lib/features/onboarding/screens/onboarding_screen.dart)

Transformed the onboarding screen from a dark, animated-blob aesthetic to a clean light design:

- **Background:** `AppColors.surfaceDark` (#111827 dark) replaced with `AppColors.background` (white). Warm feel comes from earthy circles and terracotta dots, not the page background.
- **Animated blob background removed:** Deleted `_buildBackground()` method entirely — the dark gradient base container, two AnimatedPositioned blur blob containers, and the `dart:ui` import for ImageFilter. The `Stack` wrapping body was also removed (no longer needed).
- **Icon circles:** Each page now shows a 72dp `BoxShape.circle` container with a two-stop `LinearGradient` and a 48dp white `Icon`. Earthy gradient per page: terracotta (#CC6B49→#D4845F), olive (#7A8C5E→#8EA06E), dusty teal (#0D7B74→#0A9187).
- **Text styling:** Title 20sp/w600/textPrimary, subtitle 14sp/w400/textSecondary (was 36sp/w900/white and 16sp/w500/white-50%).
- **Dot indicator:** `DotStepIndicator(stepCount: 3, currentStep: _currentPage, activeColor: AppColors.terracotta, showCheckmarks: false)` replaces the previous custom AnimatedContainer dots row.
- **Final CTA:** `ElevatedButton` with `backgroundColor: AppColors.terracotta` and text "Get Started" — locked to terracotta per D-29, not teal.
- **Non-final CTA:** Teal ElevatedButton with "Next" text (standard primary action).
- **Skip button:** TextButton with textSecondary color, only visible on non-final pages.
- **_OnboardingPageData:** Simplified — removed `accentColor` and `backgroundIcon` fields (no longer needed), added `gradientColors: List<Color>`.

### Task 2: Splash Screen Update (lib/core/router/app_router.dart)

Replaced the dark branded loading screen with a minimal warm design:

- **Background:** `AppColors.surfaceDark` replaced with `const Color(0xFFF2E8D6)` (warm sand per D-30). Used as a hard-coded hex value since this color is splash-specific and not in AppColors.
- **Body:** Replaced the `Column` with teal gradient logo box (80dp container with LinearGradient, BoxShadow, explore_rounded icon), "Rihla" text (white, 32sp, w900), and CircularProgressIndicator with a single `Text('Rihla')`: 28sp, w600, Plus Jakarta Sans, `AppColors.textPrimary` (#111827 dark).
- **Made const:** The entire `_SplashScreen.build()` returns a `const Scaffold` — possible because all child widgets are compile-time constants.
- Route configuration, redirect logic, and all other routes were not modified.

## Deviations from Plan

None — plan executed exactly as written.

## Known Stubs

None — both screens are fully implemented with real content. Onboarding logic (PageController, SharedPreferences, GoRouter navigation) is unchanged and functional.

## Self-Check: PASSED

- lib/features/onboarding/screens/onboarding_screen.dart exists and contains `AppColors.background`, `DotStepIndicator(`, `showCheckmarks: false`, `AppColors.terracotta`, `Get Started`, `backgroundColor: AppColors.terracotta`, `BoxShape.circle`, `size: 48`, zero occurrences of `surfaceDark`
- lib/core/router/app_router.dart exists and contains `Color(0xFFF2E8D6)`, `Rihla` text, `fontSize: 28`, `fontWeight: FontWeight.w600`, zero occurrences of `surfaceDark` in `_SplashScreen`
- flutter analyze: No issues found on both files
- flutter test --no-pub: 752 tests passed, 0 failures
- Commits: a72aab4 (onboarding), a045784 (splash)
