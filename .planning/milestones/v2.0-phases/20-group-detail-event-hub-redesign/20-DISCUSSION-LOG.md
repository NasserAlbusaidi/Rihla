# Phase 20: Group Detail & Event Hub Redesign - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-03-30
**Phase:** 20-group-detail-event-hub-redesign
**Areas discussed:** Event card design, ContainerTransform transition, Group detail data density, Event hub module grid

---

## Event Card Design

### Q1: How should event cards show financial state inline?

| Option | Description | Selected |
|--------|-------------|----------|
| Amount + status line | "OMR 45.500 · 3 expenses" below event name. Compact, scannable. Uses errorText/successText for personal balance. | ✓ |
| Balance chip only | Small colored chip showing "You owe OMR 12.500" or "Settled" — no expense count. | |
| No inline financials | Event cards show name, date, type only. Financial detail inside event hub. | |

**User's choice:** Amount + status line
**Notes:** User selected the recommended option with preview showing personal balance + expense count + date range layout.

### Q2: How should past events look compared to upcoming/active ones?

| Option | Description | Selected |
|--------|-------------|----------|
| Opacity reduction | Past events at 60% opacity, accent bar in textMuted gray instead of teal. Same card layout, visually receded. | ✓ |
| Section separation | "Upcoming" and "Past" section headers split the list. Past events have different card style. | |
| Collapsed past | Past events hide behind "Show N past events" button. | |

**User's choice:** Opacity reduction
**Notes:** User selected the recommended option. Clear visual distinction without hiding past event data.

---

## ContainerTransform Transition

### Q1: How ambitious should Phase 20's transition work be?

| Option | Description | Selected |
|--------|-------------|----------|
| Single transition only | ContainerTransform only on group card → group detail. All else stays slide-right. Defers broader motion to Phase 22. | ✓ |
| Group card + event card | ContainerTransform on both group card → group detail AND event card → event hub. | |
| Full M3 motion pass | All transitions get M3 treatment. Overlaps with Phase 22 scope. | |

**User's choice:** Single transition only
**Notes:** Minimal scope, delivers Success Criterion 4, defers broader motion system to Phase 22.

### Q2: Use animations package or Hero widget?

| Option | Description | Selected |
|--------|-------------|----------|
| animations package | Google's official `OpenContainer` widget. Battle-tested, handles clipping/elevation. One new dependency. | ✓ |
| Hero + CustomTransitionPage | Built-in Hero with custom GoRouter transition. No new dependency but more manual work. | |
| You decide | Let Claude pick based on GoRouter compatibility. | |

**User's choice:** animations package
**Notes:** User confirmed `OpenContainer` approach with preview showing the API surface.

---

## Group Detail Data Density

### Q1: What should be above the fold?

| Option | Description | Selected |
|--------|-------------|----------|
| Header + stats + CTA | Dark header, 2x2 stats grid, settle-up CTA above fold. Members and events scroll below. | ✓ |
| Header + members + CTA | Prioritize people over numbers. Header, top 3-4 member balances, settle-up CTA above fold. | |
| Compact — everything | Compress all sections to fit above fold. | |

**User's choice:** Header + stats + CTA
**Notes:** Financial overview prioritized above the fold.

### Q2: What should the 4th stat tile show?

| Option | Description | Selected |
|--------|-------------|----------|
| Event count | "N EVENTS" — always meaningful, always available. | ✓ |
| Days left | "N DAYS LEFT" from nearest upcoming event. Undefined for past-only groups. | |
| Last active | "N days ago" since last activity. | |

**User's choice:** Event count
**Notes:** Replaced spec's "DAYS LEFT" with universally available metric.

### Q3 (revisit): Section ordering below the fold

| Option | Description | Selected |
|--------|-------------|----------|
| Stats → Members → Events → Activity (spec) | Financial-first ordering. | |
| Stats → Events → Members → Activity | Event-first below stats. | ✓ |
| Stats → Events → Activity (no members) | Drop member balances entirely. | |
| You decide | Claude picks. | |

**User's choice:** Stats → Events → Members → Activity
**Notes:** User revisited this area specifically to change from spec ordering. Events (what's happening) come before member balances (who owes what).

---

## Event Hub Module Grid

### Q1: What should empty modules show?

| Option | Description | Selected |
|--------|-------------|----------|
| Description when empty | Show module description in textMuted when no data. Switch to live summary when data exists. | ✓ |
| Always live summary | Show "0 items" / "0 expenses" even when empty. | |
| Hide empty modules | Only show modules with data. Grid shrinks dynamically. | |

**User's choice:** Description when empty
**Notes:** SmartModuleCard already supports this pattern.

### Q2: What live summary format per module?

| Option | Description | Selected |
|--------|-------------|----------|
| Count + key metric | Ledger: "3 expenses · OMR 45.500". Gear: "5 items · 2 unchecked". Etc. | ✓ |
| Count only | Simple count: "3 expenses", "5 items". | |
| You decide | Claude picks best summary per module. | |

**User's choice:** Count + key metric
**Notes:** Each module shows its most useful number alongside the count.

---

## Claude's Discretion

- OpenContainer + GoRouter reconciliation approach
- Expense hero card pattern (reuse BalanceHeroCard or simplified)
- Skeleton composition for loading states
- Activity strip reuse from Phase 18
- Past/upcoming event determination logic

## Deferred Ideas

None — discussion stayed within phase scope
