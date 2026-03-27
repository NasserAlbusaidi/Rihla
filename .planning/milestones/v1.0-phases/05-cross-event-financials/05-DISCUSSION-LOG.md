# Phase 5: Cross-Event Financials - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-03-27
**Phase:** 05-cross-event-financials
**Areas discussed:** Group balance aggregation, Balance toggle UX, Cross-event settle-up flow, Group dashboard & activity, Offline behavior, Empty states, Activity log triggers, Testing strategy, Performance edge cases, Navigation and deep linking

---

## Group Balance Aggregation

| Option | Description | Selected |
|--------|-------------|----------|
| On-demand rollup | Query all events' expenses/settlements from Firestore streams and run BalanceCalculator across combined set. No cached rows. | ✓ |
| Cached group_ledger rows | Maintain running totals in group_ledger SQLite table. Update via side-write on Firestore listener fire. | |
| Hybrid: cache + invalidate | Cache group_ledger rows, invalidate and recompute when any event stream emits. | |

**User's choice:** On-demand rollup
**Notes:** Simple, always fresh, no staleness bugs. Fine for typical 5-15 events per group.

| Option | Description | Selected |
|--------|-------------|----------|
| All events always | Sum across every event regardless of settlement status. | ✓ |
| Only events with outstanding balances | Exclude settled events. | |

**User's choice:** All events always
**Notes:** Simple mental model — running total.

| Option | Description | Selected |
|--------|-------------|----------|
| Skip group_ledger entirely | On-demand rollup reads from existing expense/settlement data. Table is dead weight. | ✓ |
| Populate group_ledger as cache | Write rollup results for faster subsequent reads. | |
| Use group_ledger for offline snapshot | Populate on rollup for offline last-known balances. | |

**User's choice:** Skip group_ledger entirely

| Option | Description | Selected |
|--------|-------------|----------|
| Same as event modules | Any group member can read/write group settlements. | ✓ |
| Only involved parties | Only payer or recipient can create/modify. | |

**User's choice:** Same as event modules

| Option | Description | Selected |
|--------|-------------|----------|
| Firebase UID matching | Match by Firebase anonymous UID across events. | ✓ |
| Display name matching | Match by name string (fragile). | |
| Group member ID mapping | Explicit UID-to-member mapping. | |

**User's choice:** Firebase UID matching

| Option | Description | Selected |
|--------|-------------|----------|
| New groupBalancesProvider | New Riverpod provider, keeps BalanceCalculator pure. | ✓ |
| Extend BalanceCalculator | Add static method for group balance computation. | |

**User's choice:** New groupBalancesProvider

| Option | Description | Selected |
|--------|-------------|----------|
| Watch all event streams | Firestore listeners already active. Lightweight for typical groups. | ✓ |
| Batch SQLite query | Single query, loses real-time reactivity. | |
| Paginated/lazy loading | Over-engineered for typical group sizes. | |

**User's choice:** Watch all event streams

| Option | Description | Selected |
|--------|-------------|----------|
| No — independent | Group settlement doesn't change per-event balance views. | ✓ |
| Yes — distribute proportionally | Complex, harder to reason about. | |

**User's choice:** No — they're independent

---

## Balance Toggle UX

| Option | Description | Selected |
|--------|-------------|----------|
| Group dashboard with drill-down | Group detail shows group-level balances, tap to expand per-event breakdown. | ✓ |
| Tab bar on ledger screen | 'This Event' / 'All Events' tabs. | |
| Segmented control on dashboard | 'Group Totals' / 'By Event' toggle. | |

**User's choice:** Group dashboard with drill-down

| Option | Description | Selected |
|--------|-------------|----------|
| Event name + net amount per event | "Camping: +10.500 OMR". Tap navigates to event ledger. | ✓ |
| Full expense list across events | All expenses involving that member. Overwhelming. | |
| Summary cards per event | Mini balance cards per event. Takes more space. | |

**User's choice:** Event name + net amount per event

| Option | Description | Selected |
|--------|-------------|----------|
| Integrated into GroupDetailScreen | Add sections to existing group detail scroll view. | ✓ |
| New GroupFinancialsScreen | Separate screen via nav button. | |
| Bottom sheet overlay | Draggable sheet on group detail. | |

**User's choice:** Integrated into GroupDetailScreen

| Option | Description | Selected |
|--------|-------------|----------|
| Colored net balance with name | Green/red net amount, expand arrow for breakdown. | ✓ |
| Pairwise debts only | Who-owes-whom after optimization. | |
| Both views with toggle | Segmented control for both views. | |

**User's choice:** Colored net balance with name

| Option | Description | Selected |
|--------|-------------|----------|
| Event's ledger screen | Push LedgerScreen directly. | ✓ |
| Inline expense list | Expand further without navigating. | |
| Event command center | Full event hub (overkill). | |

**User's choice:** Event's ledger screen

| Option | Description | Selected |
|--------|-------------|----------|
| Yes — hero card at top | Prominent card with settle-up CTA. | ✓ |
| Inline with others | Highlighted in regular list. | |
| Floating summary bar | Sticky bar at bottom. | |

**User's choice:** Yes — hero card at top

| Option | Description | Selected |
|--------|-------------|----------|
| Green = owed, Red = you owe | Standard financial convention. | ✓ |
| Neutral colors with icons | Accessible but less intuitive. | |

**User's choice:** Green = owed to you, Red = you owe

| Option | Description | Selected |
|--------|-------------|----------|
| Show with 'settled' label | Gray badge, still visible. | ✓ |
| Hide zero-balance members | Only show active balances. | |
| Separate section | Collapsed 'Settled' section. | |

**User's choice:** Show with 'settled' label

| Option | Description | Selected |
|--------|-------------|----------|
| Yes — total spent header | "Total spent: 245.500 OMR across 4 events". | ✓ |
| No — balances only | Total shown elsewhere. | |

**User's choice:** Yes — total spent header

---

## Cross-Event Settle-Up Flow

| Option | Description | Selected |
|--------|-------------|----------|
| Group-level subcollection | groups/{groupId}/settlements/{id}. Separate from event settlements. | ✓ |
| Tag on event settlements | Record in a designated event with crossEvent flag. | |

**User's choice:** Group-level subcollection

| Option | Description | Selected |
|--------|-------------|----------|
| Hero card CTA + member tap | Two entry points to settle-up. | ✓ |
| Dedicated screen only | Single button in header. | |
| Inline settle actions | Per-card settle buttons, no separate screen. | |

**User's choice:** Hero card CTA + member tap

| Option | Description | Selected |
|--------|-------------|----------|
| New GroupSettleUpScreen | Group-context settle screen using calculateOptimalSettlements. | ✓ |
| Reuse SettleUpScreen with mode | Flag to switch modes. Mixes data sources. | |

**User's choice:** New GroupSettleUpScreen

| Option | Description | Selected |
|--------|-------------|----------|
| Card with event breakdown | Expandable per-event detail. Record button per card. | ✓ |
| Simple pairwise cards | Amount only, no breakdown. | |
| Settlement summary with one-tap | Batch settle-all option. | |

**User's choice:** Card with event breakdown

| Option | Description | Selected |
|--------|-------------|----------|
| Success dialog with updated balance | Shows new net balance, auto-dismisses. | ✓ |
| Inline card update | Card animates away. | |
| Toast notification | Brief toast. | |

**User's choice:** Success dialog with updated balance

| Option | Description | Selected |
|--------|-------------|----------|
| Yes — editable amount | Pre-filled but editable for partial settlement. | ✓ |
| Full amount only | Must settle full suggested amount. | |

**User's choice:** Yes — editable amount

| Option | Description | Selected |
|--------|-------------|----------|
| Optional note field | Matches existing event settlement pattern. | ✓ |
| No notes | Just amount and participants. | |

**User's choice:** Optional note field

| Option | Description | Selected |
|--------|-------------|----------|
| Same Settlement model + scope field | 'event' or 'group' scope. Group settlements have groupId, no eventId. | ✓ |
| New GroupSettlement model | Separate model class. | |

**User's choice:** Same Settlement model + scope field

| Option | Description | Selected |
|--------|-------------|----------|
| Optimized by default | BalanceCalculator.calculateOptimalSettlements on group-level balances. | ✓ |
| Raw debts with optimize option | All debts first, toggle to optimize. | |

**User's choice:** Optimized by default

| Option | Description | Selected |
|--------|-------------|----------|
| Disabled settle button with message | "All settled! No outstanding balances." | ✓ |
| Empty settle-up screen | Navigate but show empty state. | |

**User's choice:** Disabled settle button with message

| Option | Description | Selected |
|--------|-------------|----------|
| Yes — always logged | All settlements visible in group activity. | ✓ |
| Only visible to involved parties | Private to payer and recipient. | |

**User's choice:** Yes — always logged

---

## Group Dashboard & Activity

| Option | Description | Selected |
|--------|-------------|----------|
| Sections in scroll view | Single scrollable view with ordered sections. | ✓ |
| Tabbed dashboard | Separate tabs for overview/financials/events/activity. | |
| Collapsible sections | Accordion-style sections. | |

**User's choice:** Sections in scroll view

| Option | Description | Selected |
|--------|-------------|----------|
| Total + per-member chips | Header stat + horizontal contribution % chips. No charts. | ✓ |
| Detailed breakdown cards | Per-member cards with full financial breakdown. | |
| Minimal — just the total | Only group total, detail in sub-view. | |

**User's choice:** Total + per-member chips

| Option | Description | Selected |
|--------|-------------|----------|
| Group-level events only | 5 core action types. High-signal. | ✓ |
| Everything including expenses | Group events + per-event expense summaries. | |
| Financial events only | Settlements and financial milestones only. | |

**User's choice:** Group-level events only

| Option | Description | Selected |
|--------|-------------|----------|
| Bottom section with 'see all' | 5 most recent, full-screen list on tap. | ✓ |
| Inline with events timeline | Interleaved chronological view. | |
| Separate Activity tab | Via header icon/tab. | |

**User's choice:** Bottom section with 'see all'

| Option | Description | Selected |
|--------|-------------|----------|
| Group subcollection | groups/{groupId}/activity/{activityId}. Standard subcollection. | ✓ |
| Denormalized on group document | Last N activities as array field. | |

**User's choice:** Group subcollection

| Option | Description | Selected |
|--------|-------------|----------|
| Merge — member rows show balance | Members section replaced with balance-enabled member list. | ✓ |
| Keep separate | Two separate sections. | |

**User's choice:** Merge — member rows show balance

| Option | Description | Selected |
|--------|-------------|----------|
| No charts — text and chips only | Clean, fast, no chart package dependency. | ✓ |
| Simple pie/donut chart | Visual distribution (requires fl_chart). | |

**User's choice:** No charts — text and chips only

| Option | Description | Selected |
|--------|-------------|----------|
| Move below events | Financial sections take priority at top. | ✓ |
| Keep at current position | Leave between header and members. | |

**User's choice:** Move below events

| Option | Description | Selected |
|--------|-------------|----------|
| Hero → Stats → Balances → Events → Invite → Activity | Financial data first, core value. | ✓ |
| Events → Hero → Balances → Stats → Invite → Activity | Events first, financials below. | |
| Hero → Balances → Events → Stats → Activity → Invite | Stats lower. | |

**User's choice:** Hero → Stats → Balances → Events → Invite → Activity

---

## Offline Behavior

| Option | Description | Selected |
|--------|-------------|----------|
| Last-known Firestore cache | Firestore offline persistence serves cached snapshots. Transparent. | ✓ |
| SQLite fallback for balances | Fall back to SQLite if Firestore stale. | |

**User's choice:** Last-known Firestore cache

| Option | Description | Selected |
|--------|-------------|----------|
| Yes — Firestore queues it | Same as event-level offline writes. Optimistic UI. | ✓ |
| Block until online | Require connectivity for settlements. | |

**User's choice:** Yes — Firestore queues it

---

## Empty States

| Option | Description | Selected |
|--------|-------------|----------|
| Hidden until first expense | Hero card and stats don't appear until data exists. | ✓ |
| Zero state card | Show card with 0.000 and context text. | |
| Placeholder illustration | EmptyStateView with illustration. | |

**User's choice:** Hidden until first expense

| Option | Description | Selected |
|--------|-------------|----------|
| Member list with zero balances | All members shown with 'Settled' badge. | ✓ |
| Empty state message | Replace list with "No expenses" message. | |

**User's choice:** Member list with zero balances

---

## Activity Log Triggers

| Option | Description | Selected |
|--------|-------------|----------|
| Client-side fire-and-forget | Client writes activity document on action. No Cloud Functions. | ✓ |
| Firestore Cloud Function triggers | Auto-generate from document writes. | |
| Hybrid — client + dedup | Client writes, Cloud Function deduplicates. | |

**User's choice:** Client-side fire-and-forget

| Option | Description | Selected |
|--------|-------------|----------|
| Core group actions | Event created/deleted, settlement recorded, member joined/left. 5 types. | ✓ |
| Core + financial summaries | Plus milestones and achievements. | |
| Comprehensive logging | Plus settings changes, invite code regen, etc. | |

**User's choice:** Core group actions

---

## Testing Strategy

| Option | Description | Selected |
|--------|-------------|----------|
| Unit tests for group balance logic | Priority: BalanceCalculator cross-event, groupBalancesProvider, GroupSettleUpScreen widget. Phase 6 handles full coverage. | ✓ |
| Full TDD across all features | Complete TDD for everything. | |
| Integration tests only | End-to-end flows only. | |

**User's choice:** Unit tests for group balance logic

| Option | Description | Selected |
|--------|-------------|----------|
| Both — match the layer | Service: FakeFirebaseFirestore, Provider: mock services, Widget: overridden providers. | ✓ |
| FakeFirebaseFirestore everywhere | Realistic but slower. | |
| Mock providers only | Fast but doesn't test queries. | |

**User's choice:** Both — match the layer

---

## Performance Edge Cases

| Option | Description | Selected |
|--------|-------------|----------|
| Watch all, compute lazily | Compute only when dashboard visible. <10ms for typical groups. | ✓ |
| Paginate events in rollup | Load recent N events only. Premature optimization. | |
| Background computation | Isolate for background compute. Overkill. | |

**User's choice:** Watch all, compute lazily

| Option | Description | Selected |
|--------|-------------|----------|
| Last 50 entries with pagination | Dashboard shows 5, full list loads 50 with cursor pagination. | ✓ |
| No limit | Load all entries. | |

**User's choice:** Last 50 entries with pagination

---

## Navigation

| Option | Description | Selected |
|--------|-------------|----------|
| Navigator.push from group detail | AppPageRoute for GroupSettleUpScreen and activity list. No GoRouter routes. | ✓ |
| GoRouter routes | Deep-linkable routes. Unnecessary for group-internal screens. | |
| Bottom sheet for settle-up | Limited space for settlement cards. | |

**User's choice:** Navigator.push from group detail

| Option | Description | Selected |
|--------|-------------|----------|
| Push LedgerScreen directly | Single navigation hop. Back returns to group. | ✓ |
| Push EventCommandCenter then auto-navigate | Two hops, overkill. | |

**User's choice:** Push LedgerScreen directly

---

## Claude's Discretion

- GroupSettleUpScreen layout and visual design
- Activity log entry format and styling
- Hero balance card visual design
- Member balance card expand/collapse animation
- Per-event breakdown row styling
- Spending stats chip layout
- GroupActivityService implementation details
- groupBalancesProvider stream composition

## Deferred Ideas

- Multi-currency aggregation across events
- Financial milestone celebrations in activity log
- Spending charts/graphs on dashboard
- Comprehensive activity logging
- Export group financial summary as PDF (ENH-05)
