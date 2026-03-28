# Phase 16: Stitch Workflow & Design Reference - Context

**Gathered:** 2026-03-28
**Status:** Ready for planning

<domain>
## Phase Boundary

Create high-fidelity visual specifications for three screens (Home, Group Detail, Event Hub) using Google Stitch as a design oracle. Establish a repeatable Stitch-to-Flutter workflow with ready-to-paste prompts, post-generation checklist, and palette reconciliation process. Document the workflow in CLAUDE.md for all subsequent phases to follow.

This phase produces **design artifacts** (specs, prompts, workflow docs), not Flutter implementation. The visual specs become the contracts that Phases 18-22 build against.

</domain>

<decisions>
## Implementation Decisions

### Mockup Scope & Fidelity

- **D-01:** High-fidelity mockups for all 3 screens — full earthy palette applied, real typography, proper spacing, realistic (generic placeholder) data
- **D-02:** All 4 screen states captured per screen: loaded (primary), empty state, loading/skeleton, and error state
- **D-03:** Equal depth for all 3 screens — Home, Group Detail, and Event Hub each get full treatment across all states
- **D-04:** Generic placeholder content — "User 1, User 2, OMR 10.000, Trip A" style. Not Omani-specific names/places
- **D-05:** Single breakpoint design — target ~390px width (iPhone 14 / Pixel 7). No responsive variants

### Screen Layout Decisions

- **D-06:** Home screen includes all 4 sections from NAV-01: balance hero at top, inline group cards, quick-action FAB tray, recent activity strip at bottom
- **D-07:** Group Detail uses dense dashboard layout — member balances, event timeline, group stats, settle-up CTA all visible without scrolling on standard phone
- **D-08:** Event Hub uses module grid with status — each module card shows live summary (e.g., "3 expenses, OMR 45.500") with module accent color from Phase 15 tokens

### Stitch-to-Flutter Workflow

- **D-09:** Stitch is visual oracle only — used purely for design exploration. Never commit Stitch-generated code. Implement from scratch using AppColors tokens
- **D-10:** Stitch inputs: palette hex values, natural language screen descriptions, current screenshots of existing screens, component inventory (shared widgets list)
- **D-11:** No Stitch configuration guidance needed — user knows the tool
- **D-12:** Hybrid execution — Claude prepares Stitch input prompts and post-generation checklist; user runs Stitch; Claude processes and annotates outputs into visual specs
- **D-13:** Ready-to-paste prompts as standalone files — one .md per screen in .planning/phases/16-*/prompts/. Version-tracked separately for easy copy-paste
- **D-14:** 1-2 iteration rounds per screen — generate once, review against checklist, refine once if needed. Mockup is a visual target, not pixel-perfect
- **D-15:** Workflow designed as reusable template — documented so Phases 20-22 can follow the same Stitch-to-Flutter pipeline

### Post-Generation Checklist

- **D-16:** Four mandatory verification checks:
  1. Color token mapping — every color maps to existing AppColors/AppColorTokens
  2. Spacing consistency — follows token scale (space4–space32)
  3. Component reuse check — uses existing shared widgets where possible
  4. Accessibility check — text contrast, 48px touch targets, interactive elements visually distinct

### Visual Spec Format & Storage

- **D-17:** Annotated design doc per screen in `.planning/design/` — text-first with section descriptions, token mappings, component hierarchy, structural hints, and links to external Stitch images
- **D-18:** Stitch output images NOT committed to repo — stored externally (user's choice of service). Specs reference them by URL or description
- **D-19:** Mandatory token mapping table per spec — every visual area maps to its AppColors/token reference (e.g., "Balance hero background → AppColors.primary")
- **D-20:** Full spacing spec — define spacing at every level: section gaps, card padding, text line-height, all using token names
- **D-21:** Include navigation + key interaction notes — what happens on tap/swipe, transition types (slide, fade, bottom sheet)
- **D-22:** Map to existing shared widgets by name — specs explicitly reference ModuleHeader, EmptyStateView, SmartModuleCard, etc. where applicable
- **D-23:** Include structural layout hints — describe layout structure (Stack, Column, Grid) alongside visual description. Bridges design to implementation

### Palette Reconciliation

- **D-24:** Snap to nearest existing token — Phase 15 tokens are source of truth. Stitch adapts to them, never the reverse
- **D-25:** WCAG verification against Phase 15 matrix — any color combination in mockup must pass AA threshold. Check all pairs, not just assumed-safe ones
- **D-26:** Stitch-generated color combinations not in the existing WCAG matrix must be verified before inclusion in the spec

### Claude's Discretion

- Whether to add new tokens during Phase 16 or document the need and defer to the implementation phase (18-22) — Claude judges per-case based on whether the gap is structural (needs token now) or cosmetic (can wait)
- Exact Stitch prompt wording and structure
- Level of annotation detail in the design specs beyond the mandatory token mapping table
- Organization of the design docs within `.planning/design/`

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Requirements
- `.planning/REQUIREMENTS.md` FOUND-03 — Screen mockups for key screens designed in Stitch as visual specification

### Phase dependencies
- `.planning/phases/15-design-token-system/15-CONTEXT.md` — Full palette mapping (D-01 through D-09), token architecture (D-10 through D-15), all locked hex values
- `.planning/phases/15-design-token-system/15-RESEARCH.md` — WCAG contrast matrix, ThemeExtension API details
- `.planning/phases/15-design-token-system/15-VERIFICATION.md` — Verified token values and WCAG compliance results

### Existing code (screen targets)
- `lib/features/home/screens/home_screen.dart` — Current home screen (204 lines, single scroll, basic group list)
- `lib/features/groups/screens/group_detail_screen.dart` — Current group detail (662 lines, member list, event cards, balance section)
- `lib/features/events/screens/event_command_center.dart` — Current event hub (115 lines, module card grid)

### Token system (design inputs)
- `lib/core/theme/tokens/color_tokens.dart` — AppColorTokens with 30 typed fields, earthyLight instance
- `lib/core/theme/tokens/spacing_tokens.dart` — AppSpacingTokens with spacing scale
- `lib/core/theme/tokens/shadow_tokens.dart` — AppShadowTokens with elevation levels
- `lib/core/theme/app_theme.dart` — AppColors facade (35 static constants), AppTheme.lightTheme

### Shared widgets (component inventory for Stitch input)
- `lib/shared/widgets/module_header.dart` — Dark gradient header
- `lib/shared/widgets/app_tab_bar.dart` — Tab bar with gradient pill indicator
- `lib/shared/widgets/empty_state_view.dart` — Empty states with optional CTA
- `lib/shared/widgets/smart_module_card.dart` — Module cards for CommandCenter
- `lib/shared/widgets/offline_banner.dart` — Connectivity indicator
- `lib/shared/widgets/skeleton_loader.dart` — Loading skeleton base

### Roadmap
- `.planning/ROADMAP.md` Phase 16 — success criteria defining mockup existence, post-generation checklist, palette reconciliation, and CLAUDE.md workflow documentation

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `ModuleHeader` — dark gradient header used across all module screens. Reusable in Event Hub redesign
- `SmartModuleCard` — module cards with icon, title, subtitle. Already in Event Hub. Can show status summary
- `EmptyStateView` — consistent empty states with optional CTA. Use for all 3 screens' empty states
- `SkeletonLoader` — base skeleton loading widget. Phase 17 extends this but the base exists
- `AppTabBar` — gradient pill tab bar. Potential use in Group Detail (events/members/activity tabs)
- `OfflineBanner` — connectivity indicator. Must be included in error state mockups

### Established Patterns
- `AppColors.*` static facade — 35 constants, 895 references. Mockups reference these token names
- `context.colors` / `context.spacing` / `context.shadows` — new ThemeExtension access. Specs can reference either pattern
- `AppPageRoute` (slide-right) and `AppBottomSheetRoute` (slide-up) — existing transition patterns for interaction notes
- Module accent colors: Ledger=#CC6B49, Gear=#7A8C5E, Logistics=#5B7B8C, Vault=#8B7355, Activity=#A67C5B, Memories=#9B7A5C

### Integration Points
- Home screen: GoRouter `/home` route. Providers: `userGroupsProvider`, `connectivityProvider`
- Group Detail: `Navigator.push` from home. Providers: `groupBalancesProvider`, `groupActivityProvider`
- Event Hub (CommandCenter): `Navigator.push` from group. Providers: `eventExpensesProvider`, `eventGearItemsProvider`
- Design specs in `.planning/design/` will be referenced by implementation phases 18-22 via PLAN.md canonical_refs

</code_context>

<specifics>
## Specific Ideas

- Dense information density — user wants dashboard-style layouts where key data is visible without scrolling
- Module grid with live status summaries in Event Hub — not just icons but actual data previews
- Stitch prompts should include the full component inventory so generated designs reference existing patterns
- Workflow is a pilot run — designed to be reused by every subsequent screen redesign phase

</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope

</deferred>

---

*Phase: 16-stitch-workflow-design-reference*
*Context gathered: 2026-03-28*
