# Stitch Input Prompt — Group Detail Screen

Copy everything below this line and paste directly into Google Stitch.

---

Design a high-fidelity mobile UI mockup for the **Group Detail Screen** of a group coordination app called Rihla. Target width ~390px (iPhone 14 / Pixel 7). Single breakpoint only. Dense dashboard layout — balance data and member list visible without scrolling. Financial sections are compact and scannable (Notion-style), navigation sections breathe (Airbnb-style).

## A — Palette

Use these exact hex values. Do not approximate or modify any color. Near-monochrome with single teal accent.

```
Primary (teal): #0D7B74
Background (white): #FFFFFF
Card surface (cool gray): #F8F9FA
Input fill (gray-100): #F3F4F6
Border / divider (gray-200): #E5E7EB
Text primary (gray-900): #111827
Text secondary (gray-500): #6B7280
Text muted (gray-400): #9CA3AF  ← DECORATIVE ONLY — do not use for functional text, labels, amounts, or actions
Text on primary (white): #FFFFFF
Success display (badge/icon only): #10B981
Success text (WCAG-safe, readable): #047857
Error display (badge/icon only): #EF4444
Error text (WCAG-safe, readable): #B91C1C
Selection fill (teal 10% tint): #E6F5F3
Disabled background: #E5E7EB
Disabled text: #9CA3AF

Header gradient start: #111827  |  end: #1F2937
```

CRITICAL: Monochrome neutral palette. Only teal #0D7B74 for interactive elements.

## B — Spacing Scale

All padding, gaps, and margins must align to this scale.

```
4dp, 8dp, 12dp, 16dp (base), 20dp, 24dp, 32dp

Border radii: 8dp (chips/tags), 12dp (buttons/inputs), 16dp (cards/sheets)
Button height: 52dp
Touch targets: minimum 48dp
```

## C — Typography

Font: **Plus Jakarta Sans**

Weight hierarchy (restrained):
- 700 — display headings, large balance numbers
- 600 — section headers, card titles, button labels
- 400 — body text, descriptions

## D — Component Inventory

```
ModuleHeader (Elevated variant — dark)
  — Dark gradient header (#111827 → #1F2937)
  — White title (weight 700) + white subtitle (weight 400)
  — Back arrow + settings gear (white, 48dp touch targets)
  — Used for: this screen's header

AppTabBar
  — Solid teal pill indicator (#0D7B74), white text on active
  — Inactive: #6B7280 text
  — Background: #F3F4F6 container

EmptyStateView
  — Icon 48dp #9CA3AF + heading #111827 w600 + body #6B7280 w400
  — CTA: 52dp, teal #0D7B74, white text, 12dp radius

OfflineBanner
  — Amber #F59E0B strip, white text

SkeletonLoader
  — #F3F4F6 base, #E5E7EB shapes, pulsing
```

## E — Screen Description: Group Detail Screen

Design all 4 states.

### State 1: Loaded (Primary State)

Dense dashboard. Balance data and member list visible without scrolling. Background: white (#FFFFFF).

**Layout (top to bottom):**

1. **ModuleHeader** (elevated, dark gradient #111827 → #1F2937):
   - Back arrow (left, white, 48dp)
   - Title: "Weekend Crew" — white, weight 700, 20sp
   - Subtitle: "4 members · OMR 125.500 total" — white, weight 400, 13sp
   - Right: settings gear icon (white, 48dp)

2. **Summary Strip** (horizontal row, 16dp horizontal padding, 12dp vertical padding, white bg):
   - "4 members" chip: 8dp radius, fill #F3F4F6, text #6B7280, weight 600, 12sp
   - Gap: 8dp
   - "OMR" chip: same style
   - Right side: "Invite: ABC123" — chip, fill #E6F5F3 (teal tint), text #0D7B74, weight 600, 12sp, tap to copy

3. **Balance Card** (full-width minus 24dp horizontal margin, 16dp radius, #F8F9FA surface, 1px #E5E7EB border, soft shadow):
   - Row: "Your Balance" label (weight 600, 12sp, #6B7280) | "Settle Up" button (36dp height, 12dp radius, teal #0D7B74, white text, weight 600, 13sp)
   - Large balance: "You owe OMR 10.000" — weight 700, 22sp, teal (#0D7B74)
     OR "You are owed OMR 5.500" — weight 700, 22sp, success text (#047857)
     OR "All settled" — weight 600, 18sp, text secondary (#6B7280)
   - Hairline divider (#E5E7EB)
   - "Group total: OMR 125.500" — weight 400, 13sp, #6B7280
   - Card padding: 16dp

4. **Member Balances** (compact flat list, Notion-style — NO cards, just rows with dividers):
   Gap: 12dp below balance card.
   Each member row (12dp vertical padding, 24dp horizontal padding):
   - Left: member initial (32dp circle, #F3F4F6 fill, #111827 text, weight 600, 14sp)
   - Center: "User 1" (weight 600, 14sp, #111827) + balance below (weight 400, 12sp):
     - "owes OMR 10.000" in teal (#0D7B74)
     - "owed OMR 5.500" in success text (#047857)
     - "settled" in #6B7280
   - Hairline divider between rows (#E5E7EB)
   - Show: User 1, User 2, User 3 (max 3, "+1 more" link if 4+)

5. **Events section** (label "Events", weight 600, 13sp, #6B7280, uppercase tracking 0.5):
   Hairline divider below label.
   Gap: 12dp.
   Event cards (16dp radius, #F8F9FA, 1px border #E5E7EB, soft shadow, 16dp padding):

   **Upcoming event card:**
   - Event type text: "Trip" — weight 600, 12sp, teal (#0D7B74)
   - Title: "Trip A" — weight 600, 15sp, #111827
   - Date: "Mar 30–Apr 2, 2026" — weight 400, 12sp, #6B7280
   - Expense summary: "OMR 45.500 · 3 expenses" — weight 600, 13sp, #111827
   - Right: chevron icon, #6B7280

   **Past event card** (muted):
   - Same structure, border #E5E7EB, no shadow
   - Title in #6B7280 instead of #111827
   - Date in #9CA3AF (decorative)

   Show 1 upcoming + 1 past event. Gap 8dp between cards.

6. **Recent Activity** (compact, bottom):
   Section label: "Recent Activity" — weight 600, 13sp, #6B7280, uppercase
   Hairline divider.
   Each item: description (weight 400, 13sp, #111827) + right-aligned date (#9CA3AF, decorative)
   Hairline dividers between items. No icons, no dots.
   3 items: "User 1 added OMR 10.000", "User 2 joined", "Trip A created"

### State 2: Empty (No Events Yet)

ModuleHeader — identical to loaded.
Summary strip — identical (members, currency, invite code).
Balance card — "All settled" or "OMR 0.000", settle-up button disabled (#E5E7EB fill, #9CA3AF text).
Member balances — shows member list (members exist even with no events).

Events section — EmptyStateView:
- Icon: calendar-plus, 48dp, #9CA3AF
- Heading: "Create your first event" — weight 600, 18sp, #111827
- Body: "Add a trip, dinner, or any occasion to track together" — weight 400, 14sp, #6B7280
- CTA: "Create Event" — 52dp, full width minus 48dp margin, teal #0D7B74, white text, 12dp radius

Activity: "No activity yet" centered, #6B7280.

### State 3: Loading / Skeleton

ModuleHeader — real (dark gradient, "Weekend Crew").
Below header:
- Summary strip skeleton: 2 pills (#E5E7EB, 8dp radius, 80dp width, 28dp height)
- Balance card skeleton: 16dp radius card, 2 gray lines
- 3 member row skeletons: circle (32dp) + 2 lines
- Events section label skeleton + 2 card skeletons (16dp radius, 72dp height)
All: #E5E7EB on #F3F4F6, pulsing.

### State 4: Error

- ModuleHeader — real
- OfflineBanner: amber #F59E0B, "No connection — showing cached data"
- EmptyStateView:
  - Icon: cloud-off, 48dp, #EF4444
  - Heading: "Couldn't load group" — weight 600, 20sp, #111827
  - Body: "Check your connection and try again" — weight 400, 14sp, #6B7280
  - CTA: "Retry" — 52dp, 200dp width centered, teal #0D7B74, white text, 12dp radius

## F — Constraints

```
Target width: ~390px (iPhone 14 / Pixel 7)
Single breakpoint only
Generic placeholder data: "User 1-3", "Weekend Crew", "Trip A", "OMR 10.000/45.500/125.500/5.500", "ABC123"
Dense dashboard: balance + members + events visible without scrolling
Cards: border + shadow hybrid (1px #E5E7EB + soft shadow)
Financial rows: flat list with hairline dividers (Notion table style), NOT cards
Light theme only
Aesthetic: Notion (dense data) meets Airbnb (breathing room on navigation)
```
