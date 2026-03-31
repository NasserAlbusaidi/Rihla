---
phase: 14-test-hardening
plan: 02
subsystem: testing
tags: [test-hardening, find-bykey, widget-tests, structural-assertions, semantic-keys]
dependency_graph:
  requires: ["14-01"]
  provides: ["14-03"]
  affects: [test/features/groups, test/features/events, test/features/logistics, lib/features/groups/keys, lib/features/events/keys, lib/features/logistics/keys]
tech_stack:
  added: []
  patterns: [find.byKey over find.text for structural widget assertions]
key_files:
  created: []
  modified:
    - lib/features/groups/keys/group_keys.dart
    - lib/features/events/keys/event_keys.dart
    - lib/features/logistics/keys/logistics_keys.dart
    - lib/features/groups/screens/group_detail_screen.dart
    - lib/features/groups/screens/group_settle_up_screen.dart
    - lib/features/groups/widgets/group_balance_hero.dart
    - lib/features/groups/widgets/group_settlement_summary.dart
    - lib/features/groups/screens/group_settings_screen.dart
    - lib/features/events/screens/create_event_screen.dart
    - lib/features/events/screens/event_type_picker_screen.dart
    - lib/features/logistics/screens/logistics_screen.dart
    - lib/features/logistics/widgets/subgroup_card.dart
    - test/features/groups/group_screens_test.dart
    - test/features/events/create_event_test.dart
    - test/features/events/event_module_list_test.dart
    - test/features/events/group_detail_events_test.dart
    - test/features/logistics_screen_mutations_test.dart
    - test/features/group_settle_up_screen_test.dart
    - test/unit/shared_widgets_test.dart
    - test/features/group_detail_screen_test.dart
decisions:
  - "shared_widgets_test had zero structural find.text() calls — all assertions were content (filter chip labels, button labels, fixture text) — no changes needed"
  - "layout-order test in group_detail_screen_test converted getTopLeft(find.text(...)) to getTopLeft(find.byKey(...)) to maintain spatial assertion capability"
  - "GroupKeys.groupBalancesLabel added to group_balance_hero.dart for D-19 show/hide test"
  - "GroupKeys.recentActivitySection added to Recent Activity Text; GroupKeys.seeAllActivityButton added to See All TextButton"
metrics:
  duration: "~90 minutes (multi-session)"
  completed: "2026-03-28"
  tasks_completed: 2
  files_modified: 19
---

# Phase 14 Plan 02: Medium-Priority Test Migration Summary

Migrated 8 medium-priority test files (priority 5-12, ~115 structural calls) from `find.text()`/`find.byType()` structural assertions to `find.byKey()`. Continued the systematic conversion from Plan 01, enriching 3 key files with 22 new constants and adding `key:` parameters to 11 widget files.

## What Was Built

### Task 1: Priority 5-8 Test Files (~66 structural calls)

**File 5 — `test/features/groups/group_screens_test.dart`**
Converted 8 structural calls: `find.text('Invite Code')` → `find.byKey(GroupKeys.inviteCodeSection)`, section headers for Members & Balances, Events, Group Settings, Group Name, Currency, Invite Code settings tiles. Collapsed 2-text empty state checks into single `find.byKey(GroupKeys.noEventsEmpty)`.

**File 6 — `test/features/events/create_event_test.dart`**
Converted 18 structural calls: event type picker title, type card taps (parameterized `EventKeys.eventTypeCard('Trip')`), module toggle presence checks for all 5 modules, create event button tap.

**File 7 — `test/features/events/event_module_list_test.dart`**
Converted 14 structural calls: all module card presence/absence checks (`EventKeys.ledgerCard`, `gearCard`, `logisticsCard`, `vaultCard`, `memoriesCard`). Nearly all calls in this file were structural.

**File 8 — `test/features/events/group_detail_events_test.dart`**
Converted 5 structural calls: events count chip, empty state, events section header. Collapsed 2-text empty state into single `find.byKey(GroupKeys.noEventsEmpty)`.

### Task 2: Priority 9-12 Test Files (~46 structural calls)

**File 9 — `test/features/logistics_screen_mutations_test.dart`**
Converted 6 structural calls: REMOVE button, DELETE button, NEW GROUP title, CREATE GROUP button across main tests and all 3 error-handling tests.

**File 10 — `test/features/group_settle_up_screen_test.dart`**
Converted 8 structural calls: settle up title, GROUP TOTAL PENDING label, all-settled message, Record Settlement button, Mark as Paid button, Not Now button.

**File 11 — `test/unit/shared_widgets_test.dart`**
Zero structural calls found — all `find.text()` calls were content assertions (filter chip labels, button labels, fixture widget text). No changes needed.

**File 12 — `test/features/group_detail_screen_test.dart`**
Converted 8 structural calls: GROUP BALANCES label, Members & Balances section, Recent Activity section, See all activity button, Events section, Invite Code section (including layout-order position test).

## Keys Added

### `lib/features/groups/keys/group_keys.dart` (10 new constants)
- `settingsGroupNameTile`, `settingsCurrencyTile`, `settingsInviteCodeTile` — group settings tiles
- `recentActivitySection`, `eventsCountChip` — detail screen sections
- `settleUpTitle`, `settleUpSummaryCard`, `settleUpGroupTotalLabel`, `settleUpAllSettledMessage`, `settleUpRecordSheetTitle` — settle up screen
- `groupBalancesLabel` — GroupBalanceHero label
- `seeAllActivityButton` — See All Activity TextButton

### `lib/features/events/keys/event_keys.dart` (13 new constants)
- `eventTypePickerTitle`, `eventTypeTripOption/CampingOption/DayOutOption/DinnerOption/CustomOption` — type picker
- `createEventButton`, `modulesSection` — create event form
- `moduleLedgerToggle`, `moduleGearToggle`, `moduleLogisticsToggle`, `moduleVaultToggle`, `moduleMemoriesToggle` — module toggles
- `eventTypeCard(String label)` — parameterized card key

### `lib/features/logistics/keys/logistics_keys.dart` (1 new constant)
- `createGroupTitle` — NEW GROUP dialog title

## Verification

Full test suite: **624 tests, all passed** after both tasks.

## Deviations from Plan

None — plan executed exactly as written. `shared_widgets_test.dart` had zero structural assertions to convert, which was a valid outcome (noted in research estimates as low-priority).

## Known Stubs

None. All migrated assertions are backed by real widget keys applied to real widgets.

## Self-Check: PASSED
