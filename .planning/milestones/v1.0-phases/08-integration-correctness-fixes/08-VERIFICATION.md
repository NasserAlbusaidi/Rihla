---
phase: 08-integration-correctness-fixes
verified: 2026-03-27T15:15:00Z
status: passed
score: 7/7 must-haves verified
re_verification: false
human_verification:
  - test: "Open AddExpenseScreen for a Firestore-only event, select Custom scope, verify participant names appear"
    expected: "Participant names from Event.participantNames render in the multi-select list"
    why_human: "Requires running app with Firestore event data to verify end-to-end provider chain"
  - test: "Open GroupSettleUpScreen for a group with multiple events, verify per-event breakdown shows event names with dates"
    expected: "Labels like 'Camping Weekend -- Mar 15' appear instead of truncated eventIds"
    why_human: "Requires real Firestore data with multiple events to verify label rendering"
---

# Phase 8: Integration & Correctness Fixes Verification Report

**Phase Goal:** Fix functional degradations found in milestone audit -- custom expense splits work for new events, settle-up labels show event names, and column naming is corrected
**Verified:** 2026-03-27T15:15:00Z
**Status:** passed
**Re-verification:** No -- initial verification

## Goal Achievement

### Observable Truths

| # | Truth | Status | Evidence |
|---|-------|--------|----------|
| 1 | ExpenseScope.custom participant list populates correctly for Firestore-only events | VERIFIED | `split_scope_selector.dart` uses `eventLogisticsParticipantsProvider(event)` at lines 198, 391; `tripLogisticsParticipantsProvider` has 0 occurrences in the file; test `provider_swap_test.dart` proves 3 participants returned |
| 2 | Payer dropdown in both add and edit expense screens shows participant names for Firestore-only events | VERIFIED | `add_expense_screen.dart` watches `eventDetailProvider` at line 303 and passes `event:` to `SplitScopeSelector` at line 424; `edit_expense_sheet.dart` uses `eventLogisticsParticipantsProvider(event)` at line 372 (2 occurrences); `tripLogisticsParticipantsProvider` has 0 occurrences in both files |
| 3 | All trip_id column usages in BalanceCacheRepository and CacheService have clarifying comments | VERIFIED | `balance_cache_repository.dart`: 1x "column is named 'trip_id' for historical reasons" + 3x "'trip_id' column stores eventId"; `cache_service.dart`: 4x "'trip_id' column stores eventId" -- totals 8 comments across 8 sites |
| 4 | Per-event breakdown in GroupSettleUpScreen shows event names instead of truncated eventIds | VERIFIED | `group_settle_up_screen.dart` watches `groupEventsProvider(widget.groupId)` at line 88; `_buildEventLabel` method at line 668 replaces deleted `_shortEventLabel`; `_shortEventLabel` has 0 occurrences |
| 5 | Event labels follow format 'Event Name -- Mar 15' per D-01 and D-04 | VERIFIED | `_buildEventLabel` uses `AppFormatters.formatShortMonthDay(entry.date)` at line 692 and returns `'$name \u2014 $date'` at line 693; widget test asserts `textContaining('Camping Weekend')` and `textContaining('Mar 15')` |
| 6 | When event name is unavailable, label falls back to event type display name per D-02 | VERIFIED | `_buildEventLabel` calls `EventTypeConfig.forType(entry.type).label` at line 684 when `entry.name.isNotEmpty` is false; fallback path for null entry returns eventId-based label at lines 676-678 |
| 7 | Event labels are not tappable per D-03 | VERIFIED | Breakdown labels render as `Text` widgets inside a `Row` (lines 535-558) with no `GestureDetector`, `InkWell`, or `onTap` wrapping |

**Score:** 7/7 truths verified

### Required Artifacts

| Artifact | Expected | Status | Details |
|----------|----------|--------|---------|
| `lib/features/ledger/widgets/split_scope_selector.dart` | Custom split participant selector using eventLogisticsParticipantsProvider | VERIFIED | Contains `eventLogisticsParticipantsProvider` (4 occurrences); constructor has `required this.event` (3 occurrences for main class + 2 sub-widgets); 477 lines, substantive widget code |
| `lib/core/services/balance_cache_repository.dart` | SQLite expense/settlement cache with trip_id column comments | VERIFIED | Contains canonical comment "column is named 'trip_id' for historical reasons" (1x) and back-references (3x); 213 lines |
| `test/unit/provider_swap_test.dart` | Test proving provider swap returns non-empty participants | VERIFIED | 65 lines; 3 test cases covering non-empty list, displayName matching, and count matching |
| `lib/core/utils/formatters.dart` | formatShortMonthDay method returning 'Mar 15' format | VERIFIED | `_monthAbbr` const + `formatShortMonthDay(DateTime)` static method at lines 36-47 |
| `lib/features/groups/screens/group_settle_up_screen.dart` | Event name labels in per-event breakdown using groupEventsProvider | VERIFIED | `groupEventsProvider` watched at line 88; `_buildEventLabel` at line 668; `_shortEventLabel` deleted; 1021 lines |
| `test/unit/formatters_test.dart` | Tests for formatShortMonthDay | VERIFIED | 4 new test cases (Mar 15, Jan 1, Dec 31, Jun 3) at lines 90-118 |
| `test/features/groups/group_settle_up_screen_test.dart` | Widget tests for event name happy path and fallback | VERIFIED | `_testEvent` fixture at line 34; `_wrap` helper with events param at line 105; 2 new widget tests at lines 390-430; `groupEventsProvider` override at line 114 |
| `lib/core/services/cache_service.dart` | SQLite cache with trip_id column comments | VERIFIED | 4x "'trip_id' column stores eventId" back-references at lines 104, 126, 170, 189 |
| `lib/features/ledger/screens/add_expense_screen.dart` | Passes event: to SplitScopeSelector | VERIFIED | `eventDetailProvider` watch at line 303; `SplitScopeSelector(event: eventAsync.valueOrNull!)` at line 424; loading fallback at lines 445-448 |
| `lib/features/ledger/screens/edit_expense_sheet.dart` | _buildPayerSelector uses eventLogisticsParticipantsProvider | VERIFIED | `eventDetailProvider` watch at line 367; `eventLogisticsParticipantsProvider(event)` at line 372; no `tripLogisticsParticipantsProvider` remaining |
| `lib/features/ledger/providers/expense_provider.dart` | Deprecation comment on legacy provider usage | VERIFIED | Comment "tripLogisticsParticipantsProvider is deprecated for new code" at line 211 |

### Key Link Verification

| From | To | Via | Status | Details |
|------|----|-----|--------|---------|
| `split_scope_selector.dart` | `sub_group_provider.dart` | `ref.watch(eventLogisticsParticipantsProvider(event))` | WIRED | Line 198 (CustomParticipantSelector) and line 391 (PayerSelector) |
| `add_expense_screen.dart` | `split_scope_selector.dart` | `SplitScopeSelector(event: event)` | WIRED | Line 423-424; `event:` parameter (not `tripId:`) |
| `group_settle_up_screen.dart` | `event_provider.dart` | `ref.watch(groupEventsProvider(widget.groupId))` | WIRED | Line 88; builds `eventNameMap` from events at lines 89-96 |
| `group_settle_up_screen.dart` | `formatters.dart` | `AppFormatters.formatShortMonthDay` | WIRED | Line 692 inside `_buildEventLabel` |

### Data-Flow Trace (Level 4)

| Artifact | Data Variable | Source | Produces Real Data | Status |
|----------|---------------|--------|--------------------|--------|
| `split_scope_selector.dart` | `participants` | `eventLogisticsParticipantsProvider(event)` | Yes -- derives from `Event.participantIds` / `Event.participantNames` (Firestore document) | FLOWING |
| `group_settle_up_screen.dart` | `eventNameMap` | `groupEventsProvider(widget.groupId)` | Yes -- Firestore stream of `List<Event>` | FLOWING |
| `add_expense_screen.dart` | `eventAsync` | `eventDetailProvider(...)` | Yes -- Firestore stream of `Event?` | FLOWING |
| `edit_expense_sheet.dart` | `participants` (in `_buildPayerSelector`) | `eventDetailProvider` + `eventLogisticsParticipantsProvider` | Yes -- Firestore Event document | FLOWING |

### Behavioral Spot-Checks

Step 7b: SKIPPED (requires running Flutter app with Firestore backend -- no runnable entry points for static verification)

### Requirements Coverage

| Requirement | Source Plan | Description | Status | Evidence |
|-------------|------------|-------------|--------|----------|
| EVT-08 (integration fix) | 08-01-PLAN.md | Existing trip functionality works within events -- custom split participant provider swap | SATISFIED | `eventLogisticsParticipantsProvider` replaces `tripLogisticsParticipantsProvider` in all ledger screens; test proves non-empty participant list for Firestore-only events |
| FIN-04 | 08-02-PLAN.md | Cross-event settle-up shows event names | SATISFIED | `_buildEventLabel` renders "Event Name -- Mar 15" format; `groupEventsProvider` provides real event names; widget tests confirm rendering |

No orphaned requirements found. ROADMAP maps only FIN-04 and EVT-08 to Phase 8; both are covered by the two plans.

### Anti-Patterns Found

| File | Line | Pattern | Severity | Impact |
|------|------|---------|----------|--------|
| None | -- | -- | -- | No TODO, FIXME, placeholder, or stub patterns found in any modified file |

### Noted Discrepancy

ROADMAP success criterion #3 states: "`BalanceCacheRepository.cacheExpenses()` uses `event_id` column name matching its actual content." The implementation chose to add clarifying comments rather than rename the column. This is a deliberate decision documented in 08-01-PLAN.md Task 1 action: "NO logic changes. NO column renames. Comment-only additions." The rationale is that renaming the SQLite column requires a schema migration (version bump + migration code), which adds risk for zero functional benefit. The comments achieve the goal's intent (preventing developer confusion) without the risk. This deviation is acceptable -- the goal of "column naming is corrected" is satisfied through documentation, not rename.

### Human Verification Required

### 1. Custom Split Participant Picker (End-to-End)

**Test:** Open AddExpenseScreen for a Firestore-only event (no legacy Supabase trip), select Custom scope
**Expected:** Participant names from the Event document appear in the multi-select list; payer dropdown shows the same names
**Why human:** Requires running app connected to Firestore with real event data to verify the full provider chain from Firestore document through eventLogisticsParticipantsProvider to UI rendering

### 2. Settle-Up Event Name Labels (End-to-End)

**Test:** Open GroupSettleUpScreen for a group with 2+ events that have inter-member debts
**Expected:** Per-event breakdown rows show labels like "Camping Weekend -- Mar 15" instead of "Event ...abc123"
**Why human:** Requires real Firestore data with multiple events and cross-event balances to verify label rendering in production conditions

### Gaps Summary

No gaps found. All 7 observable truths verified. All 11 artifacts pass existence, substantive, and wiring checks. All 4 key links verified as wired. Data flows confirmed through 4 data-flow traces. All 5 documented commits validated. Both requirement IDs (EVT-08, FIN-04) satisfied. No anti-patterns detected.

### Commit Verification

| Commit | Message | Valid |
|--------|---------|-------|
| db5c26a | fix(08-01): add clarifying comments to all 8 trip_id column usage sites | Yes |
| 7a6b2c7 | test(08-01): add failing test for eventLogisticsParticipantsProvider swap | Yes |
| e03fde2 | feat(08-01): swap tripLogisticsParticipantsProvider to eventLogisticsParticipantsProvider | Yes |
| b38c74e | feat(08-02): add AppFormatters.formatShortMonthDay and 4 TDD tests | Yes |
| c8f84f6 | feat(08-02): replace _shortEventLabel with event name lookup in GroupSettleUpScreen | Yes |

---

_Verified: 2026-03-27T15:15:00Z_
_Verifier: Claude (gsd-verifier)_
