---
phase: 04-firestore-repository-layer
plan: "05"
subsystem: database
tags: [bridge-teardown, eventref-migration, screen-migration, supabase-removal]

# Dependency graph
requires:
  - phase: 04-04
    provides: All 7 module services on Firestore, BalanceCacheRepository, no SyncService

provides:
  - EventModel without bridgeTripId or Supabase bridge fields
  - EventService without Supabase bridge code (D-17 removed)
  - All screens use EventRef-based providers instead of tripId-based providers
  - Dead home/trip widgets deleted (CommandCenter, expense_summary_hero, module_list, preparation_hero, trip_header, trip_recap_card)

affects:
  - Phase 05+ (clean Firestore-only codebase, no backward-compatibility shims)

# Tech tracking
tech-stack:
  added: []
  removed: []
  upgraded: []

dependencies:
  added: []
  removed: []

# Execution tracking
started: "2026-03-26T18:20:00Z"
completed: "2026-03-26T18:40:00Z"

tasks:
  total: 3
  completed: 3

commits:
  - hash: 91b6781
    message: "feat(04-05): remove D-17 bridge from EventModel and EventService"
  - hash: ecbdee0
    message: "feat(04-05): migrate all screens from tripId/Trip to EventRef/Event providers"
  - hash: 07b2d16
    message: "test(04-05): update tests to remove bridgeTripId and use Firestore providers"
  - hash: 603113d
    message: "fix(04-05): replace tripSubGroupsProvider with eventSubGroupsProvider in add/edit screens"
  - hash: fd1e6a3
    message: "chore(04-05): delete dead home/trip widget files"

key-files:
  created:
    - lib/features/events/screens/event_expense_hero.dart
  modified:
    - lib/features/events/models/event_model.dart
    - lib/features/events/services/event_service.dart
    - lib/features/events/screens/event_command_center.dart
    - lib/features/events/widgets/event_card.dart
    - lib/features/events/widgets/event_module_list.dart
    - lib/features/ledger/providers/expense_provider.dart
    - lib/features/ledger/providers/ledger_provider.dart
    - lib/features/ledger/screens/ledger_screen.dart
    - lib/features/ledger/screens/add_expense_screen.dart
    - lib/features/ledger/screens/settle_up_screen.dart
    - lib/features/ledger/screens/edit_expense_sheet.dart
    - lib/features/logistics/providers/sub_group_provider.dart
    - lib/features/logistics/screens/logistics_screen.dart
    - lib/features/gear/screens/gear_screen.dart
    - lib/features/activity/screens/activity_feed_screen.dart
    - lib/features/memories/screens/memories_screen.dart
    - lib/features/vault/screens/vault_screen.dart
  deleted:
    - lib/features/home/screens/command_center.dart
    - lib/features/home/widgets/expense_summary_hero.dart
    - lib/features/home/widgets/module_list.dart
    - lib/features/home/widgets/preparation_hero.dart
    - lib/features/home/widgets/trip_header.dart
    - lib/features/home/widgets/trip_recap_card.dart

## Self-Check: PASSED

deviations: []
---

# Plan 04-05 Summary: Bridge Teardown & Screen Migration

## What Was Built

Removed the Supabase bridge pattern (D-17) from the entire codebase and migrated all screens from tripId-based providers to EventRef-based Firestore providers.

### Task 1: Bridge Removal from EventModel/EventService
- Removed `bridgeTripId` getter and all Supabase bridge code from EventModel
- Stripped EventService of Supabase-related imports, bridge creation, and backward-compatibility shims
- EventService now speaks pure Firestore — no Supabase references remain in the data layer

### Task 2: Screen Provider Migration
- Migrated all module screens (Ledger, Gear, Logistics, Vault, Memories, Activity) from `tripExpensesProvider(tripId)` pattern to `eventExpensesProvider(eventRef)` pattern
- Updated EventCommandCenter to pass EventRef instead of Trip objects
- Created EventExpenseHero as a replacement for the trip-based expense summary
- Updated add/edit screens (AddExpenseScreen, EditExpenseSheet, SettleUpScreen) to accept EventRef

### Task 3: Cleanup & Dead Code Removal
- Deleted 6 dead home/trip widget files (CommandCenter, expense_summary_hero, module_list, preparation_hero, trip_header, trip_recap_card) — net -2,773 lines removed
- Updated all tests to match new EventRef-based APIs

## Net Impact
- **Lines removed:** ~2,773 (dead trip-era widgets and Supabase bridge code)
- **Lines added:** ~937 (EventRef-based replacements)
- **Net:** -1,836 lines — the codebase is significantly leaner
- **Supabase references in data layer:** Zero
