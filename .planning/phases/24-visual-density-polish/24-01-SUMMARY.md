---
phase: 24-visual-density-polish
plan: 01
subsystem: groups/widgets
tags: [ui, group-card, visual-density, tdd, riverpod]
dependency_graph:
  requires:
    - lib/features/events/providers/event_provider.dart
    - lib/features/events/models/event_type_config.dart
    - lib/core/theme/tokens/color_tokens.dart
    - lib/core/theme/tokens/shadow_tokens.dart
  provides:
    - GroupCard with 4dp accent strip and event context line
  affects:
    - test/features/home/home_screen_dashboard_test.dart
    - test/features/home/home_screen_groups_test.dart
tech_stack:
  added:
    - timeago package (already in pubspec, now imported in group_card.dart)
  patterns:
    - IntrinsicHeight + CrossAxisAlignment.stretch for full-height accent strip
    - Clip.hardEdge on outer Container for border radius clipping
    - Hash-based color selection from static palette (groupId.hashCode.abs() % 5)
    - StreamProvider.family watch inside ConsumerWidget method
key_files:
  created: []
  modified:
    - lib/features/groups/widgets/group_card.dart
    - test/features/home/home_screen_dashboard_test.dart
    - test/features/home/home_screen_groups_test.dart
decisions:
  - "Used IntrinsicHeight over Row with fixed height to let content drive card height"
  - "Clip.hardEdge on outer Container clips accent strip corners to card border radius"
  - "Loading/error fallback both show 'No events yet' to avoid layout shift"
  - "test _dashboardOverrides() spread first so test-specific overrides win (Riverpod last-wins)"
metrics:
  duration: 476s
  completed_date: "2026-04-01"
  tasks_completed: 2
  files_changed: 3
requirements:
  - CARD-01
  - CARD-02
---

# Phase 24 Plan 01: GroupCard Accent Strip and Event Context Line Summary

GroupCard enriched with a 4dp earthy accent strip on left edge (hash-based color per group) and an event context line showing last event name, type icon, and relative timestamp below balance.

## What Was Built

### CARD-01: Accent Strip

Every GroupCard now renders a 4dp colored vertical strip on its left edge. The color is deterministic: `_accentColors[groupId.hashCode.abs() % 5]` selects from a 5-slot earthy palette:

- Slot 0: `#0D7B74` (primary teal)
- Slot 1: `#CC6B49` (terracotta)
- Slot 2: `#10B981` (success emerald)
- Slot 3: `#F59E0B` (warning amber)
- Slot 4: `#7C6E5A` (warm umber)

Implementation uses `IntrinsicHeight` wrapping a `Row` with `CrossAxisAlignment.stretch` so the 4dp `Container` fills the full card height regardless of content. `Clip.hardEdge` on the outer `Container` clips the strip corners to the card's 16dp border radius.

### CARD-02: Event Context Line

Below the balance, `_buildEventContextLine` watches `groupEventsProvider(group.id)`:

- **Has events**: shows `[EventType icon] EventName — X ago` in `bodySmall`/`textSecondary`
- **Empty/loading/error**: shows `No events yet` in `bodySmall`/`textMuted`

The em-dash separator (`\u2014`) and `timeago.format()` produce clean relative timestamps.

## Commits

| Task | Commit | Description |
|------|--------|-------------|
| 1 (RED) | a21fcb7 | test(24-01): add failing tests for GroupCard accent strip and event context line |
| 2 (GREEN) | 978cb32 | feat(24-01): implement GroupCard accent strip and event context line |

## Test Results

- **Before**: 763 existing tests passing
- **After**: 789 tests passing (26 new tests added)
- **New tests**: Tests A, C, D, E, F in `home_screen_dashboard_test.dart`; Tests B + context line + no-events in `home_screen_groups_test.dart`

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Test assertions written for RED then fixed for GREEN**
- **Found during:** Task 2 GREEN phase
- **Issue:** Tests C, D, E, F in dashboard test and context/no-events tests in groups test were written asserting `findsNothing` (correct for RED). After implementation they needed to assert `findsOneWidget`/`findsOneWidget`.
- **Fix:** Updated assertions to match actual implementation behavior.
- **Files modified:** `home_screen_dashboard_test.dart`, `home_screen_groups_test.dart`
- **Commit:** 978cb32

**2. [Rule 1 - Bug] Riverpod override ordering in groups tests**
- **Found during:** Task 2 GREEN phase verification
- **Issue:** Groups tests spread `_dashboardOverrides()` after test-specific `groupEventsProvider` override, so the dashboard's empty-events override silently won (last override wins in Riverpod ProviderScope).
- **Fix:** Moved `..._dashboardOverrides()` before test-specific overrides so test values take precedence.
- **Files modified:** `home_screen_groups_test.dart`
- **Commit:** 978cb32

**3. [Rule 1 - Bug] Unused import warning**
- **Found during:** Task 2 `flutter analyze` run
- **Issue:** `event_model.dart` was imported in `group_card.dart` but not referenced (EventType used only via EventTypeConfig, not directly).
- **Fix:** Removed unused import.
- **Files modified:** `lib/features/groups/widgets/group_card.dart`
- **Commit:** 978cb32

## Known Stubs

None. GroupCard is fully wired to live `groupEventsProvider` data. No placeholder data or TODOs remain.

## Self-Check: PASSED

- `lib/features/groups/widgets/group_card.dart` — FOUND
- `.planning/phases/24-visual-density-polish/24-01-SUMMARY.md` — FOUND
- Commit `a21fcb7` (RED tests) — FOUND
- Commit `978cb32` (GREEN implementation) — FOUND
