# Stitch Input Prompt — Home Screen

Copy everything below this line and paste directly into Google Stitch.

---

Design a high-fidelity mobile UI mockup for the **Home Screen** of a group coordination app called Rihla. Target width ~390px (iPhone 14 / Pixel 7). Single breakpoint only. Spacious, content-first layout inspired by Notion and Airbnb — generous whitespace, typography-driven hierarchy, one accent color used sparingly.

## A — Palette

Use these exact hex values. Do not approximate or modify any color. The design is near-monochrome with a single teal accent.

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

CRITICAL: This is a monochrome neutral palette. The ONLY color accent is teal #0D7B74. All interactive elements (buttons, links, active indicators, FABs) use teal. Everything else is grayscale.

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

Border radii: 8dp (chips/tags), 12dp (buttons/inputs), 16dp (cards/sheets)
Button height: 52dp
Touch targets: minimum 48dp
```

## C — Typography

Font: **Plus Jakarta Sans**

Weight hierarchy (restrained — size creates hierarchy, not weight):
- 700 — display headings, large balance numbers
- 600 — section headers, card titles, button labels, emphasis
- 400 — body text, secondary descriptions, all regular content

Do NOT use w800 or w900. The aesthetic is quiet authority — hierarchy comes from size differences, not heavy weights.

## D — Component Inventory

The following shared components already exist in the app. Use these patterns in your design — do not invent new variants when an existing component covers the use case.

```
ModuleHeader (Default variant — white)
  — White background (blends into scaffold), no elevation
  — Title in text primary (#111827), weight 700
  — Optional subtitle in text secondary (#6B7280), weight 400
  — Back arrow: plain icon, no container (44dp touch target)
  — Used for: most screens

ModuleHeader (Elevated variant — dark)
  — Dark gradient header (#111827 → #1F2937, left-to-right)
  — White title (weight 700) + white subtitle (weight 400)
  — Used for: screens with hero sections (balance display, profile)

AppTabBar
  — Horizontal tab row with solid teal pill indicator on active tab
  — Active pill: solid #0D7B74, white label text
  — Inactive label: #6B7280 (gray-500)
  — Background: #F3F4F6 container
  — Tab label: weight 600, 14sp

EmptyStateView
  — Vertically centered layout: icon + heading + body + optional CTA button
  — Icon: 48dp, color #9CA3AF (gray-400)
  — Heading: weight 600, text primary (#111827)
  — Body: weight 400, text secondary (#6B7280)
  — CTA button: 52dp height, teal fill (#0D7B74), white text (#FFFFFF), 12dp radius

OfflineBanner
  — Thin strip at top: amber #F59E0B background, white text
  — Universal warning style — does not change with palette

SkeletonLoader
  — Rounded neutral gray placeholder blocks (#F3F4F6 base), pulsing animation
  — Matches the shape and size of the content being loaded
```

## E — Screen Description: Home Screen

Design all 4 states of the Home Screen.

### State 1: Loaded (Primary State)

The Home Screen is the app's main entry point. It uses white (#FFFFFF) as the page background. No dark header — the screen is open, airy, and Notion-like. Content breathes.

**Layout (top to bottom, vertical scroll):**

1. **App bar area** (top, full width):
   - "Your Groups" title in text primary (#111827), weight 700, 24sp
   - Right side: [+] icon button (teal #0D7B74, 48dp touch target) — NOT a FAB, just an inline icon
   - Background: white (#FFFFFF), no elevation, no border
   - Horizontal padding: 24dp

2. **Group Cards list** (vertical stack, 24dp horizontal padding, 12dp gap between cards):
   Each group card (16dp radius, card surface #F8F9FA, 1px border #E5E7EB, subtle soft shadow, 16dp padding):
   - Line 1: group name (weight 600, 16sp, text primary #111827)
   - Line 2: "5 members" (weight 400, 14sp, text secondary #6B7280)
   - Line 3: balance summary (weight 400, 14sp):
     - Use teal (#0D7B74) for "You owe OMR 10.000"
     - Use success text (#047857) for "You are owed OMR 5.500"
     - Use text secondary (#6B7280) for "Settled up"
   - Cards are SIMPLE: just text, no icons, no avatars, no colored accents. Content-first.
   - Show 2–3 cards: "Weekend Crew", "Road Trip 2026"

3. **Section gap**: 32dp

4. **Section header** "Recent Activity" in text secondary (#6B7280), weight 600, 13sp, uppercase tracking 0.5
   Horizontal padding: 24dp
   Hairline divider below: 1px #E5E7EB

5. **Activity list** (flat, no cards, Notion table aesthetic):
   Each activity item (24dp horizontal padding, 12dp vertical padding):
   - Description: weight 400, 14sp, text primary (#111827)
   - Right-aligned date: weight 400, 13sp, text muted (#9CA3AF) — decorative
   - Hairline divider (#E5E7EB) between items
   - Example items: "User 1 added OMR 10.000", "User 2 settled up", "Road Trip 2026 created"
   - Show 3–4 items
   - NO colored dots, NO icons — just text. Notion-style flat list.

### State 2: Empty (No Groups Yet)

Full-screen EmptyStateView pattern:
- App bar identical to loaded state ("Your Groups" + [+] icon)
- Centered vertically in remaining space:
  - Icon: users-plus or similar, 48dp, color #9CA3AF
  - Heading: "Create your first group" — weight 600, 20sp, text primary (#111827)
  - Body: "Plan trips, track expenses, and settle up with friends" — weight 400, 14sp, text secondary (#6B7280)
  - Gap: 24dp
  - CTA button: "Create Group" — 52dp height, full width (minus 48dp horizontal margin), teal (#0D7B74), white text (#FFFFFF), weight 600, 16sp, 12dp radius

### State 3: Loading / Skeleton

App bar identical to loaded state (real, not skeleton).
Below app bar:
- **3 Group Card skeletons**: each card shape (16dp radius, height ~80dp, #F3F4F6 fill), neutral gray placeholder lines inside:
  - Line 1: wide (70% width, height 14dp)
  - Line 2: narrow (40% width, height 12dp)
  - Gap 12dp between skeleton cards
- Gap: 32dp
- **Section label skeleton**: narrow rectangle (width ~100dp, height 12dp)
- **3 Activity row skeletons**: full width, height 12dp, spaced 12dp apart
- All skeleton blocks use border radius 8dp, color #E5E7EB on #F3F4F6 card, pulsing opacity animation

### State 4: Error

- OfflineBanner at very top: amber #F59E0B, "No connection — showing cached data"
- App bar below banner (real, not affected)
- EmptyStateView in remaining space:
  - Error icon (wifi-off or cloud-off), 48dp, color #EF4444
  - Heading: "Something went wrong" — weight 600, 20sp, text primary (#111827)
  - Body: "Check your connection and try again" — weight 400, 14sp, text secondary (#6B7280)
  - CTA button: "Retry" — 52dp height, 200dp width (centered), teal (#0D7B74), white text, 12dp radius

## F — Constraints

```
Target width: ~390px (iPhone 14 / Pixel 7)
Single breakpoint only — no responsive variants
Generic placeholder data only:
  Names: "User 1", "User 2"
  Groups: "Weekend Crew", "Road Trip 2026"
  Amounts: "OMR 10.000", "OMR 25.500", "OMR 5.500"
Spacious layout: Airbnb-style breathing room on cards and sections
Cards use border + shadow hybrid (1px #E5E7EB border AND subtle soft shadow)
No colored module accents on Home — everything is grayscale + teal for interactive
Light theme only — no dark mode variant
Aesthetic: Notion meets Airbnb — typography-driven, content-first, one accent color
```
