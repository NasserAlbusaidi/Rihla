# Phase 15: Design Token System - Context

**Gathered:** 2026-03-28
**Status:** Ready for planning

<domain>
## Phase Boundary

Build a ThemeExtension-based design token system with the warm earthy palette (terracotta, sand, olive, dark brown). All existing AppColors references (962 across 63 files) continue to compile and produce warm palette values without call-site changes. CI lint rule blocks future hardcoded Color(0xFF...) values outside the token system.

</domain>

<decisions>
## Implementation Decisions

### Palette Mapping

- **D-01:** Primary action color is terracotta (#CC6B49) — buttons, FABs, focused inputs, links, selection highlights
- **D-02:** Financial status colors stay standard green/red — success (#10B981) for positive balances, error (#EF4444) for negative. Universal financial convention, not brand colors
- **D-03:** Module accent colors are earthy per-module variants:
  - Ledger: #CC6B49 (terracotta)
  - Gear: #7A8C5E (olive)
  - Logistics: #5B7B8C (dusty teal)
  - Vault: #8B7355 (warm bronze)
  - Activity: #A67C5B (caramel)
  - Memories: #9B7A5C (desert sand)
- **D-04:** Background/surface colors use warm sand canvas:
  - Scaffold background: #F2E8D6 (sand)
  - Card surface: #FFF9F2 (warm white)
  - Input fill: #F5EDE1 (sand light)
  - Border: #E5D5C0 (warm gray)
- **D-05:** Text color hierarchy uses earthy brown:
  - Primary text: #2C1A0E (dark brown) — ~13:1 contrast on sand (AAA)
  - Secondary text: #6B5B4E (warm gray) — ~4.8:1 contrast on sand (AA)
  - Muted text: #A89888 (sand gray) — ~2.8:1 contrast on sand (AA large text only)
  - Text on primary: #FFFFFF (white on terracotta)
- **D-06:** Gradients use dark brown tones — header gradient: #2C1A0E to #3D2B1E. Module headers can use their own accent darkened variants
- **D-07:** Shadows use warm brown base color (#2C1A0E) with low opacity instead of current slate 900
- **D-08:** Disabled states use desaturated earthy colors — warm beige (#E5D5C0) background, sand gray (#A89888) text
- **D-09:** Focus ring and selection color is terracotta — focused inputs get #CC6B49 border, selected chips get #F5DDD3 (terracotta at 15%)

### Token Architecture

- **D-10:** Split ThemeExtensions by concern — separate classes: AppColorTokens, AppSpacingTokens, AppShadowTokens
- **D-11:** Two-layer naming — core tokens use generic role names (primary, surface, textPrimary, success, error), domain aliases map to core tokens (balancePositive=success, moduleLedger=primary)
- **D-12:** File layout: `lib/core/theme/tokens/` directory with one file per extension (color_tokens.dart, spacing_tokens.dart, shadow_tokens.dart, domain_aliases.dart). app_theme.dart stays as ThemeData builder
- **D-13:** Gradient tokens are included in AppColorTokens as start/end color fields with convenience LinearGradient getters
- **D-14:** Module accent colors are fields in AppColorTokens (moduleLedger, moduleGear, etc.) with corresponding light tint variants (moduleLedgerLight, moduleGearLight, etc.)
- **D-15:** BuildContext extension methods for terse access: context.colors, context.spacing, context.shadows

### Migration Approach

- **D-16:** AppColors becomes a thin static facade — color values updated to earthy palette in place, all 962 call sites compile unchanged. No delegating to ThemeExtension from AppColors
- **D-17:** Migration from AppColors.x to context.colors.x happens during screen redesign phases (18-22), not in Phase 15. Each screen switches when it gets redesigned
- **D-18:** AppColors facade remains valid throughout v2.0. Final cleanup/deletion happens in Phase 22 (Polish Pass)

### CI Lint Rule

- **D-19:** Grep-based CI step in GitHub Actions — scans for Color(0x patterns, zero dependencies, matches Phase 14's approach
- **D-20:** Hard fail enforcement — CI build fails if hardcoded Color(0xFF...) found outside allowlist. FOUND-04 says "prevents" not "warns"
- **D-21:** Allowlist: lib/core/theme/app_theme.dart, lib/core/theme/tokens/*.dart, lib/features/ledger/models/expense_category_model.dart, test/**/*.dart. All other lib/ files are blocked

### Claude's Discretion

- Exact WCAG contrast verification approach and which tool to use
- Precise hex values for module light tint variants (general direction decided: ~15% opacity tints)
- Whether to include a ColorScheme mapping alongside the ThemeExtension or keep them separate
- Exact lerp implementation details for ThemeExtension copyWith/lerp methods
- Order of implementation tasks within the phase

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Requirements
- `.planning/REQUIREMENTS.md` FOUND-01 — ThemeExtension-based design token system with warm earthy palette
- `.planning/REQUIREMENTS.md` FOUND-02 — WCAG AA contrast ratios (4.5:1 body text, 3:1 large text/icons)
- `.planning/REQUIREMENTS.md` FOUND-04 — CI lint rule preventing hardcoded Color(0xFF...) outside token system

### Phase dependencies
- `.planning/ROADMAP.md` Phase 15 — success criteria defining palette rendering, WCAG compliance, CI lint, and AppColors compatibility
- `.planning/phases/14-test-hardening/14-CONTEXT.md` — Phase 14 context (semantic Keys, CI warning pattern to follow)

### Existing code
- `lib/core/theme/app_theme.dart` — current AppColors class (35 color constants, spacing, radii, shadows, gradients) and AppTheme (ThemeData builder). This is the primary file being evolved
- `.github/workflows/release_android.yml` — CI pipeline where the hardcoded color lint step will be added

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `AppColors` class (lib/core/theme/app_theme.dart): 35 static color constants, spacing scale, border radius scale, shadow definitions, gradients. Direct migration target
- `AppTheme.lightTheme` (same file): Already builds ThemeData with ColorScheme — ThemeExtensions will be added to its `.extensions` list
- Plus Jakarta Sans font family already configured throughout text theme

### Established Patterns
- Static class pattern (`AppColors.*`) used across 63 files with 962 references — facade must preserve this API
- `GoogleFonts.getFont('Plus Jakarta Sans', ...)` used throughout text theme — no change needed
- `const` constructors used for all Color values — tokens can maintain const where possible
- No existing ThemeExtension usage anywhere in the codebase — this phase introduces the pattern

### Integration Points
- `lib/main.dart` — `AppTheme.lightTheme` is passed to MaterialApp. ThemeExtensions attach here
- `lib/core/theme/app_theme.dart` — AppColors values get updated; AppTheme.lightTheme gets .extensions list
- `lib/core/theme/tokens/` — new directory for token extension classes
- `.github/workflows/release_android.yml` — new CI step for hardcoded color check
- Every file importing `app_theme.dart` gets the earthy palette via AppColors facade (zero call-site changes)

### Hardcoded Color(0xFF...) Hotspots
- `lib/core/theme/app_theme.dart` — 33 occurrences (exempt: this is where tokens are defined)
- `lib/core/router/app_router.dart` — 4 occurrences (needs migration)
- `lib/core/theme/error_widgets.dart` — 3 occurrences (needs migration)
- `lib/features/onboarding/screens/onboarding_screen.dart` — 3 occurrences (needs migration)
- `lib/features/events/widgets/event_spending_hero.dart` — 2 occurrences (needs migration)
- `lib/features/events/screens/event_expense_hero.dart` — 2 occurrences (needs migration)
- `lib/features/ledger/models/expense_category_model.dart` — 1 occurrence (exempt: category colors)
- `lib/features/groups/widgets/group_balance_hero.dart` — 1 occurrence (needs migration)
- ~46 total hardcoded Color() calls in lib/ outside app_theme.dart that need migration to tokens

</code_context>

<specifics>
## Specific Ideas

- Palette inspired by warm, earthy, outdoor/travel aesthetic — parchment/paper feel for backgrounds
- Module accents should feel "distinct but cohesive" — each earthy, but visually distinguishable
- Financial colors are functional, not brand — green/red stay universal
- The app should feel like "warm, inviting, confident" after the palette swap

</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope

</deferred>

---

*Phase: 15-design-token-system*
*Context gathered: 2026-03-28*
