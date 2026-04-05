---
phase: 32-event-creation
plan: "01"
subsystem: events/screens
tags: [ui, event-creation, module-header, wcag, animation]
dependency_graph:
  requires: [32-00]
  provides: [event-type-picker-dark-header, camping-wcag-color]
  affects:
    - lib/features/events/models/event_type_config.dart
    - lib/features/events/screens/event_type_picker_screen.dart
tech_stack:
  added: []
  patterns:
    - ConsumerWidget watching groupDetailProvider for dynamic subtitle
    - ModuleHeader(useDarkTheme: true) as AppBar replacement
    - SingleChildScrollView + Column (vs ListView) for fixed-count lists in test-safe way
key_files:
  created: []
  modified:
    - lib/features/events/models/event_type_config.dart
    - lib/features/events/screens/event_type_picker_screen.dart
decisions:
  - "SingleChildScrollView + Column used instead of ListView.separated to ensure all 5 fixed cards remain in widget tree during tests — plan specified ListView.separated but 5 items is a constant-count list"
  - "groupDetailProvider valueOrNull returns null in tests without override — subtitle rendered as null (hidden), not empty string — graceful fallback"
metrics:
  duration: "~8 minutes"
  completed: "2026-04-05T12:00:00Z"
  tasks_completed: 2
  files_modified: 2
---

# Phase 32 Plan 01: EventTypePickerScreen Visual Refresh Summary

**One-liner:** Refreshed EventTypePickerScreen with dark ModuleHeader + group name subtitle, fixed camping color to successText (#047857) for WCAG 4.56:1 compliance, and updated stagger animation to 80ms delay per card.

## What Was Done

### Task 1: Fix EventTypeConfig camping color (commit: eac9362)

Changed camping `EventTypeConfig` color from `Color(0xFF10B981)` (AppColorTokens.light.success) to `Color(0xFF047857)` (AppColorTokens.light.successText). The new value achieves WCAG 4.56:1 contrast ratio on white, making the camping icon accessible. Also updated the class-level doc comment to reflect accurate color assignments for all 5 event types.

All 39 `event_model_test.dart` tests pass including the camping color RED test from Plan 00.

### Task 2: Refresh EventTypePickerScreen (commit: b478777)

Rewrote `EventTypePickerScreen`:
- Converted `StatelessWidget` to `ConsumerWidget` with `WidgetRef ref` in `build`
- Added import for `flutter_riverpod` and `group_provider.dart`
- Watches `groupDetailProvider(groupId).valueOrNull?.name ?? ''` for the subtitle
- Replaced `appBar: AppBar(title: Text('Choose Event Type', key: EventKeys.eventTypePickerTitle))` with `ModuleHeader(useDarkTheme: true, title: 'New Event', subtitle: groupName.isEmpty ? null : groupName)`
- Removed the `appBar:` parameter from `Scaffold` entirely
- Updated stagger animation delay from `(40 * index).ms` to `(80 * index).ms` (both fadeIn and slideY)
- `_ModuleChip` and `_enabledModuleNames` unchanged

All 14 `create_event_test.dart` tests pass including all 4 `EventTypePickerScreen` tests.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Used SingleChildScrollView + Column instead of ListView.separated**

- **Found during:** Task 2 verification
- **Issue:** `ListView.separated` with lazy rendering caused the last cards ("Custom") to not be built when the dark `ModuleHeader` reduced available viewport height from ~744dp (AppBar) to ~658dp. The 5 cards with module chip wraps exceeded the visible area, so `find.text('Custom')` found 0 widgets.
- **Fix:** Replaced `ListView.separated` inside `Expanded` with `SingleChildScrollView` + `Column` using `List.generate`. This ensures all 5 fixed cards are always in the widget tree, regardless of viewport height.
- **Files modified:** `lib/features/events/screens/event_type_picker_screen.dart`
- **Commit:** b478777

## Known Stubs

None. All data sources are wired — `groupDetailProvider` provides the group name; `EventTypeConfig.allTypes` provides the 5 type cards. Both are real implementations.

## Self-Check: PASSED

- [x] `lib/features/events/models/event_type_config.dart` exists with `Color(0xFF047857)` for camping
- [x] `lib/features/events/screens/event_type_picker_screen.dart` exists as ConsumerWidget with ModuleHeader
- [x] Commit eac9362 exists: `fix(32-01): update camping color to successText (#047857) for WCAG compliance`
- [x] Commit b478777 exists: `feat(32-01): refresh EventTypePickerScreen with dark ModuleHeader and 80ms stagger`
- [x] All 53 tests pass (39 event_model_test + 14 create_event_test)
- [x] flutter analyze: zero errors on both modified files
