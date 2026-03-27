# Phase 8: Integration & Correctness Fixes - Context

**Gathered:** 2026-03-27
**Status:** Ready for planning

<domain>
## Phase Boundary

Fix three functional degradations found in v1.0 milestone audit:
1. `ExpenseScope.custom` participant list empty for Firestore-only events (wrong provider)
2. `GroupSettleUpScreen` per-event breakdown shows truncated eventIds instead of event names
3. `BalanceCacheRepository.cacheExpenses()` uses `trip_id` column name for eventId values

These are surgical corrections to existing code. No new features, no architectural changes.

</domain>

<decisions>
## Implementation Decisions

### Settle-up Label Format
- **D-01:** Per-event breakdown labels show full event name (truncate with ellipsis only if 30+ chars)
- **D-02:** Fallback to event type (e.g., "Trip", "Camping") when event name is missing
- **D-03:** No navigation from event labels — tapping does nothing, this is a settle-up screen
- **D-04:** Show event date alongside name in format: "Event Name — Mar 15" (short month + day)

### Column Rename Strategy
- **D-05:** Code-only fix — add clear comments at each usage site noting `trip_id` column stores eventId. No SQLite schema migration.
- **D-06:** Quick audit of `BalanceCacheRepository` and `CacheService` for other trip_id/event_id mismatches while fixing the flagged one
- **D-07:** If audit finds more mismatches, fix them in this phase (don't defer as tech debt)

### Testing Approach
- **D-08:** Unit tests + widget tests. Unit tests for provider swap and cache column fix; widget test for GroupSettleUpScreen label rendering.
- **D-09:** Widget test covers both happy path (event name displays) and fallback (event type when name missing)
- **D-10:** Provider swap test verifies `ExpenseScope.custom` returns non-empty participant list (proves the fix works end-to-end)

### Claude's Discretion
- How to pass event name map to GroupSettleUpScreen (prop drilling vs provider)
- Date formatting utility — reuse existing AppFormatters or inline
- Exact comment wording for the column name mismatch

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Milestone Audit (Source of Truth for Fixes)
- `.planning/v1.0-MILESTONE-AUDIT.md` — Defines all three issues, severity, affected requirements, and suggested fixes

### Provider Swap (Fix #1)
- `lib/features/trip/providers/trip_provider.dart` — Contains `tripLogisticsParticipantsProvider` (the wrong provider)
- `lib/features/logistics/providers/sub_group_provider.dart` — Contains `eventLogisticsParticipantsProvider` (the correct provider)
- `lib/features/ledger/screens/add_expense_screen.dart` — Uses wrong provider for custom splits
- `lib/features/ledger/screens/edit_expense_sheet.dart` — Uses wrong provider for custom splits
- `lib/features/ledger/widgets/split_scope_selector.dart` — Uses wrong provider for custom splits

### Settle-up Labels (Fix #2)
- `lib/features/groups/screens/group_settle_up_screen.dart` — Contains `_shortEventLabel()` that needs replacing
- `lib/features/events/providers/event_provider.dart` — Contains `groupEventsProvider` for event name lookup

### Column Naming (Fix #3)
- `lib/core/services/balance_cache_repository.dart` — Contains `cacheExpenses()` with the mismatched column
- `lib/core/services/cache_service.dart` — Related cache code to audit for similar mismatches

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `groupEventsProvider` in `event_provider.dart` — provides event list per group, can be used to build eventId → name map
- `eventLogisticsParticipantsProvider` in `sub_group_provider.dart` — correct provider for event-scoped participant lists
- `AppFormatters` — existing date formatting utilities that may handle short month + day format

### Established Patterns
- Provider-based data flow: screens watch providers, providers fetch from Firestore/SQLite
- `_shortEventLabel()` is a private method in GroupSettleUpScreen — replacement logic stays in the same file
- `BalanceCacheRepository` writes to SQLite `expenses` table with batch inserts

### Integration Points
- `add_expense_screen.dart`, `edit_expense_sheet.dart`, `split_scope_selector.dart` all import from `trip_provider.dart` — need to switch import to `sub_group_provider.dart`
- `GroupSettleUpScreen` already receives group data — needs event data passed alongside or via provider

</code_context>

<specifics>
## Specific Ideas

- Event name + date format: "Camping Weekend — Mar 15" (short month + day, no year)
- Fallback chain: event name → event type → should never reach "unknown" given model constraints

</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope

</deferred>

---

*Phase: 08-integration-correctness-fixes*
*Context gathered: 2026-03-27*
