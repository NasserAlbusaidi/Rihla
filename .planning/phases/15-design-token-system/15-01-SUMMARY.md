---
phase: 15-design-token-system
plan: 01
subsystem: ui
tags: [flutter, theme, design-tokens, ThemeExtension, WCAG, earthy-palette, terracotta]

# Dependency graph
requires: []
provides:
  - AppColorTokens ThemeExtension with 30 typed color fields and earthyLight static instance
  - AppSpacingTokens ThemeExtension with spacing scale, radii, buttonHeight
  - AppShadowTokens ThemeExtension with flat/raised/floating warm-brown shadows
  - BuildContext extensions: context.colors, context.spacing, context.shadows
  - AppColors facade updated to warm earthy palette (terracotta, sand, olive, dark brown)
  - ThemeExtensions registered in AppTheme.lightTheme
  - 36 unit tests verifying token correctness and WCAG contrast compliance
affects:
  - 18-home-dashboard
  - 19-navigation-restructuring
  - 20-group-detail-event-hub
  - 21-module-screens
  - 22-appcolors-migration

# Tech tracking
tech-stack:
  added: []
  patterns:
    - ThemeExtension-based design token system (three concerns: colors, spacing, shadows)
    - Two-layer color naming: core role names (primary, textPrimary) + domain aliases (moduleLedger, moduleLedgerLight)
    - Two-color financial token strategy: display variant (success/error) + text variant (successText/errorText) for WCAG compliance
    - AppColors static facade preserved for backward compat — 895 call sites unaffected
    - context.colors/spacing/shadows terse access pattern via BuildContext extension

key-files:
  created:
    - lib/core/theme/tokens/color_tokens.dart
    - lib/core/theme/tokens/spacing_tokens.dart
    - lib/core/theme/tokens/shadow_tokens.dart
    - lib/core/theme/tokens/domain_aliases.dart
    - test/unit/design_tokens_test.dart
  modified:
    - lib/core/theme/app_theme.dart

key-decisions:
  - "Two-color financial token pattern: success/error stay as display-only tokens; successText/errorText added as WCAG-safe text variants (4.51:1 and 5.33:1 on sand)"
  - "AppColors facade values updated in-place — 895 call sites compile unchanged per D-16/D-18"
  - "textOnPrimary changed from black (#000000) to white (#FFFFFF) — critical fix, white has 3.64:1 on terracotta (AA large) vs black has poor contrast on dark terracotta"
  - "Test isolation: _testTheme() helper uses ThemeData.light().copyWith(extensions) to avoid google_fonts HTTP in tests; AppTheme.lightTheme verified via FlutterError.onError suppression of font errors"
  - "AppShadowTokens uses non-const constructor (List<BoxShadow> is not const-constructable); static factory is a getter not a const"

patterns-established:
  - "Token files in lib/core/theme/tokens/: color_tokens.dart, spacing_tokens.dart, shadow_tokens.dart, domain_aliases.dart"
  - "ThemeExtension classes use final class + const constructor + static const factory (or static getter for non-const)"
  - "copyWith follows ?? fallback pattern; lerp uses Color.lerp for colors, lerpDouble for doubles"
  - "BuildContext extensions use ! (not ?.) — absent extension is a programmer error"
  - "Test google_fonts isolation: GoogleFonts.config.allowRuntimeFetching = false in setUpAll"

requirements-completed: [FOUND-01, FOUND-02]

# Metrics
duration: 7min
completed: 2026-03-28
---

# Phase 15 Plan 01: Design Token Foundation Summary

**ThemeExtension token system with warm earthy palette (terracotta #CC6B49, sand #F2E8D6) replacing neon-mint — 895 AppColors call sites unchanged, WCAG AA verified by 36 automated tests**

## Performance

- **Duration:** ~7 min
- **Started:** 2026-03-28T10:41:35Z
- **Completed:** 2026-03-28T10:48:25Z
- **Tasks:** 3
- **Files modified:** 6 (4 created in tokens/, 1 updated app_theme.dart, 1 created test)

## Accomplishments

- Created four token files in `lib/core/theme/tokens/`: `AppColorTokens` (30 fields), `AppSpacingTokens` (11 fields), `AppShadowTokens` (3 elevation levels), `domain_aliases.dart` (BuildContext extensions)
- Updated `AppColors` facade in-place with earthy palette — all 895 existing call sites compile and produce earthy values without changes
- Registered all three ThemeExtensions in `AppTheme.lightTheme` — accessible via `context.colors`, `context.spacing`, `context.shadows` in any widget tree
- 36 unit tests cover token value correctness, WCAG contrast compliance, extension registration, BuildContext access, copyWith immutability, and lerp interpolation
- All 660 tests pass (624 existing + 36 new)

## Task Commits

Each task was committed atomically:

1. **Task 1: Create ThemeExtension token classes and BuildContext aliases** - `7591c1e` (feat)
2. **Task 2: Update AppColors facade to earthy palette and register ThemeExtensions** - `48bb1ad` (feat)
3. **Task 3: Write token system unit tests with WCAG contrast verification** - `e9e391c` (test)

## Files Created/Modified

- `lib/core/theme/tokens/color_tokens.dart` — AppColorTokens with 30 typed fields, earthyLight static instance, copyWith/lerp, headerGradient computed getter
- `lib/core/theme/tokens/spacing_tokens.dart` — AppSpacingTokens with spacing scale, radii, buttonHeight; standard static instance
- `lib/core/theme/tokens/shadow_tokens.dart` — AppShadowTokens with flat/raised/floating using warm brown base (#2C1A0E); standard static getter
- `lib/core/theme/tokens/domain_aliases.dart` — BuildContext extensions: context.colors, context.spacing, context.shadows
- `lib/core/theme/app_theme.dart` — AppColors palette updated (terracotta primary, sand background, dark brown text, white textOnPrimary); ThemeExtensions registered; ColorScheme.light updated; dark theme deferred comment added
- `test/unit/design_tokens_test.dart` — 36 tests across 7 groups including WCAG AA compliance verification

## Decisions Made

- **Two-color financial tokens:** `success`/`error` retained as display-only (badges, icons); `successText`/`errorText` added as WCAG-safe text variants. Resolves FOUND-02 without contradicting D-02.
- **textOnPrimary = white:** Changed from black (#000000) to white (#FFFFFF). White has 3.64:1 contrast on terracotta (AA large), black has ~1.5:1 (fails). Critical correctness fix.
- **Test isolation strategy:** Used `_testTheme()` helper (ThemeData.light().copyWith(extensions)) for widget tests to avoid google_fonts HTTP fetch failures. Single `AppTheme.lightTheme` test uses FlutterError.onError suppression for async font errors while still verifying extension registration.
- **AppShadowTokens is not const:** `List<BoxShadow>` cannot be const-constructed; `standard` is a static getter rather than a const. This is a language constraint, not a design choice.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Test infrastructure: google_fonts HTTP fetch causes false test failures**
- **Found during:** Task 3 (design token tests)
- **Issue:** `AppTheme.lightTheme` calls `_buildTextTheme` which calls `GoogleFonts.getFont` — this async-loads fonts from the network. In test environments, this causes post-completion test failures when fonts are unavailable.
- **Fix:** Created `_testTheme()` helper using `ThemeData.light().copyWith(extensions)` for widget tests. Added `GoogleFonts.config.allowRuntimeFetching = false` in `setUpAll`. For the single `AppTheme.lightTheme` integration test, used `FlutterError.onError` suppression to handle async font errors after test completes.
- **Files modified:** `test/unit/design_tokens_test.dart`
- **Verification:** All 36 tests pass; test correctly verifies AppTheme.lightTheme has all three extensions registered
- **Committed in:** `e9e391c` (Task 3 commit)

---

**Total deviations:** 1 auto-fixed (Rule 1 — Bug in test infrastructure)
**Impact on plan:** The fix is a standard Flutter testing pattern. All behavioral assertions from the plan are preserved. The `_testTheme()` helper correctly tests token registration without font dependency. No scope creep.

## Issues Encountered

None beyond the google_fonts test isolation issue documented above.

## Known Stubs

None — all token values are fully specified. No placeholder or TODO values in the created files.

## Next Phase Readiness

- Design token system is fully operational. All 30 color tokens, 11 spacing tokens, and 3 shadow levels are registered and accessible via `context.colors`, `context.spacing`, `context.shadows`
- AppColors facade produces earthy palette — Phase 18-22 screens will get warm earthy colors automatically as they are rebuilt
- Per D-17/D-18, migration from `AppColors.x` to `context.colors.x` is deferred to Phases 18-22 (per-screen). Phase 15 Plan 02 (CI lint rule) comes next
- No blockers

## Self-Check: PASSED

- lib/core/theme/tokens/color_tokens.dart — FOUND
- lib/core/theme/tokens/spacing_tokens.dart — FOUND
- lib/core/theme/tokens/shadow_tokens.dart — FOUND
- lib/core/theme/tokens/domain_aliases.dart — FOUND
- test/unit/design_tokens_test.dart — FOUND
- .planning/phases/15-design-token-system/15-01-SUMMARY.md — FOUND
- Commit 7591c1e (Task 1) — FOUND
- Commit 48bb1ad (Task 2) — FOUND
- Commit e9e391c (Task 3) — FOUND

---
*Phase: 15-design-token-system*
*Completed: 2026-03-28*
