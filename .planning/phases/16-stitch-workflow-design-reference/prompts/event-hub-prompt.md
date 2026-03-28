# Stitch Input Prompt — Event Hub Screen

Copy everything below this line and paste directly into Google Stitch.

---

Design a high-fidelity mobile UI mockup for the **Event Hub Screen** (also called CommandCenter) of a group trip planning app called Rihla. Target width ~390px (iPhone 14 / Pixel 7). Single breakpoint only. Dense dashboard layout — the expense hero and module grid visible without scrolling.

## A — Palette

Use these exact hex values. Do not approximate or modify any color.

```
Primary (terracotta): #CC6B49
Background (sand): #F2E8D6
Card surface (warm white): #FFF9F2
Input fill: #F5EDE1
Border / divider: #E5D5C0
Text primary (dark brown): #2C1A0E
Text secondary: #6B5B4E
Text muted: #A89888  ← DECORATIVE ONLY — do not use for functional text, labels, amounts, or actions
Text on primary (white): #FFFFFF
Success display (badge/icon only): #10B981
Success text (WCAG-safe, readable): #047857
Error display (badge/icon only): #EF4444
Error text (WCAG-safe, readable): #B91C1C
Selection fill (terracotta 15% tint): #F5DDD3
Disabled background: #E5D5C0
Disabled text: #A89888

Module accent colors (CRITICAL — use these exact values per module):
  Ledger accent: #CC6B49    |  Ledger light tint: #ECD5C0
  Gear accent: #7A8C5E      |  Gear light tint: #E0DAC4
  Logistics accent: #5B7B8C |  Logistics light tint: #DBD7CA
  Vault accent: #8B7355     |  Vault light tint: #E2D6C2
  Activity accent: #A67C5B  |  Activity light tint: #E6D7C3
  Memories accent: #9B7A5C  |  Memories light tint: #E4D7C3

Header gradient start: #2C1A0E  |  end: #3D2B1E
```

CRITICAL: The module accent colors above are the INTENDED design tokens from the Phase 15 design system. Use them exactly as listed. Do NOT swap module colors.

## B — Spacing Scale

All padding, gaps, and margins must align to this scale. Do not use non-scale values (e.g., 6dp, 10dp, 15dp).

```
4dp (space4)
8dp (space8)
12dp (space12)
16dp (space16) ← base/default
20dp (space20)
24dp (space24)
32dp (space32)

Border radii: 12dp (chips/tags), 16dp (buttons/inputs), 20dp (cards/sheets)
Button height: 52dp
Touch targets: minimum 48dp
```

## C — Typography

Font: **Plus Jakarta Sans**

Weight hierarchy:
- 800 — screen headings, large numbers (expense totals)
- 700 — card titles, section headers, button labels
- 600 — body emphasis, labels, chips, module summaries
- 400 — body text, secondary descriptions

## D — Component Inventory

The following shared components already exist in the app. Use these patterns in your design — do not invent new variants when an existing component covers the use case.

```
ModuleHeader
  — Dark gradient header (#2C1A0E → #3D2B1E, left-to-right)
  — White title (weight 800) + white subtitle (weight 400)
  — Back arrow icon (left side, 48dp touch target) + options/more icon (right side, 48dp)
  — Used for: this screen's header (Event Hub)

AppTabBar
  — Horizontal tab row with gradient pill indicator on active tab
  — Active pill uses primary terracotta (#CC6B49)
  — Tab label: weight 600, 14sp
  — Not primary use on this screen

EmptyStateView
  — Vertically centered layout: icon placeholder + heading + body message + optional CTA button
  — Heading: weight 700, text primary (#2C1A0E)
  — Body: weight 400, text secondary (#6B5B4E)
  — CTA button: 52dp height, primary terracotta fill (#CC6B49), white text (#FFFFFF), 16dp radius
  — Used for: error state

SmartModuleCard
  — List-style card (full-width minus 16dp horizontal margin):
    — Left: 44×44 circle icon container with colored background (module light tint at 12% fill), icon in module accent color
    — Center: title (weight 700, 15sp, text primary) + summary subtitle (weight 400, 13sp, text secondary)
    — Right: chevron icon (text secondary, #6B5B4E)
  — Card surface: #FFF9F2, 20dp radius, subtle raised shadow
  — Touch target: entire card, minimum 48dp height (typically 64–72dp)
  — Used for: ALL 6 module entries in this screen

OfflineBanner
  — Thin strip immediately below ModuleHeader indicating connectivity loss
  — Background: error display (#EF4444) or muted tone
  — Text: short message, weight 600
  — Used for: error state

SkeletonLoader
  — Rounded grey placeholder blocks, pulsing animation
  — Matches the shape and size of the content being loaded
  — Used for: loading state
```

## E — Screen Description: Event Hub Screen

Design all 4 states of the Event Hub Screen.

### State 1: Loaded (Primary State)

The Event Hub is the per-event dashboard. Layout is compact to show the hero card and all 6 module cards without scrolling. Background: sand (#F2E8D6).

**Layout (top to bottom):**

1. **ModuleHeader** (full-width, dark gradient #2C1A0E → #3D2B1E):
   - Back arrow (left, white, 48dp)
   - Title: "Trip A" — white, weight 800, 20sp
   - Subtitle: "Trip · Group A" — white, weight 400, 13sp
   - Right: options/more icon (⋮), white, 48dp

2. **Expense Hero Card** (full-width minus 16dp horizontal margin, 20dp radius, card surface #FFF9F2, raised shadow):
   Card padding: 16dp all sides.
   - Row 1: label "Total Expenses" — weight 600, 12sp, text secondary (#6B5B4E)
   - Row 2: large amount "OMR 45.500" — weight 800, 28sp, primary terracotta (#CC6B49)
   - Row 3: horizontal chips row:
     - "3 participants" chip: 12dp radius, fill #F5EDE1, text #6B5B4E, weight 600, 12sp
     - Gap 8dp
     - "Mar 30–Apr 2" chip: same style
   - Divider (#E5D5C0), 8dp vertical margin
   - Row 4: "Add Expense" shortcut button — 36dp height, 16dp radius, primary #CC6B49 fill, white text (#FFFFFF), weight 700, 13sp, positioned right OR full-width

3. **Module List** (vertical stack, all 6 modules):
   Gap between expense card and first module: 12dp.
   Gap between module cards: 8dp.

   Each module is one SmartModuleCard:

   **Ledger card:**
   - Icon container: 44×44 circle, fill #ECD5C0 (12% tint), icon in #CC6B49
   - Icon: receipt or wallet symbol
   - Title: "Ledger" — weight 700, 15sp, text primary (#2C1A0E)
   - Summary: "3 expenses · OMR 45.500" — weight 400, 13sp, text secondary (#6B5B4E)
   - Chevron: text secondary (#6B5B4E)

   **Gear card:**
   - Icon container: 44×44 circle, fill #E0DAC4 (12% tint), icon in #7A8C5E
   - Icon: backpack or checklist symbol
   - Title: "Gear" — weight 700, 15sp, text primary (#2C1A0E)
   - Summary: "5 items · 2 unclaimed" — weight 400, 13sp, text secondary (#6B5B4E)
   - Chevron: text secondary (#6B5B4E)

   **Logistics card:**
   - Icon container: 44×44 circle, fill #DBD7CA (12% tint), icon in #5B7B8C
   - Icon: car or map-pin symbol
   - Title: "Logistics" — weight 700, 15sp, text primary (#2C1A0E)
   - Summary: "2 transport entries" — weight 400, 13sp, text secondary (#6B5B4E)
   - Chevron: text secondary (#6B5B4E)

   **Vault card:**
   - Icon container: 44×44 circle, fill #E2D6C2 (12% tint), icon in #8B7355
   - Icon: folder or lock symbol
   - Title: "Vault" — weight 700, 15sp, text primary (#2C1A0E)
   - Summary: "4 documents" — weight 400, 13sp, text secondary (#6B5B4E)
   - Chevron: text secondary (#6B5B4E)

   **Activity card:**
   - Icon container: 44×44 circle, fill #E6D7C3 (12% tint), icon in #A67C5B
   - Icon: activity or pulse symbol
   - Title: "Activity" — weight 700, 15sp, text primary (#2C1A0E)
   - Summary: "12 actions today" — weight 400, 13sp, text secondary (#6B5B4E)
   - Chevron: text secondary (#6B5B4E)

   **Memories card:**
   - Icon container: 44×44 circle, fill #E4D7C3 (12% tint), icon in #9B7A5C
   - Icon: camera or image symbol
   - Title: "Memories" — weight 700, 15sp, text primary (#2C1A0E)
   - Summary: "8 photos" — weight 400, 13sp, text secondary (#6B5B4E)
   - Chevron: text secondary (#6B5B4E)

4. **FAB** (floating, bottom-right):
   - 56dp circle, primary terracotta (#CC6B49)
   - White plus icon (#FFFFFF)
   - Label: "Add Expense" (optional, if extended FAB variant)

### State 2: Empty (New Event, No Data Yet)

ModuleHeader — identical to loaded state.
Expense Hero Card — identical structure but:
- Amount: "OMR 0.000" in text secondary (#6B5B4E) instead of terracotta (no amount to highlight)
- "0 participants" chip, no date chip
- "Add Expense" button: same style (still actionable)

Module List — all 6 SmartModuleCards with empty state summaries:
- Ledger: summary "No expenses yet" — icon container uses 6% opacity fill instead of 12% (lighter)
- Gear: summary "No items yet"
- Logistics: summary "No entries yet"
- Vault: summary "No documents yet"
- Activity: summary "No activity yet"
- Memories: summary "No photos yet"

Icon containers in empty state: same accent colors, but 6% opacity fill instead of 12%. Icons remain in their accent colors.

### State 3: Loading / Skeleton

ModuleHeader — real (dark gradient, shows "Trip A", subtitle "Trip · Group A").
OfflineBanner: hidden in loading state.

Below header:
- **Expense hero card skeleton**: full card shape (20dp radius), height ~100dp, 2 placeholder lines inside
- Gap: 12dp
- **6 module card skeletons**: each full-width card shape (20dp radius, height 64dp):
  - Circle placeholder (44×44) on left
  - 2 line placeholders: wide (50% width, height 12dp) + narrow (35% width, height 10dp)
  - Gap 8dp between skeleton cards

All skeleton blocks: color #E5D5C0, pulsing opacity animation.

### State 4: Error

- ModuleHeader — real (dark gradient, shows "Trip A", subtitle "Trip · Group A", back arrow, options)
- OfflineBanner immediately below header: "No connection — showing cached data"
- EmptyStateView in remaining space:
  - Error icon (cloud-off or wifi-off), 48dp, color #EF4444
  - Heading: "Couldn't load event" — weight 700, 20sp, text primary (#2C1A0E)
  - Body: "Check your connection and try again" — weight 400, 14sp, text secondary (#6B5B4E)
  - CTA button: "Retry" — 52dp height, 200dp width (centered), primary terracotta (#CC6B49), white text

## F — Constraints

```
Target width: ~390px (iPhone 14 / Pixel 7)
Single breakpoint only — no responsive variants
Generic placeholder data only:
  Names: "User 1", "User 2", "User 3"
  Groups: "Group A"
  Events: "Trip A"
  Amounts: "OMR 45.500", "OMR 10.000"
  Participant count: "3 participants"
  Date range: "Mar 30–Apr 2"
Dense layout: expense hero + all 6 module cards visible without scrolling
Light theme only — no dark mode variant
Module accent colors are FIXED — do not swap Ledger (#CC6B49) with any other color
```
