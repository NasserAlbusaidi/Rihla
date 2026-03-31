# Phase 21: Module Screens Redesign - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-03-30
**Phase:** 21-module-screens-redesign
**Areas discussed:** Expense card design, Empty state style, Module layout template, Form flow redesign, Vault document layout, Activity timeline style, Logistics sub-group cards

---

## Expense Card Design

### Card Info Density

| Option | Description | Selected |
|--------|-------------|----------|
| Full detail | Payer name, amount, category icon, date, split indicator, who-owes-what summary | ✓ |
| Compact summary | Payer name, amount, balance line only | |
| Two-line with icon | Category icon left, title + amount line 1, balance line 2 | |

**User's choice:** Full detail
**Notes:** Matches the info-dense style from Phase 20 event cards

### Color Coding

| Option | Description | Selected |
|--------|-------------|----------|
| Text color only | Balance text changes color (green/red/gray), card bg stays white | ✓ |
| Left accent bar + text | Colored left border plus colored text | |
| Tinted card background | Entire card gets subtle color tint | |

**User's choice:** Text color only
**Notes:** Consistent with Phase 20 event card color coding

### Ledger Hero Card

| Option | Description | Selected |
|--------|-------------|----------|
| Balance summary hero | Card with balance, total, expense count, settle-up CTA | ✓ |
| No hero | Jump straight to cards | |
| Inline stats row | Compact single-row stats | |

**User's choice:** Balance summary hero

### Settlement Display

| Option | Description | Selected |
|--------|-------------|----------|
| Mixed timeline | Settlements and expenses in one chronological list | ✓ |
| Separate tabs | Expenses and settlements in separate tabs | |
| Settlements below expenses | All expenses first, then settlements section | |

**User's choice:** Mixed timeline

### Ledger Tabs

| Option | Description | Selected |
|--------|-------------|----------|
| Single scroll | Hero → mixed timeline. No tabs. | ✓ |
| Keep tabs | Preserve Spending/Balances tabs | |
| Segmented control | Compact filter control | |

**User's choice:** Single scroll

### Add Expense Button

| Option | Description | Selected |
|--------|-------------|----------|
| Floating action button | Bottom-right FAB | |
| Inline in hero card | "+ Add Expense" chip inside hero, next to Settle Up | ✓ |
| Header action button | '+' icon in ModuleHeader | |

**User's choice:** Inline in hero card

### Swipe Actions

| Option | Description | Selected |
|--------|-------------|----------|
| Tap to edit only | Tap opens edit sheet. No swipe/long-press. | ✓ |
| Swipe to reveal actions | Swipe left reveals Edit/Delete | |
| Long-press context menu | Long press shows bottom sheet menu | |

**User's choice:** Tap to edit only

### Edit Flow

| Option | Description | Selected |
|--------|-------------|----------|
| Bottom sheet | Tap opens bottom sheet with editable fields | ✓ |
| Full-screen edit page | Navigate to dedicated edit screen | |
| Inline editing | Card expands in-place | |

**User's choice:** Bottom sheet

---

## Empty State Style

### Visual Style

| Option | Description | Selected |
|--------|-------------|----------|
| Icon + warm gradient circle | 48dp icon in 72dp gradient circle, title, subtitle, CTA | ✓ |
| Custom SVG illustrations | Hand-drawn illustrations per module | |
| Minimal text-only | Centered text with CTA only | |
| Lottie animations | Animated illustrations per module | |

**User's choice:** Icon + warm gradient circle

### Circle Colors

| Option | Description | Selected |
|--------|-------------|----------|
| Module accent colors | Each module uses its Phase 15 accent color | ✓ |
| Uniform teal/primary | All use primary teal | |
| Uniform sand/neutral | All use warm sand gradient | |

**User's choice:** Module accent colors

### CTA Text

| Option | Description | Selected |
|--------|-------------|----------|
| Module-specific | Each CTA matches module action | ✓ |
| Generic "Get Started" | All use same CTA text | |

**User's choice:** Module-specific

---

## Module Layout Template

### Layout Structure

| Option | Description | Selected |
|--------|-------------|----------|
| Unified template | All modules: Header → Hero → Content list | ✓ |
| Per-module layouts | Each module keeps its own layout | |
| Two templates | List modules vs grid modules | |

**User's choice:** Unified template

### Hero Cards

| Option | Description | Selected |
|--------|-------------|----------|
| Stats + CTA per module | Each hero shows 2-3 metrics + primary action | ✓ |
| Minimal metric + CTA | Single number + action | |
| You decide | Claude picks | |

**User's choice:** Stats + CTA per module

### Header Style

| Option | Description | Selected |
|--------|-------------|----------|
| All dark gradient | Every module uses dark gradient header | ✓ |
| Module accent headers | Per-module accent color headers | |
| Light headers | Sand/cream background | |

**User's choice:** All dark gradient

### Card Style

| Option | Description | Selected |
|--------|-------------|----------|
| Standardize at 16dp/24r | 16dp padding, 24dp radius, cardShadow, surface bg | ✓ |
| 20dp padding | More breathing room | |
| Mixed by density | Adapt spacing to content density | |

**User's choice:** Standardize at 16dp/24r

---

## Form Flow Redesign

### Redesign Depth

| Option | Description | Selected |
|--------|-------------|----------|
| Reskin + polish | Apply earthy tokens, add card containers, keep step flow | ✓ |
| Visual + flow rethink | Redesign both visuals and step flow | |
| Minimal token swap | Only replace color values | |

**User's choice:** Reskin + polish

### Form Inputs

| Option | Description | Selected |
|--------|-------------|----------|
| Shared theme | One InputDecorationTheme in app_theme.dart | ✓ |
| Per-form customization | Each form overrides theme | |

**User's choice:** Shared theme

### Onboarding

| Option | Description | Selected |
|--------|-------------|----------|
| Earthy hero images + warm typography | Large icon in gradient circle, earthy dots, terracotta CTA | ✓ |
| Full-bleed gradient backgrounds | Full-screen earthy gradients per page | |
| Minimal token swap | Just replace colors | |

**User's choice:** Earthy hero images + warm typography

### Splash Screen

| Option | Description | Selected |
|--------|-------------|----------|
| Sand background + logo | Sand bg, dark brown logo centered | ✓ |
| Gradient splash | Dark brown → sand gradient | |
| You decide | Claude picks | |

**User's choice:** Sand background + logo

### Settings Layout

| Option | Description | Selected |
|--------|-------------|----------|
| Section cards | iOS grouped-table style with card sections | ✓ |
| Flat list with dividers | Current flat layout with tokens | |
| You decide | Claude picks | |

**User's choice:** Section cards

### Add Expense Step Indicator

| Option | Description | Selected |
|--------|-------------|----------|
| Numbered dots | Terracotta dots: filled/outlined/checked | ✓ |
| Progress bar | Horizontal bar that fills | |
| No indicator | Keep as-is | |

**User's choice:** Numbered dots

### Memories Layout

| Option | Description | Selected |
|--------|-------------|----------|
| Photo grid | 3-column grid, 8dp gap, 8dp radius thumbnails | ✓ |
| Card list like other modules | Memory cards with thumbnail + metadata | |
| You decide | Claude picks | |

**User's choice:** Photo grid

---

## Vault Document Layout

| Option | Description | Selected |
|--------|-------------|----------|
| File type icon + metadata card | 52dp icon container, title, size/date/uploader metadata | ✓ |
| Thumbnail grid for images | Split view based on file type | |
| Compact list rows | Dense ListTile rows | |

**User's choice:** File type icon + metadata card

---

## Activity Timeline Style

| Option | Description | Selected |
|--------|-------------|----------|
| Date-grouped flat list | Sticky date headers, avatar + action cards, no connector line | ✓ |
| Vertical timeline connector | Classic timeline with vertical line and dots | |
| Simple flat list | No date grouping, just chronological | |

**User's choice:** Date-grouped flat list

---

## Logistics Sub-group Cards

### Card Layout

| Option | Description | Selected |
|--------|-------------|----------|
| Card with member chips + capacity bar | Name, capacity bar, member chips. Dusty teal accent. | ✓ |
| Simple member list card | Name, count, vertical member list | |
| Keep current tab layout | Apply tokens to current layout | |

**User's choice:** Card with member chips + capacity bar

### Logistics Tabs

| Option | Description | Selected |
|--------|-------------|----------|
| Single scroll | Hero → sub-group card list. Drop tabs. | ✓ |
| Keep tabs | All Members / By Group tabs | |

**User's choice:** Single scroll

---

## Claude's Discretion

- Hero card layout composition details
- Skeleton loading variants for Ledger and Memories
- Date-grouped section implementation
- Gear hero adaptation
- SearchFilterBar retention on Gear/Vault
- Card entrance animations
- Photo grid implementation

## Deferred Ideas

None — discussion stayed within phase scope
