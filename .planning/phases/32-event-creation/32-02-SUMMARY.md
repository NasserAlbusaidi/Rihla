---
phase: 32-event-creation
plan: "02"
subsystem: events
tags: [ui, create-event, module-header, select-all, animations]
dependency_graph:
  requires: [32-00, 32-01]
  provides: [refreshed-create-event-screen]
  affects: [lib/features/events/screens/create_event_screen.dart]
tech_stack:
  added: []
  patterns: [dark-ModuleHeader, staggered-flutter_animate, GestureDetector-row-tap, Select-All-checkbox]
key_files:
  created: []
  modified:
    - lib/features/events/screens/create_event_screen.dart
    - test/features/events/create_event_test.dart
decisions:
  - "_ParticipantRow wrapped in GestureDetector for row-level tap (better UX + test compatibility)"
  - "ModuleHeader title and badge both show typeConfig.label — test assertions updated to findsAtLeastNWidgets(1)"
  - "tester.ensureVisible required before CreateEventButton tap in 800x600 test viewport"
metrics:
  duration: 418s
  completed: "2026-04-05"
  tasks_completed: 2
  files_modified: 2
---

# Phase 32 Plan 02: CreateEventScreen Refresh Summary

**One-liner:** Dark ModuleHeader replaces AppBar, event type badge uses type-specific config.color, Select All checkbox added with immutable set toggle, 3-level card stagger at 60/100/200/300ms.

## Tasks Completed

| Task | Description | Commit |
|------|-------------|--------|
| 1 | Replace AppBar with ModuleHeader, fix badge colors, add Select All, add stagger animations | 0810afe |
| 2 | Fix all create_event tests to GREEN (GestureDetector row tap, findsAtLeastNWidgets, ensureVisible) | 0961728 |

## What Was Built

### Task 1: CreateEventScreen Visual Refresh

**AppBar replaced with dark ModuleHeader:**
- Removed `appBar: AppBar(title: Text('New ${typeConfig.label} Event'))`
- Body restructured as `Column([ModuleHeader(useDarkTheme: true, title: typeConfig.label), Expanded(...)])`
- Back navigation handled by ModuleHeader's built-in `_DarkBackButton`

**Event type badge fixed:**
- Was: `AppColorTokens.light.moduleLedgerLight` background, `AppColorTokens.light.moduleLedger` icon/text (always teal)
- Now: `typeConfig.color.withValues(alpha: 0.12)` background, `typeConfig.color` icon/text (type-specific)
- Trip = primary teal, Camping = success green, Travel/Night Out = gray, Custom = warning amber

**Select All Checkbox added:**
- Positioned above member list with 'Select All' label
- Key: `EventKeys.selectAllButton`
- Value: `members.isNotEmpty && _selectedParticipantIds.length == members.length`
- Immutable set toggle: selects all → `Set.unmodifiable(allIds)`, deselects all → `Set.unmodifiable(<String>{})`

**Staggered entrance animations:**
- Event type badge: `.animate().fadeIn(delay: 60.ms).slideY(begin: 0.05)`
- Event Details card: `.animate().fadeIn(delay: 100.ms).slideY(begin: 0.1)`
- Participants card: `.animate().fadeIn(delay: 200.ms).slideY(begin: 0.1)`
- Modules card (custom only): `.animate().fadeIn(delay: 300.ms).slideY(begin: 0.1)`
- All guarded by `MediaQuery.of(context).disableAnimations`

### Task 2: Test Fixes

Three test issues discovered and fixed:

1. **Off-screen button tap** — `LoadingButton` at y=706 outside 800x600 test viewport. Added `tester.ensureVisible` before tap.

2. **Duplicate text 'Trip'/'Camping'** — ModuleHeader renders `typeConfig.label` as the title (white 28px), badge also renders it (teal/green 14px). Both are correct. Updated `findsOneWidget` → `findsAtLeastNWidgets(1)`.

3. **Row-level tap not working for Alice deselect** — `_ParticipantRow` had no GestureDetector on the row. Test used `tester.tap(find.text('Alice'))` which only hit the `Text` widget, not the `Checkbox`. Fixed by wrapping `SizedBox` in `GestureDetector(onTap: () => onToggle(!isSelected), behavior: HitTestBehavior.opaque)`.

## Verification

- `flutter analyze lib/features/events/screens/create_event_screen.dart` — zero issues
- `flutter test test/features/events/create_event_test.dart` — 14/14 pass
- `flutter test` (full suite) — 864 tests, 2 pre-existing navigation flakes (existed before these changes with 6 failures — unchanged navigation_test.dart tests that pass individually but flake in full-suite ordering)

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Row-level tap not working on _ParticipantRow**
- **Found during:** Task 2 test verification
- **Issue:** Test tapped `find.text('Alice')` but `_ParticipantRow` had no GestureDetector — text tap had no effect, so deselect didn't happen, making "Select All selects all" test fail
- **Fix:** Wrapped `SizedBox` in `GestureDetector(onTap: () => onToggle(!isSelected), behavior: HitTestBehavior.opaque)` — also improves real-world UX (tapping anywhere on the row toggles)
- **Files modified:** `lib/features/events/screens/create_event_screen.dart`
- **Commit:** 0961728

**2. [Rule 1 - Bug] Off-screen button in test viewport**
- **Found during:** Task 2 test verification
- **Issue:** `LoadingButton` at y=706 exceeds 800x600 test bounds; `tester.tap` warned and form validation never fired
- **Fix:** Added `await tester.ensureVisible(find.byKey(EventKeys.createEventButton))` before the tap
- **Files modified:** `test/features/events/create_event_test.dart`
- **Commit:** 0961728

**3. [Rule 1 - Bug] Test assertions too strict for new dual-label design**
- **Found during:** Task 2 test verification
- **Issue:** `find.text('Trip')` and `find.text('Camping')` now find 2 widgets each — ModuleHeader title + badge. Tests expected `findsOneWidget`
- **Fix:** Updated to `findsAtLeastNWidgets(1)` — the correct assertion since both occurrences are intentional
- **Files modified:** `test/features/events/create_event_test.dart`
- **Commit:** 0961728

## Known Stubs

None — all data flows through real providers overridden in tests.

## Self-Check: PASSED

- FOUND: `lib/features/events/screens/create_event_screen.dart`
- FOUND: `test/features/events/create_event_test.dart`
- FOUND: commit `0810afe` (feat: replace AppBar with ModuleHeader)
- FOUND: commit `0961728` (fix: make all create_event tests GREEN)
- 14/14 create_event tests passing
- Full suite: 864 tests, 2 pre-existing navigation flakes (confirmed pre-existing)
