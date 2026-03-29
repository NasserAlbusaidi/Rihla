# Post-Generation Review Checklist

**Phase:** 16 (Stitch Workflow & Design Reference)
**Applies to:** All Stitch-generated screen mockups before they are annotated into visual specifications
**Reusable for:** Phases 18–22 (follow the same Stitch-to-Flutter pipeline)
**Design system:** Clean Slate — monochrome neutral + teal (#0D7B74)

This checklist is applied every time a Stitch-generated screen mockup is reviewed. Complete all 4 checks before treating any Stitch output as ready for spec annotation.

---

## Check 1: Color Token Mapping

> Every color in the Stitch output must map to an existing `AppColors.*` constant or `AppColorTokens` field. Stitch adapts to tokens — never the reverse. If no exact match exists, snap to the nearest token.

**Instructions:** For every distinct color visible in the Stitch output, identify it and fill in the table below.

| Visual Area | Color in Stitch Output | Nearest AppColorTokens Token | Hex Match? | Action Needed |
|-------------|------------------------|------------------------------|------------|---------------|
| (fill in)   | (fill in)              | (fill in)                    | Yes / No   | (fill in)     |

**Checkboxes:**

- [ ] All colors in the output map to an existing `AppColors.*` or `AppColorTokens` field
- [ ] No color exists in the output that is NOT in the token system (flag any new color in Token Gap Log)
- [ ] All text-on-background color pairs appear in the WCAG-verified set (see Check 4)
- [ ] Only teal (#0D7B74) is used for interactive elements — no other accent colors

**Complete Color Token Reference (AppColorTokens.light):**

| Token Field | Hex Value | AppColors Alias | WCAG on White | Notes |
|-------------|-----------|----------------|---------------|-------|
| `primary` | #0D7B74 | `AppColors.primary` | 5.12:1 (AA) | Teal — buttons, FABs, links, active states |
| `scaffoldBackground` | #FFFFFF | `AppColors.background` | Reference surface | White page background |
| `cardSurface` | #F8F9FA | `AppColors.surface` | Reference surface | Cool gray card background |
| `inputFill` | #F3F4F6 | `AppColors.surfaceLight` | Reference surface | Gray-100 input fill |
| `border` | #E5E7EB | `AppColors.border` | Decorative only | Gray-200 dividers/borders |
| `textPrimary` | #111827 | `AppColors.textPrimary` | 17.15:1 (AAA) | Gray-900 — headlines, body |
| `textSecondary` | #6B7280 | `AppColors.textSecondary` | 5.03:1 (AA) | Gray-500 — secondary labels |
| `textMuted` | #9CA3AF | `AppColors.textMuted` | 2.86:1 (FAIL) | **DECORATIVE ONLY** — never functional |
| `textOnPrimary` | #FFFFFF | `AppColors.textOnPrimary` | 5.12:1 on teal (AA) | White on #0D7B74 |
| `success` | #10B981 | `AppColors.success` | Display only | Badges/icons — use successText for text |
| `successText` | #047857 | — | 5.92:1 (AA) | WCAG-safe success text |
| `error` | #EF4444 | `AppColors.error` | Display only | Badges/icons — use errorText for text |
| `errorText` | #B91C1C | — | 6.57:1 (AA) | WCAG-safe error text |
| `disabled` | #E5E7EB | — | Disabled state | Gray-200 disabled background |
| `disabledText` | #9CA3AF | — | Below AA | Disabled state text only |
| `focusRing` | #0D7B74 | `AppColors.primary` | Focus indicator | Teal focus ring |
| `selectionFill` | #E6F5F3 | `AppColors.primaryLight` | Reference surface | Teal 10% tint — selected items |
| `moduleLedger` | #0D7B74 | `AppColors.primary` | Module accent | Teal — Ledger (primary module) |
| `moduleLedgerLight` | #E6F5F3 | — | Module tint | Teal-50 — Ledger card tint |
| `moduleGear` | #6B7280 | `AppColors.accentSecondary` | Module accent | Gray-500 — all non-Ledger modules |
| `moduleGearLight` | #F3F4F6 | — | Module tint | Gray-100 — neutral card tint |
| `moduleLogistics` | #6B7280 | — | Module accent | Gray-500 |
| `moduleLogisticsLight` | #F3F4F6 | — | Module tint | Gray-100 |
| `moduleVault` | #6B7280 | — | Module accent | Gray-500 |
| `moduleVaultLight` | #F3F4F6 | — | Module tint | Gray-100 |
| `moduleActivity` | #6B7280 | — | Module accent | Gray-500 |
| `moduleActivityLight` | #F3F4F6 | — | Module tint | Gray-100 |
| `moduleMemories` | #6B7280 | — | Module accent | Gray-500 |
| `moduleMemoriesLight` | #F3F4F6 | — | Module tint | Gray-100 |
| `headerGradientStart` | #111827 | `AppColors.surfaceDark` | Dark header start | Gray-900 |
| `headerGradientEnd` | #1F2937 | — | Dark header end | Gray-800 |

---

## Check 2: Spacing Consistency

- [ ] All padding and gap values align to the 4dp grid: 4, 8, 12, 16, 20, 24, or 32dp
- [ ] Spacing values named using tokens: `space4`–`space32`
- [ ] No non-token spacing values (6dp, 10dp, 15dp — snap to nearest)
- [ ] Border radii use only: 8dp (`radiusSmall`), 12dp (`radiusMedium`), 16dp (`radiusLarge`)
- [ ] Button heights are 52dp (`buttonHeight`)
- [ ] All touch targets >= 48dp

**Snap rule:** 6dp → 8dp. 10dp → 8dp or 12dp (whichever fits). Document snap decisions.

---

## Check 3: Component Reuse

- [ ] **ModuleHeader (white variant)** used for standard screen headers — white bg, plain back icon, no elevation
- [ ] **ModuleHeader (elevated variant)** used only for screens with hero sections (balance display)
- [ ] **EmptyStateView** used for all empty states — gray icon, teal CTA button
- [ ] **SmartModuleCard** used for Event Hub module grid — neutral gray icons, teal only on alert
- [ ] **SkeletonLoader** used for all loading states — gray-100 base, gray-200 shapes
- [ ] **OfflineBanner** included in all error states — amber #F59E0B
- [ ] **AppTabBar** used for tabs — solid teal pill, no gradient
- [ ] Cards use **border + shadow hybrid** (1px #E5E7EB + soft shadow)
- [ ] Financial data rows use **flat list with hairline dividers** (Notion-style), NOT cards

**If Stitch generates a component with no existing equivalent:** Note in Token Gap Log as potential new shared widget.

---

## Check 4: Accessibility

- [ ] All body text uses `textPrimary` (#111827) or `textSecondary` (#6B7280) on white/gray backgrounds — both WCAG AA
- [ ] Success text uses `successText` (#047857, 5.92:1 AA), NOT `success` (#10B981)
- [ ] Error text uses `errorText` (#B91C1C, 6.57:1 AA), NOT `error` (#EF4444)
- [ ] `textMuted` (#9CA3AF) used decoratively ONLY — never for functional labels, amounts, or actions
- [ ] `textOnPrimary` (#FFFFFF) used for all text on teal (#0D7B74) backgrounds — 5.12:1 AA
- [ ] All interactive elements visually distinct from non-interactive
- [ ] All touch targets >= 48dp

**Pre-computed WCAG Verified Pairs:**

| Text Color | Background Color | Contrast Ratio | Level | Status |
|------------|----------------|----------------|-------|--------|
| `textPrimary` (#111827) | `scaffold` (#FFFFFF) white | 17.15:1 | AAA | Verified |
| `textPrimary` (#111827) | `cardSurface` (#F8F9FA) cool gray | ~16.30:1 | AAA | Verified |
| `textSecondary` (#6B7280) | `scaffold` (#FFFFFF) white | 5.03:1 | AA | Verified |
| `textSecondary` (#6B7280) | `cardSurface` (#F8F9FA) cool gray | ~4.78:1 | AA | Verified |
| `primary` (#0D7B74) | `scaffold` (#FFFFFF) white | 5.12:1 | AA | Verified |
| `successText` (#047857) | `scaffold` (#FFFFFF) white | 5.92:1 | AA | Verified |
| `errorText` (#B91C1C) | `scaffold` (#FFFFFF) white | 6.57:1 | AA | Verified |
| `textOnPrimary` (#FFFFFF) | `primary` (#0D7B74) teal | 5.12:1 | AA | Verified |
| `textMuted` (#9CA3AF) | `scaffold` (#FFFFFF) white | 2.86:1 | FAIL | **Decorative only** |

**Rule:** Any color pair NOT in the table above requires manual calculation before inclusion in spec. Use https://webaim.org/resources/contrastchecker/

---

## Token Gap Log

| Gap Description | Structural or Cosmetic? | Recommended Action |
|----------------|------------------------|-------------------|
| (fill in) | (Structural / Cosmetic) | (Add token now / Defer to Phase NN) |

**Categorization:**
- **Structural:** Missing token blocks spec completeness (functional UI, interactive element, semantic color)
- **Cosmetic:** Nice-to-have refinement; snapping to nearest token still produces correct, accessible result
