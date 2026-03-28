# Phase 15: Design Token System - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-03-28
**Phase:** 15-design-token-system
**Areas discussed:** Palette mapping strategy, Token architecture, Migration approach for AppColors, CI lint rule design

---

## Palette Mapping Strategy

### Primary Action Color

| Option | Description | Selected |
|--------|-------------|----------|
| Terracotta | ~#CC6B49 — warm, earthy, high-energy. ~4.7:1 contrast on sand (AA) | ✓ |
| Olive | ~#7A8C5E — earthy, calm, nature-forward. ~3.2:1 contrast (fails AA body) | |
| Warm brown | ~#8B5E3C — between terracotta and dark brown. ~5.1:1 contrast (AA) | |

**User's choice:** Terracotta (Recommended)
**Notes:** Strong contrast on sand backgrounds, natural CTA color for outdoor/travel app

### Financial Status Colors

| Option | Description | Selected |
|--------|-------------|----------|
| Keep green/red | Standard #10B981 and #EF4444. Universal financial convention | ✓ |
| Earthy warm/cool | Terracotta tints for debt, olive for positive | |
| Desaturated green/red | Softer versions that blend with earthy palette | |

**User's choice:** Keep green/red (Recommended)
**Notes:** Financial colors are functional, not brand. Universal convention reduces cognitive load

### Module Accent Colors

| Option | Description | Selected |
|--------|-------------|----------|
| Earthy per-module accents | Replace neon module colors with earthy variants. Distinct but cohesive | ✓ |
| Single accent, vary by tone | Terracotta only, differentiate by lightness/saturation | |
| Keep current vibrant colors | Keep indigo, sky, amber, emerald for modules | |

**User's choice:** Earthy per-module accents (Recommended)
**Notes:** Each module gets its own earthy tint — terracotta, olive, dusty teal, warm bronze, caramel, desert sand

### Background and Surface Colors

| Option | Description | Selected |
|--------|-------------|----------|
| Warm sand canvas | Sand (#F2E8D6) scaffold, warm white (#FFF9F2) cards. Parchment feel | ✓ |
| Subtle warm tint | Near-white (#FAFAF5) scaffold, pure white cards. Safer, less dramatic | |
| Deep sand | Richer sand (#EDE0CC) scaffold. Bold and immersive | |

**User's choice:** Warm sand canvas (Recommended)
**Notes:** Wanted the full parchment/paper feel, not a subtle tint

### Text Color Hierarchy

| Option | Description | Selected |
|--------|-------------|----------|
| Earthy brown hierarchy | Dark brown #2C1A0E primary, warm gray #6B5B4E secondary, sand gray #A89888 muted | ✓ |
| Neutral gray hierarchy | Keep current Slate grays (0F172A/475569/94A3B8) | |
| Hybrid | Dark brown primary, neutral gray secondary/muted | |

**User's choice:** Earthy brown hierarchy (Recommended)
**Notes:** Full earthy text hierarchy for cohesive warm palette

### Gradient/Header Colors

| Option | Description | Selected |
|--------|-------------|----------|
| Dark brown gradient | #2C1A0E to #3D2B1E. Module headers can use accent darkened variants | ✓ |
| Terracotta-tinted gradient | Terracotta-to-brown gradient for primary headers | |
| Keep dark slate | Current #0F172A to #1E293B gradient unchanged | |

**User's choice:** Dark brown gradient (Recommended)
**Notes:** Warm and cohesive with sand backgrounds

### Shadow Colors

| Option | Description | Selected |
|--------|-------------|----------|
| Warm brown shadows | Use #2C1A0E with low opacity for shadow color | ✓ |
| Keep neutral shadows | Keep current slate-based shadow colors | |

**User's choice:** Warm brown shadows (Recommended)
**Notes:** Subtle warmth in shadows adds cohesion to the palette

### Disabled State Colors

| Option | Description | Selected |
|--------|-------------|----------|
| Desaturated earthy | Warm beige (#E5D5C0) bg, sand gray (#A89888) text | ✓ |
| Standard Material gray | Default gray disabled states | |

**User's choice:** Desaturated earthy (Recommended)
**Notes:** Clearly disabled but still part of the warm palette

### Focus Ring / Selection Color

| Option | Description | Selected |
|--------|-------------|----------|
| Terracotta focus | #CC6B49 border for focused inputs, #F5DDD3 for selected chips | ✓ |
| Olive focus | Olive for focus/selection, terracotta for CTAs only | |

**User's choice:** Terracotta focus (Recommended)
**Notes:** Consistent with primary = terracotta decision

---

## Token Architecture

### Extension Structure

| Option | Description | Selected |
|--------|-------------|----------|
| Split by concern | Separate AppColorTokens, AppSpacingTokens, AppShadowTokens | ✓ |
| Single extension | One AppTokens class with everything (~50+ fields) | |
| Colors only as ThemeExtension | Only colors become extension; spacing/radii stay static | |

**User's choice:** Split by concern (Recommended)
**Notes:** Independently testable and composable

### Token Naming

| Option | Description | Selected |
|--------|-------------|----------|
| Both layers | Generic role names (primary, surface) + domain aliases (balancePositive, moduleLedger) | ✓ |
| Generic roles only | All tokens generic, no domain-specific aliases | |
| Semantic only | All tokens domain-specific (40+ unique names) | |

**User's choice:** Both layers (Recommended)
**Notes:** Keeps system reusable with domain-specific convenience

### File Layout

| Option | Description | Selected |
|--------|-------------|----------|
| Theme directory with one file per extension | lib/core/theme/tokens/ directory | ✓ |
| Single tokens file | All token classes in one app_tokens.dart | |
| Feature-colocated aliases | Core tokens central, aliases in feature directories | |

**User's choice:** Theme directory with one file per extension (Recommended)

### Gradient Tokens

| Option | Description | Selected |
|--------|-------------|----------|
| Include in color tokens | Gradient start/end as color token fields with convenience getters | ✓ |
| Separate gradient tokens extension | Dedicated AppGradientTokens ThemeExtension | |

**User's choice:** Include in color tokens (Recommended)

### Module Accent Tokens

| Option | Description | Selected |
|--------|-------------|----------|
| Map in color tokens | Module accent colors as fields in AppColorTokens with light tint variants | ✓ |
| Enum-based module palette | ModuleAccent enum with .color and .lightColor getters | |
| Separate module tokens extension | Dedicated AppModuleTokens ThemeExtension | |

**User's choice:** Map in color tokens (Recommended)

### Access API

| Option | Description | Selected |
|--------|-------------|----------|
| Yes, extension methods | context.colors, context.spacing, context.shadows | ✓ |
| No, direct Theme.of access | Theme.of(context).extension<T>()! everywhere | |

**User's choice:** Yes, extension methods (Recommended)

---

## Migration Approach for AppColors

### AppColors Evolution

| Option | Description | Selected |
|--------|-------------|----------|
| Thin facade — static values only | Update color values to earthy palette in place. 962 call sites unchanged | ✓ |
| Delegating facade — reads from theme | Static getters read from global theme reference. Complex, needs context | |
| Deprecate and replace immediately | Rewrite all 962 call sites now. Clean break, massive scope | |

**User's choice:** Thin facade — static values only (Recommended)
**Notes:** Lowest risk, preserves all call sites, earthy palette visible immediately

### Migration Timing

| Option | Description | Selected |
|--------|-------------|----------|
| During screen redesign phases | Each screen switches when redesigned (Phases 18-22) | ✓ |
| Batch migration in Phase 22 | Single find-and-replace at the end | |
| Immediately in Phase 15 | Replace all 962 references now | |

**User's choice:** During screen redesign phases (Recommended)
**Notes:** Gradual, low-risk. AppColors stays valid throughout v2.0

---

## CI Lint Rule Design

### Implementation Approach

| Option | Description | Selected |
|--------|-------------|----------|
| Grep-based CI step | Shell script in GitHub Actions. Zero dependencies. Matches Phase 14 approach | ✓ |
| custom_lint package | Dart analyzer plugin with IDE integration. Adds dependency | |
| dart_code_linter | DCM rules. Mature but adds dependency. Free tier limits | |

**User's choice:** Grep-based CI step (Recommended)

### Enforcement Level

| Option | Description | Selected |
|--------|-------------|----------|
| Hard fail | CI build fails on hardcoded colors. FOUND-04 says "prevents" | ✓ |
| Warning first, hard fail later | Non-blocking warning in Phase 15, hard fail in Phase 22 | |

**User's choice:** Hard fail (Recommended)
**Notes:** FOUND-04 says "prevents" not "warns about"

### Allowlist

| Option | Description | Selected |
|--------|-------------|----------|
| Token files + tests + category model | app_theme.dart, tokens/*.dart, expense_category_model.dart, test/**/*.dart | ✓ |
| Token files only | Strictest: only token definition files exempt | |

**User's choice:** Token files + tests + category model (Recommended)
**Notes:** Category model has 6 hardcoded category colors; tests need raw colors for assertions

---

## Claude's Discretion

- Exact WCAG contrast verification approach
- Precise hex values for module light tint variants
- ColorScheme mapping alongside ThemeExtension
- Lerp implementation details
- Order of implementation tasks

## Deferred Ideas

None — discussion stayed within phase scope
