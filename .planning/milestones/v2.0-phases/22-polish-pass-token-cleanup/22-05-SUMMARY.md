---
phase: 22-polish-pass-token-cleanup
plan: 05
subsystem: design-tokens
tags: [token-migration, appcolors-deletion, refactor, dart-const]
dependency_graph:
  requires: [22-01, 22-02, 22-03, 22-04]
  provides: [PLSH-05, zero-AppColors-refs, AppColors-deleted]
  affects: [all-ui-files, app_theme, design-system]
tech_stack:
  added: []
  patterns:
    - AppColorTokens.light.x for all color references (ThemeExtension access)
    - AppSpacingTokens.standard.x for spacing (or literal values in const contexts)
    - AppShadowTokens.standard.x for box shadows
    - Inline const Color(0xFF...) for default parameter values and const Map entries
key_files:
  created: []
  modified:
    - lib/core/theme/app_theme.dart (AppColors class deleted; AppTheme uses tokens directly)
    - lib/core/theme/error_widgets.dart
    - lib/core/router/app_router.dart
    - lib/features/events/models/event_type_config.dart
    - lib/shared/widgets/dot_step_indicator.dart
    - test/unit/design_tokens_test.dart (added 5 new Phase 22 fields to constructor calls)
    - "...83 additional UI files (see commit d073b94)"
decisions:
  - ThemeExtension fields via static const instance are NOT Dart compile-time constants — const must be removed from parent constructors that contain token property accesses
  - EventTypeConfig const Map and default parameter values require inline const Color literals (not token properties) — values documented in comments referencing the token name
  - design_tokens_test.dart lerp tests updated with 5 new required fields (inputFillWarm, focusBorderWarm, borderWarm, warning, primaryDark) added in Phase 22
  - group_balance_card_test.dart dead AppColors stub class removed (was never used)
metrics:
  duration_minutes: 60
  completed_date: "2026-03-31"
  tasks_completed: 1
  tasks_total: 1
  files_modified: 88
---

# Phase 22 Plan 05: AppColors Deletion — Bulk Token Migration Summary

Migrated all 1375 AppColors references across 85 files to AppColorTokens/AppSpacingTokens/AppShadowTokens, then deleted the AppColors class entirely.

## What Was Built

Complete deletion of the AppColors compatibility facade class. All 1375 call sites in lib/ and test/ now reference tokens directly via `AppColorTokens.light.x`, literal values for spacing in const contexts, and `AppShadowTokens.standard.x` for shadows.

## Tasks Completed

| Task | Name | Commit | Files |
|------|------|--------|-------|
| 1 | Bulk replace AppColors across 85 files + delete class | d073b94 | 88 files (85 lib + 3 test) |

## Verification Results

```
grep -rc "AppColors\." lib/ test/ --include="*.dart" | grep -v ":0$"
# → 0 results (zero AppColors references remain)

grep "class AppColors" lib/core/theme/app_theme.dart
# → 0 results (class deleted)

flutter analyze → 0 errors (230 info/style hints only)
flutter test → 767/767 passed
```

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] `primarySurface` undefined getter in invite_code_display.dart**
- **Found during:** Task 1 — flutter analyze after migration
- **Issue:** Migration script incorrectly replaced `AppColors.mintSurface` with `AppColorTokens.light.primarySurface` (which doesn't exist) in one file. Root cause: the `mint` replacement pattern partially matched `mintSurface` despite ordering.
- **Fix:** Replaced `AppColorTokens.light.primarySurface` with `AppColorTokens.light.selectionFill` (the correct token for mintSurface)
- **Files modified:** `lib/features/groups/widgets/invite_code_display.dart`

**2. [Rule 1 - Bug] 335 const_eval_property_access errors — ThemeExtension const constraint**
- **Found during:** Task 1 — flutter analyze after migration
- **Issue:** `AppColorTokens.light.x` cannot be used in `const` expressions because ThemeExtension fields accessed via a static const instance are not Dart compile-time constants. The original `AppColors.x` was `static const Color`, which was a true compile-time constant.
- **Fix:** Removed `const` keyword from the 335 affected parent constructors across 69 files. For 3 special cases (default parameter values, const Map) used inline `const Color(0xFF...)` literals with comments referencing the token name.
- **Files modified:** 69 lib/ files + special handling for event_type_config.dart, error_widgets.dart, dot_step_indicator.dart

**3. [Rule 2 - Missing critical functionality] design_tokens_test.dart missing required constructor args**
- **Found during:** Task 1 — flutter analyze after migration
- **Issue:** Two `const AppColorTokens(...)` constructor calls in lerp tests were missing the 5 new required fields added in Phase 22 (inputFillWarm, focusBorderWarm, borderWarm, warning, primaryDark).
- **Fix:** Added the 5 new fields with `Color(0xFF000000)` test values to both constructor calls.
- **Files modified:** `test/unit/design_tokens_test.dart`

**4. [Rule 1 - Bug] `const NetworkErrorWidget()` call — non-const constructor**
- **Found during:** Task 1 — flutter analyze after migration
- **Issue:** `category_selection_step.dart` used `const NetworkErrorWidget()` but after the migration, NetworkErrorWidget's constructor has a non-const default parameter (inline Color literal in default value requires `const` on the arg, not the constructor).
- **Fix:** Removed `const` from `const NetworkErrorWidget()` call.
- **Files modified:** `lib/features/ledger/widgets/category_selection_step.dart`

## Known Stubs

None. All token references are wired to real AppColorTokens.light values.

## Self-Check: PASSED

- [x] Commit d073b94 exists: `git log --oneline | grep d073b94` → confirmed
- [x] AppColors class deleted: `grep "class AppColors" lib/core/theme/app_theme.dart` → 0 results
- [x] Zero AppColors refs: `grep -rc "AppColors\." lib/ test/ --include="*.dart" | grep -v ":0$"` → 0 results
- [x] flutter analyze: 0 errors
- [x] flutter test: 767/767 passed
