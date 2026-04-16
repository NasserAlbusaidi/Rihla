---
phase: 36-architecture-refactor
plan: "07"
subsystem: dashboard-providers
tags: [refactor, riverpod, firestore, arch-02, arch-03, provider-fan-out, range-query]
dependency_graph:
  requires: [36-06 (expenseServiceProvider available), 36-00 (test scaffolding — not executed, created inline)]
  provides: [weeklyGroupExpensesProvider, ExpenseService.watchExpensesInRange, ARCH-02, ARCH-03]
  affects: [lib/features/home/providers/dashboard_providers.dart, lib/features/ledger/services/expense_service.dart]
tech_stack:
  added: []
  patterns: [StreamProvider.family per-group aggregate, manual N-stream combiner, server-side Firestore range filter]
key_files:
  created: []
  modified:
    - lib/features/ledger/services/expense_service.dart
    - lib/features/home/providers/dashboard_providers.dart
    - test/unit/expense_service_test.dart
    - test/unit/dashboard_providers_test.dart
decisions:
  - "Path A taken for Firestore index: existing (isDeleted ASC, createdAt DESC) index on expenses covers the new range predicate — no new index needed"
  - "_combineExpenseStreams uses StreamController with onCancel cleanup; close_sinks lint suppressed with // ignore comment since lifecycle is managed via onCancel"
  - "weeklyGroupSpendingProvider remains Provider<AsyncValue<...>> (not StreamProvider) — it folds N per-group StreamProvider.family results via ref.watch in a loop, which is safe in Provider body per RESEARCH.md Pitfall 1 note"
  - "TDD inline: 36-00 plan was never executed, so ARCH-02/ARCH-03 tests were added RED in this plan before implementation"
metrics:
  duration: "~10 minutes"
  completed: "2026-04-16"
  tasks: 3
  files_modified: 4
  loc_added: ~175 (service method + provider + combiner + tests)
requirements: [ARCH-02, ARCH-03]
---

# Phase 36 Plan 07: Dashboard Fan-out Fix + Firestore Range Query Summary

**One-liner:** Rewired `weeklyGroupSpendingProvider` from O(G×E) `eventExpensesProvider` fan-out to O(G) `weeklyGroupExpensesProvider` per-group aggregate, backed by a new server-side Firestore `createdAt` range query on `ExpenseService`.

## What Was Built

### New Service Method

`ExpenseService.watchExpensesInRange({required String groupId, required String eventId, required DateTime startUtc, required DateTime endExclusiveUtc})` — server-side Firestore query:

```dart
eventSubcollection(groupId, eventId, 'expenses')
    .where('isDeleted', isEqualTo: false)
    .where('createdAt', isGreaterThanOrEqualTo: startUtc.toIso8601String())
    .where('createdAt', isLessThan: endExclusiveUtc.toIso8601String())
    .orderBy('createdAt', descending: true)
```

Uses ISO-8601 lexicographic ordering, which is correct for UTC timestamps. Only downloads current-week documents (not the entire expense history).

### New Provider: `weeklyGroupExpensesProvider`

`StreamProvider.family<List<Expense>, String>` — one provider per group. Watches `groupEventsProvider(groupId)` to get events, then calls `watchExpensesInRange` for each event in the current UTC week, combining N event streams via `_combineExpenseStreams`.

### Rewritten Provider: `weeklyGroupSpendingProvider`

Now loops over groups watching `weeklyGroupExpensesProvider(group.id)` — O(G) Riverpod subscriptions instead of O(G×E). The `eventExpensesProvider` fan-out is completely removed from the weekly spending logic.

### Stream Combiner

`_combineExpenseStreams(List<Stream<List<Expense>>>)` — manual combiner that:
- Maintains per-stream latest state
- Waits for all N streams to emit at least once before emitting (prevents partial state)
- Cancels all subscriptions and closes the controller when the subscriber disposes

### Firestore Index Verification (Path A)

The existing `(isDeleted ASC, createdAt DESC)` composite index on the `expenses` collection covers:

```
where('isDeleted', ==, false)
  .where('createdAt', >=, X)
  .where('createdAt', <, Y)
  .orderBy('createdAt', desc)
```

Firestore documentation guarantees that equality-first + range-on-same-field + ordering-on-same-field is covered by a single composite index. No `FAILED_PRECONDITION` error expected. If deployment produces one, the error URL will specify the exact fields required.

## Verification Results

| Check | Result |
|-------|--------|
| `flutter test test/unit/expense_service_test.dart` | GREEN (9/9) |
| `flutter test test/unit/dashboard_providers_test.dart` | GREEN (7/7) |
| `flutter test test/architecture/` | GREEN (3/3, unchanged) |
| `flutter test test/unit/` | GREEN (564 tests, 0 failures, 3 skipped) |
| `flutter analyze lib/features/ledger/services/ lib/features/home/providers/` | No issues |
| ARCH-03 test "watchExpensesInRange filters server-side by createdAt" | GREEN |
| ARCH-02 test "weeklyGroupSpendingProvider resolves via weeklyGroupExpensesProvider" | GREEN |
| `grep -n 'eventExpensesProvider' dashboard_providers.dart` (live ref.watch call) | 0 matches |
| `firestore.indexes.json` expenses index preserved | Verified |
| `gear_items` index coexists | Verified |

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] `close_sinks` lint on StreamController in `_combineExpenseStreams`**
- **Found during:** Task 2 — `flutter analyze lib/features/home/` flagged it
- **Issue:** Analyzer cannot see that `controller.close()` is called inside `onCancel` callback; fires `close_sinks` info lint
- **Fix:** Added `// ignore: close_sinks` comment on the controller declaration; also added explicit `await controller.close()` inside `onCancel` for correctness
- **Files modified:** `lib/features/home/providers/dashboard_providers.dart`
- **Commit:** f5e14f8

**2. [Rule 3 - Missing test scaffolding] Plan 36-00 was never executed**
- **Found during:** Pre-execution check — both test files were GREEN (no ARCH-02/ARCH-03 tests existed)
- **Issue:** The plan assumed ARCH-02/ARCH-03 RED tests already existed from Plan 36-00; they did not
- **Fix:** Added RED tests inline (TDD: RED first, then GREEN via implementation) following the same TDD workflow
- **Files modified:** `test/unit/expense_service_test.dart`, `test/unit/dashboard_providers_test.dart`
- **Commit:** cfdfcb6 (ARCH-03 RED + GREEN), f5e14f8 (ARCH-02 RED + GREEN)

## Known Stubs

None — `weeklyGroupExpensesProvider` is fully wired to `ExpenseService.watchExpensesInRange` which queries real Firestore. No placeholder data.

## Threat Flags

None — no new network endpoints, auth paths, or schema changes. The new Firestore range query uses the same collection path as `watchExpenses`; it adds server-side filters, which reduce (not expand) the data returned.

## Self-Check: PASSED

- `lib/features/ledger/services/expense_service.dart` — `watchExpensesInRange` method present: VERIFIED
- `lib/features/home/providers/dashboard_providers.dart` — `weeklyGroupExpensesProvider` present: VERIFIED
- `lib/features/home/providers/dashboard_providers.dart` — `weeklyGroupSpendingProvider` uses `weeklyGroupExpensesProvider`, not `eventExpensesProvider`: VERIFIED
- Commits cfdfcb6, f5e14f8 exist: VERIFIED
- ARCH-02 test GREEN: VERIFIED
- ARCH-03 test GREEN: VERIFIED
- 564 unit tests, 0 failures: VERIFIED
