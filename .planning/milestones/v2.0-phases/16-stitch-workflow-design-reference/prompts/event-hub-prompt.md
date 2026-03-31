# Stitch Input Prompt — Event Hub Screen

Copy everything below this line and paste directly into Google Stitch.

---

Design a high-fidelity mobile UI mockup for the **Event Hub Screen** (also called CommandCenter) of a group coordination app called Rihla. Target width ~390px (iPhone 14 / Pixel 7). Single breakpoint only. Hybrid density — the expense summary breathes, the module grid is compact and scannable. Near-monochrome aesthetic with one teal accent.

## A — Palette

Use these exact hex values. Do not approximate or modify any color.

```
Primary (teal): #0D7B74
Background (white): #FFFFFF
Card surface (cool gray): #F8F9FA
Input fill (gray-100): #F3F4F6
Border / divider (gray-200): #E5E7EB
Text primary (gray-900): #111827
Text secondary (gray-500): #6B7280
Text muted (gray-400): #9CA3AF  ← DECORATIVE ONLY
Text on primary (white): #FFFFFF
Success display (badge/icon only): #10B981
Success text (WCAG-safe): #047857
Error display (badge/icon only): #EF4444
Error text (WCAG-safe): #B91C1C
Selection fill (teal tint): #E6F5F3
Disabled background: #E5E7EB
Disabled text: #9CA3AF

Header gradient start: #111827  |  end: #1F2937
```

CRITICAL: Monochrome palette. Only teal #0D7B74 for interactive/accent. All module cards use NEUTRAL gray — no per-module color differentiation. Modules are distinguished by their icon and label, not by color.

## B — Spacing Scale

```
4dp, 8dp, 12dp, 16dp (base), 20dp, 24dp, 32dp

Border radii: 8dp (chips/tags), 12dp (buttons/inputs), 16dp (cards/sheets)
Button height: 52dp
Touch targets: minimum 48dp
```

## C — Typography

Font: **Plus Jakarta Sans**

Weight hierarchy (restrained):
- 700 — display headings, large expense totals
- 600 — section headers, card titles, button labels, module names
- 400 — body text, descriptions, summaries

## D — Component Inventory

```
ModuleHeader (Default variant — white)
  — White background, blends into scaffold
  — Title: #111827, weight 700 + subtitle: #6B7280, weight 400
  — Back arrow: plain icon, no container (44dp touch target)
  — Right: options icon (#6B7280, 48dp)
  — Used for: this screen's header

SmartModuleCard
  — Card: #F8F9FA surface, 16dp radius, 1px #E5E7EB border, subtle soft shadow
  — Left: 44×44 circle icon container:
    — Normal state: #F3F4F6 background, #111827 icon
    — Alert/active state: #E6F5F3 background, #0D7B74 icon, teal border on card
  — Center: title (weight 600, 15sp, #111827) + summary (weight 400, 13sp, #6B7280)
  — Right: chevron (#6B7280)
  — ALL modules use the SAME neutral color scheme. No per-module colors.

EmptyStateView
  — Icon 48dp #9CA3AF + heading #111827 w600 + body #6B7280 w400
  — CTA: 52dp, teal #0D7B74, white text, 12dp radius

OfflineBanner
  — Amber #F59E0B strip, white text

SkeletonLoader
  — #F3F4F6 base, #E5E7EB shapes, pulsing
```

## E — Screen Description: Event Hub Screen

Design all 4 states.

### State 1: Loaded (Primary State)

The Event Hub is the per-event dashboard. White background (#FFFFFF). The header and expense area breathe (spacious), the module grid is compact (dense). This screen should feel clean and functional — like a well-organized Notion page.

**Layout (top to bottom):**

1. **Header area** (white, blends into page — NOT dark gradient):
   - Back arrow (left, #111827, plain icon, 44dp)
   - Title: "Trip A" — #111827, weight 700, 20sp
   - Subtitle: "5 members · 12 expenses" — #6B7280, weight 400, 13sp
   - Right: options icon (⋮), #6B7280, 48dp
   - Horizontal padding: 24dp
   - Background: white, no border, no elevation

2. **Expense Summary** (24dp horizontal padding, 16dp vertical padding):
   - Label: "Total Expenses" — weight 600, 12sp, #6B7280
   - Amount: "OMR 45.500" — weight 700, 28sp, #111827 (NOT teal — this is informational, not interactive)
   - Chips row below amount (8dp gap between):
     - "3 participants" chip: 8dp radius, #F3F4F6 fill, #6B7280 text, weight 600, 12sp
     - "Mar 30–Apr 2" chip: same style
   - Hairline divider (#E5E7EB) below chips, 12dp margin
   - "Add Expense" button: 36dp height, 12dp radius, teal #0D7B74, white text, weight 600, 13sp — right-aligned

3. **Module Grid** (2-column grid, 24dp horizontal padding, 12dp gap between cards):
   Gap between expense summary and grid: 24dp.

   All 6 modules as SmartModuleCards in 2×3 grid (not a vertical list). Each card:
   - 16dp radius, #F8F9FA surface, 1px #E5E7EB border, soft shadow
   - Padding: 16dp
   - Top: 44×44 circle icon (#F3F4F6 bg, #111827 icon)
   - Below icon: module name (weight 600, 14sp, #111827)
   - Below name: summary line (weight 400, 12sp, #6B7280)

   **Grid layout:**
   ```
   ┌──────────┐  ┌──────────┐
   │ 💰       │  │ 🎒       │
   │ Ledger   │  │ Gear     │
   │ OMR 45   │  │ 8 items  │
   └──────────┘  └──────────┘
   ┌──────────┐  ┌──────────┐
   │ 🚗       │  │ 📁       │
   │ Logistics│  │ Vault    │
   │ 2 cars   │  │ 3 docs   │
   └──────────┘  └──────────┘
   ┌──────────┐  ┌──────────┐
   │ 📋       │  │ 📸       │
   │ Activity │  │ Memories │
   │ 5 logs   │  │ 0 photos │
   └──────────┘  └──────────┘
   ```

   Cards with data needing attention get a teal treatment:
   - Icon circle: #E6F5F3 bg, #0D7B74 icon
   - Card border: 1.5px #0D7B74 instead of #E5E7EB
   - Example: Ledger card (has unsettled balances) gets teal border

   Cards with no data:
   - Icon circle: #F3F4F6 bg (slightly lighter), #9CA3AF icon (muted)
   - Summary: "No photos yet" in #9CA3AF

### State 2: Empty (New Event, No Data Yet)

Header — identical to loaded.
Expense summary:
- Amount: "OMR 0.000" in #6B7280 (not emphasized)
- "0 participants" chip, no date chip
- "Add Expense" button: still active (teal)

Module grid — all 6 cards with empty summaries:
- All icon circles: #F3F4F6 bg, #9CA3AF icon (no teal highlights)
- Summaries: "No expenses yet", "No items yet", etc.
- No teal borders (nothing needs attention)

### State 3: Loading / Skeleton

Header — real (white bg, "Trip A", subtitle).
Below header:
- Expense summary skeleton: label placeholder (60dp wide, 12dp tall) + large number placeholder (120dp wide, 28dp tall) + 2 chip placeholders
- Module grid: 6 card skeletons in 2×3 grid (16dp radius, height ~100dp each):
  - Circle placeholder (44dp) + 2 line placeholders below
All: #E5E7EB on #F3F4F6, pulsing.

### State 4: Error

- Header — real
- OfflineBanner: amber #F59E0B, "No connection — showing cached data"
- EmptyStateView:
  - Icon: cloud-off, 48dp, #EF4444
  - Heading: "Couldn't load event" — weight 600, 20sp, #111827
  - Body: "Check your connection and try again" — weight 400, 14sp, #6B7280
  - CTA: "Retry" — 52dp, 200dp width centered, teal #0D7B74, white text, 12dp radius

## F — Constraints

```
Target width: ~390px (iPhone 14 / Pixel 7)
Single breakpoint only
Generic placeholder data: "User 1-3", "Group A", "Trip A", "OMR 45.500/10.000", "3 participants", "Mar 30–Apr 2"
Hybrid density: expense summary is spacious, module grid is compact
Module cards in 2×3 GRID (not vertical list) — all neutral gray, teal only on cards needing attention
Cards: border + shadow hybrid
NO per-module accent colors — monochrome. Modules are distinguished by icon + label only.
Light theme only
Aesthetic: Notion page structure — clean, functional, content-first
```
