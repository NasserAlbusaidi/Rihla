# Phase 18: Home Dashboard Redesign - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-03-29
**Phase:** 18-home-dashboard-redesign
**Areas discussed:** Cross-group balance hero, Quick-action tray, Bottom nav shell scope, Activity & spending sections

---

## Cross-group Balance Hero

### Q1: Where should the cross-group net balance appear?

| Option | Description | Selected |
|--------|-------------|----------|
| Hero card at top | Prominent card above group list showing aggregate balance | ✓ |
| Inline subtitle under title | Compact one-liner below "Your Groups" | |
| Per-card only, no aggregate | Each GroupCard shows personal balance, no single number | |

**User's choice:** Hero card at top
**Notes:** Most direct answer to NAV-02. Always visible without scrolling.

### Q2: What should the hero show when settled up?

| Option | Description | Selected |
|--------|-------------|----------|
| "All settled up" with checkmark | Gray-toned card with check icon, card stays visible | ✓ |
| Hide hero when settled | Card disappears, layout shifts | |
| Show OMR 0.000 in green | Same layout, green-toned with zero amount | |

**User's choice:** "All settled up" with checkmark
**Notes:** Positive reinforcement, consistent layout across states.

---

## Quick-action Tray

### Q3: How should context-dependent actions work from home?

| Option | Description | Selected |
|--------|-------------|----------|
| Group picker sheet | Bottom sheet listing groups, user picks one | ✓ |
| Most recent group auto-selected | Targets last-interacted group, can switch | |
| You decide | Claude picks best pattern | |

**User's choice:** Group picker sheet
**Notes:** Follows existing FAB bottom sheet pattern.

### Q4: Where should the tray sit in the layout?

| Option | Description | Selected |
|--------|-------------|----------|
| Below hero, above groups | Horizontal row between hero and group list | ✓ |
| Floating bottom bar | Fixed bar above bottom nav | |
| Inside hero card | Embedded in the hero card itself | |

**User's choice:** Below balance hero, above groups
**Notes:** Must be visible without scrolling on standard phones.

---

## Bottom Nav Shell Scope

### Q5: Should Phase 18 implement bottom navigation?

| Option | Description | Selected |
|--------|-------------|----------|
| Visual shell only | Add bar with Groups active, other tabs placeholder | ✓ |
| Defer to Phase 19 | Only build home content, no nav bar | |
| Full nav in Phase 18 | GoRouter StatefulShellRoute with real routing | |

**User's choice:** Phase 18 visual shell only
**Notes:** Gets visual layout right early. Phase 19 wires real GoRouter routes.

---

## Activity & Spending Sections

### Q6: What should the activity strip show?

| Option | Description | Selected |
|--------|-------------|----------|
| Cross-group aggregate | Merge recent from all groups chronologically | ✓ |
| Per-group only | Activity only inside groups, home skips it | |
| You decide | Claude picks based on existing services | |

**User's choice:** Cross-group aggregate
**Notes:** Most useful dashboard — see what's happening across all groups at a glance.

### Q7: Include weekly spending card?

| Option | Description | Selected |
|--------|-------------|----------|
| Include with real data | Weekly spending card with Firestore data, teal bar chart | ✓ |
| Defer spending card | Skip in Phase 18, add in Phase 22 | |
| Static placeholder | Layout with dummy data | |

**User's choice:** Include spending card with real data
**Notes:** Rounds out the dashboard as a full financial snapshot.

### Q8: How many activity rows?

| Option | Description | Selected |
|--------|-------------|----------|
| 5 most recent | Enough to see what's happening, matches existing limit | ✓ |
| 3 most recent | Tighter, with "View All" link | |
| You decide | Claude picks based on layout | |

**User's choice:** 5 most recent

---

## Claude's Discretion

- Chart rendering approach for weekly spending
- Cross-group balance aggregation provider implementation
- Exact skeleton composition for balance hero
- Activity row widget internal layout
- SliverAppBar vs fixed header for title

## Deferred Ideas

None — discussion stayed within phase scope
