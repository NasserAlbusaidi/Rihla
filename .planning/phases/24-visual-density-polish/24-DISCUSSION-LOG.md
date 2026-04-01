# Phase 24: Visual Density & Polish - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-04-01
**Phase:** 24-visual-density-polish
**Areas discussed:** Group card enrichment, Chart improvements, Dashboard density & rhythm, Card visual distinction

---

## Group Card Enrichment

### What extra context should each card surface?

| Option | Description | Selected |
|--------|-------------|----------|
| Last event name + date | Shows "Camping Trip — 2 days ago" below balance. Uses groupEventsProvider. | ✓ |
| Total group spend | Cumulative spend across all events. Heavier computation. | |
| Both last event + total spend | Two extra lines. Most dense but may crowd the card. | |

**User's choice:** Last event name + date
**Notes:** Recommended approach — lightweight, uses existing provider

### How should member representation look?

| Option | Description | Selected |
|--------|-------------|----------|
| Keep member count badge | Current icon + number badge. Clean, compact, already works. | ✓ |
| Overlapping avatar circles | 3-4 colored initial circles. More visual but needs new widget. | |
| You decide | Claude picks based on layout. | |

**User's choice:** Keep member count badge

### What should groups with zero events show?

| Option | Description | Selected |
|--------|-------------|----------|
| "No events yet" in muted text | Simple, honest. Matches existing empty state patterns. | ✓ |
| "Created 3 days ago" | Shows creation date as fallback context. | |
| Hide the context line entirely | Cleaner but inconsistent card heights. | |

**User's choice:** "No events yet" in muted text

### Balance display format?

| Option | Description | Selected |
|--------|-------------|----------|
| Keep exact amount | Current: "You owe OMR 12.500". Precise and actionable. | ✓ |
| Simplified status only | "You owe" / "Owed to you" / "Settled" with no amounts. | |
| Amount + mini arrow indicator | Amount plus up/down arrow icon. | |

**User's choice:** Keep exact amount

### Include event type icon on context line?

| Option | Description | Selected |
|--------|-------------|----------|
| Yes, small type icon | 16px icon before event name. Icons exist in event templates. | ✓ |
| No, text only | Just "Camping Trip — 2d ago" with no icon. | |
| You decide | Claude picks based on layout. | |

**User's choice:** Yes, small type icon

---

## Chart Improvements

### How should spending amounts appear?

| Option | Description | Selected |
|--------|-------------|----------|
| Amount label on each bar | Small text at end/top of each bar. Directly answers "how much?" | ✓ |
| Y-axis scale on the left | Vertical axis with 3-4 tick marks. More chart-like but takes space. | |
| Tooltip on tap | Tap bar to see amount. Clean when idle but requires interaction. | |

**User's choice:** Amount label on each bar

### Chart title wording?

| Option | Description | Selected |
|--------|-------------|----------|
| "Weekly Spending (OMR)" | Clear label with currency context. | ✓ |
| "This Week - OMR" | Keeps "This Week" with currency suffix. | |
| "Spending — Mon-Sun" | Date range instead of currency. | |

**User's choice:** "Weekly Spending (OMR)"

### Zero-spending day labels?

| Option | Description | Selected |
|--------|-------------|----------|
| No label, just placeholder bar | 2px gray bar stays, no "0" text. Clean. | ✓ |
| Show "0" on zero days | Explicit zero. Consistent but noisy. | |
| Hide zero-day bars entirely | Only show days with spending. Breaks Mon-Sun rhythm. | |

**User's choice:** No label, just placeholder bar

---

## Dashboard Density & Rhythm

### Group list section header?

| Option | Description | Selected |
|--------|-------------|----------|
| "Your Groups" header with count | Styled label like "Your Groups (3)". Clear visual separation. | ✓ |
| Subtle divider line only | Thin line before group cards. Minimal. | |
| No change | Cards flow after quick actions as-is. | |

**User's choice:** "Your Groups" header with count

### Section spacing?

| Option | Description | Selected |
|--------|-------------|----------|
| Tighten to 12px between sections | Reduce from 16-24px to consistent 12px. | ✓ |
| Tighten to 8px between sections | More aggressive. May feel cramped. | |
| You decide | Claude picks spacing targeting denser layout. | |

**User's choice:** Tighten to 12px between sections

### Section order?

| Option | Description | Selected |
|--------|-------------|----------|
| Keep current order | Hero → Quick Actions → Groups → Activity → Chart. | ✓ |
| Move chart above activity | Chart more prominent, activity drops to bottom. | |
| Move groups above hero | Groups first, hero below. | |

**User's choice:** Keep current order

---

## Card Visual Distinction

### How should groups be distinguished?

| Option | Description | Selected |
|--------|-------------|----------|
| Color accent strip on left edge | 4px vertical bar cycling through earthy palette. Subtle, scannable. | ✓ |
| Tinted card background | Light tinted background per group. More distinct but contrast risks. | |
| Icon or emoji per group | Auto-assigned icon from name hash. Visual identity without color. | |

**User's choice:** Color accent strip on left edge

### Color assignment method?

| Option | Description | Selected |
|--------|-------------|----------|
| Hash-based from group ID | Deterministic from palette of 5-6 colors. Same across devices. | ✓ |
| Index-based (order in list) | First = teal, second = terracotta. Color changes on reorder. | |
| User-chosen per group | Color picker on creation. Requires model change. Scope creep. | |

**User's choice:** Hash-based from group ID

### Accent color tint scope?

| Option | Description | Selected |
|--------|-------------|----------|
| Left strip only | 4px bar only. Rest of card neutral. Avoids WCAG issues. | ✓ |
| Strip + light background tint | Strip plus faint wash. More immersive but needs WCAG check. | |
| You decide | Claude picks what looks best. | |

**User's choice:** Left strip only

---

## Claude's Discretion

- Exact earthy color palette for accent strips
- Amount label formatting on chart bars
- "Your Groups" header typography
- Card internal spacing for new context line
- Event type icon mapping

## Deferred Ideas

None — discussion stayed within phase scope
