# Stitch Input Prompt — Group Detail Screen

Copy everything below this line and paste directly into Google Stitch.

---

Design a high-fidelity mobile UI mockup for the **Group Detail Screen** of a group trip planning app called Rihla. Target width ~390px (iPhone 14 / Pixel 7). Single breakpoint only. Dense dashboard layout — all key data visible without scrolling on a standard phone (~844dp tall viewport).

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

Module accent colors (for event type chips and event cards):
  Trip / Ledger: #CC6B49  |  Trip light: #ECD5C0
  Gear / Camping: #7A8C5E  |  Camping light: #E0DAC4
  Logistics / Day Out: #5B7B8C | Day Out light: #DBD7CA
  Vault / Dinner: #8B7355  |  Dinner light: #E2D6C2
  Activity: #A67C5B | Activity light: #E6D7C3
  Memories: #9B7A5C | Memories light: #E4D7C3

Header gradient start: #2C1A0E  |  end: #3D2B1E
```

Event type color mapping for event type chips and cards:
- Trip → terracotta #CC6B49 / #ECD5C0
- Camping → olive #7A8C5E / #E0DAC4
- Day Out → dusty teal #5B7B8C / #DBD7CA
- Dinner → warm bronze #8B7355 / #E2D6C2
- Custom → caramel #A67C5B / #E6D7C3

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
  — Back arrow icon (left side, 48dp touch target) + optional right action icons (settings gear, 48dp)
  — Used for: this screen (Group Detail header)

AppTabBar
  — Horizontal tab row with gradient pill indicator on active tab
  — Active pill uses primary terracotta (#CC6B49)
  — Tab label: weight 600, 14sp
  — Used for: optional tab layout (Events / Members / Activity)

EmptyStateView
  — Vertically centered layout: icon placeholder + heading + body message + optional CTA button
  — Heading: weight 700, text primary (#2C1A0E)
  — Body: weight 400, text secondary (#6B5B4E)
  — CTA button: 52dp height, primary terracotta fill (#CC6B49), white text (#FFFFFF), 16dp radius
  — Used for: empty events section

SmartModuleCard
  — List-style card with: 44×44 circle icon container (colored background), title (weight 700), subtitle/summary text (weight 400), right-side chevron
  — Card surface: #FFF9F2, 20dp radius, subtle shadow
  — Not primary use on this screen (used in Event Hub)

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

## E — Screen Description: Group Detail Screen

Design all 4 states of the Group Detail Screen.

### State 1: Loaded (Primary State)

The Group Detail Screen is a dense dashboard. All key data should be visible without scrolling on a ~844dp tall phone screen. Background: sand (#F2E8D6).

**Layout (top to bottom):**

1. **ModuleHeader** (full-width, dark gradient #2C1A0E → #3D2B1E):
   - Back arrow (left, white, 48dp)
   - Title: "Group A" — white, weight 800, 20sp
   - Subtitle: "4 members · OMR 125.500 total" — white, weight 400, 13sp
   - Right: settings gear icon (white, 48dp)

2. **Summary Strip** (horizontal row, 16dp horizontal padding, 12dp vertical padding):
   - "4 members" chip: 12dp radius, fill #F5EDE1, text #6B5B4E, weight 600, 12sp
   - Gap: 8dp
   - "OMR" chip (currency indicator): same style
   - Right side: "Invite Code: ABC123" — small chip, fill #F5DDD3 (selection fill), text #CC6B49, weight 600, 12sp, tap to copy

3. **Balance Hero Card** (full-width minus 16dp horizontal margin, 20dp radius, card surface #FFF9F2, shadow):
   - Row: "Your Balance" label (weight 600, 12sp, text secondary) aligned left | "Settle Up" CTA button aligned right
     - "Settle Up" button: 36dp height, 16dp radius, primary #CC6B49 fill, white text (#FFFFFF), weight 700, 13sp
   - Large balance: "You owe OMR 10.000" — weight 800, 22sp, error text (#B91C1C)
     OR "You are owed OMR 5.500" — weight 800, 22sp, success text (#047857)
     OR "All settled" — weight 700, 18sp, text secondary (#6B5B4E)
   - Divider (#E5D5C0)
   - "Group total: OMR 125.500" — weight 400, 13sp, text secondary (#6B5B4E)
   - Card padding: 12dp all sides

4. **Member Balances section** (compact, no section label needed — inline below balance card):
   Gap: 8dp below balance card.
   Horizontal scroll row OR compact vertical list (2–3 members visible):
   Each member balance item (horizontal row, 12dp vertical padding, 16dp horizontal padding):
   - Left: member initial avatar (32dp circle, fill #F5EDE1, text #6B5B4E, weight 700, 14sp)
   - Center: "User 1" name (weight 600, 14sp, text primary) + small balance line below (weight 400, 12sp)
     - "owes OMR 10.000" in error text (#B91C1C)
     - "owed OMR 5.500" in success text (#047857)
     - "settled" in text secondary (#6B5B4E)
   - Divider between items (#E5D5C0)
   - Show: User 1, User 2, User 3 (max 3 visible, "+1 more" link if 4+)

5. **Events section** (labeled "Events", weight 700, 16sp, text primary):
   Gap: 12dp.
   Vertical list of event cards (each card: full-width minus 16dp horizontal margin, 20dp radius, 12dp padding):

   **Upcoming event card** (full color):
   - Left: event type chip pill (12dp radius, accent fill e.g., #ECD5C0, accent text e.g., #CC6B49) showing "Trip"
   - Title: "Trip A" — weight 700, 15sp, text primary (#2C1A0E)
   - Date: "Mar 30–Apr 2, 2026" — weight 400, 12sp, text secondary (#6B5B4E)
   - Expense summary: "OMR 45.500 · 3 expenses" — weight 600, 13sp, text primary
   - Right: chevron icon, text secondary
   - Card surface: #FFF9F2, subtle shadow

   **Past event card** (muted/desaturated):
   - Same structure, but card surface tinted slightly muted — border color #E5D5C0, no shadow
   - Title in text secondary (#6B5B4E) instead of text primary
   - Date: "Jan 15–18, 2026" — weight 400, 12sp, text muted (#A89888) — this is purely decorative metadata, acceptable use for date labels

6. **Recent Activity strip** (bottom, 3 items, compact):
   Section label: "Recent Activity" — weight 700, 14sp, text secondary
   Each item: small colored dot (8dp, module accent color) + description (weight 400, 13sp, text primary) + date (weight 400, 11sp, text muted — decorative)
   Examples: "User 1 added OMR 10.000", "User 2 joined", "Trip A created"

### State 2: Empty (No Events Yet)

ModuleHeader — identical to loaded state (real, not skeleton).
Summary strip — identical to loaded state (shows members, currency, invite code).
Balance hero card — shows "All settled" or "OMR 0.000" with disabled settle-up button.
Member balances — shows member list (members exist even with no events).

Events section — uses EmptyStateView:
- Icon: calendar-plus or similar, 40dp, color #CC6B49
- Heading: "Create your first event" — weight 700, 18sp, text primary
- Body: "Add a trip, dinner, or any occasion to track together" — weight 400, 14sp, text secondary
- CTA: "Create Event" — 52dp height, primary terracotta (#CC6B49), white text, 16dp radius, full width minus 32dp margin

Recent activity strip: "No activity yet" in text secondary, centered.

### State 3: Loading / Skeleton

ModuleHeader — real (dark gradient, shows "Group A").
OfflineBanner: hidden in loading state.

Below header:
- Summary strip skeleton: 2 rectangle placeholders (12dp radius, #E5D5C0, height 28dp, width 80dp each)
- Balance hero card skeleton: full card shape, 20dp radius, 2 grey lines inside
- Member balance row skeletons: 3 rows, each with circle placeholder (32dp) + 2 line placeholders
- Events section header skeleton: rectangle (width 60dp, height 14dp)
- 2 event card skeletons: full-width shape (20dp radius, height 72dp)

All skeleton blocks: color #E5D5C0, pulsing opacity animation.

### State 4: Error

- ModuleHeader — real (dark gradient, shows "Group A", back arrow, settings)
- OfflineBanner immediately below header: "No connection — showing cached data"
- EmptyStateView in remaining space:
  - Error icon (cloud-off or wifi-off), 48dp, color #EF4444
  - Heading: "Couldn't load group" — weight 700, 20sp, text primary (#2C1A0E)
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
  Amounts: "OMR 10.000", "OMR 45.500", "OMR 125.500", "OMR 5.500"
  Invite code: "ABC123"
Dense dashboard layout: all key data visible without scrolling on standard phone (~844dp)
Light theme only — no dark mode variant
```
