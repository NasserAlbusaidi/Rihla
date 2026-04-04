# Phase 30: Group Settle Up & Activity - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-04-04
**Phase:** 30-group-settle-up-activity
**Areas discussed:** Settle-up screen design, Activity feed design, Functional gaps, GroupDetail integration

---

## Settle-up Screen Design

### Header pattern

| Option | Description | Selected |
|--------|-------------|----------|
| ModuleHeader (Recommended) | Consistent with other v2.0 screens — dark gradient header with title | ✓ |
| Keep current header | The plain back-button + centered title works fine | |
| ProfileScreen-style header | Large identity/stats area at top | |

**User's choice:** ModuleHeader
**Notes:** Already imported but not used in settle-up screen.

### Section organization

| Option | Description | Selected |
|--------|-------------|----------|
| Current 3-section layout | Keep YOUR ACTIONS / WAITING FOR OTHERS / OTHERS SETTLING | |
| Tabbed view | Tabs for 'You Owe' / 'Owed to You' / 'Between Others' | ✓ |
| Single list with badges | All settlements in one list with colored badges | |

**User's choice:** Tabbed view
**Notes:** None

### Bottom sheet design

| Option | Description | Selected |
|--------|-------------|----------|
| Polish existing (Recommended) | Keep same fields, apply design tokens properly | ✓ |
| Add payment method picker | Add payment method chips before note field | |
| Minimal — just confirm | Remove amount field, single-tap confirm | |

**User's choice:** Polish existing
**Notes:** None

### Empty state

| Option | Description | Selected |
|--------|-------------|----------|
| Current style is fine | Green checkmark circle, existing copy | ✓ |
| Add celebration feel | Confetti/Lottie animation | |
| You decide | Claude picks | |

**User's choice:** Current style is fine
**Notes:** None

### Tile design

| Option | Description | Selected |
|--------|-------------|----------|
| Card-style tiles (Recommended) | Rounded cards with avatars, prominent amount, collapsible breakdown | ✓ |
| Keep current grouped style | Tiles grouped inside GroupSettlementGroupCard | |
| You decide | Claude picks based on tabbed layout | |

**User's choice:** Card-style tiles
**Notes:** None

### Tab widget

| Option | Description | Selected |
|--------|-------------|----------|
| AppTabBar (Recommended) | Shared gradient pill tab bar | ✓ |
| Segmented control | M3 segmented button | |
| You decide | Claude picks | |

**User's choice:** AppTabBar
**Notes:** None

---

## Activity Feed Design

### Header pattern

| Option | Description | Selected |
|--------|-------------|----------|
| ModuleHeader (Recommended) | Dark gradient header | ✓ |
| Keep current header | Plain centered title | |

**User's choice:** ModuleHeader
**Notes:** None

### Entry grouping

| Option | Description | Selected |
|--------|-------------|----------|
| Date-grouped (Recommended) | Section headers by date, match event-level pattern | ✓ |
| Flat list with dividers | Keep current simple list | |
| Type-grouped | Group by action type | |

**User's choice:** Date-grouped
**Notes:** None

### Tile design

| Option | Description | Selected |
|--------|-------------|----------|
| Rich tiles (Recommended) | Avatar, actor name, description, timestamp, type icon | ✓ |
| Keep current tiles | Just ensure token usage | |
| You decide | Claude decides | |

**User's choice:** Rich tiles
**Notes:** None

### Filtering

| Option | Description | Selected |
|--------|-------------|----------|
| Filter chips (Recommended) | Horizontal scrollable: All, Settlements, Events, Members | ✓ |
| No filtering | Show everything chronologically | |
| You decide | Claude decides based on volume | |

**User's choice:** Filter chips
**Notes:** None

### Pagination

| Option | Description | Selected |
|--------|-------------|----------|
| Infinite scroll (Recommended) | Auto-load near bottom | ✓ |
| Keep 'Load more' button | Explicit user action | |

**User's choice:** Infinite scroll
**Notes:** None

---

## Functional Gaps

### Gap types identified

| Option | Description | Selected |
|--------|-------------|----------|
| Settlement history missing | No way to see past/completed settlements | ✓ |
| Balance accuracy issues | Balance calculations don't seem right | ✓ |
| Activity logging gaps | Some actions aren't being logged | ✓ |

**User's choice:** All three selected
**Notes:** None

### Settlement history location

| Option | Description | Selected |
|--------|-------------|----------|
| Tab on settle-up screen (Recommended) | History tab alongside active tabs | ✓ |
| In the activity feed | Activity feed IS the history | |
| Both places | History tab + activity feed | |

**User's choice:** Tab on settle-up screen
**Notes:** None

### Balance accuracy detail

**User's choice:** Let me describe it
**Notes:** User described: "sometimes when I'm in the group screen I see that I'm owed 4 OMR but when I enter the activity [event] that this transaction came from I see that I OWE 4 OMR — so there's this strange switching that happens between users or something." This is a sign flip / payer-recipient swap bug in the group-level balance aggregation.

### Activity logging gaps

| Option | Description | Selected |
|--------|-------------|----------|
| Expense actions missing | Expense CRUD not in group activity | |
| Settlement recordings missing | Settlements not always in feed | |
| Not sure specifically | Feed seems sparse | ✓ |
| Let me describe it | Custom description | |

**User's choice:** Not sure specifically
**Notes:** Will audit all action types as part of this phase.

---

## GroupDetail Integration

### Entry points

| Option | Description | Selected |
|--------|-------------|----------|
| Keep current CTAs (Recommended) | Gradient Settle Up button + View All on activity | ✓ |
| Redesign entry points | Rethink placement and design | |
| Let me describe what's wrong | Flag specific issues | |

**User's choice:** Keep current CTAs
**Notes:** None

### Activity preview

| Option | Description | Selected |
|--------|-------------|----------|
| Keep 5-item preview | 5 recent + View All, match new tile design | ✓ |
| Expand to richer preview | Mini activity cards with icon + description | |
| You decide | Claude decides based on space | |

**User's choice:** Keep 5-item preview
**Notes:** Update tile rendering to match new rich tile design.

---

## Claude's Discretion

- Exact spacing and padding within new card-style settlement tiles
- Skeleton/loading state design for tabbed settle-up view
- Filter chip visual styling
- Date section header typography and spacing
- Infinite scroll threshold distance

## Deferred Ideas

None — discussion stayed within phase scope
