---
phase: 17-animation-library-loading-states
plan: 01
subsystem: ui
tags: [flutter, shimmer, skeleton, loading-states, animation, design-tokens]

# Dependency graph
requires:
  - phase: 15-design-token-system
    provides: AppColors tokens (surfaceLight, surface, radiusSmall/Medium/Large) used as shimmer colors and shape parameters

provides:
  - 5 composable skeleton primitive widgets (SkeletonCircle, SkeletonBar, SkeletonBlock, SkeletonRow, SkeletonCard)
  - 6 named content-aware skeleton factories on SkeletonLoader (dashboardHero, eventCard, groupList, expenseList, gearList, generic)
  - 3 backward-compatible factories preserved (cardList, documentList, groupList)
  - 21 widget tests covering all primitives and factory variants
  - Warm-neutral shimmer colors (#F3F4F6 base, #F8F9FA highlight)

affects:
  - phase-18-home-screen-redesign (dashboardHero, groupList factories ready)
  - phase-20-group-detail-event-hub (eventCard, expenseList factories ready)
  - phase-21-module-screens (gearList, expenseList factories ready)

# Tech tracking
tech-stack:
  added: []
  patterns:
    - Composable skeleton primitives — base shapes assembled into named layout variants
    - Content-aware skeletons — placeholder layout mirrors real widget layout to prevent jump
    - Shimmer parent / opaque-child — children use AppColors.surface fill; Shimmer.fromColors handles animation
    - Column over ListView.builder in build() — avoids zero-height with unbounded parent
    - const widget trees in factory closures — all skeleton factories produce const widget trees for performance

key-files:
  created:
    - lib/shared/widgets/skeleton_primitives.dart
    - test/unit/skeleton_loader_test.dart
  modified:
    - lib/shared/widgets/skeleton_loader.dart

key-decisions:
  - "Column over ListView.builder in SkeletonLoader.build() — ListView inside an unbounded parent produces zero-height; Column avoids the constraint issue"
  - "Public SkeletonCard primitive replaces private _SkeletonCard — enables reuse across any calling code without re-instantiating privately"
  - "Shimmer colors use AppColors.surfaceLight (#F3F4F6) as base and AppColors.surface (#F8F9FA) as highlight — warm-neutral pair prevents harsh contrast flash"
  - "Shimmer API check: shimmer 3.0.0 Shimmer widget does not expose baseColor/highlightColor as getters; test verifies via gradient.colors list"

patterns-established:
  - "Skeleton primitives pattern: SkeletonCircle/Bar/Block/Row/Card are the atoms; factories are molecules assembled from atoms"
  - "TDD approach: test file written before implementation, verified RED before GREEN"
  - "const factory closures: all itemBuilder lambdas return const widget trees (all children are literals)"

requirements-completed: [NAV-05]

# Metrics
duration: 8min
completed: 2026-03-29
---

# Phase 17 Plan 01: Skeleton Primitives + Content-Aware Factories Summary

**5 composable skeleton primitive widgets and 6 named content-aware loading state factories using shimmer 3.x and AppColors warm-neutral tokens**

## Performance

- **Duration:** 8 min
- **Started:** 2026-03-29T10:57:23Z
- **Completed:** 2026-03-29T11:05:00Z
- **Tasks:** 2
- **Files modified:** 3 created/modified

## Accomplishments

- Built `skeleton_primitives.dart` with 5 public composable widgets: SkeletonCircle, SkeletonBar, SkeletonBlock, SkeletonRow, SkeletonCard
- Refactored `skeleton_loader.dart` to use primitives in 6 named content-aware factories (dashboardHero, eventCard, groupList, expenseList, gearList, generic)
- Preserved 3 backward-compatible factories (cardList, documentList, groupList) — existing consumers in gear_screen, vault_screen, home_screen, logistics_screen unchanged
- Replaced `ListView.builder` with `Column` in `build()` to fix zero-height issue with unbounded parents
- Removed private `_SkeletonCard` class (replaced by public `SkeletonCard` primitive)
- 21 widget tests covering all primitives, all factory variants, shimmer colors, and backward compat

## Task Commits

Each task was committed atomically:

1. **Task 1: Skeleton primitives + TDD test file** - `e0ea2c7` (feat)
2. **Task 2: SkeletonLoader refactor with 6 named factories** - `0e49c5b` (feat)
3. **Bug fix: Column overflow in bounded parent** - `38041e1` (fix)

## Files Created/Modified

- `lib/shared/widgets/skeleton_primitives.dart` — 5 primitive StatelessWidgets: SkeletonCircle, SkeletonBar, SkeletonBlock, SkeletonRow, SkeletonCard
- `lib/shared/widgets/skeleton_loader.dart` — Refactored: 6 named factories + 3 compat factories, Column build(), no _SkeletonCard
- `test/unit/skeleton_loader_test.dart` — 21 widget tests, no pumpAndSettle

## Decisions Made

- `Column` over `ListView.builder` in `SkeletonLoader.build()`: ListView inside an unbounded parent produces zero-height constraint errors. Column is the correct pattern for inline skeleton lists.
- Public `SkeletonCard` replaces private `_SkeletonCard`: enables reuse anywhere without import ceremony.
- Shimmer color verification via `gradient.colors`: shimmer 3.0.0 does not expose `baseColor`/`highlightColor` as public getters on the `Shimmer` widget — the factory converts them into `LinearGradient.colors`. Tests check gradient.colors contains both token colors.
- `const` factory closures: `dart fix` was used to apply const constructors throughout factory item builders for performance.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Shimmer test method corrected for shimmer 3.0.0 API**
- **Found during:** Task 2 (SkeletonLoader refactor tests)
- **Issue:** Initial test used `shimmer.baseColor` and `shimmer.highlightColor` which don't exist as public getters on shimmer 3.0.0's `Shimmer` widget
- **Fix:** Test updated to check `shimmer.gradient as LinearGradient` and verify `gradient.colors` contains both `AppColors.surfaceLight` and `AppColors.surface`
- **Files modified:** `test/unit/skeleton_loader_test.dart`
- **Verification:** 21 tests pass
- **Committed in:** `e0ea2c7` (Task 1 commit)

**2. [Rule 1 - Bug] RenderFlex overflow in bounded parent (Expanded) contexts**
- **Found during:** Post-task 2 — gear_screen_mutations_test.dart (8 tests failing with RenderFlex overflow by 90px)
- **Issue:** Column-based `build()` expands to natural height (5 items × ~84px = ~420px) which overflows bounded parent (`Expanded` inside gear screen's `Scaffold > Column > Expanded`). Old `ListView.builder` with `NeverScrollableScrollPhysics` clipped silently within bounded height.
- **Fix:** Wrapped Column in `SingleChildScrollView(physics: NeverScrollableScrollPhysics())` — clips in bounded contexts, preserves Column layout in unbounded contexts
- **Files modified:** `lib/shared/widgets/skeleton_loader.dart`
- **Verification:** All 8 gear tests pass, 694 total tests pass
- **Committed in:** `38041e1`

---

**Total deviations:** 2 auto-fixed (2 bugs — shimmer API, overflow)
**Impact on plan:** Both bugs were correctness issues requiring fixing. No scope creep. All plan acceptance criteria met.

## Issues Encountered

None beyond the auto-fixed deviations above.

## User Setup Required

None — no external service configuration required.

## Next Phase Readiness

- `SkeletonLoader.dashboardHero()` is ready for Phase 18 (Home Screen Redesign)
- `SkeletonLoader.eventCard()` and `expenseList()` are ready for Phase 20 (Group Detail & Event Hub)
- `SkeletonLoader.gearList()` is ready for Phase 21 (Module Screens)
- All existing consumers (gear_screen, vault_screen, home_screen, logistics_screen) compile unchanged — backward compat confirmed

## Self-Check: PASSED

| Item | Status |
|------|--------|
| `lib/shared/widgets/skeleton_primitives.dart` | FOUND |
| `lib/shared/widgets/skeleton_loader.dart` | FOUND |
| `test/unit/skeleton_loader_test.dart` | FOUND |
| `.planning/phases/17-animation-library-loading-states/17-01-SUMMARY.md` | FOUND |
| Task 1 commit `e0ea2c7` | FOUND |
| Task 2 commit `0e49c5b` | FOUND |
| Bug fix commit `38041e1` | FOUND |
| Full test suite (694 tests) | PASSED |

---
*Phase: 17-animation-library-loading-states*
*Completed: 2026-03-29*
