# Design Overhaul: Clean Slate + Soft Shadows

**Date:** 2026-03-28
**Status:** Approved
**Supersedes:** 2026-03-06-ui-ux-overhaul-design.md (earthy palette direction)

## Design Intent

Near-monochrome neutral UI with a single teal accent (`#0D7B74`). Inspired by Notion (typography-driven hierarchy, content-first) and Airbnb (generous whitespace on navigation screens, soft tactile shadows). Icon/typography-driven — no imagery on cards.

**Density strategy:** Navigation screens (home, event hub) are spacious. Data screens (ledger, gear lists) are dense and scannable.

**Migration approach:** Value swap on existing Phase 15 token infrastructure. No structural changes to `AppColorTokens`, `AppSpacingTokens`, or `AppShadowTokens` classes.

---

## 1. Color Palette

### Core Tokens

| Token | Hex | Contrast on #FFF | Role |
|-------|-----|-----------------|------|
| `primary` | `#0D7B74` | 5.12:1 AA | Buttons, FABs, links, active states |
| `scaffoldBackground` | `#FFFFFF` | — | Page background |
| `cardSurface` | `#F8F9FA` | — | Card/surface background |
| `inputFill` | `#F3F4F6` | — | Input backgrounds |
| `border` | `#E5E7EB` | — | Dividers, card borders |
| `textPrimary` | `#111827` | 17.15:1 AAA | Headlines, body text |
| `textSecondary` | `#6B7280` | 5.03:1 AA | Secondary labels |
| `textMuted` | `#9CA3AF` | 2.86:1 decorative only | Hints, placeholders |
| `textOnPrimary` | `#FFFFFF` | 5.12:1 on teal AA | Text on primary buttons |
| `success` | `#10B981` | — | Income badges/icons (display only) |
| `successText` | `#047857` | 5.92:1 AA | Success text |
| `error` | `#EF4444` | — | Debt badges/icons (display only) |
| `errorText` | `#B91C1C` | 6.57:1 AA | Error text |
| `disabled` | `#E5E7EB` | — | Disabled backgrounds |
| `disabledText` | `#9CA3AF` | — | Disabled text |
| `focusRing` | `#0D7B74` | — | Focus indicator |
| `selectionFill` | `#E6F5F3` | — | Selected chip/item background (teal-50) |

### Module Accents — Collapsed

All modules use neutral gray. Only Ledger (primary financial module) gets the teal accent.

| Token | Hex | Role |
|-------|-----|------|
| `moduleLedger` | `#0D7B74` | Ledger accent (teal) |
| `moduleLedgerLight` | `#E6F5F3` | Ledger light tint (teal-50) |
| `moduleGear` | `#6B7280` | Neutral (gray-500) |
| `moduleGearLight` | `#F3F4F6` | Neutral light (gray-100) |
| `moduleLogistics` | `#6B7280` | Neutral (gray-500) |
| `moduleLogisticsLight` | `#F3F4F6` | Neutral light (gray-100) |
| `moduleVault` | `#6B7280` | Neutral (gray-500) |
| `moduleVaultLight` | `#F3F4F6` | Neutral light (gray-100) |
| `moduleActivity` | `#6B7280` | Neutral (gray-500) |
| `moduleActivityLight` | `#F3F4F6` | Neutral light (gray-100) |
| `moduleMemories` | `#6B7280` | Neutral (gray-500) |
| `moduleMemoriesLight` | `#F3F4F6` | Neutral light (gray-100) |

### Header Gradient

| Token | Hex |
|-------|-----|
| `headerGradientStart` | `#111827` (gray-900) |
| `headerGradientEnd` | `#1F2937` (gray-800) |

### Gradients

| Name | Colors | Use |
|------|--------|-----|
| `darkHeaderGradient` | `#111827` → `#1F2937` | Elevated header variant |
| `primaryGradient` | `#0D7B74` → `#0A6B65` | Accent gradient (rare — prefer solid teal) |
| `backgroundGradient` | Removed | White scaffold doesn't need a gradient |

### Shadows

Base color: `#111827` (neutral gray-900, replaces warm brown `#2C1A0E`).

| Level | Layer 1 | Layer 2 |
|-------|---------|---------|
| `flat` | — | — |
| `raised` | 10px blur, 4dp offset, 4% opacity | 4px blur, 2dp offset, 2% opacity |
| `floating` | 24px blur, 8dp offset, 7% opacity | 10px blur, 4dp offset, 3% opacity |

Slightly higher opacity than the earthy palette (white backgrounds need more shadow presence to read).

---

## 2. Typography

**Font:** Plus Jakarta Sans (no change).

**Philosophy:** Lighter weights across the board. Hierarchy from size difference, not weight. Only display sizes use w700+. Body text uses w400 (regular). This is the Notion approach — quiet authority.

| Style | Size | Weight | Letter Spacing | Color |
|-------|------|--------|---------------|-------|
| `displayLarge` | 44px | w800 | -1.0 | textPrimary |
| `displayMedium` | 36px | w700 | -0.5 | textPrimary |
| `displaySmall` | 28px | w700 | -0.3 | textPrimary |
| `headlineLarge` | 24px | w700 | -0.3 | textPrimary |
| `headlineMedium` | 20px | w600 | 0 | textPrimary |
| `headlineSmall` | 18px | w600 | 0 | textPrimary |
| `titleLarge` | 17px | w600 | 0 | textPrimary |
| `titleMedium` | 15px | w600 | 0 | textPrimary |
| `titleSmall` | 13px | w600 | 0 | textPrimary |
| `bodyLarge` | 16px | w400 | 0 | textSecondary |
| `bodyMedium` | 14px | w400 | 0 | textSecondary |
| `bodySmall` | 12px | w400 | 0 | textMuted |
| `labelLarge` | 14px | w600 | 0 | textPrimary |
| `labelMedium` | 12px | w500 | 0 | textSecondary |
| `labelSmall` | 11px | w500 | 0.3 | textMuted |

---

## 3. Spacing & Radii

### Spacing Scale (Unchanged)

4, 8, 12, 16, 20, 24, 32dp. No changes.

### New Token

| Token | Value | Use |
|-------|-------|-----|
| `sectionGap` | 24dp | Gap between content sections (explicit intent) |

### Border Radii (Tightened)

| Token | Old | New | Why |
|-------|-----|-----|-----|
| `radiusSmall` | 12dp | **8dp** | Chips, tags, badges |
| `radiusMedium` | 16dp | **12dp** | Buttons, inputs |
| `radiusLarge` | 20dp | **16dp** | Cards, sheets |
| Bottom sheet top | 28dp | **20dp** | radiusLarge + 4 |
| Dialog | 24dp | **20dp** | Consistent with sheets |

### Button Height (Unchanged)

52dp.

---

## 4. Component Patterns

### ModuleHeader

| Variant | Background | Text | Back Button | When |
|---------|-----------|------|-------------|------|
| **Default** | `#FFFFFF` (blends into scaffold) | `#111827` | Plain icon, no container | Most screens |
| **Elevated** | `#111827` → `#1F2937` gradient | `#FFFFFF` | Tinted circle, subtle border | Balance hero, profile header |

Default variant is new. Most screens should feel like content starts immediately.

### Cards

| Property | Value |
|----------|-------|
| Background | `#F8F9FA` |
| Border | 1px `#E5E7EB` |
| Radius | 16dp |
| Shadow | `raised` |
| Padding | 16dp |

Border AND shadow together — border for definition on white, shadow for subtle lift.

### SmartModuleCard

- Normal: `#F3F4F6` icon circle, `#111827` icon
- Active/alert: `#E6F5F3` icon circle, `#0D7B74` icon, teal border
- No per-module color differentiation

### AppTabBar

- Pill indicator: solid `#0D7B74` (no gradient)
- Active label: `#FFFFFF` on teal
- Inactive label: `#6B7280`
- Background: `#F3F4F6` container
- Always teal — no per-module colors

### Buttons

**Primary:** `#0D7B74` fill, `#FFFFFF` text, 12dp radius, 52dp height, no elevation.
**Secondary:** Transparent, 1.5px `#E5E7EB` border, `#111827` text. Press: `#F3F4F6` fill.
**Text:** `#0D7B74` text, no background.

### FAB

Circle, `#0D7B74` fill, `#FFFFFF` icon, `raised` shadow, 56dp.

### Inputs

- Fill: `#F3F4F6`
- Enabled border: 1.5px `#E5E7EB`
- Focused border: 2px `#0D7B74`
- Error border: 1.5px `#EF4444`
- Radius: 12dp

### Empty States

- Icon: `#9CA3AF`, 48dp
- Title: `#111827`, titleMedium
- Message: `#6B7280`, bodyMedium
- CTA: teal text button
- Animation: keep fade-in

### OfflineBanner

Keep amber `#F59E0B`. Universal warning color, works in any palette.

---

## 5. Screen Layout Strategy

### Home Screen (Spacious — Airbnb-mode)

- Page title "Your Groups" with inline `[+]` button (no FAB)
- Group cards: border+shadow, 3 lines (name, members, total spend)
- 12dp gap between cards
- "Recent Activity" section below: flat list with hairline dividers
- Staggered fade-in on cards

### Command Center / Event Hub (Hybrid)

- White default header (event name as page title)
- Subtitle: member count + expense count in bodyMedium gray-500
- 2-column grid of module cards (icon + label + summary line)
- Neutral icon circles; teal border only on cards needing attention

### Ledger Screen (Dense — Notion-mode)

- Elevated dark header with balance hero (large number, teal for owed, green for receiving)
- AppTabBar: [Spending] [Balances] with teal pill
- Balance rows: flat list with hairline dividers (no cards). Name left, amount right
- Transactions: icon + description + amount, metadata below, hairline dividers
- FAB for add expense

### Settings Screen (Spacious)

- Flat list with section headers and hairline dividers
- No cards — text rows with chevrons
- Notion settings page aesthetic

---

## 6. Animation & Motion

### Preserved

| Pattern | Behavior |
|---------|----------|
| Staggered fade-in + slide-up | 50ms delay between items, max 500ms |
| Haptic feedback | Light impact (FAB), selection (tab), medium (card) |
| Reduced motion | `MediaQuery.disableAnimations` checks |
| `AppPageRoute` | Slide-right push transition |
| `AppBottomSheetRoute` | Slide-up entry |

### Adjusted

| Pattern | Old | New | Why |
|---------|-----|-----|-----|
| Slide-up distance | 20-30dp (varied) | **16dp** (standardized) | Subtler on neutral UI |
| Fade duration | 300ms | **200ms** | Snappier — less visual noise to track |
| Tab content switch | Instant | **Cross-fade 150ms** | Smooth without slow |
| Card press | None | **Scale 0.98, 100ms** | Tactile feedback on flat cards |

### New

| Pattern | Behavior | Where |
|---------|----------|-------|
| Skeleton shimmer | Neutral gray shimmer on `#F3F4F6` | All loading states |
| Number transitions | Animated count-up, 300ms ease-out | Ledger balance hero, group totals |

### Removed

| Pattern | Why |
|---------|-----|
| Glass-effect back button | Doesn't fit flat/clean language |
| Gradient tab pill indicator | Solid teal. Gradients add complexity |
| Per-module indicator colors | Always teal. One accent = one animation color |

---

## 7. Migration Notes

### Infrastructure Preserved

- `AppColorTokens` class — all 30 fields stay, new hex values
- `AppSpacingTokens` — unchanged except `sectionGap` addition
- `AppShadowTokens` — same structure, new base color
- `context.colors`, `context.spacing`, `context.shadows` — untouched
- `AppColors` facade — 895 references compile with new values
- 36 WCAG unit tests — update expected values, same assertions

### Renames

- `AppColorTokens.earthyLight` → `AppColorTokens.light`

### Not Affected

- 257 `find.text()` test calls — this design changes no labels
- Navigation structure — no GoRouter changes
- Data layer — pure visual change

### Dependencies on Existing Phases

- Phase 15 (design tokens): **complete** — this design swaps values within that system
- Phase 16 (Stitch prompts): **superseded** — Stitch prompts used earthy palette values. If Stitch is still desired, prompts need updating with new hex values
- Phase 17+ (planned screen redesigns): **informed by this design** — layout strategy in Section 5 guides those phases

---

## Appendix: WCAG Compliance Summary

| Pair | Ratio | Standard |
|------|-------|----------|
| textPrimary `#111827` on scaffold `#FFFFFF` | 17.15:1 | AAA |
| textPrimary `#111827` on cardSurface `#F8F9FA` | 16.30:1 | AAA |
| textSecondary `#6B7280` on `#FFFFFF` | 5.03:1 | AA |
| textSecondary `#6B7280` on `#F8F9FA` | 4.78:1 | AA |
| textMuted `#9CA3AF` on `#FFFFFF` | 2.86:1 | Decorative only |
| primary `#0D7B74` on `#FFFFFF` | 5.12:1 | AA |
| textOnPrimary `#FFFFFF` on primary `#0D7B74` | 5.12:1 | AA |
| successText `#047857` on `#FFFFFF` | 5.92:1 | AA |
| errorText `#B91C1C` on `#FFFFFF` | 6.57:1 | AA |
