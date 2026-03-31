---
phase: 21-module-screens-redesign
plan: 01
subsystem: design-tokens-shared-widgets
tags: [tokens, theme, empty-state, skeleton, dot-indicator, foundation]
dependency_graph:
  requires: []
  provides: [sandLight, terracotta, warmGray, module-facade-aliases, InputDecorationTheme-earthy, EmptyStateView-gradient-circle, SkeletonLoader.photoGrid, DotStepIndicator]
  affects: [lib/core/theme/app_theme.dart, lib/shared/widgets/empty_state_view.dart, lib/shared/widgets/skeleton_loader.dart, lib/shared/widgets/dot_step_indicator.dart]
tech_stack:
  added: []
  patterns: [earthy-color-tokens, module-facade-alias, gradient-circle-empty-state, photo-grid-skeleton, dot-step-indicator]
key_files:
  created:
    - lib/shared/widgets/dot_step_indicator.dart
  modified:
    - lib/core/theme/app_theme.dart
    - lib/shared/widgets/empty_state_view.dart
    - lib/shared/widgets/skeleton_loader.dart
decisions:
  - sandLight/terracotta/warmGray added as static const on AppColors — earthy token foundation for Phase 21 form fields and empty state circles
  - Module facade aliases added to AppColors — all module screens can now reference AppColors.moduleLedger etc. without importing AppColorTokens.light directly
  - InputDecorationTheme updated globally — sand fill, terracotta focus border, warm gray enabled border, dark brown labels, 12dp radius per D-26
  - EmptyStateView accentGradient is backward-compatible — existing call sites without accentGradient see unchanged tinted-square behavior
  - DotStepIndicator uses AppColors.terracotta as default activeColor — direct reference rather than const Color literal for consistency
metrics:
  duration: ~10 minutes
  completed: 2026-03-31
  tasks: 2
  files: 4
---

# Phase 21 Plan 01: Foundation Tokens + Shared Widget Upgrades Summary

**One-liner:** Earthy token trio (sandLight/terracotta/warmGray) + module facade aliases added to AppColors, InputDecorationTheme overhauled to sand-fill/terracotta-focus design, EmptyStateView upgraded with gradient circle, SkeletonLoader.photoGrid factory added, DotStepIndicator widget created.

## What Was Built

### Task 1 — Color Tokens + Module Facade Aliases + InputDecorationTheme (commit: 165db7d)

Added three earthy accent tokens to `AppColors`:
- `sandLight = Color(0xFFF5EDE1)` — form field fill
- `terracotta = Color(0xFFCC6B49)` — focused borders, step dots, CTA accent
- `warmGray = Color(0xFFE5D5C0)` — enabled border

Added 14 module color facade aliases (mirrors `AppColorTokens.light` values) so module screen code can reference `AppColors.moduleLedger` etc. without importing the token extension directly.

Updated `InputDecorationTheme` in `lightTheme`:
- Fill: `sandLight` (was `surfaceLight`)
- Enabled border: `warmGray 1.5dp` (was `borderLight`)
- Focused border: `terracotta 2dp` (was `primary teal`)
- Label color: `#2C1A0E` dark brown (was `textSecondary`)
- Hint color: `#A89888` sand gray (was `textMuted`)
- Floating label: `terracotta` (was `primary`)
- Border radius: `radiusMedium 12dp` everywhere (was `radiusLarge 16dp`)

### Task 2 — Widget Upgrades (commit: 56fb13f)

**EmptyStateView** — Added `accentGradient` parameter (`LinearGradient?`):
- When provided: renders 72x72 circle with gradient background, icon white, icon size 48dp
- When null: preserves existing tinted-square behavior (backward compatible)
- Icon size updated from 32dp to 48dp globally per D-17

**SkeletonLoader.photoGrid** — New factory:
- 3-column `GridView.builder` with 8dp gutters
- Default 9 skeleton blocks (configurable via `count` param)
- Used as loading placeholder for MemoriesScreen redesign in subsequent plans

**DotStepIndicator** — New widget (`lib/shared/widgets/dot_step_indicator.dart`):
- Renders filled / outlined / checked dots in a Row
- `stepCount` / `currentStep` (0-indexed) required params
- `activeColor` defaults to `AppColors.terracotta`
- `showCheckmarks` bool: true for Add Expense multi-step, false for onboarding page indicator
- Completed steps show `Iconsax.tick_circle` check icon in white

## Decisions Made

1. **Module facade aliases on AppColors** — Phase 20 used `AppColorTokens.light.*` directly but Phase 21 module screens need `AppColors.*` for consistency with the 895-call-site public API. Aliases bridge the gap without touching token definitions.

2. **InputDecorationTheme is global** — Updating it affects all form fields across the app. The earthy palette is now the canonical form aesthetic. No per-screen override needed.

3. **EmptyStateView backward compatible** — `accentGradient` is optional. All 6 module screens in subsequent plans will pass their earthy gradient; all other call sites see no change.

4. **DotStepIndicator uses `AppColors.terracotta` default** — Ensures the widget compiles after Task 1 lands and doesn't hardcode a hex literal that diverges from the token definition.

## Deviations from Plan

**1. [Rule 1 - Bug] Fixed lint: `unnecessary_underscores` in photoGrid factory**
- **Found during:** Task 2 verification
- **Issue:** `itemBuilder: (_, __) =>` triggered `unnecessary_underscores` lint in `skeleton_loader.dart`
- **Fix:** Renamed to `(context2, index2)` — semantically clear, lint-clean
- **Files modified:** `lib/shared/widgets/skeleton_loader.dart`
- **Commit:** 56fb13f

## Verification Results

- `flutter analyze lib/core/theme/app_theme.dart` — No issues found
- `flutter analyze lib/shared/widgets/empty_state_view.dart lib/shared/widgets/skeleton_loader.dart lib/shared/widgets/dot_step_indicator.dart` — No issues found
- `flutter test --no-pub` — 752 tests passed, 0 failures
- `grep -c 'sandLight\|terracotta\|warmGray' lib/core/theme/app_theme.dart` — 7 (3 definitions + 4 usages in InputDecorationTheme)
- `grep -c 'moduleLedger' lib/core/theme/app_theme.dart` — 2 (definition + facade alias comment block)

## Known Stubs

None — this plan only adds tokens and shared widget infrastructure. No screen-level data wiring involved.

## Self-Check: PASSED

- [x] `lib/core/theme/app_theme.dart` — exists, contains `sandLight`, `terracotta`, `warmGray`, module aliases, updated InputDecorationTheme
- [x] `lib/shared/widgets/empty_state_view.dart` — exists, contains `accentGradient`, `BoxShape.circle`, `size: 48`
- [x] `lib/shared/widgets/skeleton_loader.dart` — exists, contains `SkeletonLoader.photoGrid`, `crossAxisCount: 3`
- [x] `lib/shared/widgets/dot_step_indicator.dart` — exists, contains `DotStepIndicator`, `stepCount`, `currentStep`, `Color(0xFFCC6B49)` default
- [x] Commit 165db7d exists (Task 1)
- [x] Commit 56fb13f exists (Task 2)
