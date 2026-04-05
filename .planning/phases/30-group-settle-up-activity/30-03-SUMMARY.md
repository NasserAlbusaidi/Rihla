---
phase: 30-group-settle-up-activity
plan: "03"
subsystem: groups-activity
tags: [activity, timeline, filter-chips, infinite-scroll, redesign]
dependency_graph:
  requires: ["30-00", "30-01"]
  provides: ["group-activity-screen-redesign", "activity-tile-redesign"]
  affects: ["group_detail_screen", "group_activity_screen", "group_activity_tile"]
tech_stack:
  added: []
  patterns: ["date-grouped-timeline", "client-side-filter", "infinite-scroll", "compact-tile-variant"]
key_files:
  created: []
  modified:
    - lib/features/groups/screens/group_activity_screen.dart
    - lib/features/groups/widgets/group_activity_tile.dart
    - lib/features/groups/screens/group_detail_screen.dart
    - lib/features/groups/keys/group_keys.dart
    - test/features/groups/group_activity_screen_test.dart
decisions:
  - "Compact tile variant uses Padding(8dp vertical) instead of card container for in-preview use"
  - "flutter_animate timers in last test fixed with pump(Duration) instead of pumpAndSettle"
  - "group_keys.dart duplicate declarations removed (Phase 30 keys appeared twice)"
metrics:
  duration: "4 minutes"
  completed: "2026-04-05T08:18:28Z"
  tasks: 2
  files: 5
---

# Phase 30 Plan 03: Activity Screen Redesign Summary

**One-liner:** GroupActivityScreen redesigned with ModuleHeader, date-grouped timeline, client-side filter chips (All/Settlements/Events/Members), infinite scroll, and rich card tiles replacing flat list with Load more button.

## What Was Built

### Task 1: Redesign GroupActivityTile + GroupActivityScreen + verify D-15 navigation

**GroupActivityTile (D-09):**
- Rewritten as a card-style rich tile with 48dp initials circle, actor name, description, relative timestamp, and semantic type icon
- `compact: bool` parameter added — `false` (default) renders full card with `cardSurface` background and `AppShadowTokens.standard.raised`; `true` renders bare Row without card container
- Icon mapping updated per UI-SPEC: `group_settlement` → `Iconsax.money_recive` (primary), others → textMuted
- All icons wrapped in `Semantics(label: ...)` for accessibility

**GroupActivityScreen (D-07, D-08, D-10, D-11):**
- `ModuleHeader(title: 'Activity', subtitle: groupName, useDarkTheme: true)` replaces custom header
- `groupDetailProvider` watched for subtitle (group name)
- Filter chip row (D-10): All / Settlements / Events / Members with `selectionFill` active state
- `_filteredActivities` getter applies client-side filtering without modifying `_activities` list
- `_groupByDate` and `_dateLabel` copied from `ActivityFeedScreen` pattern, using `.timestamp` (not `.createdAt`)
- `_DateSectionHeader` widget renders TODAY / YESTERDAY / MMM d labels
- `ScrollController` with `_onScroll` listener triggers next page at 200px from bottom
- "Load more" button removed entirely
- Empty states: no-activity (EmptyStateView) and filter-empty (EmptyStateView with filter name)

**GroupDetailScreen (D-15, D-16):**
- Activity preview tiles updated to `GroupActivityTile(activity: a, compact: true)` (D-16)
- D-15 CTA comments added to all 3 entry points: settle-up button, member balance tap, "See all" activity

**group_keys.dart (bug fix):**
- Removed duplicate Phase 30 key declarations (settle-up tab bar + activity filter keys appeared twice)

### Task 2: Update activity screen tests + unskip Wave 0 stubs

- Updated helper `_buildActivityScreen` to override `groupDetailProvider` for subtitle
- Added `_seedActivities` helper and fixture data (`_todayActivity`, `_yesterdayActivity`, `_memberActivity`)
- Unskipped all 5 Phase 30 stub tests
- Added 2 new tests: "All filter shows all activities" and "empty filter state shows no-results message"
- 12 tests total, all passing

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] group_keys.dart duplicate key declarations**
- **Found during:** Task 1 initial analysis
- **Issue:** Phase 30 settle-up tab bar keys and activity filter keys were declared twice in `group_keys.dart` — once inline (lines 62-78) and once again at the bottom of the file (lines 122-136)
- **Fix:** Removed the duplicate block at the bottom of the file
- **Files modified:** `lib/features/groups/keys/group_keys.dart`
- **Commit:** 60f940c

**2. [Rule 3 - Blocking] flutter_animate pending timer in last test**
- **Found during:** Task 2 test run
- **Issue:** `pumpAndSettle` leaves pending timers when flutter_animate animations are in progress, causing test failure with "A Timer is still pending even after the widget tree was disposed"
- **Fix:** Changed last test to use `pump(Duration)` instead of `pumpAndSettle` to advance time without waiting for all timers
- **Files modified:** `test/features/groups/group_activity_screen_test.dart`
- **Commit:** 1a6571e

## Pre-existing Issues (Out of Scope)

`lib/features/groups/screens/group_settle_up_screen.dart` has 2 compile errors (`showDivider` named parameter undefined, `GroupSettlementGroupCard` undefined). These are from Plan 02 (parallel wave) and are pre-existing before Plan 03 started. Deferred to Plan 02 resolution.

## Self-Check: PASSED

- `lib/features/groups/screens/group_activity_screen.dart` — exists, contains ModuleHeader, _scrollController.addListener, _activeFilter, _groupByDate, _dateLabel, _DateSectionHeader, Settlements/Events/Members filter labels
- `lib/features/groups/widgets/group_activity_tile.dart` — exists, contains Semantics(label:, Iconsax.money_recive, borderRadius, final bool compact
- `lib/features/groups/screens/group_detail_screen.dart` — exists, contains compact: true, 3x D-15 CTAs
- `test/features/groups/group_activity_screen_test.dart` — 12 tests, all pass
- Commits verified: 60f940c (Task 1), 1a6571e (Task 2)
