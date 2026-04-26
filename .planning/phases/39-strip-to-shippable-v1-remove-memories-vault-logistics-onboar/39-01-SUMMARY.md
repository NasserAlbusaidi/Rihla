---
phase: 39
plan: 01
subsystem: router + events
tags: [strip, routes, EventModules]
requires: []
provides: [unreachable-cut-features, ledger-only-EventModules]
affects: [router, EventCommandCenter, CreateEventScreen, EventTypePicker]
tech-stack:
  added: []
  patterns: [delete-only refactor]
key-files:
  created: []
  modified:
    - lib/core/router/app_router.dart
    - lib/features/events/models/event_model.dart
    - lib/features/events/widgets/event_module_list.dart
    - lib/features/events/screens/create_event_screen.dart
    - lib/features/events/screens/event_type_picker_screen.dart
  deleted:
    - lib/features/events/widgets/event_modules_card.dart
    - test/features/events/widgets/event_modules_card_test.dart
decisions:
  - "EventModules retains a single ledger field; forType collapses to const EventModules(ledger: true) for every type"
  - "fromMap silently tolerates legacy keys on persisted Firestore docs — no migration needed for back-compat"
metrics:
  completed: 2026-04-26
---

# Phase 39 Plan 01: Strip Cut Features from Router and Event Modules — Summary

Wave 1 of the strip phase: made the six cut feature areas unreachable without deleting their source. App still compiles because directories still exist on disk; only entry points are gone.

## Deliverables

| Item | Result |
|------|--------|
| app_router.dart cut-feature route strip | ✓ done |
| onboardingCompleteProvider deleted | ✓ done |
| Splash redirect simplified to always go to /home | ✓ done |
| EventModules class reduced to ledger-only | ✓ done |
| event_module_list.dart shows Ledger + Activity only | ✓ done |
| event_modules_card.dart deleted (with caller cleanup) | ✓ done |

## Files Changed

### Modified

- **`lib/core/router/app_router.dart`**
  - Removed imports for `gear_screen`, `logistics_screen`, `memories_screen`, `onboarding_screen`, `vault_screen`
  - Removed `AppRoutes.onboarding`, `eventGear`, `eventLogistics`, `eventVault`, `eventMemories`, `eventMemoryDetail` constants
  - Deleted `onboardingCompleteProvider` FutureProvider
  - Replaced `redirect` callback: splash always returns `AppRoutes.home`
  - Deleted `/onboarding` GoRoute block
  - Deleted `/gear`, `/logistics`, `/vault`, `/memories` (and nested `/:memId`) GoRoute blocks under `event/:eid`
  - **Net:** 1 file changed, 4 insertions(+), 111 deletions(-)
  - Commit: `cf2de7f`

- **`lib/features/events/models/event_model.dart`**
  - `EventModules` reduced from 5 fields (ledger/gear/logistics/vault/memories) to single `ledger` field
  - `EventModules.forType(...)` collapsed to a single `const EventModules(ledger: true)` for every event type
  - `fromMap` silently tolerates legacy keys (only reads `ledger`)
  - `toMap`, `copyWith` pruned to single-field signatures
  - **Net:** 1 file changed, 13 insertions(+), 105 deletions(-)
  - Commit: `430106d`

- **`lib/features/events/widgets/event_module_list.dart`**
  - Removed imports for gear/logistics/vault provider/model files
  - Removed `showGear/showLogistics/showVault/showMemories` locals and their provider watches
  - Removed `_addGearCard`, `_addLogisticsCard`, `_addVaultCard`, `_addMemoriesCard` private methods
  - Card list now: Ledger (when enabled) + Activity (always)
  - Dropped unused `actionText` config field

- **`lib/features/events/screens/create_event_screen.dart`**
  - Removed `import '../widgets/event_modules_card.dart'`
  - Dropped `modulesCard` local for Custom event type
  - Dropped the conditional render block for the modules card
  - Updated docstring to drop bullet for `EventModulesCard`

- **`lib/features/events/screens/event_type_picker_screen.dart`**
  - `_enabledModuleNames` reduced to `[if (modules.ledger) 'Ledger']` (the four cut module checks failed compilation after EventModules pruning — Rule 3 auto-fix)

### Deleted

- `lib/features/events/widgets/event_modules_card.dart` (152 lines) — all four toggles were for cut features
- `test/features/events/widgets/event_modules_card_test.dart` — widget test for the deleted card

## Verification

```bash
$ grep -E "(import.*\b(memories|vault|logistics|onboarding|gear)\b|GoRoute\(.*\b(memories|vault|logistics|onboarding|gear)\b|AppRoutes\.(eventGear|eventLogistics|eventVault|eventMemories|onboarding))" lib/core/router/app_router.dart
# (no output — exit 1)

$ awk '/^class EventModules/,/^}/' lib/features/events/models/event_model.dart | grep -cE "\bgear\b|\blogistics\b|\bvault\b|\bmemories\b"
0

$ grep -rn "EventModulesCard\|event_modules_card" lib/ test/
# (no output)

$ flutter analyze lib/features/events/
# 2 issues — both pre-existing info-level lints in event_expense_hero.dart and event_service.dart (out of scope per plan)
```

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] Fixed `event_type_picker_screen._enabledModuleNames`**
- **Found during:** Task 3 verification
- **Issue:** After reducing `EventModules` in Task 2, `_enabledModuleNames` still referenced `modules.gear`, `modules.logistics`, `modules.vault`, `modules.memories` — undefined-getter errors blocked analyze
- **Fix:** Reduced to `[if (modules.ledger) 'Ledger']`
- **File:** `lib/features/events/screens/event_type_picker_screen.dart`
- **Commit:** `4a948bf` (bundled with Task 3 commit)

The plan listed this as a Wave 3 cleanup target, but it was load-bearing for Wave 1 to compile.

## Commits

- `cf2de7f` refactor(39-01): strip cut-feature routes and onboarding from app_router
- `430106d` refactor(39-01): reduce EventModules to ledger-only field
- `4a948bf` refactor(39-01): strip cut modules from event_module_list and delete event_modules_card

## Self-Check: PASSED

- [x] `lib/features/events/widgets/event_modules_card.dart` deleted (verified absent)
- [x] `test/features/events/widgets/event_modules_card_test.dart` deleted (verified absent)
- [x] `flutter analyze lib/core/router/ lib/features/events/` reports zero errors
- [x] All three task commits land on main: cf2de7f, 430106d, 4a948bf

## Handoff to Wave 2

Wave 2 (plan 39-02) physically deletes the five feature directories. App will produce many orphaned-import errors after that delete; those are catalogued in 39-02-SUMMARY.md as the input list for Wave 3.
