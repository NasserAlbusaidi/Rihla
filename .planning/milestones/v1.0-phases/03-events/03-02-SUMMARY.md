---
phase: 03-events
plan: 02
subsystem: ui
tags: [flutter, screens, events, event-creation, riverpod, widget-tests, form-validation]

# Dependency graph
requires:
  - phase: 03-events-00
    provides: EventTypeConfig.allTypes, EventType enum, EventModules.forType
  - phase: 03-events-01
    provides: eventServiceProvider, groupMembersProvider, groupDetailProvider, EventService.createEvent

provides:
  - EventTypePickerScreen (full-screen 5-card type picker)
  - CreateEventScreen (event creation form with participant picker and module toggles)

affects:
  - lib/features/events/services/event_service.dart (added optional modules parameter)

# Tech stack
tech_stack:
  added: []
  patterns:
    - flutter_animate staggered list entry (fadeIn + slideY, 40ms delay per item)
    - ConsumerStatefulWidget with WidgetsBinding.addPostFrameCallback for provider-initialized state
    - Immutable set updates (Set.unmodifiable) for participant selection
    - WidgetStateProperty for Checkbox/Switch theming (replaces deprecated activeColor)

# Key files
key_files:
  created:
    - lib/features/events/screens/event_type_picker_screen.dart
    - lib/features/events/screens/create_event_screen.dart
  modified:
    - lib/features/events/services/event_service.dart
    - test/features/events/create_event_test.dart

# Decisions
decisions:
  - Custom type module overrides pass through EventService.createEvent via optional modules parameter
  - Checkbox/Switch use WidgetStateProperty instead of deprecated activeColor (Flutter 3.31+)
  - Participant pre-population uses addPostFrameCallback to avoid setState-in-build

# Metrics
metrics:
  duration: 5 min
  completed: 2026-03-26
  tasks: 2
  files: 4
---

# Phase 03 Plan 02: Event Creation UI Flow Summary

**One-liner:** Two-step event creation flow — EventTypePickerScreen with 5 animated type cards and CreateEventScreen with participant picker, date fields, and Custom module toggles.

## What Was Built

### Task 1: EventTypePickerScreen

`lib/features/events/screens/event_type_picker_screen.dart`

Full-screen type picker presenting all 5 event types (Trip, Camping, Travel, Night/Day Out, Custom) as visual cards in a scrollable list. Each card displays:

- 48×48dp icon container with type-specific semantic color at 0.1 alpha
- Type name (titleMedium, 16sp w700)
- Short description (bodySmall, 12sp textMuted)
- Module chips (Chip, AppColors.surfaceLight, radiusSmall) showing only enabled modules
- Trailing arrow (Iconsax.arrow_right_3, 18dp, textMuted)
- 0.98 scale press animation (80ms easeInOut) via `_PressableCard`
- Staggered entry animation (fadeIn + slideY, 40ms delay per item, 400ms duration)
- `MediaQuery.disableAnimations` guard skips all animations when true
- `Semantics(label: '${type}: ${desc}. Modules: ${list}', button: true)` on each card

Tapping a card navigates to `CreateEventScreen(groupId, eventType)` via `AppPageRoute`.

### Task 2: CreateEventScreen

`lib/features/events/screens/create_event_screen.dart`

ConsumerStatefulWidget form implementing Step 2 of event creation:

**Fields in order:**
1. Event Name — TextFormField with hint "e.g. Summer camping trip"; validator returns "Event name can't be empty."
2. Dates — two OutlinedButton date pickers ("Start date" / "End date", labeled "(optional)")
3. Participants — checkbox list of group members, all pre-checked by default (D-04)
4. Modules — Switch toggle rows for each module, visible ONLY for Custom type (D-14)
5. LoadingButton — "Create Event" / "Creating…" loading state

**Participant selection:** Uses immutable `Set.unmodifiable` updates on every toggle. `_participantsInitialized` flag prevents re-population on subsequent builds.

**Custom modules:** Five toggle rows (Ledger, Gear, Logistics, Vault, Memories) with semantic colors. Ledger is on by default and fully toggleable — user can turn it off for Custom events (D-14). Non-Custom types show no toggles.

**Submit flow:**
- Validates name is not empty
- Checks at least one participant selected (SnackBar if not)
- Calls `EventService.createEvent` with all fields including optional `modules` for Custom type
- On success: pops both creation screens (picker + form) → user returns to GroupDetailScreen
- On error: SnackBar "Couldn't create event. Check your connection and try again." (5s)

### EventService fix (Rule 1 — Bug)

Added optional `modules` parameter to `EventService.createEvent`. Without this, Custom event module overrides were silently discarded — the service always called `EventModules.forType(type)` regardless of user selection.

### Tests

`test/features/events/create_event_test.dart` — 11 widget tests (0 skipped):

| Test | Result |
|------|--------|
| EventTypePickerScreen displays all 5 type cards | PASS |
| EventTypePickerScreen shows AppBar title | PASS |
| EventTypePickerScreen shows 5 type descriptions | PASS |
| Tapping type card navigates to CreateEventScreen | PASS |
| CreateEventScreen pre-checks all group members | PASS |
| CreateEventScreen shows AppBar title with event type name | PASS |
| CreateEventScreen shows module toggles for Custom type | PASS |
| Ledger toggle is enabled (onChanged not null) for Custom type | PASS |
| Does NOT show module toggles for non-Custom types | PASS |
| Validates event name is required | PASS |
| Shows correct event name field hint text | PASS |

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] EventService.createEvent did not accept custom modules override**
- **Found during:** Task 2 implementation
- **Issue:** `createEvent` internally computed `EventModules.forType(type)` and discarded any Custom-type module toggles set by the user
- **Fix:** Added optional `modules` parameter to `createEvent`; resolved modules = `modules ?? EventModules.forType(type)`. Updated bridge trip call to use `resolvedModules`
- **Files modified:** `lib/features/events/services/event_service.dart`
- **Commit:** 9c881ad

**2. [Rule 1 - Bug] Deprecated Flutter 3.31+ APIs**
- **Found during:** Task 2 analysis
- **Issue:** `Switch.activeColor` and `Checkbox.activeColor` deprecated after Flutter 3.31.0-2.0.pre
- **Fix:** Replaced with `WidgetStateProperty.resolveWith` for both `thumbColor`/`trackColor` (Switch) and `fillColor` (Checkbox)
- **Files modified:** `lib/features/events/screens/create_event_screen.dart`
- **Commit:** 9c881ad

## Known Stubs

None — all fields in both screens are wired to real providers and data. The `// TODO(Plan 03-04): Navigate to EventCommandCenter after creation` in `_submitForm` is intentional and documented per plan instruction: EventCommandCenter does not exist yet.

## Self-Check: PASSED

| Item | Status |
|------|--------|
| `lib/features/events/screens/event_type_picker_screen.dart` | FOUND |
| `lib/features/events/screens/create_event_screen.dart` | FOUND |
| `test/features/events/create_event_test.dart` | FOUND |
| `.planning/phases/03-events/03-02-SUMMARY.md` | FOUND |
| Commit 7ddffce (Task 1) | FOUND |
| Commit 9c881ad (Task 2) | FOUND |
| `flutter analyze lib/features/events/screens/` | No issues |
| `flutter test test/features/events/create_event_test.dart` | 11/11 PASS |
