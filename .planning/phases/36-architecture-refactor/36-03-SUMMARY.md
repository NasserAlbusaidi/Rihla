---
phase: 36-architecture-refactor
plan: "03"
subsystem: gear
tags: [refactor, decompose, widget-extraction, tdd]
dependency_graph:
  requires: ["36-00"]
  provides: ["gear_item_card", "gear_add_input", "gear_list_view"]
  affects: ["lib/features/gear/screens/gear_screen.dart"]
tech_stack:
  added: []
  patterns: ["widget extraction", "callback lifting", "stateless child widgets"]
key_files:
  created:
    - lib/features/gear/widgets/gear_item_card.dart
    - lib/features/gear/widgets/gear_add_input.dart
    - lib/features/gear/widgets/gear_list_view.dart
    - test/features/gear/widgets/gear_item_card_test.dart
    - test/features/gear/widgets/gear_add_input_test.dart
    - test/features/gear/widgets/gear_list_view_test.dart
  modified:
    - lib/features/gear/screens/gear_screen.dart
decisions:
  - GearListView holds filter logic (_filtered()) keeping GearScreen free of that computation
  - GearAddInput accepts controller from parent so _focusAddField can work without coupling
  - FadeInList animation timer leak in tests fixed via MediaQuery(disableAnimations:true) wrapper
  - _buildFloatingAction kept on screen (owns _hideClaimed state, small enough at 12 LOC)
  - _buildErrorState kept on screen (owns ref.invalidate call site, tiny helper)
metrics:
  duration: "~25 minutes"
  completed: "2026-04-16"
  tasks_completed: 3
  files_created: 6
  files_modified: 1
---

# Phase 36 Plan 03: Gear Screen Decomposition Summary

Decomposed `gear_screen.dart` (729 LOC) into an orchestrator screen + 3 sibling widgets. Screen is now 341 LOC — well below the 400 stretch target.

## Before / After

| Metric | Before | After |
|--------|--------|-------|
| gear_screen.dart LOC | 729 | 341 |
| Widget files in gear/widgets/ | 1 (gear_hero_card.dart) | 4 |
| Test files for extracted widgets | 0 | 3 |
| Tests added | 0 | 17 |

## What Was Built

**GearItemCard** (`gear_item_card.dart`, ~240 LOC) — card widget for a single gear item. Encapsulates the packed checkbox, item name, status chip (`_StatusChip`), priority badge (`_PriorityBadge`), assignee chip (`_AssigneeChip`), and popup menu. All mutation callbacks (`onTogglePacked`, `onMenuAction`) are passed in from the screen.

**GearAddInput** (`gear_add_input.dart`, ~80 LOC) — stateless input row for adding a new gear item. Accepts `TextEditingController` from parent (so focus control works without coupling), plus `isHighPriority` / `onPriorityChanged` lifted state, and `onSubmit` callback.

**GearListView** (`gear_list_view.dart`, ~175 LOC) — filter + search + CustomScrollView list. Owns the `_filtered()` computation. Composes GearHeroCard, SearchFilterBar, GearAddInput, and GearItemCard instances. All state (search query, status filter, hideClaimed) passed as params; changes lifted via callbacks to screen.

**GearScreen** (reduced to 341 LOC) — orchestrator only: provider watches, mutation handlers (`_addItem`, `_togglePacked`, `_handleMenuAction`, `_confirmDelete`), tiny helpers (`_buildErrorState`, `_buildFloatingAction`, `_focusAddField`).

## Tasks Completed

| Task | Commit | Description |
|------|--------|-------------|
| 1 — Extract GearItemCard | fcf9197 | Removed _buildGearItemCard, _buildStatusChip, _buildPriorityBadge; created gear_item_card.dart |
| 2 — Extract GearAddInput + GearListView | 067f2e5 | Removed _buildContent, _buildAddItemInput; created gear_add_input.dart + gear_list_view.dart; screen to 341 LOC |
| 3 — Widget tests | f05f42b | 17 tests across 3 test files; all green |

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] FadeInList pending timer in GearListView tests**
- **Found during:** Task 3 — first test run
- **Issue:** FadeInList uses flutter_animate AnimateList which leaves timer pending after widget disposal; 5 of 17 tests failed with `!timersPending` assertion
- **Fix:** Wrap test `MaterialApp` with `MediaQuery(data: MediaQueryData(disableAnimations: true))` — FadeInList already respects this flag and falls back to a plain Column
- **Files modified:** test/features/gear/widgets/gear_list_view_test.dart
- **Commit:** f05f42b (included in Task 3 commit)

**2. [Rule 2 - Missing] GearItemCard onMenuAction signature**
- **Found during:** Task 1 design
- **Issue:** Plan specified `onLongPress: ValueChanged<GearItem>` for delete trigger, but the screen uses a PopupMenuButton (not long-press) for all item actions. Matching the screen's actual interaction model required `onMenuAction: void Function(String action, GearItem item)` instead.
- **Fix:** Used `onMenuAction` signature consistent with the existing `_handleMenuAction` method on screen. No behavior change — existing mutations tests confirmed correct wiring.
- **Commit:** fcf9197

## Known Stubs

None. All callbacks are wired to real handlers on GearScreen.

## Threat Flags

None. No new network endpoints, auth paths, or trust boundary changes introduced. Pure structural refactor.

## Self-Check: PASSED

| Check | Result |
|-------|--------|
| gear_item_card.dart exists | FOUND |
| gear_add_input.dart exists | FOUND |
| gear_list_view.dart exists | FOUND |
| gear_item_card_test.dart exists | FOUND |
| gear_add_input_test.dart exists | FOUND |
| gear_list_view_test.dart exists | FOUND |
| commit fcf9197 (Task 1) | FOUND |
| commit 067f2e5 (Task 2) | FOUND |
| commit f05f42b (Task 3) | FOUND |
| gear_screen.dart LOC ≤ 400 | 341 — PASS |
