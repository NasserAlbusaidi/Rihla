---
phase: 05-cross-event-financials
plan: "02"
subsystem: ledger/testing
tags:
  - tdd
  - balance-calculator
  - cross-event
  - unit-tests
dependency_graph:
  requires:
    - 05-00
  provides:
    - cross-event balance test coverage for FIN-01 and FIN-07
  affects:
    - 05-03 (groupBalancesProvider can now build on validated assumptions)
tech_stack:
  added: []
  patterns:
    - TDD cross-event test group added to existing unit test file
key_files:
  created: []
  modified:
    - test/unit/balance_calculations_test.dart
decisions:
  - "D-06 confirmed: BalanceCalculator handles combined multi-event inputs without production code changes — expense list is scope-agnostic, tripId on Expense is irrelevant to balance math"
  - "Test 3 uses tripId='group-g1' as sentinel for group-scoped settlement — balance calculation is unaffected by the sentinel value, only payerParticipantId/recipientParticipantId/amount matter"
  - "Optimal settlements test (Test 4) uses 4 participants across 3 events that collapse to a single debtor-creditor pair after netting — verifies greedy min-transactions algorithm works cross-event"
metrics:
  duration: "3 minutes"
  completed: "2026-03-26T22:05:00Z"
  tasks_completed: 1
  files_modified: 1
---

# Phase 05 Plan 02: Cross-Event Balance Calculation Tests Summary

**One-liner:** Six TDD tests confirming BalanceCalculator correctly handles combined multi-event expense lists — proving D-06 assumption before groupBalancesProvider is built.

## What Was Built

Extended `test/unit/balance_calculations_test.dart` with a new `group('Cross-event balance scenarios', ...)` containing 6 tests that validate `BalanceCalculator` behavior when fed combined expense/settlement lists from multiple events — exactly the usage pattern `groupBalancesProvider` will use.

## Tasks Completed

| Task | Description | Commit | Files |
|------|-------------|--------|-------|
| 1 | Add cross-event balance calculation tests (TDD) | 6d3dd35 | test/unit/balance_calculations_test.dart |

## Test Coverage Added

All 6 new tests pass GREEN without production code changes:

| Test | Scenario | Verified |
|------|----------|---------|
| Test 1 | Two events, same 3 participants — combined net balances | uid-1 net=0, uid-2 net=+30, uid-3 net=-30 |
| Test 2 | Participant absent from event C (custom scope) — balance limited to events A and B | uid-3 net=-20 (not -30) |
| Test 3 | Group-level settlement (sentinel tripId) zeroes cross-event debt | uid-2 and uid-3 both settled |
| Test 4 | calculateOptimalSettlements collapses 3-event debts to 1 transaction | 1 settlement, uid-4 → uid-1 for 20.000 |
| Test 5 | calculateTotalExpenses sums across different tripIds | 30+45.5+24.5 = 100.000 |
| Test 6 | Empty expenses from event A + non-empty from event B | Correct balances from event B only |

## Deviations from Plan

None — plan executed exactly as written.

**Key design confirmation:** The plan predicted "BalanceCalculator already handles combined lists correctly — these tests should pass without production code changes, confirming the assumption from D-06." All 6 tests passed GREEN on first run. D-06 is validated.

## Requirements Validated

- **FIN-01**: Per-event balance calculation remains correct when called per-event (no regressions) ✓
- **FIN-07**: Settlement optimization at group level produces minimum transactions for cross-event balances ✓

## Known Stubs

None. This plan adds tests only — no production code stubs.

## Self-Check: PASSED

- test/unit/balance_calculations_test.dart exists and contains 'Cross-event balance scenarios' group
- Commit 6d3dd35 exists
- All 10 tests pass (4 existing + 6 new)
