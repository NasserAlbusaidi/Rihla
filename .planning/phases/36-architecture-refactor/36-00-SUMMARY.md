---
phase: 36-architecture-refactor
created: 2026-04-16
status: planned
planner: opus-4.6
---

# Phase 36 — Architecture Refactor Plan Overview

**Milestone:** v2.4 — Technical Debt & Dark Theme
**Goal:** Eliminate god screens (>600 LOC), bound provider fan-out on the dashboard, and split the CacheService god class — without regressing existing features or tests.
**Requirements:** ARCH-01, ARCH-02, ARCH-03, ARCH-04
**UI change:** none

## Wave Structure

| Wave | Plan(s) | Purpose | Parallel-safe |
|------|---------|---------|---------------|
| 0 | 36-00 | Wave 0 — Failing test scaffolding for all 4 requirements (TDD RED) | — |
| 1 | 36-01, 36-02, 36-03, 36-04, 36-05 | God screen decompositions (ARCH-01) — one per screen | Yes (disjoint file sets) |
| 2 | 36-06 | CacheService + BalanceCacheRepository decomposition (ARCH-04) | No (cross-cutting) |
| 3 | 36-07 | Dashboard fan-out fix + weekly spending range query (ARCH-02 + ARCH-03) | No |

## Plan Inventory

| Plan | Title | Wave | Depends on | Requirements |
|------|-------|------|-----------|--------------|
| 36-00 | Wave 0 — TDD test scaffolding (RED) | 0 | — | ARCH-01, ARCH-02, ARCH-03, ARCH-04 |
| 36-01 | Decompose `group_settle_up_screen.dart` (990 → ≤400) | 1 | 36-00 | ARCH-01 |
| 36-02 | Decompose `edit_expense_screen.dart` (799 → ≤450) | 1 | 36-00 | ARCH-01 |
| 36-03 | Decompose `gear_screen.dart` (729 → ≤380) | 1 | 36-00 | ARCH-01 |
| 36-04 | Decompose `logistics_screen.dart` (690 → ≤400) | 1 | 36-00 | ARCH-01 |
| 36-05 | Decompose `create_event_screen.dart` (689 → ≤500) | 1 | 36-00 | ARCH-01 |
| 36-06 | Split `CacheService` + rename `BalanceCacheRepository` | 2 | 36-00 | ARCH-04 |
| 36-07 | Bound dashboard fan-out + Firestore date-range query | 3 | 36-00 | ARCH-02, ARCH-03 |

## Decision Coverage Matrix

| Requirement | Plan(s) | Full/Partial | Notes |
|-------------|---------|--------------|-------|
| ARCH-01 — screen LOC ≤ 600 | 36-01, 36-02, 36-03, 36-04, 36-05 | Full | One plan per god screen |
| ARCH-02 — dashboard O(G), not O(G×E) | 36-07 | Full | Per-group `StreamProvider.family` replaces per-event fan-out |
| ARCH-03 — weekly spending range query | 36-07 | Full | `watchExpensesInRange` server-side filter on `createdAt` ISO-8601 |
| ARCH-04 — CacheService split + dedup | 36-06 | Full | 9 domain repos + `BalanceCacheRepository` renamed to Expense/Settlement |

All 4 requirements have Full coverage. No phase split needed.

## Open Questions Resolved in Plans

1. **BalanceCacheRepository split?** Yes — Plan 36-06 splits into `ExpenseCacheRepository` + `SettlementCacheRepository`. The name `BalanceCacheRepository` was never accurate (it is SQLite I/O, not balance math).

2. **Reuse `split_scope_selector.dart` in edit-expense?** Yes — Plan 36-02 reuses the existing shared widget. Its constructor already accepts `scope`, `onScopeChanged`, `customSplitParticipants`, `onCustomSplitChanged`, `selectedSubGroupId`, `selectedPayerId`, and `onPayerChanged` — no modification needed.

3. **Per-group weekly provider shape?** `StreamProvider.family<List<Expense>, String groupId>` for per-group + `Provider<AsyncValue<List<DailySpending>>>` at the top level (folding). Plan 36-07 implements this.

4. **Goldens vs widget tests?** Widget tests. No goldens currently run in CI. Plan 36-01..05 add widget tests per extracted widget.

## Verification Gates (goal-backward must-haves)

These assertions must all be TRUE at phase end:

### Line-count ceilings (ARCH-01)
- `wc -l lib/features/groups/screens/group_settle_up_screen.dart` ≤ 600 (stretch ≤ 400)
- `wc -l lib/features/ledger/screens/edit_expense_screen.dart` ≤ 600 (stretch ≤ 450)
- `wc -l lib/features/gear/screens/gear_screen.dart` ≤ 600 (stretch ≤ 400)
- `wc -l lib/features/logistics/screens/logistics_screen.dart` ≤ 600 (stretch ≤ 400)
- `wc -l lib/features/events/screens/create_event_screen.dart` ≤ 600 (stretch ≤ 500)
- `flutter test test/architecture/screen_size_test.dart` passes (GREEN)

### Dashboard fan-out (ARCH-02)
- `test/unit/dashboard_providers_test.dart` assertion: `weeklyGroupSpendingProvider` evaluation does NOT cause any `eventExpensesProvider` to materialize
- Listener count for dashboard: O(G) providers observed, not O(G×E)

### Weekly range query (ARCH-03)
- `ExpenseService.watchExpensesInRange(...)` exists with signature `(groupId, eventId, startUtc, endExclusiveUtc)`
- `test/unit/expense_service_test.dart` assertion: query filters expenses whose `createdAt < startUtc` and `createdAt >= endUtc` are excluded server-side (fake_cloud_firestore)

### CacheService decomposition (ARCH-04)
- `flutter test test/architecture/no_cache_service_test.dart` passes: zero matches for `CacheService.` in `lib/`
- `lib/core/services/cache_service.dart` file DOES NOT EXIST
- `lib/core/services/balance_cache_repository.dart` file DOES NOT EXIST (replaced by `cache/expense_cache_repository.dart` + `cache/settlement_cache_repository.dart`)
- `grep -r 'balanceCacheRepositoryProvider' lib/` returns 0 matches (renamed to `expenseCacheRepositoryProvider` / `settlementCacheRepositoryProvider`)
- All 9 domain repos exist under `lib/core/services/cache/`

### No regressions
- `flutter test` — full suite green
- `flutter analyze` — clean (no new warnings or errors)
- Existing tests unchanged in behavior except for renamed imports (BalanceCacheRepository → ExpenseCacheRepository)

## Migration Risk Notes

1. **SQLite column `trip_id`:** DO NOT RENAME. 8 annotated comments confirm this column stores eventId. Renaming would silently return zero rows. Column stays as `trip_id` through the refactor.

2. **Firestore composite index for range query:** The existing `(isDeleted ASC, createdAt DESC)` index on `expenses` collection covers the new range predicate `where('isDeleted', ==, false) AND where('createdAt', >=, X) AND where('createdAt', <, Y)`. Plan 36-07 verifies this with `fake_cloud_firestore` first; if production Firestore demands a different index, the error URL identifies the exact fields to add.

3. **Widget extraction — `widget.xxx` capture:** Each `_buildX` helper inside a State class accesses `widget.groupId` or `widget.eventId` implicitly. Extracted widgets MUST receive these as constructor args. Pitfall 4 from RESEARCH.md applies.

4. **`StreamProvider` vs `Provider` at aggregate level:** Per-group provider is `StreamProvider.family`. The top-level weekly provider stays as `Provider<AsyncValue<List<DailySpending>>>` because it folds N per-group streams via `ref.watch` in a loop — which is safe in `Provider.family` body but NOT in `StreamProvider.family` body (Pitfall 1).

5. **`BalanceCacheRepository` → split:** Plan 36-06 folds balance caching into two new repos. All `balanceCacheRepositoryProvider` references (at `lib/features/ledger/providers/expense_provider.dart:60,85,175,184`) become `expenseCacheRepositoryProvider` / `settlementCacheRepositoryProvider`. The `watchExpenses`/`watchSettlements` deprecated methods are deleted in the same plan (research notes "already shipped — remove during ARCH-04").

## Files Modified (aggregate view)

### Created in this phase
- `test/architecture/screen_size_test.dart` (Plan 36-00)
- `test/architecture/no_cache_service_test.dart` (Plan 36-00)
- `test/features/groups/widgets/settle_up_tab_layout_test.dart` + siblings (Plan 36-01)
- `test/features/ledger/widgets/edit_expense_form_test.dart` + siblings (Plan 36-02)
- `test/features/gear/widgets/gear_item_card_test.dart` + siblings (Plan 36-03)
- `test/features/logistics/widgets/logistics_hero_card_test.dart` + siblings (Plan 36-04)
- `test/features/events/widgets/event_details_card_test.dart` + siblings (Plan 36-05)
- `lib/features/groups/widgets/settle_up_tab_layout.dart` + 3 siblings (Plan 36-01)
- `lib/features/ledger/widgets/edit_expense_scope_section.dart` + 2 siblings (Plan 36-02)
- `lib/features/gear/widgets/gear_item_card.dart` + 2 siblings (Plan 36-03)
- `lib/features/logistics/widgets/logistics_hero_card.dart` + 2 siblings (Plan 36-04)
- `lib/features/events/widgets/event_details_card.dart` + 2 siblings (Plan 36-05)
- `lib/core/services/cache/trip_cache_repository.dart` + 8 siblings (Plan 36-06)
- `test/unit/expense_cache_repository_test.dart` + `settlement_cache_repository_test.dart` (Plan 36-06)

### Modified in this phase
- 5 god screen files (shrunk) — Plans 36-01..05
- `lib/features/trip/providers/trip_provider.dart` (CacheService caller migrated) — Plan 36-06
- `lib/features/ledger/providers/expense_provider.dart` (provider renames) — Plan 36-06
- `lib/core/README.md` (cache service references) — Plan 36-06
- `lib/features/home/providers/dashboard_providers.dart` (weekly provider rewrite) — Plan 36-07
- `lib/features/ledger/services/expense_service.dart` (new `watchExpensesInRange`) — Plan 36-07
- `test/unit/dashboard_providers_test.dart` (new fan-out tests) — Plans 36-00, 36-07
- `test/unit/expense_service_test.dart` (new range-query test) — Plans 36-00, 36-07

### Deleted in this phase
- `lib/core/services/cache_service.dart` — Plan 36-06
- `lib/core/services/balance_cache_repository.dart` — Plan 36-06
- `test/unit/balance_cache_repository_test.dart` — Plan 36-06 (renamed to expense/settlement)
