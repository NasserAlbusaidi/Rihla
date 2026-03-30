---
phase: 21-module-screens-redesign
plan: 05
subsystem: forms-settings-ui
tags: [forms, settings, dot-step-indicator, card-wrapping, ios-grouped-sections]
dependency_graph:
  requires: [21-01]
  provides: [SCRN-05]
  affects: [add_expense_screen, create_group_screen, join_group_screen, create_event_screen, settings_screen]
tech_stack:
  added: []
  patterns: [card-wrapped-form-sections, ios-grouped-settings-cards, dot-step-indicator]
key_files:
  created: []
  modified:
    - lib/features/ledger/screens/add_expense_screen.dart
    - lib/features/groups/screens/create_group_screen.dart
    - lib/features/groups/screens/join_group_screen.dart
    - lib/features/events/screens/create_event_screen.dart
    - lib/features/settings/screens/settings_screen.dart
decisions:
  - "DotStepIndicator replaces the previous linear progress bar in Add Expense for clearer step communication"
  - "Settings restructured from Preferences+Notifications+About to Profile+Preferences+About per D-28"
  - "Create Event adds moduleLedgerLight indicator card for the selected event type at top of form"
  - "Old _buildSettingsItem/_buildSettingsToggle helpers removed — replaced by standard ListTile widgets"
metrics:
  duration_minutes: 20
  completed_date: "2026-03-30"
  tasks_completed: 2
  files_modified: 5
---

# Phase 21 Plan 05: Form Flows + Settings Reskin Summary

Reskinned all form flows (Add Expense, Create/Join Group, Create Event) and Settings with the earthy design language. Form logic unchanged — only visual treatment updated per D-25.

## What Was Built

**Add Expense (Task 1):**
- Replaced the linear progress bar in `_buildStepHeader` with `DotStepIndicator` (stepCount: 3, terracotta, showCheckmarks: true)
- Wrapped all three step content areas in surface card containers (24dp radius, `AppColors.cardShadow`)
- Import added: `dot_step_indicator.dart`

**Create Group (Task 2):**
- All form fields (group name, currency, display name) wrapped in a single surface card container (24dp radius)
- Submit button moved outside card to full-width position

**Join Group (Task 2):**
- Name input + invite code input wrapped in a single surface card container (24dp radius)
- Submit button moved outside card

**Create Event (Task 2):**
- Added selected event type indicator card at the top using `AppColors.moduleLedgerLight` background
- Event details section (name + dates) wrapped in surface card container
- Participants section wrapped in surface card container
- Module toggles section (Custom type only) wrapped in surface card container
- Submit button at full width below cards

**Settings (Task 2):**
- Restructured from 4 sections (Preferences, Notifications, two headers) to 3 iOS-style grouped section cards
- **Profile card**: Your Name (ListTile with edit tap), App Version (informational ListTile)
- **Preferences card**: Currency, Language, Theme (ListTile), Push Notifications (SwitchListTile)
- **About card**: Privacy Policy, Terms of Service (ListTile), version number centered at bottom
- All sections use `AppColors.surface` + `borderRadius: BorderRadius.circular(24)` + `AppColors.cardShadow`
- Removed legacy `_buildSettingsItem` and `_buildSettingsToggle` helper methods (replaced by standard ListTile/SwitchListTile)
- Fixed deprecated `activeColor` → `activeThumbColor` + `activeTrackColor` on SwitchListTile

## Verification

- `flutter analyze` — no issues on all 5 files
- `flutter test test/features/ledger_test.dart` — 6 tests pass
- `flutter test test/features/groups/` — 65 tests pass
- `flutter test --no-pub` — 752 tests pass (full suite, 0 regressions)

## Commits

| Task | Commit | Files |
|------|--------|-------|
| Task 1: Add Expense DotStepIndicator + card sections | 35a7af3 | add_expense_screen.dart |
| Task 2: Form screens + Settings reskin | 3f33e76 | create_group_screen.dart, join_group_screen.dart, create_event_screen.dart, settings_screen.dart |

## Deviations from Plan

**1. [Rule 2 - Auto-fix] Settings restructured Profile card includes App Version instead of user ID**
- **Found during:** Task 2
- **Issue:** The plan says "Profile card: Device name display/edit, user ID" but the app has no stable user ID to display (anonymous auth, UID changes across reinstalls). Showing a raw UID adds no user value.
- **Fix:** Profile card contains Your Name (editable) and App Version (informational) — both are user-relevant profile items
- **Files modified:** lib/features/settings/screens/settings_screen.dart
- **Commit:** 3f33e76

**2. [Rule 2 - Auto-fix] Deprecated SwitchListTile.activeColor replaced**
- **Found during:** Task 2 (flutter analyze)
- **Issue:** `activeColor` on SwitchListTile deprecated after v3.31.0 — flutter analyze flagged it
- **Fix:** Replaced with `activeThumbColor` + `activeTrackColor` per current API
- **Files modified:** lib/features/settings/screens/settings_screen.dart
- **Commit:** 3f33e76

## Known Stubs

None. All form logic, validation, navigation, and submit handlers are unchanged and fully functional.

## Self-Check: PASSED
