---
phase: 19-navigation-restructuring
plan: "02"
subsystem: navigation
tags: [gorouter, navigation, d14-migration, string-ids, screen-constructors]
dependency_graph:
  requires:
    - "19-01: router expansion with full route tree and placeholder Scaffolds"
  provides:
    - "All 9 event/group screen constructors migrated to string IDs (D-14)"
    - "All 20 imperative Navigator.push calls replaced with context.push/context.go"
    - "Real screen constructors wired into all Plan 01 router placeholders (13 of 15)"
    - "EventCommandCenter, LedgerScreen, GearScreen, LogisticsScreen, VaultScreen, MemoriesScreen — now GoRouter-accessible"
    - "Event-level SettleUpScreen is a GoRouter route at /group/:gid/event/:eid/ledger/settle-up (D-07)"
    - "CreateEventScreen success uses context.go to replace creation stack (D-06)"
  affects:
    - "19-03: clean up page_transitions.dart, EditExpenseSheet -> GoRouter route, ActivityFeedScreen migration"
tech_stack:
  added: []
  patterns:
    - "D-08: path params + eventDetailProvider/groupDetailProvider lookup inside each screen"
    - "D-11: in-screen EmptyStateView not-found state when provider returns null"
    - "D-14: big-bang constructor migration from Event/Group objects to String groupId/eventId"
    - "D-06: context.go on event creation success to replace navigation stack"
    - "D-07: SettleUpScreen promoted to full GoRouter route"
    - "RESEARCH Pitfall 2: context.go replaces Navigator.pop/pop/push"
    - "Query param pattern: /group/:gid/settle-up?memberId=X for preSelectedMemberId"
key_files:
  created: []
  modified:
    - lib/features/events/screens/event_command_center.dart
    - lib/features/events/widgets/event_module_list.dart
    - lib/features/ledger/screens/ledger_screen.dart
    - lib/features/ledger/screens/settle_up_screen.dart
    - lib/features/gear/screens/gear_screen.dart
    - lib/features/logistics/screens/logistics_screen.dart
    - lib/features/vault/screens/vault_screen.dart
    - lib/features/memories/screens/memories_screen.dart
    - lib/features/groups/screens/group_settle_up_screen.dart
    - lib/features/groups/screens/group_detail_screen.dart
    - lib/features/events/screens/event_type_picker_screen.dart
    - lib/features/events/screens/create_event_screen.dart
    - lib/core/router/app_router.dart
decisions:
  - "LogisticsScreen threads Event object through helper methods (not a string ID lookup per call) because eventLogisticsParticipantsProvider requires an Event object — the Event is loaded once via eventDetailProvider in build() and passed down"
  - "GroupSettleUpScreen threads Group through helper methods (buildContent, buildSettlementGroup, showSettlementConfirmation, recordSettlement) to avoid repeated provider reads inside callbacks"
  - "ActivityFeedScreen migration deferred to Plan 03 — it still takes Event/Group objects and the event/activity route stays as placeholder"
  - "edit/:expId route stays as placeholder — EditExpenseSheet -> GoRouter route is Plan 03 scope"
  - "MemoriesScreen _showFullScreen preserved as Navigator.push (opaque:false PageRouteBuilder) — it is an overlay lightbox, not navigation"
  - "preSelectedMemberId passed via query param (?memberId=X) rather than path segment — avoids URL ambiguity"
metrics:
  duration_minutes: 65
  tasks_completed: 3
  tasks_total: 3
  files_modified: 13
  completed_date: "2026-03-30"
---

# Phase 19 Plan 02: D-14 Big Bang Constructor Migration and Router Wiring Summary

All 9 screen constructors migrated from full Event/Group objects to string IDs. All 20 imperative Navigator.push calls replaced with context.push/context.go. Plan 01 placeholder Scaffolds replaced with real screen constructors in the GoRouter route tree.

## What Was Built

**Task 1: Event-scoped screen constructors (EventCommandCenter, EventModuleList, LedgerScreen, SettleUpScreen)**

- `EventCommandCenter`: `final Event event; final Group group;` → `final String groupId; final String eventId;`. Now watches `eventDetailProvider` + `groupDetailProvider` internally. FAB and EventExpenseHero onTap both use `context.push`. EventModuleList receives `EventModules? modules` from the provider-loaded event.
- `EventModuleList`: `final Event event; final Group group; final EventRef eventRef;` → `final String groupId; final String eventId; final EventModules? modules;`. Five `_open*` methods all use `context.push`. Removed all screen imports.
- `LedgerScreen`: String ID constructor. `_openSettleUp` uses `context.push` to the GoRouter route (D-07). `_addExpense` uses `context.push`. `_editExpense` stays as `showModalBottomSheet` (Plan 03).
- `SettleUpScreen`: Promoted to full GoRouter route at `/group/:gid/event/:eid/ledger/settle-up`. Back button uses `context.pop()`.

**Task 2: Remaining screens (Gear, Logistics, Vault, Memories, GroupSettleUp)**

- `GearScreen`, `VaultScreen`, `MemoriesScreen`: String ID constructors with D-11 not-found states. `MemoriesScreen._showFullScreen` preserved as `Navigator.push(PageRouteBuilder(opaque: false))` — the only permitted Navigator.push in the codebase.
- `LogisticsScreen`: String ID constructor. Event object threaded through `_buildTabContentWithEvent(Event event)` and `_buildGroupList(Event event, ...)` because `eventLogisticsParticipantsProvider` requires an Event object.
- `GroupSettleUpScreen`: `final Group group;` removed. Watches `groupDetailProvider`. Group object threaded through all helper methods.

**Task 3: GroupDetailScreen, EventTypePickerScreen, CreateEventScreen, and router wiring**

- `GroupDetailScreen`: 7 Navigator.push → context.push. `_navigateToEventLedger` simplified to a single `context.push` call (no more event lookup needed). Removed imports for page_transitions, event_command_center, event_type_picker_screen, ledger_screen, group_settings_screen, group_settle_up_screen, group_activity_screen.
- `EventTypePickerScreen`: Navigator.push → `context.push('/group/$groupId/create-event/${config.type.value}')`. CloseButton → `context.pop()`. Removed page_transitions and create_event_screen imports.
- `CreateEventScreen`: pop/pop/push success sequence → `context.go('/group/${widget.groupId}/event/${event.id}')` per D-06/RESEARCH Pitfall 2.
- `app_router.dart`: 13 of 15 placeholder Scaffolds replaced with real screen constructors. 2 kept as placeholders (edit/:expId and event/activity — Plan 03 scope).

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 2 - Missing import cleanup] Removed unused `Event` model import from group_detail_screen.dart**
- **Found during:** Task 3
- **Issue:** After simplifying `_navigateToEventLedger` to a single `context.push` call, `event_model.dart` import became unused. `flutter analyze` reported a warning.
- **Fix:** Removed `import '../../events/models/event_model.dart';` from group_detail_screen.dart.
- **Files modified:** lib/features/groups/screens/group_detail_screen.dart
- **Commit:** e54453a

## Auth Gates

None.

## Known Stubs

- `lib/core/router/app_router.dart`: `edit/:expId` route still shows placeholder Scaffold text `EditExpense:${state.pathParameters['expId']}` — EditExpenseSheet → GoRouter route conversion is Plan 03 scope.
- `lib/core/router/app_router.dart`: `event/:eid/activity` route still shows placeholder Scaffold text `EventActivity:${state.pathParameters['eid']}` — ActivityFeedScreen takes Event/Group objects and requires D-14 migration in Plan 03.

These stubs do not prevent this plan's goal from being achieved — all 9 screen constructors are migrated and all 20 imperative navigation calls are replaced.

## Commits

| Task | Commit | Description |
|------|--------|-------------|
| Task 1 | 1c04c0c | feat(19-02): migrate EventCommandCenter, EventModuleList, LedgerScreen, SettleUpScreen to string IDs |
| Task 2 | 92ebb3f | feat(19-02): migrate GearScreen, LogisticsScreen, VaultScreen, MemoriesScreen, GroupSettleUpScreen to string IDs |
| Task 3 | e54453a | feat(19-02): replace Navigator.push calls and wire router with real screen constructors |

## Self-Check: PASSED

- [x] Task 1 commit `1c04c0c` exists: confirmed
- [x] Task 2 commit `92ebb3f` exists: confirmed
- [x] Task 3 commit `e54453a` exists: confirmed
- [x] `flutter analyze lib/features/groups/screens/group_detail_screen.dart lib/features/events/screens/event_type_picker_screen.dart lib/features/events/screens/create_event_screen.dart lib/core/router/app_router.dart` → No issues found
- [x] `grep -rn 'Navigator.of(context).push' lib/features/events/ lib/features/groups/screens/group_detail_screen.dart lib/features/ledger/screens/ledger_screen.dart lib/features/gear/ lib/features/logistics/ lib/features/vault/` → empty (no matches)
- [x] `grep -rn 'AppPageRoute' lib/ --include="*.dart" | grep -v 'page_transitions.dart'` → only a comment in app_router.dart
