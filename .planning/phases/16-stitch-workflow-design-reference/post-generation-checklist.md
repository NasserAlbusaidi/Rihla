# Post-Generation Review Checklist

**Phase:** 16 (Stitch Workflow & Design Reference)
**Applies to:** All Stitch-generated screen mockups before they are annotated into visual specifications
**Reusable for:** Phases 20, 21, 22 (follow the same Stitch-to-Flutter pipeline)

This checklist is applied every time a Stitch-generated screen mockup is reviewed (per D-16). Complete all 4 checks before treating any Stitch output as ready for spec annotation. The checklist enforces D-24 (tokens are source of truth), D-25 (WCAG verification), and D-26 (unlisted combinations must be verified).

---

## Check 1: Color Token Mapping

> Per D-16.1, D-24: Every color in the Stitch output must map to an existing `AppColors.*` constant or `AppColorTokens` field. Stitch adapts to tokens — never the reverse. If no exact match exists, snap to the nearest token. Do NOT introduce new hex values into specs or code without a deliberate token decision.

**Instructions:** For every distinct color visible in the Stitch output, identify it (eyedropper or estimate from palette) and fill in the table below.

| Visual Area | Color in Stitch Output | Nearest AppColorTokens Token | Hex Match? | Action Needed |
|-------------|------------------------|------------------------------|------------|---------------|
| (fill in)   | (fill in)              | (fill in)                    | Yes / No   | (fill in)     |

**Checkboxes:**

- [ ] All colors in the output map to an existing `AppColors.*` or `AppColorTokens` field
- [ ] No color exists in the output that is NOT in the token system (flag any new color below in Token Gap Log)
- [ ] All text-on-background color pairs appear in the Phase 15 WCAG-verified set (see table below)

**Complete Color Token Reference (AppColorTokens.earthyLight):**

Use this table to identify which token each Stitch color corresponds to.

| Token Field | Hex Value | AppColors Alias | WCAG on Sand | Notes |
|-------------|-----------|----------------|--------------|-------|
| `primary` | #CC6B49 | `AppColors.primary` | N/A as bg; textOnPrimary = 3.64:1 AA large | Terracotta — buttons, FABs, focused inputs |
| `scaffoldBackground` | #F2E8D6 | `AppColors.background` | Reference surface | Sand page background |
| `cardSurface` | #FFF9F2 | `AppColors.surface` | Reference surface | Warm white card background |
| `inputFill` | #F5EDE1 | `AppColors.surfaceLight` | Reference surface | Sand light input fill |
| `border` | #E5D5C0 | `AppColors.border` | Decorative only | Warm gray dividers/borders |
| `textPrimary` | #2C1A0E | `AppColors.textPrimary` | 13.71:1 (AAA) | Dark brown — body text |
| `textSecondary` | #6B5B4E | `AppColors.textSecondary` | 5.35:1 (AA) | Warm gray — secondary labels |
| `textMuted` | #A89888 | `AppColors.textMuted` | 2.30:1 (FAIL) | **DECORATIVE ONLY** — never functional |
| `textOnPrimary` | #FFFFFF | `AppColors.textOnPrimary` | 3.64:1 on terracotta (AA large) | White on #CC6B49 |
| `success` | #10B981 | `AppColors.success` | Display only | Badges/icons — use successText for text |
| `successText` | #047857 | `AppColors.success` (as text) | 4.51:1 (AA body) | WCAG-safe success text |
| `error` | #EF4444 | `AppColors.error` | Display only | Badges/icons — use errorText for text |
| `errorText` | #B91C1C | `AppColors.error` (as text) | 5.33:1 (AA body) | WCAG-safe error text |
| `disabled` | #E5D5C0 | `AppColors.disabled` | Disabled state | Warm beige disabled background |
| `disabledText` | #A89888 | — | Below AA | Disabled state text only |
| `focusRing` | #CC6B49 | `AppColors.primary` | Focus indicator | Terracotta focus ring |
| `selectionFill` | #F5DDD3 | `AppColors.primaryLight` | Reference surface | Selected chip/item — terracotta 15% tint |
| `moduleLedger` | #CC6B49 | `AppColors.primary` | Module accent | Terracotta — Ledger module |
| `moduleLedgerLight` | #ECD5C0 | — | Module tint | Ledger card background |
| `moduleGear` | #7A8C5E | `AppColors.accentSecondary` | Module accent | Olive — Gear module |
| `moduleGearLight` | #E0DAC4 | — | Module tint | Gear card background |
| `moduleLogistics` | #5B7B8C | `AppColors.sky` | Module accent | Dusty teal — Logistics module |
| `moduleLogisticsLight` | #DBD7CA | — | Module tint | Logistics card background |
| `moduleVault` | #8B7355 | `AppColors.indigo` | Module accent | Warm bronze — Vault module |
| `moduleVaultLight` | #E2D6C2 | — | Module tint | Vault card background |
| `moduleActivity` | #A67C5B | — | Module accent | Caramel — Activity module |
| `moduleActivityLight` | #E6D7C3 | — | Module tint | Activity card background |
| `moduleMemories` | #9B7A5C | — | Module accent | Desert sand — Memories module |
| `moduleMemoriesLight` | #E4D7C3 | — | Module tint | Memories card background |
| `headerGradientStart` | #2C1A0E | `AppColors.surfaceDark` | Dark header gradient start | Same as textPrimary |
| `headerGradientEnd` | #3D2B1E | — | Dark header gradient end | Slightly lighter dark brown |

---

## Check 2: Spacing Consistency

> Per D-16.2: All spacing must align to the 4dp token grid. Non-token values (6dp, 10dp, 15dp, etc.) are not permitted in the spec.

- [ ] All padding and gap values align to the 4dp grid: 4, 8, 12, 16, 20, 24, or 32dp
- [ ] Spacing values are named using token names in the spec: `space4`, `space8`, `space12`, `space16`, `space20`, `space24`, `space32`
- [ ] No non-token spacing values appear in the Stitch output (e.g., 6dp, 10dp, 15dp — snap to nearest token)
- [ ] Border radii use only: 12dp (`radiusSmall` — chips/tags), 16dp (`radiusMedium` — buttons/inputs), 20dp (`radiusLarge` — cards/sheets)
- [ ] Button heights are 52dp (`buttonHeight`)
- [ ] All touch targets are >= 48dp

**Snap rule:** If Stitch generates 6dp → snap to 8dp. If 10dp → snap to 8dp or 12dp (whichever fits better visually). Document the snap decision in the spec.

---

## Check 3: Component Reuse

> Per D-16.3: Stitch output should align to existing shared widgets. If Stitch invents a new variant of something that already exists, the spec annotates it as "use existing [Widget]" rather than describing a custom implementation.

- [ ] `ModuleHeader` is used for all dark gradient header sections (not a custom gradient header)
- [ ] `EmptyStateView` is used for all empty state sections (not a custom-built empty layout)
- [ ] `SmartModuleCard` is used for all module list items in the Event Hub screen (not custom cards)
- [ ] `SkeletonLoader` is used for all loading/skeleton states (not custom shimmer layouts)
- [ ] `OfflineBanner` is included in all error state mockups (check all 3 screens)
- [ ] `AppTabBar` is used for any tab layout sections (if applicable to the screen)

**If Stitch generates a component that has no existing equivalent:** Note it in the Token Gap Log at the bottom as a potential new shared widget candidate. Do not implement it as a one-off inline widget in the spec.

---

## Check 4: Accessibility

> Per D-16.4, D-25, D-26: All color combinations must meet WCAG AA thresholds. Verify every text-on-background pair. If a pair is not in the pre-computed matrix below, calculate manually before including in the spec.

- [ ] All body text uses `textPrimary` (#2C1A0E) or `textSecondary` (#6B5B4E) on sand/surface backgrounds — both are WCAG AA verified
- [ ] Success text uses `successText` (#047857, 4.51:1 AA), NOT `success` (#10B981) — `success` is display-only (icons/badges)
- [ ] Error text uses `errorText` (#B91C1C, 5.33:1 AA), NOT `error` (#EF4444) — `error` is display-only (icons/badges)
- [ ] `textMuted` (#A89888) is used decoratively only — NEVER for functional labels, balance amounts, action labels, or any interactive text
- [ ] `textOnPrimary` (#FFFFFF) is used for all text placed on primary (#CC6B49) backgrounds
- [ ] All interactive elements (buttons, tappable cards, chips) are visually distinct from non-interactive elements
- [ ] All touch targets are >= 48dp (per D-16 and WCAG 2.5.5)

**Pre-computed WCAG Verified Pairs (Phase 15):**

| Text Color | Background Color | Contrast Ratio | Level | Status |
|------------|----------------|----------------|-------|--------|
| `textPrimary` (#2C1A0E) | `scaffoldBackground` (#F2E8D6) sand | 13.71:1 | AAA | Verified |
| `textPrimary` (#2C1A0E) | `cardSurface` (#FFF9F2) warm white | ~14.8:1 | AAA | Verified |
| `textSecondary` (#6B5B4E) | `scaffoldBackground` (#F2E8D6) sand | 5.35:1 | AA | Verified |
| `successText` (#047857) | `scaffoldBackground` (#F2E8D6) sand | 4.51:1 | AA body | Verified |
| `errorText` (#B91C1C) | `scaffoldBackground` (#F2E8D6) sand | 5.33:1 | AA body | Verified |
| `textOnPrimary` (#FFFFFF) | `primary` (#CC6B49) terracotta | 3.64:1 | AA large | Verified |
| `textMuted` (#A89888) | `scaffoldBackground` (#F2E8D6) sand | 2.30:1 | FAIL | **Never use for functional text** |

**Rule:** Any color combination in the Stitch output NOT listed in the verified pairs table above requires manual WCAG contrast ratio calculation before it can be included in the annotated spec (per D-26). Use https://webaim.org/resources/contrastchecker/ or equivalent. Document the result in the spec.

---

## Token Gap Log

> Per Claude's Discretion (CONTEXT.md): Structural gaps (missing token that blocks spec completeness) are added to `color_tokens.dart` immediately. Cosmetic gaps (refinements) are logged here and deferred to the implementation phase.

Apply this log after each Stitch output review. One row per gap found.

| Gap Description | Structural or Cosmetic? | Recommended Action |
|----------------|------------------------|-------------------|
| (fill in — e.g., "Stitch generated #D4A896 for badge background") | (Structural: blocks spec / Cosmetic: visual refinement) | (Add token now → which phase / Defer to Phase NN) |

**Categorization guide:**
- **Structural:** The missing token is used for functional UI (text color, interactive element, semantic color like balance positive/negative). If the spec cannot be written without it, it is structural.
- **Cosmetic:** The gap is a nice-to-have refinement, hover state, or subtle variant that the implementation phases can resolve with an existing nearby token. If snapping to the nearest token still produces a correct and accessible result, it is cosmetic.
