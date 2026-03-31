---
phase: 19-navigation-restructuring
plan: "01"
subsystem: routing
tags: [go_router, navigation, routes, module_header, test_helpers]
dependency_graph:
  requires: []
  provides: [full-route-tree, slide-right-transition-helper, test-router-factory]
  affects: [app_router.dart, module_header.dart, test/helpers/test_router.dart]
tech_stack:
  added: []
  patterns: [nested GoRoute, CustomTransitionPage, context.pop() GoRouter extension]
key_files:
  created:
    - test/helpers/test_router.dart
  modified:
    - lib/core/router/app_router.dart
    - lib/shared/widgets/module_header.dart
decisions:
  - _slideRightTransition extracted as module-level function to eliminate 8 inline lambda duplicates
  - Placeholder Scaffolds used for 15 new routes (Plan 02 will wire real screens)
  - context.pop() replaces Navigator.of(context).pop() in ModuleHeader for GoRouter stack compatibility
  - testRouter() uses builder: not pageBuilder: to avoid CustomTransitionPage overhead in tests
metrics:
  duration_seconds: 174
  completed_date: "2026-03-30T10:56:39Z"
  tasks_completed: 2
  tasks_total: 2
  files_modified: 3
---

# Phase 19 Plan 01: Router Expansion & ModuleHeader GoRouter Migration Summary

GoRouter expanded with full D-02+D-07 route tree (15 new subroutes under /group/:gid), slide-right transition helper extracted, :id renamed to :gid, ModuleHeader back button migrated to context.pop(), and shared testRouter() factory created for test files.

## Tasks Completed

| Task | Name | Commit | Files |
|------|------|--------|-------|
| 1 | Expand app_router.dart with full route tree, transition helper, :id->:gid rename | a416100 | lib/core/router/app_router.dart |
| 2 | Update ModuleHeader back button and create testRouter helper | 511f2ce | lib/shared/widgets/module_header.dart, test/helpers/test_router.dart |

## What Was Built

### lib/core/router/app_router.dart

- 23 total `AppRoutes` constants (8 existing + 15 new per D-02 + D-07)
- `_slideRightTransition` helper function replacing all inline `Offset(1,0)→zero` lambdas
- `/group/:gid` param renamed from `:id` — `pathParameters['gid']` in GroupDetailScreen and GroupSettingsScreen constructors
- Complete nested GoRoute tree:
  - `/group/:gid/settle-up` (group-level settle-up)
  - `/group/:gid/activity` (group activity feed)
  - `/group/:gid/create-event` (event type selector)
  - `/group/:gid/create-event/:type` (typed event creation)
  - `/group/:gid/event/:eid` (event hub)
  - `/group/:gid/event/:eid/ledger` (+ add, edit/:expId, settle-up)
  - `/group/:gid/event/:eid/gear`
  - `/group/:gid/event/:eid/logistics`
  - `/group/:gid/event/:eid/vault`
  - `/group/:gid/event/:eid/memories` (+ :memId)
  - `/group/:gid/event/:eid/activity`
- All new routes use placeholder Scaffolds; Plan 02 wires real screens

### lib/shared/widgets/module_header.dart

- `import 'package:go_router/go_router.dart'` added
- `_LightBackButton` and `_DarkBackButton` callbacks changed from `Navigator.of(context).pop()` to `context.pop()`

### test/helpers/test_router.dart (new)

- `testRouter()` factory function returning a GoRouter with stub Scaffold routes for the full D-02+D-07 tree
- Accepts `initialLocation` and `extraRoutes` params for test customization

## Deviations from Plan

None — plan executed exactly as written.

## Verification Results

- `flutter analyze` on all 6 modified/created files: no issues
- `flutter test test/features/home/`: 35 tests passed — :id→:gid rename did not affect interpolated context.push('/group/${group.id}') callers
- `grep -c 'static const String' lib/core/router/app_router.dart` → 23 (8 existing + 15 new)

## Self-Check: PASSED

Files confirmed present:
- lib/core/router/app_router.dart — FOUND
- lib/shared/widgets/module_header.dart — FOUND
- test/helpers/test_router.dart — FOUND

Commits confirmed:
- a416100 (Task 1 — router expansion)
- 511f2ce (Task 2 — ModuleHeader + testRouter)
