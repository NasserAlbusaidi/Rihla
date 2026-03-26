# Phase 5: Cross-Event Financials - Context

**Gathered:** 2026-03-27
**Status:** Ready for planning

<domain>
## Phase Boundary

The group dashboard shows live running balances across all events. Users can see what they owe per event or in total across the group. Cross-event settle-up works with optimized minimum transactions. Group dashboard shows spending stats and an activity log. Per-event ledger screen remains event-scoped and unchanged.

</domain>

<decisions>
## Implementation Decisions

### Group Balance Aggregation
- **D-01:** On-demand rollup: when user opens group dashboard, compute group balances from all events' expenses/settlements via Firestore streams. No cached group_ledger rows — always fresh.
- **D-02:** Group balances include ALL events always, regardless of per-event settlement status. Running total that only changes when new expenses/settlements are added.
- **D-03:** Skip the `group_ledger` SQLite table entirely. On-demand rollup reads from existing Firestore expense/settlement streams (which side-write to SQLite for BalanceCalculator). The group_ledger table is dead weight — no writes, no reads.
- **D-04:** Firebase UID matching for participant identity across events. Same UID = same person. Works because group memberIds and event participantIds are both UIDs.
- **D-05:** New `groupBalancesProvider` (Riverpod provider) that watches all events in a group, reads per-event expenses/settlements, and runs BalanceCalculator across the combined dataset. BalanceCalculator stays pure — it doesn't need to know about groups.
- **D-06:** Watch all event streams, compute lazily. For typical groups (5-15 events, ~30 expenses each), BalanceCalculator runs in <10ms — pure in-memory math on lists. No performance concern.

### Group-Level Settlements
- **D-07:** New Firestore subcollection: `groups/{groupId}/settlements/{id}`. Cross-event settlements live at the group level, separate from per-event settlements.
- **D-08:** Security rules: any group member can read/write group settlements. Same trust model as event-level data (Phase 4 D-11).
- **D-09:** Group-level settlements are independent of per-event balances. A group settlement reduces the GROUP balance between two people but doesn't change any individual event's balance view.
- **D-10:** Reuse existing `Settlement` model with a `scope` field: `'event'` or `'group'`. Group settlements have `groupId` but no `eventId`. BalanceCalculator treats them the same way.
- **D-11:** Partial settlements supported — suggested amount is pre-filled but user can edit to settle partially.
- **D-12:** Optional note/description field on group settlements, matching existing event SettleUpScreen pattern.

### Balance Toggle UX
- **D-13:** Group dashboard with drill-down approach: GroupDetailScreen shows group-level balances by default. Tapping a member's balance expands to show per-event breakdown. No toggle on per-event ledger screen.
- **D-14:** Per-event breakdown shows: event name + net amount per event ("Camping: +10.500 OMR"). Tapping an event row navigates to that event's full LedgerScreen.
- **D-15:** Balances section integrated into GroupDetailScreen as a section in the scrollable view — not a separate screen or tab.

### Member Balance Cards
- **D-16:** Each member shows: name, net amount (green if owed money, red if owes), expand arrow for per-event breakdown. Color scheme: green = owed to you, red = you owe — standard financial convention.
- **D-17:** Hero balance card at top of balances section showing current user's net position ("You owe 15.500 OMR" or "You are owed 8.200 OMR") with 'Settle up' CTA button. Mirrors existing event expense summary hero.
- **D-18:** Zero-balance members shown with neutral gray 'Settled' badge. Not hidden — the full member list is always visible.
- **D-19:** Hero card hidden until first expense exists in any event. Stats chips also hidden until there's data. Avoids confusing zero-state cards.
- **D-20:** Members at zero balances section shows all members with '0.000 OMR' and 'Settled' badge when events exist but no expenses.
- **D-21:** Settle-up CTA disabled with "All settled! No outstanding balances." when current user's net balance is zero.

### Cross-Event Settle-Up Flow
- **D-22:** Two entry points: (1) 'Settle up' button on hero card — shows all optimized debts, (2) Tap any member's balance card to settle with just that person. Both navigate to GroupSettleUpScreen.
- **D-23:** New `GroupSettleUpScreen` — shows optimized settlements across ALL events using `BalanceCalculator.calculateOptimalSettlements` with group-level balances. Separate from existing per-event SettleUpScreen.
- **D-24:** Each settlement card shows pairwise amount with expandable per-event breakdown ("Ahmed -> Nasser: 15.500 OMR" with "Camping: 10.000, Dinner: 5.500" detail). 'Record settlement' button per card.
- **D-25:** Optimized settlements shown by default (minimum transactions via greedy algorithm). No raw/simplified toggle.
- **D-26:** Success confirmation dialog: "Settlement recorded. Ahmed now owes Nasser 0.000 OMR." Shows updated balance, auto-dismisses or tap to close.

### Group Dashboard Layout
- **D-27:** Section order from top to bottom: (1) Hero balance card with settle-up CTA, (2) Spending stats chips, (3) Member balances with expandable per-event breakdown, (4) Events timeline, (5) Invite code, (6) Recent activity with 'see all'.
- **D-28:** Spending stats: header stat "Total: 245.500 OMR across 4 events" + horizontal chips showing top spenders with contribution %. No charts — text and chips only.
- **D-29:** Existing members section merges with balances section. Each member tile shows name AND net balance. Member count moves to section header.
- **D-30:** Invite code section moves below events (less important once group is active). Financial sections take priority position.

### Group Activity Log
- **D-31:** Group-level events only: event created, event deleted, group settlement recorded, member joined group, member left group. 5 action types. NOT individual expenses.
- **D-32:** Activity stored in Firestore subcollection: `groups/{groupId}/activity/{activityId}`. Each entry: type, actorId, actorName, description, metadata (eventId, amount, etc.), timestamp.
- **D-33:** Client-side fire-and-forget writes. When a group action happens, client writes an activity document. No Cloud Functions needed. Same pattern as existing event activity logs.
- **D-34:** Dashboard shows 5 most recent activities. 'See all' navigates to full-screen activity list loading 50 entries at a time with Firestore cursor pagination.
- **D-35:** All group settlements visible in activity log to all group members ("Ahmed settled 15.500 OMR with Nasser").

### Offline Behavior
- **D-36:** Firestore offline persistence serves last-fetched snapshots when offline. groupBalancesProvider watches Firestore streams which serve cached data offline. Same transparent behavior as event-level data.
- **D-37:** Users can record group settlements while offline. Firestore queues the write. Optimistic UI shows it immediately. Consistent with Phase 4 offline behavior.

### Navigation
- **D-38:** GroupSettleUpScreen and full activity log pushed via Navigator.push with AppPageRoute from GroupDetailScreen. No new GoRouter routes.
- **D-39:** Per-event drill-down: tapping "Camping: +10.500" pushes LedgerScreen(event: campingEvent, group: group) directly via Navigator.push. Back returns to group detail.

### Testing Strategy
- **D-40:** Priority 1: unit tests for BalanceCalculator with cross-event data (multiple events' expenses combined). Priority 2: groupBalancesProvider with FakeFirebaseFirestore. Priority 3: GroupSettleUpScreen widget test. Phase 6 handles full coverage.
- **D-41:** Layered test approach: service tests use FakeFirebaseFirestore, provider tests use mock services, widget tests use overridden providers. Same approach as Phase 4.

### Claude's Discretion
- GroupSettleUpScreen layout and visual design
- Activity log entry format and display styling
- Hero balance card visual design (gradients, shadows, typography)
- Member balance card expand/collapse animation
- Per-event breakdown row styling
- Spending stats chip layout and styling
- Activity log full-screen list layout
- Error handling for failed group settlement writes
- GroupActivityService implementation details
- groupBalancesProvider stream composition (how to combine multiple event streams)

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Financial requirements
- `.planning/REQUIREMENTS.md` lines 39-47 — FIN-01 through FIN-07 acceptance criteria
- `.planning/REQUIREMENTS.md` lines 23-24 — GRP-04 (group dashboard) and GRP-05 (group activity log)
- `.planning/ROADMAP.md` Phase 5 section — success criteria and requirement mapping

### Phase 4 decisions (Firestore repository pattern)
- `.planning/phases/04-firestore-repository-layer/04-CONTEXT.md` — FirestoreRepository base class (D-05), provider migration to Firestore streams (D-13), SQLite retained for BalanceCalculator (D-14/D-15), security rules pattern (D-11)

### Existing financial code
- `lib/features/ledger/providers/expense_provider.dart` — eventExpensesProvider, eventSettlementsProvider, eventBalancesProvider, BalanceCalculator (calculateBalances + calculateOptimalSettlements)
- `lib/core/services/balance_cache_repository.dart` — BalanceCacheRepository with SQLite side-write pattern
- `lib/features/ledger/screens/settle_up_screen.dart` — Existing per-event SettleUpScreen (pattern for GroupSettleUpScreen)
- `lib/features/ledger/screens/ledger_screen.dart` — LedgerScreen (navigation target for per-event drill-down)

### Group code (to be extended)
- `lib/features/groups/screens/group_detail_screen.dart` — GroupDetailScreen (receives new financial sections)
- `lib/features/groups/providers/group_provider.dart` — groupDetailProvider, groupMembersProvider patterns
- `lib/features/groups/models/group_model.dart` — Group model with Firestore + SQLite serialization

### Event code (read for aggregation)
- `lib/features/events/providers/event_provider.dart` — groupEventsProvider (list of events per group)
- `lib/features/events/models/event_model.dart` — Event model with participantIds, participantNames

### Phase 1 decisions (money serialization)
- `.planning/phases/01-data-foundation/1-CONTEXT.md` — MoneySerializer (D-01..D-04), integer fils in Firestore, Decimal at boundary

### Security rules
- `security/firestore.rules` — Existing rules for groups, events, and module subcollections (extend for group settlements and activity)

### SQLite schema
- `lib/core/services/local_database.dart` — group_ledger table schema (exists but will not be used per D-03)

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `BalanceCalculator` — Pure function for balance computation and settlement optimization. Reuse directly for group-level aggregation by combining expenses/settlements from all events.
- `eventExpensesProvider` / `eventSettlementsProvider` — Firestore-backed streams with SQLite side-write. groupBalancesProvider will watch these for each event.
- `eventBalancesProvider` — Pattern for deriving balances from event data + Firestore streams. Mirror for group-level.
- `SettleUpScreen` — UI pattern for settlement optimization display. Clone and adapt for GroupSettleUpScreen.
- `ModuleHeader` — Dark gradient header, already used in GroupDetailScreen.
- `EmptyStateView` — Consistent empty states with optional CTA.
- `GroupMemberTile` — Member list tile, to be extended with balance display.
- `AppPageRoute` — Slide-right navigation transitions.
- Spending stats chips pattern already exists in GroupDetailScreen header.

### Established Patterns
- `StreamProvider.family` for reactive Firestore data — use for group settlements and activity streams
- `Provider.family` for derived computations — use for groupBalancesProvider
- Feature-first directory structure — new files in `lib/features/groups/` and `lib/features/ledger/`
- Navigator.push for sub-screens from group detail
- Fire-and-forget activity logging (existing event activity pattern)
- FakeFirebaseFirestore for service tests, provider overrides for widget tests

### Integration Points
- `GroupDetailScreen` — receives new sections (hero, stats, balances, activity)
- `GroupMemberTile` — extends to show balance alongside name
- `eventExpensesProvider` / `eventSettlementsProvider` — watched by new groupBalancesProvider
- `groupEventsProvider` — provides list of events to iterate for balance aggregation
- `security/firestore.rules` — new rules for `groups/{groupId}/settlements` and `groups/{groupId}/activity`
- `Settlement` model — add scope field (`event` | `group`)

</code_context>

<specifics>
## Specific Ideas

- The hero balance card with "Settle up" CTA mirrors the event expense summary hero in EventCommandCenter — consistent financial UX across event and group levels.
- Per-event breakdown on member balance cards is the key UX differentiator: "you still owe me from 3 trips ago" becomes visible and actionable.
- Group settlements as a separate Firestore subcollection (not tagged on events) keeps the data model clean — a group settlement is a group concept, not an event concept.
- The merged members/balances section eliminates a redundant section and puts financial data front-and-center, reflecting the app's core value proposition.

</specifics>

<deferred>
## Deferred Ideas

- Multi-currency aggregation across events — events can have different currencies, but group-level currency conversion is out of Phase 5 scope. Group balances assume same currency (OMR) across all events for now.
- Financial milestone celebrations in activity log ("Group total crossed 500 OMR") — nice-to-have but adds milestone detection complexity.
- Spending charts/graphs on group dashboard — no chart packages for now, text and chips suffice.
- Comprehensive activity logging (settings changes, invite code regeneration) — keep to 5 core action types.
- Export group financial summary as PDF — ENH-05 in REQUIREMENTS.md, separate milestone.

</deferred>

---

*Phase: 05-cross-event-financials*
*Context gathered: 2026-03-27*
