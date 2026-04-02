# Phase 28: Group Detail - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-04-02
**Phase:** 28-group-detail
**Areas discussed:** Redesign scope, Section layout & hierarchy, Event card presentation, Balance & member display, Loading & error states, Header design, FAB & navigation

---

## Redesign Scope

| Option | Description | Selected |
|--------|-------------|----------|
| Visual refresh only | Keep same layout and data, refine spacing/typography/polish | ✓ |
| Layout restructure | Reorganize sections, change info hierarchy | |
| Full rebuild | Start from scratch with new design vision | |

**User's choice:** Visual refresh only
**Notes:** General quality pass — spacing & density, visual consistency, and polish & details all need attention.

---

| Option | Description | Selected |
|--------|-------------|----------|
| UI only | Only touch widgets, spacing, styling, animations | |
| UI + provider cleanup | Also refactor providers for inefficiencies | ✓ |

**User's choice:** UI + provider cleanup

---

## Section Layout & Hierarchy

| Option | Description | Selected |
|--------|-------------|----------|
| Keep current order | Stats → Settle-Up → Events → Members → Invite → Activity | ✓ |
| Events first | Move events higher, right after header/stats | |
| You decide | Claude evaluates | |

**User's choice:** Keep current order

---

| Option | Description | Selected |
|--------|-------------|----------|
| Keep all sections | All 6 sections stay | |
| Merge activity into events | Inline activity with events section | |
| Drop invite code section | Move invite code to group settings (Phase 29) | ✓ |

**User's choice:** Drop invite code section

---

| Option | Description | Selected |
|--------|-------------|----------|
| Keep 2x2 as-is | Same 4 stats, visually refreshed | ✓ |
| Simplify to key metrics | Reduce to 2-3 stats | |
| You decide | Claude picks | |

**User's choice:** Keep 2x2 as-is

---

## Event Card Presentation

| Option | Description | Selected |
|--------|-------------|----------|
| Polish existing cards | Keep type-specific design, improve spacing/shadows/typography, add animations | ✓ |
| Uniform card style | All types get same layout, differentiated by icon/color only | |
| Compact list rows | Dense rows instead of full cards | |

**User's choice:** Polish existing cards

---

| Option | Description | Selected |
|--------|-------------|----------|
| Staggered fade-in | Each card animates in with delay, matches FadeInList pattern | ✓ |
| No entrance animation | Cards appear instantly | |
| You decide | Claude picks | |

**User's choice:** Staggered fade-in (Recommended)

---

## Balance & Member Display

| Option | Description | Selected |
|--------|-------------|----------|
| Keep accordion pattern | Expandable cards with per-event breakdown, visual refresh | ✓ |
| Always-visible breakdown | Show breakdown inline without expand/collapse | |
| Summary only | Net balance per member, move breakdown to detail view | |

**User's choice:** Keep accordion pattern

---

| Option | Description | Selected |
|--------|-------------|----------|
| Keep conditional CTA | Only show when user has non-zero balance | ✓ |
| Always show CTA | Always visible, styled differently when zero | |
| You decide | Claude picks | |

**User's choice:** Keep conditional CTA

---

## Loading & Error States

| Option | Description | Selected |
|--------|-------------|----------|
| Skeleton + pull-to-refresh | Skeleton on initial load + pull-to-refresh for re-fetch | ✓ |
| Skeleton only | No pull-to-refresh, rely on realtime listeners | |
| You decide | Claude picks | |

**User's choice:** Skeleton + pull-to-refresh (Recommended)

---

| Option | Description | Selected |
|--------|-------------|----------|
| Inline error + retry | Error message in body with retry button | ✓ |
| Full-screen error | Replace entire content with centered error | |
| You decide | Claude picks | |

**User's choice:** Inline error + retry

---

## Header Design

| Option | Description | Selected |
|--------|-------------|----------|
| Refresh existing | Dark gradient + group name + creation date, polish typography | ✓ |
| Add member count | Show member count alongside creation date in subtitle | |
| Minimal header | Group name only, move metadata to stats grid | |

**User's choice:** Refresh existing

---

## FAB & Navigation

| Option | Description | Selected |
|--------|-------------|----------|
| Keep FAB for create event | FAB stays as primary entry point, visual refresh | ✓ |
| Move to inline button | Replace FAB with inline button in events section | |
| You decide | Claude picks | |

**User's choice:** Keep FAB for create event

---

| Option | Description | Selected |
|--------|-------------|----------|
| Add OpenContainer transitions | M3 ContainerTransform when tapping cards | |
| Keep slide-right transitions | Standard slide-right for all sub-nav | |
| You decide | Claude picks per navigation type | ✓ |

**User's choice:** You decide

---

## Claude's Discretion

- Navigation transition type per sub-screen (OpenContainer vs slide-right)
- Specific provider refactoring decisions
- Exact spacing/density values within design token system

## Deferred Ideas

- Invite code display moves to Phase 29 (Group Management/Settings)
