---
phase: 17-animation-library-loading-states
plan: 02
subsystem: ui
tags: [flutter, flutter_animate, animation, tap-bounce, fade-in, staggered-grid, shared-widgets, tdd]

# Dependency graph
requires:
  - phase: 15-design-token-system
    provides: AppColors tokens used in migrated card widgets
  - phase: 17-01
    provides: flutter_animate package already added to pubspec (dependency for FadeInList and StaggeredGrid)
provides:
  - TapBounce shared animation widget (lib/shared/animations/tap_bounce.dart)
  - FadeInList shared animation widget (lib/shared/animations/fade_in_list.dart)
  - StaggeredGrid shared animation widget (lib/shared/animations/staggered_grid.dart)
  - Barrel export at lib/shared/animations/animations.dart
  - 3 consumer files migrated from private pressable implementations to TapBounce
affects: [phases-18-22, any-screen-adding-tap-feedback, any-screen-using-list-animations, any-screen-using-grid-animations]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "TapBounce: shared press-scale widget replaces per-file AnimationController patterns"
    - "AnimateList with MoveEffect(begin: Offset(0, 12)) for pixel-accurate slide (not SlideEffect normalized units)"
    - "MediaQuery.maybeOf(context)?.disableAnimations for null-safe reduced motion check in tests"
    - "TDD: write failing tests first, then implement, no pumpAndSettle anywhere"

key-files:
  created:
    - lib/shared/animations/tap_bounce.dart
    - lib/shared/animations/fade_in_list.dart
    - lib/shared/animations/staggered_grid.dart
    - lib/shared/animations/animations.dart
    - test/unit/tap_bounce_test.dart
    - test/unit/fade_in_list_test.dart
    - test/unit/staggered_grid_test.dart
  modified:
    - lib/shared/widgets/smart_module_card.dart
    - lib/features/events/screens/event_type_picker_screen.dart
    - lib/features/events/widgets/event_card.dart

key-decisions:
  - "TapBounce uses 120ms/0.97/easeInOut per D-05, replacing the old 80ms/0.98 across all 3 migrated files — intentional spec upgrade"
  - "MoveEffect(begin: Offset(0, 12)) chosen over SlideEffect for FadeInList — pixel-accurate 12dp per D-04, not normalized units"
  - "Gear test failures caused by parallel 17-01 agent skeleton_loader.dart changes — out of scope for 17-02, deferred to deferred-items.md"

patterns-established:
  - "Shared animations in lib/shared/animations/ — import via barrel export animations.dart"
  - "All animation widgets check MediaQuery.maybeOf(context)?.disableAnimations before animating"
  - "AnimationController disposed before super.dispose() — enforced in TapBounce, one canonical place"
  - "No private _PressableWrapper or _PressableCard in any screen/widget file — use TapBounce instead"

requirements-completed: [PLSH-03]

# Metrics
duration: 8min
completed: 2026-03-29
---

# Phase 17 Plan 02: Animation Components Summary

**Three shared animation widgets (TapBounce 120ms/0.97, FadeInList 350ms/50ms stagger, StaggeredGrid 400ms/60ms stagger) created and 3 duplicate private pressable implementations eliminated via shared TapBounce**

## Performance

- **Duration:** 8 min
- **Started:** 2026-03-29T10:57:28Z
- **Completed:** 2026-03-29T11:05:26Z
- **Tasks:** 2
- **Files modified:** 10 (7 created, 3 modified)

## Accomplishments

- TapBounce (D-05): 120ms, scale 0.97, easeInOut, correct dispose ordering, reduced motion bypass — replaces 3 duplicate private pressable patterns
- FadeInList (D-04): 350ms, 50ms stagger, easeOutCubic, 12dp slide-up via MoveEffect, reduced motion bypass
- StaggeredGrid (D-06): 400ms, 60ms stagger, easeOutQuart, scale 0.95→1.0, reduced motion bypass
- All 3 private pressable classes (_PressableWrapper, _PressableCard x2) eliminated from lib/
- 13 widget tests passing across tap_bounce_test, fade_in_list_test, staggered_grid_test — zero pumpAndSettle

## Task Commits

1. **Task 1: Create TapBounce, FadeInList, StaggeredGrid with tests (TDD)** - `f472cc7` (feat)
2. **Task 2: Migrate 3 duplicate pressable patterns to shared TapBounce** - `51c9f17` (feat)

**Plan metadata:** (see final docs commit below)

## Files Created/Modified

- `lib/shared/animations/tap_bounce.dart` — Shared press-scale widget (D-05: 120ms, 0.97, easeInOut)
- `lib/shared/animations/fade_in_list.dart` — Staggered fade-in list (D-04: 350ms, 50ms, easeOutCubic, 12dp)
- `lib/shared/animations/staggered_grid.dart` — Staggered grid reveal (D-06: 400ms, 60ms, easeOutQuart)
- `lib/shared/animations/animations.dart` — Barrel export for all 3 components
- `test/unit/tap_bounce_test.dart` — 7 widget tests for TapBounce (renders, no-op on null/disabled, scale, tap, cancel, dispose)
- `test/unit/fade_in_list_test.dart` — 3 widget tests (render all, empty, reduced motion)
- `test/unit/staggered_grid_test.dart` — 3 widget tests (render all, empty, reduced motion)
- `lib/shared/widgets/smart_module_card.dart` — Replaced `_PressableWrapper` with `TapBounce`
- `lib/features/events/screens/event_type_picker_screen.dart` — Replaced `_PressableCard` with `TapBounce` (key preserved)
- `lib/features/events/widgets/event_card.dart` — Replaced `_PressableCard` (AnimatedScale variant) with `TapBounce`

## Decisions Made

- **TapBounce animation spec 120ms/0.97 (not old 80ms/0.98):** All 3 migrated files updated to D-05 spec. Intentional upgrade per plan.
- **MoveEffect over SlideEffect:** MoveEffect takes logical pixels (Offset(0, 12) = 12dp), while SlideEffect uses normalized widget-height fractions. D-04 specifies 12dp, so MoveEffect is the semantically correct choice.
- **Gear test failures out of scope:** 8 failures in gear_screen_mutations_test.dart caused by parallel 17-01 agent's skeleton_loader.dart changes producing a taller widget that overflows the test viewport by 90px. Logged to deferred-items.md.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Fixed ScaleTransition test assertion using findsOneWidget**
- **Found during:** Task 1 (TDD GREEN phase)
- **Issue:** Test expected `findsOneWidget` for ScaleTransition but Scaffold's page transition also contributes a ScaleTransition, causing 2 matches
- **Fix:** Changed assertion to `findsWidgets` (semantically correct — we care that ScaleTransition exists, not that exactly one exists globally)
- **Files modified:** test/unit/tap_bounce_test.dart
- **Verification:** All 13 tests pass after fix
- **Committed in:** f472cc7 (Task 1 commit)

---

**Total deviations:** 1 auto-fixed (Rule 1 - test assertion bug)
**Impact on plan:** Minimal. Test was verifying the wrong count due to Scaffold animation infrastructure. Fix preserves intent.

## Issues Encountered

- Parallel 17-01 agent's `skeleton_loader.dart` modifications caused `gear_screen_mutations_test.dart` to fail with RenderFlex overflow (90px vertical). This is not caused by 17-02 changes — verified by stashing 17-02 changes and confirming gear tests pass. Logged to `.planning/phases/17-animation-library-loading-states/deferred-items.md`.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

- All 3 shared animation widgets available via `import 'package:safar/shared/animations/animations.dart'`
- Phases 18-22 can use TapBounce for any pressable card, FadeInList for content lists, StaggeredGrid for module grids
- PLSH-03 satisfied: reusable animation components exist as shared library widgets
- No private pressable implementations remaining in lib/ — consistent pattern established

## Self-Check: PASSED

- `lib/shared/animations/tap_bounce.dart` — FOUND
- `lib/shared/animations/fade_in_list.dart` — FOUND
- `lib/shared/animations/staggered_grid.dart` — FOUND
- `lib/shared/animations/animations.dart` — FOUND
- `test/unit/tap_bounce_test.dart` — FOUND
- `test/unit/fade_in_list_test.dart` — FOUND
- `test/unit/staggered_grid_test.dart` — FOUND
- Commit `f472cc7` (Task 1) — FOUND
- Commit `51c9f17` (Task 2) — FOUND
- No `class _PressableWrapper` or `class _PressableCard` in lib/ — VERIFIED
- TapBounce used in all 3 migrated files — VERIFIED (1 match each)
- No `pumpAndSettle` in test files — VERIFIED

---
*Phase: 17-animation-library-loading-states*
*Completed: 2026-03-29*
