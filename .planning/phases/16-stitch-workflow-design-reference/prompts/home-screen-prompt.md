# Stitch Input Prompt — Home Screen

Copy everything below this line and paste directly into Google Stitch.

---

Design a high-fidelity mobile UI mockup for the **Home Screen** of a group trip planning app called Rihla. Target width ~390px (iPhone 14 / Pixel 7). Single breakpoint only. Dense, dashboard-style layout with key data visible without excessive scrolling.

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

Module accent colors (for future reference — not primary use on Home):
  Ledger: #CC6B49  |  Ledger light: #ECD5C0
  Gear: #7A8C5E    |  Gear light: #E0DAC4
  Logistics: #5B7B8C | Logistics light: #DBD7CA
  Vault: #8B7355   |  Vault light: #E2D6C2
  Activity: #A67C5B | Activity light: #E6D7C3
  Memories: #9B7A5C | Memories light: #E4D7C3

Header gradient start: #2C1A0E  |  end: #3D2B1E
```

## B — Spacing Scale

All padding, gaps, and margins must align to this scale. Do not use non-scale values (e.g., 6dp, 10dp, 15dp).

Scale: 4dp, 8dp, 12dp, 16dp (base), 20dp, 24dp, 32dp

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
- 800 — screen headings, large numbers (balance amounts)
- 700 — card titles, section headers, button labels
- 600 — body emphasis, labels, chips
- 400 — body text, secondary descriptions

## D — Component Inventory

The following shared components already exist in the app. Use these patterns in your design — do not invent new variants when an existing component covers the use case.

```
ModuleHeader
  — Dark gradient header (#2C1A0E → #3D2B1E, left-to-right)
  — White title (weight 800) + optional white subtitle (weight 400)
  — Optional action icon buttons (right side, 48dp touch target)
  — Used for: all detail screens that push from Home

AppTabBar
  — Horizontal tab row with gradient pill indicator on active tab
  — Active pill uses primary terracotta (#CC6B49)
  — Tab label: weight 600, 14sp
  — Used for: screens with multiple content sections

EmptyStateView
  — Vertically centered layout: icon placeholder + heading + body message + optional CTA button
  — Heading: weight 700, text primary (#2C1A0E)
  — Body: weight 400, text secondary (#6B5B4E)
  — CTA button: 52dp height, primary terracotta fill (#CC6B49), white text (#FFFFFF), 16dp radius
  — Used for: all empty state screens and sections

SmartModuleCard
  — List-style card with: 44×44 circle icon container (colored background), title (weight 700), subtitle/summary text (weight 400), right-side chevron
  — Card surface: #FFF9F2, 20dp radius, subtle shadow
  — Used for: Event Hub module list

OfflineBanner
  — Thin strip at top of screen (or below app bar) indicating connectivity loss
  — Background: error display (#EF4444) or muted tone
  — Text: short message, weight 600
  — Used for: all error states when offline is the likely cause

SkeletonLoader
  — Rounded grey placeholder blocks, pulsing animation
  — Matches the shape and size of the content being loaded
  — Used for: all loading states
```

## E — Screen Description: Home Screen

Design all 4 states of the Home Screen.

### State 1: Loaded (Primary State)

The Home Screen is the app's main dashboard. It uses the sand background (#F2E8D6) as the page background. No dark header — the screen is open and light.

**Layout (top to bottom, vertical scroll):**

1. **App bar area** (top, full width):
   - "Rihla" wordmark or app name in text primary (#2C1A0E), weight 800, 24sp
   - Settings icon button (right side, 48dp touch target)
   - Background: sand (#F2E8D6), no elevation

2. **Balance Hero Card** (full-width card, 20dp radius, card surface #FFF9F2, subtle shadow):
   - Small label: "Net Balance" in text secondary (#6B5B4E), weight 600, 12sp
   - Large amount: e.g., "OMR 15.250" in weight 800, 28sp
     - If user owes: use error text (#B91C1C) — "You owe OMR 15.250"
     - If user is owed: use success text (#047857) — "You are owed OMR 8.500"
     - If settled: use text secondary (#6B5B4E) — "All settled"
   - Horizontal rule / divider (#E5D5C0)
   - Small "across N groups" caption in text secondary (#6B5B4E), weight 400, 12sp
   - Card padding: 16dp all sides

3. **Section label** "Your Groups" in text primary (#2C1A0E), weight 700, 16sp
   Horizontal padding: 16dp

4. **Group Cards list** (vertical stack, each card is full-width minus 16dp horizontal margin):
   Each group card (20dp radius, card surface #FFF9F2, subtle shadow, 16dp padding):
   - Row: group name (weight 700, 16sp, text primary) + member count chip (right side)
   - Member count chip: "4 members" — border radius 12dp, fill #F5EDE1, text #6B5B4E, weight 600, 12sp
   - Balance summary line (weight 400, 14sp): show net for current user in this group
     - Use error text (#B91C1C) for "You owe OMR 10.000"
     - Use success text (#047857) for "You are owed OMR 5.500"
     - Use text secondary (#6B5B4E) for "Settled up"
   - Last activity line: "2 days ago" in text muted (#A89888) — this is decorative metadata, 12sp, weight 400
   - Card gap between cards: 8dp
   - Show 2–3 group cards: "Group A", "Group B"

5. **Section label** "Recent Activity" in text primary (#2C1A0E), weight 700, 16sp
   Horizontal padding: 16dp

6. **Activity strip** (last 3 items, compact list):
   Each activity item (no card, just row with 16dp horizontal padding, 12dp vertical padding):
   - Left: small colored circle (12dp) in module accent color
   - Center: description text (weight 400, 14sp, text primary), with sub-text date (weight 400, 12sp, text muted — decorative)
   - No chevron
   - Divider (#E5D5C0) between items
   - Example items: "User 1 added OMR 10.000", "User 2 settled up with User 1", "Group A created"

7. **FAB Tray** (pinned above bottom of screen, visible without scrolling):
   - 4 small circular action buttons in a horizontal row: Add Expense, Settle Up, Invite, Activity
   - Each button: 48dp circle, primary terracotta fill (#CC6B49), white icon (#FFFFFF)
   - Button labels below icon: weight 600, 10sp, text secondary (#6B5B4E)
   - Row centered horizontally, card surface background strip behind row (#FFF9F2), subtle top shadow
   - Row sits above a larger primary FAB (56dp circle, #CC6B49) — or the 4 buttons ARE the FAB tray

### State 2: Empty (No Groups Yet)

Full-screen EmptyStateView pattern:
- App bar identical to loaded state
- Centered vertically in remaining space:
  - Illustration placeholder (128×128 rounded square, border #E5D5C0, text "illustration")
  - Heading: "Create your first group" — weight 700, 20sp, text primary (#2C1A0E)
  - Body: "Plan trips, track expenses, and settle up with friends" — weight 400, 14sp, text secondary (#6B5B4E)
  - Gap: 24dp
  - CTA button: "Create Group" — 52dp height, full width (minus 32dp horizontal margin), primary terracotta (#CC6B49), white text (#FFFFFF), weight 700, 16sp, 16dp radius

### State 3: Loading / Skeleton

App bar identical to loaded state (real, not skeleton).
Below app bar:
- **Balance Hero skeleton**: full-width card shape (20dp radius), pulsing grey placeholder (height ~80dp)
- Gap: 16dp
- **Section label skeleton**: narrow rectangle (width ~100dp, height 16dp)
- Gap: 12dp
- **3 Group Card skeletons**: each card shape (20dp radius, height ~80dp), grey placeholder lines inside:
  - Line 1: wide (70% width, height 14dp)
  - Line 2: narrow (40% width, height 12dp)
  - Gap 8dp between skeleton cards
- All skeleton blocks use border radius 8dp, color #E5D5C0, pulsing opacity animation

### State 4: Error

- OfflineBanner at very top (below status bar): "No connection — showing cached data" or "Could not load your groups"
- App bar below banner (real, not affected)
- EmptyStateView in remaining space:
  - Error icon (e.g., wifi-off or cloud-off), 48dp, color #EF4444
  - Heading: "Something went wrong" — weight 700, 20sp, text primary (#2C1A0E)
  - Body: "Check your connection and try again" — weight 400, 14sp, text secondary (#6B5B4E)
  - CTA button: "Retry" — 52dp height, 200dp width (centered), primary terracotta (#CC6B49), white text, 16dp radius

## F — Constraints

```
Target width: ~390px (iPhone 14 / Pixel 7)
Single breakpoint only — no responsive variants
Generic placeholder data only:
  Names: "User 1", "User 2"
  Groups: "Group A", "Group B"
  Events: "Trip A"
  Amounts: "OMR 10.000", "OMR 25.500", "OMR 15.250", "OMR 8.500"
Dense information density: dashboard-style, key data visible with minimal scrolling
Light theme only — no dark mode variant
```
