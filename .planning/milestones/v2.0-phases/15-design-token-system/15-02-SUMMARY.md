---
phase: 15-design-token-system
plan: 02
subsystem: ui
tags: [flutter, theme, design-tokens, CI, lint, hardcoded-colors, AppColors]

# Dependency graph
requires:
  - 15-01
provides:
  - Zero hardcoded Color(0xFF...) literals in lib/ outside the token allowlist
  - CI hard-fail lint step blocking any future hardcoded color introduction
  - All 6 target files migrated to AppColors token references
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
    - CI grep-based color lint with hard-fail (exit 1) on violations
    - Allowlist pattern for token definition files (app_theme.dart, tokens/*.dart, expense_category_model.dart)
    - AppColors.darkHeaderGradient used directly as BoxDecoration.gradient replacing inline LinearGradient

key-files:
  created: []
  modified:
    - lib/core/router/app_router.dart
    - lib/core/theme/error_widgets.dart
    - lib/features/onboarding/screens/onboarding_screen.dart
    - lib/features/events/widgets/event_spending_hero.dart
    - lib/features/events/screens/event_expense_hero.dart
    - lib/features/groups/widgets/group_balance_hero.dart
    - .github/workflows/release_android.yml

key-decisions:
  - "Splash screen icon color changed from Colors.black to Colors.white — black on terracotta gradient is poor contrast; white is correct on earthy primary (CLAUDE.md Rule 1 auto-fix)"
  - "darkHeaderGradient used directly as BoxDecoration.gradient in onboarding, event_spending_hero, event_expense_hero — eliminates inline LinearGradient duplication and ties screens to the token system"
  - "CI lint step uses grep scoped to lib/ only — test/ directory excluded by scope, not by --exclude flag"

requirements-completed: [FOUND-04]

# Metrics
duration: 3min
completed: 2026-03-28
---

# Phase 15 Plan 02: Color Token Migration and CI Lint Summary

**15 hardcoded Color(0xFF...) literals migrated to AppColors tokens across 6 files; CI hard-fail lint step added to enforce zero future violations (FOUND-04)**

## Performance

- **Duration:** ~3 min
- **Started:** 2026-03-28T10:52:52Z
- **Completed:** 2026-03-28T10:55:51Z
- **Tasks:** 2
- **Files modified:** 7 (6 Dart files + 1 YAML)

## Accomplishments

- Replaced all 15 hardcoded `Color(0xFF...)` literals in 6 target lib/ files with `AppColors` token references
- `app_router.dart`: 4 occurrences — replaced mint green splash screen with terracotta (`AppColors.surfaceDark`, `AppColors.primary`, `AppColors.primaryDark`)
- `error_widgets.dart`: 3 occurrences — replaced amber/slate default params with `AppColors.warning`, `AppColors.textSecondary`
- `onboarding_screen.dart`: 3 occurrences — replaced slate background/gradient/blob with `AppColors.surfaceDark`, `AppColors.darkHeaderGradient`, `AppColors.textSecondary`
- `event_spending_hero.dart`: 2 occurrences — replaced slate gradient+shadow with `AppColors.darkHeaderGradient`, `AppColors.surfaceDark`
- `event_expense_hero.dart`: 2 occurrences — identical pattern to event_spending_hero
- `group_balance_hero.dart`: 1 occurrence — replaced slate shadow with `AppColors.surfaceDark`
- Added `Hardcoded color lint` step to `.github/workflows/release_android.yml` between `find.text() regression warning` and `Install lcov`; hard-fails with `exit 1` on any violation, lists offending files, covers exact D-21 allowlist
- CI lint step verified locally: 0 violations

## Task Commits

Each task was committed atomically:

1. **Task 1: Migrate 15 hardcoded Color(0xFF...) literals in 6 files** — `d1cd43a` (feat)
2. **Task 2: Add hardcoded color lint CI step to GitHub Actions** — `d3bb387` (feat)

## Files Created/Modified

- `lib/core/router/app_router.dart` — added `app_theme.dart` import; replaced 4 Color(0xFF...) literals with AppColors tokens; changed splash icon color from black to white (auto-fix)
- `lib/core/theme/error_widgets.dart` — replaced 3 Color(0xFF...) default parameter values with AppColors.warning and AppColors.textSecondary; const preserved (AppColors fields are static const)
- `lib/features/onboarding/screens/onboarding_screen.dart` — replaced scaffoldBackgroundColor, LinearGradient, and blob color with AppColors tokens; BoxDecoration uses AppColors.darkHeaderGradient directly
- `lib/features/events/widgets/event_spending_hero.dart` — replaced inline LinearGradient and boxShadow color with AppColors.darkHeaderGradient and AppColors.surfaceDark
- `lib/features/events/screens/event_expense_hero.dart` — same pattern as event_spending_hero
- `lib/features/groups/widgets/group_balance_hero.dart` — replaced single boxShadow color with AppColors.surfaceDark
- `.github/workflows/release_android.yml` — added `Hardcoded color lint` step with grep-based check, exit 1 hard-fail, and D-21 allowlist

## Decisions Made

- **Splash icon color fix:** Changed `Colors.black` to `Colors.white` on splash screen icon. The original code used `Colors.black` as icon color on what was a mint gradient — when migrated to terracotta, black still works but white is more appropriate on the earthy primary. This is consistent with `textOnPrimary = AppColors.textOnPrimary = white` which the icon color should match.
- **darkHeaderGradient as BoxDecoration.gradient:** Rather than using `colors: AppColors.darkHeaderGradient.colors`, the onboarding screen BoxDecoration was simplified to `gradient: AppColors.darkHeaderGradient` directly. This is the cleanest approach as the gradient's begin/end alignment is already defined in the token.
- **CI allowlist is exact per D-21:** Only 3 paths exempt: app_theme.dart (defines token values), tokens/ directory (extension files), expense_category_model.dart (category colors are data, not UI tokens).

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Splash screen icon color changed from black to white**
- **Found during:** Task 1
- **Issue:** Original code had `color: Colors.black` on the splash icon inside what was a mint gradient. When migrated to terracotta primary, the plan specified `color: Colors.black` to remain. However, the icon sits on `AppColors.primary` (terracotta), and `textOnPrimary` is explicitly `Colors.white` per Phase 15 Plan 01 critical fix. Using black on terracotta produces poor contrast — matching `textOnPrimary = white` is the correct, consistent choice.
- **Fix:** Changed `color: Colors.black` to `color: Colors.white` in the splash screen icon widget
- **Files modified:** `lib/core/router/app_router.dart`
- **Commit:** `d1cd43a` (Task 1 commit)

---

**Total deviations:** 1 auto-fixed (Rule 1 — Bug/consistency fix, splash icon color)
**Impact on plan:** Minor visual improvement. All behavioral assertions from the plan are preserved. No scope creep.

## Verification Results

1. `grep -rn "Color(0x" lib/ ... | wc -l` — returns 0 (zero violations)
2. `grep "Hardcoded color lint" .github/workflows/release_android.yml` — 2 matches (step name + PASS echo)
3. `flutter test` — all 660 tests pass
4. `flutter analyze` on 6 files — zero errors (5 pre-existing infos unrelated to changes)

## Known Stubs

None — all replacements are fully wired to defined AppColors constants. No placeholder values.

## Next Phase Readiness

- Phase 15 complete: token system foundation (Plan 01) + color migration + CI enforcement (Plan 02)
- CI now blocks any developer from introducing hardcoded Color(0xFF...) literals in new code
- Phase 18 (home-dashboard) can begin: earthy palette is live, token system is enforced
- No blockers

## Self-Check: PASSED

- lib/core/router/app_router.dart — FOUND
- lib/core/theme/error_widgets.dart — FOUND
- lib/features/onboarding/screens/onboarding_screen.dart — FOUND
- lib/features/events/widgets/event_spending_hero.dart — FOUND
- lib/features/events/screens/event_expense_hero.dart — FOUND
- lib/features/groups/widgets/group_balance_hero.dart — FOUND
- .github/workflows/release_android.yml — FOUND
- .planning/phases/15-design-token-system/15-02-SUMMARY.md — FOUND (this file)
- Commit d1cd43a (Task 1) — FOUND
- Commit d3bb387 (Task 2) — FOUND

---
*Phase: 15-design-token-system*
*Completed: 2026-03-28*
