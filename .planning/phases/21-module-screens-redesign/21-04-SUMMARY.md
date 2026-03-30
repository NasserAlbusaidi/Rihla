---
phase: 21-module-screens-redesign
plan: 04
subsystem: memories-activity
tags: [ui, redesign, module-screens, photo-grid, date-grouped-timeline]
dependency_graph:
  requires: [21-01]
  provides: [MemoriesHeroCard, ActivityHeroCard, ActivityEntryCard, MemoriesScreen-redesign, ActivityFeedScreen-redesign]
  affects: [memories-screen, activity-feed-screen, app-router]
tech_stack:
  added: []
  patterns: [ModuleHeader-migration, GridView-3-column, date-grouped-timeline, deterministic-avatar-color]
key_files:
  created:
    - lib/features/memories/widgets/memories_hero_card.dart
    - lib/features/activity/widgets/activity_hero_card.dart
    - lib/features/activity/widgets/activity_entry_card.dart
  modified:
    - lib/features/memories/screens/memories_screen.dart
    - lib/features/activity/screens/activity_feed_screen.dart
    - lib/core/router/app_router.dart
decisions:
  - "ActivityFeedScreen migrated from Event/Group object params to string IDs (groupId/eventId) — aligns with D-14 pattern used throughout codebase"
  - "GridView.builder with crossAxisCount: 3 used directly (not StaggeredGrid Wrap) — ensures 8dp gap/radius acceptance criteria are met and matches plan spec"
  - "ActivityFeedScreen wired into router — stub removed, live screen now at /group/:gid/event/:eid/activity"
  - "logText used directly in ActivityEntryCard — ActivityLog already stores human-readable action descriptions, no action mapping needed"
metrics:
  duration: 8 minutes
  completed: 2026-03-31
  tasks_completed: 2
  tasks_total: 2
  files_modified: 6
---

# Phase 21 Plan 04: Memories + Activity Screen Redesign Summary

Memories and Activity screens redesigned. Memories migrates from a custom header to ModuleHeader and switches from the date-grouped MemoriesPhotoGrid widget to a flat 3-column GridView per D-24. Activity expands from a 79-line placeholder with `Event`/`Group` object constructor params to a full date-grouped timeline with string-ID-based construction — wired into the live router for the first time.

## What Was Built

### Task 1: Hero Cards + ActivityEntryCard

**MemoriesHeroCard** (`lib/features/memories/widgets/memories_hero_card.dart`):
- Photo count + date range (pre-formatted) in D-15 layout
- "MEMORIES" overline (12sp, w400, textMuted, letter-spacing 0.5)
- `$photoCount photos · $dateRange` display using RichText for mixed styles
- Full-width "Add Photo" ElevatedButton (teal, 52dp) — calls `onAddPhoto`

**ActivityHeroCard** (`lib/features/activity/widgets/activity_hero_card.dart`):
- Entry count + last update in D-16 layout
- "ACTIVITY" overline (same style as MemoriesHeroCard)
- No CTA button — Activity is read-only per D-16

**ActivityEntryCard** (`lib/features/activity/widgets/activity_entry_card.dart`):
- 36dp deterministic avatar circle using `Colors.primaries[actorName.hashCode.abs() % Colors.primaries.length]` — same pattern as Phase 18 ActivityRow
- Avatar background at 15% alpha, initial letter at full color
- `logText` displayed directly (ActivityLog already stores human-readable descriptions)
- Relative time via `timeago.format(log.createdAt)` — 12sp, textMuted

### Task 2: Screen Rewrites

**MemoriesScreen** (`lib/features/memories/screens/memories_screen.dart`):
- Custom `_buildHeader()` removed entirely — replaced by `ModuleHeader(useDarkTheme: true)`
- FAB removed — "Add Photo" CTA moved into MemoriesHeroCard
- Photo display: `GridView.builder` with `crossAxisCount: 3`, `crossAxisSpacing: 8`, `mainAxisSpacing: 8`, `BorderRadius.circular(8)` thumbnails
- Loading: `SkeletonLoader.photoGrid()` (added in Plan 01)
- Empty state: `EmptyStateView` with desert sand `accentGradient` (D-18 Memories earthy circle)
- `PageRouteBuilder(opaque: false)` full-screen viewer preserved

**ActivityFeedScreen** (`lib/features/activity/screens/activity_feed_screen.dart`):
- Migrated from `Event event, Group group` constructor to `String groupId, String eventId`
- `eventDetailProvider` used for event name in ModuleHeader subtitle
- Date-grouped timeline: `_groupByDate()` returns `Map<String, List<ActivityLog>>` keyed on "TODAY", "YESTERDAY", or "MMM d" format
- `FadeInList` wraps each date group's `ActivityEntryCard` list
- Empty state: caramel `accentGradient` (D-18 Activity earthy circle), no CTA (read-only)
- Loading: `SkeletonLoader.cardList()` generic skeleton

**app_router.dart**:
- `ActivityFeedScreen` import added
- `/group/:gid/event/:eid/activity` route: stub replaced with live `ActivityFeedScreen(groupId:, eventId:)`

## Decisions Made

1. **`GridView.builder` over `StaggeredGrid`** — The plan spec explicitly defines `GridView.builder` with `crossAxisCount: 3`. StaggeredGrid uses `Wrap` which doesn't support `crossAxisCount`. GridView.builder satisfies the layout spec and acceptance criteria.

2. **`logText` as action description** — The `ActivityLog` model stores human-readable `logText` strings already (e.g., "Ahmed added an expense for Fuel"). No action string mapping needed; using `logText` directly avoids duplicating the formatting logic that the service layer already handles.

3. **String-ID constructor on ActivityFeedScreen** — Consistent with the Phase 19 D-14 migration pattern. The router passes `gid`/`eid` path parameters. `eventDetailProvider` fetches the event name for the ModuleHeader subtitle.

4. **FadeInList per date group** — The plan specifies FadeInList for activity entries. Wrapping each group's entries in a separate FadeInList gives staggered entrance per group rather than one flat stagger for the whole list — more visually correct for date-grouped content.

## Deviations from Plan

### Auto-fixed Issues

None.

### Router Update (Rule 2 — Missing Critical Functionality)

The plan rewrites `ActivityFeedScreen` to use string IDs, but the router stub would have left the Activity screen unreachable via the real implementation. Updated `app_router.dart` to import and wire `ActivityFeedScreen` — required for the screen to be accessible. The plan implicitly expects this (the screen exists; users should be able to navigate to it).

## Test Results

- `flutter analyze lib/features/memories/ lib/features/activity/` — 4 info items, 0 errors (2 `prefer_const_constructors` infos in activity_feed_screen, 2 `use_super_parameters` in pre-existing service files)
- `flutter test --no-pub` — 749 pass, 3 fail
  - The 3 failures are pre-existing in `gear_screen_mutations_test.dart: shows snackbar error when addGearItem throws` — confirmed pre-existing via `git stash` verification; unrelated to this plan's changes

## Known Stubs

None — no placeholder data or hardcoded stubs in any file created or modified in this plan.

## Self-Check: PASSED
