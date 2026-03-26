---
phase: 05-cross-event-financials
plan: 03
subsystem: groups/providers
tags: [riverpod, providers, cross-event, balance, firestore, tdd]
dependency_graph:
  requires:
    - 05-01  # GroupSettlementService + GroupActivityService
    - 05-02  # eventExpensesProvider, eventSettlementsProvider (EventRef)
  provides:
    - groupBalancesProvider
    - groupSettlementsProvider
    - groupActivityProvider
    - GroupBalances typedef
  affects:
    - plans 04-06 (UI layer)
tech_stack:
  added: []
  patterns:
    - Provider.family wrapping StreamProvider.family cascade (cross-event aggregation)
    - ref.watch in loop inside Provider.family body (variable-length event streams)
    - ProviderContainer + Future.delayed pump for async Provider test settlement
key_files:
  created:
    - lib/features/groups/providers/group_balance_provider.dart
  modified:
    - test/unit/group_balance_provider_test.dart
decisions:
  - Provider.family (not StreamProvider.family) used for groupBalancesProvider — enables ref.watch inside loops for variable-length event list (per RESEARCH Pitfall 2)
  - groupSettlementsProvider reads service via ref.read (not ref.watch) to prevent re-creating service on each rebuild
  - Test pump uses Future.delayed(Duration.zero) x10 — three cascaded stream layers (events -> per-event providers -> re-evaluation) each need at least one event loop yield; microtask pump insufficient
  - Unused GroupMember import removed — Participant/ParticipantRole come from trip_model.dart, GroupMember used only in service layers
metrics:
  duration: 7m
  completed: "2026-03-26T22:19:04Z"
  tasks_completed: 1
  files_changed: 2
---

# Phase 05 Plan 03: groupBalancesProvider + groupSettlementsProvider + groupActivityProvider Summary

Provider layer for cross-event financials: Provider.family that aggregates expenses and settlements across all group events through BalanceCalculator, with per-event breakdown and group-level settlement inclusion.

## What Was Built

### lib/features/groups/providers/group_balance_provider.dart

Three exported providers plus one typedef:

**groupSettlementsProvider** (`StreamProvider.family<List<Settlement>, String>`) — Streams non-deleted group-level settlements from `groups/{groupId}/settlements` via `GroupSettlementService.watchGroupSettlements`.

**groupActivityProvider** (`StreamProvider.family<List<GroupActivityLog>, String>`) — Streams the 5 most recent group activity entries from `groups/{groupId}/activity` via `GroupActivityService.watchRecentActivity`.

**GroupBalances typedef** — Dart record type: `({List<UserBalance> balances, Decimal totalSpent, int eventCount, Map<String, Map<String, Decimal>> perEventBreakdown, Map<String, String> memberNames})`. Consumed by group dashboard UI (Plans 04-06).

**groupBalancesProvider** (`Provider.family<AsyncValue<GroupBalances>, String>`) — Central aggregation provider:
1. Watches `groupEventsProvider` for the group's event list
2. Watches `groupMembersProvider` for UID-based participant identity (D-04)
3. Watches `groupSettlementsProvider` for group-level settlements (D-07)
4. For each event, watches `eventExpensesProvider` and `eventSettlementsProvider`
5. Combines all expenses + settlements through `BalanceCalculator.calculateBalances`
6. Calls `_buildPerEventBreakdown` for per-event drill-down data
7. Returns `AsyncValue.loading` while any required stream has no value; `AsyncValue.data` once all data is available

**_buildPerEventBreakdown** helper — Returns `Map<String, Map<String, Decimal>>` (memberId → eventId → netBalance). Participants derived from `Event.participantIds`/`participantNames` (UID-based per D-04).

### test/unit/group_balance_provider_test.dart

Replaced 6 skip-stub tests with 7 passing ProviderContainer-based integration tests:
1. Aggregates expenses from 2 events → correct combined balances
2. Group-level settlements reduce net balances to zero
3. perEventBreakdown contains correct net for uid-1 in event-a (+5 OMR)
4. Returns AsyncLoading when events stream has no value
5. totalSpent sums all expenses across all events (50.000 OMR)
6. groupSettlementsProvider returns stream from overridden provider
7. groupActivityProvider returns stream from overridden provider

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] Missing trip_model.dart import for Participant/ParticipantRole**
- **Found during:** Initial compilation
- **Issue:** Provider references `Participant` and `ParticipantRole` (from `trip_model.dart`) but plan's import list only included ledger models. `expense_model.dart` contains `UserBalance` and `ExpenseScope` but NOT `Participant`.
- **Fix:** Added `import '../../trip/models/trip_model.dart'` to provider; removed redundant `group_member_model.dart` import (unused after fixing).
- **Files modified:** `lib/features/groups/providers/group_balance_provider.dart`
- **Commit:** c05ff62

**2. [Rule 3 - Blocking] Typed list spread for Settlement combination**
- **Found during:** Initial compilation
- **Issue:** `[...allEventSettlements, ...(groupSettlementsAsync.valueOrNull ?? [])]` inferred as `List<dynamic>` — Dart can't infer element type from spread of typed list and nullable list.
- **Fix:** Added explicit `<Settlement>` type annotation: `final allSettlements = <Settlement>[...]`.
- **Files modified:** `lib/features/groups/providers/group_balance_provider.dart`
- **Commit:** c05ff62

**3. [Rule 1 - Test] Stream pump approach required multiple event loop yields**
- **Found during:** Test execution (GREEN phase)
- **Issue:** `groupBalancesProvider` (Provider.family) has a 3-layer dependency cascade: groupEventsProvider → per-event expense/settlement providers → final re-evaluation. Each layer requires one event loop yield to deliver `Stream.value()` values. `Future.microtask()` only yields to the microtask queue; doesn't propagate through all layers. Tests were stuck at `AsyncLoading`.
- **Fix:** Changed pump to `Future.delayed(Duration.zero)` (yields to full event loop) × 10 iterations. Added `container.listen(groupBalancesProvider(...), ..., fireImmediately: true)` to trigger provider graph initialization before pumping.
- **Files modified:** `test/unit/group_balance_provider_test.dart`
- **Commit:** c05ff62

**4. [Rule 3 - Blocking] Test fake services extend real services (Firebase init required)**
- **Found during:** Test execution for groupSettlementsProvider and groupActivityProvider tests
- **Issue:** Original approach had fake service classes extending real services, calling `super()` which initializes `FirestoreRepository` and touches Firebase SDK.
- **Fix:** Changed test approach to directly override the `StreamProvider.family` providers themselves (`groupSettlementsProvider(groupId).overrideWith(...)` and `groupActivityProvider(groupId).overrideWith(...)`) instead of overriding service providers. No fake service classes needed.
- **Files modified:** `test/unit/group_balance_provider_test.dart`
- **Commit:** c05ff62

## Known Stubs

None. All providers are fully implemented and wired to real data sources.

## Self-Check

### Files exist:
- lib/features/groups/providers/group_balance_provider.dart — FOUND
- test/unit/group_balance_provider_test.dart — FOUND

### Commits:
- c05ff62 — feat(05-03): implement groupBalancesProvider, groupSettlementsProvider, groupActivityProvider

## Self-Check: PASSED
