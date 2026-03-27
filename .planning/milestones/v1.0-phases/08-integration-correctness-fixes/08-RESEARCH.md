# Phase 8: Integration & Correctness Fixes - Research

**Researched:** 2026-03-27
**Domain:** Flutter/Riverpod provider wiring, SQLite column naming, widget data-passing
**Confidence:** HIGH

## Summary

Phase 8 is three surgical corrections identified in the v1.0 milestone audit. Each fix is isolated: one provider swap across three files, one label-rendering improvement in one screen, and one code-comment-plus-audit on one repository class.

The core risk in all three is "does the fix break existing tests?" All three touch code that already has widget test coverage. The planner must ensure existing tests are updated to exercise the new behavior rather than silently passing with the old broken behavior.

The most architecturally interesting fix is #2 (settle-up labels): `_buildPerEventBreakdown` is a private method that currently only has access to `GroupBalances` — which has `perEventBreakdown` keyed by eventId — but no event name map. Getting event names into that method requires either prop-drilling through `_buildSettlementTile`/`_buildSettlementGroup` call chains or watching `groupEventsProvider` inside the widget. Both approaches are architecturally sound given the project's patterns; the CONTEXT.md assigns this choice to Claude's discretion.

**Primary recommendation:** Implement in dependency order — Fix #3 (column comment, zero logic change), Fix #1 (provider swap), Fix #2 (event name labels) — so each fix is independently verifiable.

---

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions

**D-01: Settle-up label format**
Per-event breakdown labels show full event name (truncate with ellipsis only if 30+ chars).

**D-02: Fallback when event name is missing**
Fall back to event type (e.g., "Trip", "Camping").

**D-03: No navigation from event labels**
Tapping does nothing — this is a settle-up screen.

**D-04: Date alongside name**
Show event date alongside name in format: "Event Name — Mar 15" (short month + day).

**D-05: Column rename strategy**
Code-only fix — add clear comments at each usage site noting `trip_id` column stores eventId. No SQLite schema migration.

**D-06: Quick audit scope**
Quick audit of `BalanceCacheRepository` and `CacheService` for other trip_id/event_id mismatches while fixing the flagged one.

**D-07: Fix audit findings in this phase**
If audit finds more mismatches, fix them here (don't defer).

**D-08: Test strategy**
Unit tests + widget tests. Unit tests for provider swap and cache column fix; widget test for GroupSettleUpScreen label rendering.

**D-09: Widget test coverage**
Widget test covers both happy path (event name displays) and fallback (event type when name missing).

**D-10: Provider swap test**
Provider swap test verifies `ExpenseScope.custom` returns non-empty participant list (proves the fix works end-to-end).

### Claude's Discretion

- How to pass event name map to GroupSettleUpScreen (prop drilling vs provider)
- Date formatting utility — reuse existing AppFormatters or inline
- Exact comment wording for the column name mismatch

### Deferred Ideas (OUT OF SCOPE)

None — discussion stayed within phase scope.
</user_constraints>

---

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| FIN-04 | Cross-event settle-up: "You owe Nasser 15.500 across 3 events — settle now?" | Fix #2 directly completes this: per-event breakdown now shows event names instead of truncated eventIds, making the settle-up UI meaningful to users |
| EVT-08 | Existing trip functionality (ledger, gear, logistics, vault, activity, memories) works within events | Fix #1 directly restores this: `ExpenseScope.custom` participant picker was returning empty list for Firestore-only events due to the wrong provider |
</phase_requirements>

---

## Standard Stack

### Core (no new dependencies)
| Library | Current Version | Purpose | Notes |
|---------|----------------|---------|-------|
| `flutter_riverpod` | `^2.4.9` | Provider-based state | All three fixes use existing providers — no new providers needed |
| `sqflite` | `^2.4.2` | SQLite local storage | Fix #3 only adds comments to existing insert calls |
| `sqflite_common_ffi` | dev dependency | In-memory SQLite for tests | Already used in `balance_cache_repository_test.dart` |
| `fake_cloud_firestore` | `^4.1.0+1` | Firestore testing | Needed for provider swap test if testing `eventLogisticsParticipantsProvider` indirectly |

No installation needed. Zero new packages.

---

## Architecture Patterns

### Fix #1: Provider Swap (ExpenseScope.custom empty participant list)

**Root cause:** `tripLogisticsParticipantsProvider` (in `trip_provider.dart`) reads from SQLite `participants` table via `CacheService.getCachedParticipants()`. For Firestore-only events, the participants table is never populated — Firestore events store participant data in the `Event` document's `participantIds`/`participantNames` fields, not in SQLite.

**Correct provider:** `eventLogisticsParticipantsProvider` (in `sub_group_provider.dart`) takes an `Event` object and derives `List<Participant>` directly from `event.participantIds`/`event.participantNames`. No SQLite read needed.

**Signature difference (critical):**
```dart
// WRONG — takes String (eventId), reads SQLite
final tripLogisticsParticipantsProvider =
    StreamProvider.family<List<Participant>, String>

// CORRECT — takes Event object, derives from Firestore data
final eventLogisticsParticipantsProvider =
    Provider.family<List<Participant>, Event>
```

**Files affected:**
- `lib/features/ledger/widgets/split_scope_selector.dart` — Two usages: `_CustomParticipantSelector` (line 194) and `_PayerSelector` (line 387). Both receive `tripId: String` but need to switch to `event: Event`.
- `lib/features/ledger/screens/add_expense_screen.dart` — One usage in debug logging block (line 185). This is inside a null-participant fallback block and can safely be removed since `tripLogisticsParticipantsProvider` is no longer meaningful there.
- `lib/features/ledger/screens/edit_expense_sheet.dart` — One usage in `_buildPayerSelector` (line 361) for the payer dropdown.

**Interface change for `SplitScopeSelector`:** Currently receives `tripId: String`. To use `eventLogisticsParticipantsProvider`, it needs the `Event` object or a pre-resolved `List<Participant>`. The cleaner approach consistent with the project's Riverpod 2.x patterns is to pass the `Event` object and watch `eventLogisticsParticipantsProvider(event)` inside the widget. This requires updating `SplitScopeSelector`'s constructor and both call sites (`add_expense_screen.dart` and `edit_expense_sheet.dart`).

**`expense_provider.dart` also uses `tripLogisticsParticipantsProvider`:**
Grep shows `expense_provider.dart:211` uses `tripLogisticsParticipantsProvider(tripId).future`. That file must also be audited and updated if it serves the custom split flow.

**Test pattern (D-10):** Override `eventLogisticsParticipantsProvider(testEvent)` with a list containing 2+ participants. Verify that when `ExpenseScope.custom` is selected, the participant list is non-empty.

### Fix #2: Settle-up Event Name Labels

**Root cause:** `_buildPerEventBreakdown()` (line 592 in `group_settle_up_screen.dart`) iterates over `allEventIds` from `balancesData.perEventBreakdown` but only has eventId strings. It calls `_shortEventLabel(eventId)` which returns `'Event …{last6chars}'`.

**What's needed:** An `eventId → {name, type, date}` lookup. The source of truth is `groupEventsProvider(groupId)` which is already available in scope (the screen already receives `groupId`).

**Two approaches (Claude's discretion):**

Option A — Watch provider inside screen:
```dart
// Inside _GroupSettleUpScreenState.build():
final eventsAsync = ref.watch(groupEventsProvider(widget.groupId));
final eventNameMap = {
  for (final e in eventsAsync.valueOrNull ?? <Event>[])
    e.id: (name: e.name, type: e.type, date: e.startDate ?? e.createdAt)
};
// Pass eventNameMap down to _buildPerEventBreakdown
```

Option B — Prop drill from build to `_buildPerEventBreakdown`:
`build()` → `_buildContent()` → `_buildSettlementTile()` → `_buildPerEventBreakdown()`

Both are valid. Option A is slightly less invasive to method signatures. The screen is already a `ConsumerStatefulWidget` so `ref.watch` is available in `build()`.

**Label format (D-01, D-04):** `"Camping Weekend — Mar 15"` (name ≤ 30 chars) or `"Camping Weekend th… — Mar 15"` (name > 30 chars; truncate with ellipsis). Fallback chain: event name → event type display name → never reaches "unknown".

**Date formatting:** `AppFormatters` currently has `formatRelativeDate` but no short month+day formatter. The required format is "Mar 15" (abbreviated month, day, no year). Options:
- Add `formatShortMonthDay(DateTime)` to `AppFormatters` — consistent with project patterns, easily testable
- Inline: `'${_monthAbbr[date.month - 1]} ${date.day}'` with a const list — lighter but scattered

Recommendation: add to `AppFormatters` (aligns with project pattern of centralizing formatters, and is required by D-08 for unit test coverage).

**Test pattern (D-09):**
- Happy path: `perEventBreakdown` contains real eventId, `groupEventsProvider` returns event with matching id → label renders "Camping Weekend — Mar 15"
- Fallback: `perEventBreakdown` contains eventId with no matching event in provider → label renders event type fallback (e.g., "Trip")

### Fix #3: BalanceCacheRepository Column Naming Comment

**Root cause:** `BalanceCacheRepository.cacheExpenses()` writes `'trip_id': expense.tripId` into the SQLite `expenses` table (line 67). For Firestore-only events, `expense.tripId` IS the eventId (the Expense model uses `tripId` as its field name, populated from Firestore's `eventId`). The column is named `trip_id` in the SQLite schema but stores eventId values. This works at runtime but is a cognitive trap for future readers.

**Audit findings (D-06):**

Reviewing `BalanceCacheRepository` and `CacheService`:

1. `BalanceCacheRepository.cacheExpenses()` — writes `'trip_id': expense.tripId` (line 67). Comment needed: `// NOTE: column 'trip_id' stores the Firestore eventId. The Expense model uses tripId as its field name; for Firestore-only events this value is the event document ID.`

2. `BalanceCacheRepository.getExpenses()` — queries `WHERE trip_id = ?` with `eventId` arg (line 128). Comment needed at the WHERE clause.

3. `BalanceCacheRepository.cacheSettlements()` — writes `'trip_id': s.tripId` (line 103). Same pattern, same comment needed.

4. `BalanceCacheRepository.getSettlements()` — queries `WHERE trip_id = ?` (line 162). Comment needed.

5. `CacheService.cacheExpenses()` (line 93) — same `'trip_id': expense.tripId` pattern. Same comment.

6. `CacheService.getCachedExpenses()` (line 123) — same WHERE clause. Same comment.

7. `CacheService.cacheSettlements()` (line 157) — same pattern.

8. `CacheService.getCachedSettlements()` (line 183) — same pattern.

**None require logic changes.** All are comment-only fixes. The SQLite schema migration decision (D-05) explicitly rules out renaming the column.

**Test pattern (D-08):** Existing `balance_cache_repository_test.dart` already covers `cacheExpenses/getExpenses`. The test uses `tripId: 'trip-1'` as the key and the fix doesn't change behavior — no new test logic needed for Fix #3 itself. The test is already passing and will remain so.

---

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Short month+day formatting | Custom date parsing | `AppFormatters.formatShortMonthDay()` (new method, 3 lines) | Project pattern for all formatting lives in AppFormatters; testable in isolation |
| Event name lookup | Map-building in widget method | Watch `groupEventsProvider(widget.groupId).valueOrNull` | Provider is already in scope; no extra network call — Firestore offline cache serves it |
| Participant list for custom splits | Re-querying SQLite | `eventLogisticsParticipantsProvider(event)` | Already exists, derives from Event Firestore doc, zero SQL overhead |

---

## Common Pitfalls

### Pitfall 1: SplitScopeSelector loses Event context
**What goes wrong:** `SplitScopeSelector` currently takes `tripId: String`. If the planner changes it to take `event: Event`, the caller (`add_expense_screen.dart`) must pass the full Event object. `AddExpenseScreen` currently receives `groupId` and `eventId` as constructor params but not `Event`. Fetching the Event requires watching `eventDetailProvider((groupId: widget.groupId, eventId: widget.eventId))`.
**Why it happens:** The screen was designed before the EventRef migration that replaced trip objects with Firestore events.
**How to avoid:** Add a `ref.watch(eventDetailProvider(...))` at the top of `AddExpenseScreen.build()`. Handle the `AsyncValue` states (loading/error). Pass `event` to `SplitScopeSelector` only when data is available.
**Warning signs:** If you see `null` participant list in custom split even after the fix, the event object is likely null/loading.

### Pitfall 2: edit_expense_sheet.dart custom participant selector is already broken differently
**What goes wrong:** `EditExpenseSheet._buildScopeSection()` already passes `AsyncValue.data(const <Participant>[])` as `participantsAsync` to `_buildCustomParticipantSelector()` (line 203-204). This is intentionally empty with a comment "scope editing can still change the scope type." The payer dropdown at line 361 reads `tripLogisticsParticipantsProvider(widget.eventId)`.
**Why it happens:** Edit sheet had a partial fix during the Firestore migration. The custom participant selector was left intentionally empty; the payer dropdown was not.
**How to avoid:** Fix only the payer dropdown in `_buildPayerSelector()`. The custom participant section in edit sheet may require a separate design decision if it should also show participants — but this is NOT in scope for Phase 8. Fix only the stated broken behavior (FIN-04, EVT-08).

### Pitfall 3: groupEventsProvider may emit loading while perEventBreakdown has data
**What goes wrong:** `_buildPerEventBreakdown` runs whenever `_buildSettlementTile` is called. If `groupEventsProvider` is still loading, the event name map is empty and all labels fall back to event type. This is correct fallback behavior per D-02, but the screen may briefly show fallback labels before updating to real names.
**Why it happens:** Riverpod stream providers emit loading before data.
**How to avoid:** Use `groupEventsProvider(widget.groupId).valueOrNull ?? []` — returns empty list when loading, which triggers the fallback labels. When data arrives, `ref.watch` causes rebuild and real names appear. This is acceptable UX.

### Pitfall 4: Existing test for GroupSettleUpScreen uses `perEventBreakdown` with eventId keys
**What goes wrong:** `group_settle_up_screen_test.dart` uses `perEventBreakdown: {'uid-alice': {'event-1': ...}}` where `'event-1'` is the eventId. After the fix, `_buildPerEventBreakdown` looks up `'event-1'` in the event name map. The existing tests do NOT override `groupEventsProvider`, so the map will be empty and the fallback will render.
**Why it happens:** Tests only override `groupBalancesProvider`, not `groupEventsProvider`.
**How to avoid:** The existing tests remain valid — they test the fallback path. New tests (D-09) must add `groupEventsProvider(groupId)` to the override list to test the happy path where event names actually appear.

### Pitfall 5: `expense_provider.dart` also calls `tripLogisticsParticipantsProvider`
**What goes wrong:** `lib/features/ledger/providers/expense_provider.dart:211` uses `tripLogisticsParticipantsProvider(tripId).future`. If this is in a code path involved in custom split validation or submission, failing to update it leaves a latent bug.
**Why it happens:** The Firestore migration preserved the old provider call as a shim.
**How to avoid:** Read `expense_provider.dart` at the relevant line during implementation to determine whether this call is in an active code path and whether it should also be updated.

---

## Code Examples

### eventLogisticsParticipantsProvider signature (verified from source)
```dart
// Source: lib/features/logistics/providers/sub_group_provider.dart:57
final eventLogisticsParticipantsProvider =
    Provider.family<List<Participant>, Event>((ref, event) {
  return event.participantIds.map((id) {
    return Participant(
      id: id,
      tripId: event.id,
      role: ParticipantRole.member,
      joinedAt: event.createdAt,
      displayName: event.participantNames[id],
      avatarUrl: null,
    );
  }).toList();
});
```

Note: Returns `List<Participant>` directly (not `AsyncValue` or `Stream`). The provider type is `Provider.family`, not `StreamProvider.family`. This is important for how it is consumed: `ref.watch(eventLogisticsParticipantsProvider(event))` returns `List<Participant>` directly, not wrapped in `AsyncValue`.

### groupEventsProvider signature (verified from source)
```dart
// Source: lib/features/events/providers/event_provider.dart:37
final groupEventsProvider =
    StreamProvider.family<List<Event>, String>((ref, groupId) { ... });
```

Usage for event name lookup in GroupSettleUpScreen:
```dart
// Inside build() or passed down as parameter
final events = ref.watch(groupEventsProvider(widget.groupId)).valueOrNull ?? [];
final eventNameMap = <String, ({String name, EventType type, DateTime date})>{
  for (final e in events)
    e.id: (name: e.name, type: e.type, date: e.startDate ?? e.createdAt),
};
```

### Short month+day formatter (to be added to AppFormatters)
```dart
// Proposed addition to lib/core/utils/formatters.dart
static const _monthAbbr = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];

/// Format a date as "Mar 15" (short month + day, no year).
static String formatShortMonthDay(DateTime date) {
  return '${_monthAbbr[date.month - 1]} ${date.day}';
}
```

### Event name label construction (D-01, D-02, D-04)
```dart
String _buildEventLabel(String eventId, Map<String, ({String name, EventType type, DateTime date})> eventMap) {
  final entry = eventMap[eventId];
  if (entry == null) {
    // D-02 fallback: should not happen given model constraints,
    // but return empty string to suppress the breakdown line entirely
    return '';
  }
  final name = entry.name.length > 30
      ? '${entry.name.substring(0, 27)}...'
      : entry.name;
  final date = AppFormatters.formatShortMonthDay(entry.date);
  return '$name — $date';
}
```

### Column naming comment pattern (D-05)
```dart
// In BalanceCacheRepository.cacheExpenses():
batch.insert(
  'expenses',
  {
    'id': expense.id,
    // NOTE: The SQLite column is named 'trip_id' for historical reasons.
    // For Firestore-only events this value is the Firestore event document ID.
    // Do NOT rename this column without a SQLite schema migration (version bump
    // in LocalDatabase._createDb and a corresponding migration in _onUpgrade).
    'trip_id': expense.tripId,
    ...
  },
  conflictAlgorithm: ConflictAlgorithm.replace,
);
```

---

## Runtime State Inventory

Step 2.5 is SKIPPED. Phase 8 involves no rename, no rebrand, no string replacement, and no data migration. The column naming fix is code-comment-only with no schema change. No runtime state is mutated.

---

## Environment Availability

Step 2.6: Phase 8 is purely code/logic changes within the Flutter app. No external services, CLI tools, or databases beyond the project's existing dependencies.

Flutter and Dart are verified to be present (the project has been actively built through Phase 7). No new tools required.

---

## Validation Architecture

### Test Framework
| Property | Value |
|----------|-------|
| Framework | flutter_test (built-in with Flutter SDK) |
| Config file | none — standard `flutter test` discovery |
| Quick run command | `flutter test test/unit/balance_cache_repository_test.dart test/features/groups/group_settle_up_screen_test.dart` |
| Full suite command | `flutter test` |

### Phase Requirements → Test Map
| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| EVT-08 (Fix #1) | `ExpenseScope.custom` returns non-empty participant list using event data | unit/provider | `flutter test test/unit/provider_swap_test.dart -x` | Wave 0 |
| FIN-04 (Fix #2 happy) | Per-event breakdown shows "Camping — Mar 15" format | widget | `flutter test test/features/groups/group_settle_up_screen_test.dart -x` | Exists (extend) |
| FIN-04 (Fix #2 fallback) | When event not found, shows event type fallback | widget | `flutter test test/features/groups/group_settle_up_screen_test.dart -x` | Exists (extend) |
| D-05 (Fix #3) | `cacheExpenses` column comment present; behavior unchanged | unit | `flutter test test/unit/balance_cache_repository_test.dart -x` | Exists (passes as-is) |
| AppFormatters | `formatShortMonthDay` returns "Mar 15" for March 15 input | unit | `flutter test test/unit/formatters_test.dart -x` | Exists (extend) |

### Sampling Rate
- **Per task commit:** `flutter test test/unit/ -x` (fast, catches regressions in unit layer)
- **Per wave merge:** `flutter test` (full suite)
- **Phase gate:** Full suite green before `/gsd:verify-work`

### Wave 0 Gaps
- [ ] `test/unit/provider_swap_test.dart` — covers EVT-08 / Fix #1: provider swap returns non-empty participants for Firestore-only event
- [ ] `test/unit/formatters_test.dart` — extend existing file with `formatShortMonthDay` test cases
- [ ] `test/features/groups/group_settle_up_screen_test.dart` — extend existing file with two new test cases: happy path (event name + date) and fallback (event type)

*(Existing `balance_cache_repository_test.dart` already covers Fix #3 behavior — no gap there.)*

---

## Open Questions

1. **`expense_provider.dart:211` usage of `tripLogisticsParticipantsProvider`**
   - What we know: Grep shows it is used in expense_provider.dart at line 211
   - What's unclear: Whether this code path is active for custom splits and whether it needs updating
   - Recommendation: Read the surrounding context in expense_provider.dart during Wave 1 implementation; update if in the custom split validation path

2. **`SplitScopeSelector` constructor change scope**
   - What we know: The current `tripId: String` param must become something that can source an `Event` object
   - What's unclear: Whether to pass `Event` directly or to pass `groupId`+`eventId` and watch `eventDetailProvider` inside the widget
   - Recommendation: Pass `Event` directly from the caller (add_expense_screen.dart and edit_expense_sheet.dart already have access to groupId/eventId and can watch eventDetailProvider). This is cleaner than having the selector widget own the Firestore fetch.

3. **`_PayerSelector` in `edit_expense_sheet.dart` — should it also get participants from Event?**
   - What we know: `_buildPayerSelector` (edit sheet line 351) uses `tripLogisticsParticipantsProvider` to populate the payer dropdown. This is a different class from `_PayerSelector` in `split_scope_selector.dart`.
   - What's unclear: Is this a duplicate fix or is edit_expense_sheet's payer selector expected to remain broken?
   - Recommendation: Fix it — it is the same bug (SQLite participants not populated for Firestore-only events). Both payer selectors should use the Event-sourced participant list.

---

## Sources

### Primary (HIGH confidence)
- Direct code inspection of all 7 canonical reference files listed in CONTEXT.md
- `lib/features/trip/providers/trip_provider.dart` — `tripLogisticsParticipantsProvider` reads SQLite, confirmed deprecated
- `lib/features/logistics/providers/sub_group_provider.dart` — `eventLogisticsParticipantsProvider` derives from Event object, confirmed correct provider
- `lib/features/ledger/widgets/split_scope_selector.dart` — confirmed two usages of wrong provider (lines 194, 387)
- `lib/features/ledger/screens/add_expense_screen.dart` — confirmed one usage of wrong provider in debug block (line 185)
- `lib/features/ledger/screens/edit_expense_sheet.dart` — confirmed one usage in `_buildPayerSelector` (line 361), custom participant selector already passes empty list
- `lib/features/groups/screens/group_settle_up_screen.dart` — confirmed `_shortEventLabel()` at line 626 using last-6-chars-of-eventId pattern
- `lib/core/services/balance_cache_repository.dart` — confirmed `'trip_id': expense.tripId` at line 67, and four total sites requiring comments
- `lib/core/services/cache_service.dart` — confirmed four additional `trip_id` column usage sites in `cacheExpenses`, `getCachedExpenses`, `cacheSettlements`, `getCachedSettlements`
- `lib/core/utils/formatters.dart` — confirmed no short month+day formatter exists; `formatRelativeDate` exists but does not meet D-04 requirements
- `lib/features/events/providers/event_provider.dart` — `groupEventsProvider` confirmed available and returns `List<Event>` with `name`, `type`, `startDate`, `createdAt` fields
- `lib/features/events/models/event_model.dart` — `Event` model confirmed with `participantIds: List<String>` and `participantNames: Map<String, String>` — exactly what `eventLogisticsParticipantsProvider` iterates
- `.planning/v1.0-MILESTONE-AUDIT.md` — confirms all three issues and severity ratings
- `test/unit/balance_cache_repository_test.dart` — existing test infrastructure confirmed, uses sqflite_common_ffi
- `test/features/groups/group_settle_up_screen_test.dart` — existing widget tests confirmed; need to extend for new label assertions

### Secondary (MEDIUM confidence)
- None — all findings are from direct source inspection, no external sources consulted

### Tertiary (LOW confidence)
- None

---

## Metadata

**Confidence breakdown:**
- Fix #1 (provider swap): HIGH — source confirmed, provider signatures confirmed, affected files confirmed
- Fix #2 (event name labels): HIGH — current broken code confirmed, correct data source confirmed, format requirements from CONTEXT.md
- Fix #3 (column naming): HIGH — all 8 affected sites confirmed by code inspection; no logic change, comment-only

**Research date:** 2026-03-27
**Valid until:** Stable — these are code-only fixes in a stable codebase; no external dependencies or moving ecosystem targets
