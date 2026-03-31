# Phase 16: Stitch Workflow & Design Reference - Research

**Researched:** 2026-03-28
**Domain:** Design tooling workflow, visual specification, design-to-Flutter handoff, WCAG verification
**Confidence:** HIGH

---

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions

**Mockup Scope & Fidelity**
- D-01: High-fidelity mockups for all 3 screens — full earthy palette applied, real typography, proper spacing, realistic (generic placeholder) data
- D-02: All 4 screen states captured per screen: loaded (primary), empty state, loading/skeleton, and error state
- D-03: Equal depth for all 3 screens — Home, Group Detail, and Event Hub each get full treatment across all states
- D-04: Generic placeholder content — "User 1, User 2, OMR 10.000, Trip A" style. Not Omani-specific names/places
- D-05: Single breakpoint design — target ~390px width (iPhone 14 / Pixel 7). No responsive variants

**Screen Layout Decisions**
- D-06: Home screen includes all 4 sections from NAV-01: balance hero at top, inline group cards, quick-action FAB tray, recent activity strip at bottom
- D-07: Group Detail uses dense dashboard layout — member balances, event timeline, group stats, settle-up CTA all visible without scrolling on standard phone
- D-08: Event Hub uses module grid with status — each module card shows live summary (e.g., "3 expenses, OMR 45.500") with module accent color from Phase 15 tokens

**Stitch-to-Flutter Workflow**
- D-09: Stitch is visual oracle only — used purely for design exploration. Never commit Stitch-generated code. Implement from scratch using AppColors tokens
- D-10: Stitch inputs: palette hex values, natural language screen descriptions, current screenshots of existing screens, component inventory (shared widgets list)
- D-11: No Stitch configuration guidance needed — user knows the tool
- D-12: Hybrid execution — Claude prepares Stitch input prompts and post-generation checklist; user runs Stitch; Claude processes and annotates outputs into visual specs
- D-13: Ready-to-paste prompts as standalone files — one .md per screen in .planning/phases/16-*/prompts/. Version-tracked separately for easy copy-paste
- D-14: 1-2 iteration rounds per screen — generate once, review against checklist, refine once if needed. Mockup is a visual target, not pixel-perfect
- D-15: Workflow designed as reusable template — documented so Phases 20-22 can follow the same Stitch-to-Flutter pipeline

**Post-Generation Checklist**
- D-16: Four mandatory verification checks:
  1. Color token mapping — every color maps to existing AppColors/AppColorTokens
  2. Spacing consistency — follows token scale (space4–space32)
  3. Component reuse check — uses existing shared widgets where possible
  4. Accessibility check — text contrast, 48px touch targets, interactive elements visually distinct

**Visual Spec Format & Storage**
- D-17: Annotated design doc per screen in `.planning/design/` — text-first with section descriptions, token mappings, component hierarchy, structural hints, and links to external Stitch images
- D-18: Stitch output images NOT committed to repo — stored externally (user's choice of service). Specs reference them by URL or description
- D-19: Mandatory token mapping table per spec — every visual area maps to its AppColors/token reference (e.g., "Balance hero background → AppColors.primary")
- D-20: Full spacing spec — define spacing at every level: section gaps, card padding, text line-height, all using token names
- D-21: Include navigation + key interaction notes — what happens on tap/swipe, transition types (slide, fade, bottom sheet)
- D-22: Map to existing shared widgets by name — specs explicitly reference ModuleHeader, EmptyStateView, SmartModuleCard, etc. where applicable
- D-23: Include structural layout hints — describe layout structure (Stack, Column, Grid) alongside visual description. Bridges design to implementation

**Palette Reconciliation**
- D-24: Snap to nearest existing token — Phase 15 tokens are source of truth. Stitch adapts to them, never the reverse
- D-25: WCAG verification against Phase 15 matrix — any color combination in mockup must pass AA threshold. Check all pairs, not just assumed-safe ones
- D-26: Stitch-generated color combinations not in the existing WCAG matrix must be verified before inclusion in the spec

### Claude's Discretion

- Whether to add new tokens during Phase 16 or document the need and defer to the implementation phase (18-22) — Claude judges per-case based on whether the gap is structural (needs token now) or cosmetic (can wait)
- Exact Stitch prompt wording and structure
- Level of annotation detail in the design specs beyond the mandatory token mapping table
- Organization of the design docs within `.planning/design/`

### Deferred Ideas (OUT OF SCOPE)

None — discussion stayed within phase scope.
</user_constraints>

---

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| FOUND-03 | Screen mockups for key screens (Home, Group Detail, Event Hub) are designed in Stitch and serve as visual specification | All three screens audited below; existing component inventory documented; Stitch prompt structure defined; post-generation checklist authored; token reconciliation process specified |
</phase_requirements>

---

## Summary

Phase 16 is a design artifact phase — it produces no Flutter code. Its output is three annotated design spec documents (one per screen), three Stitch input prompt files (one per screen), a post-generation checklist, and a CLAUDE.md workflow section. All of these are text artifacts stored in `.planning/` and the repo root.

The planner needs to understand three things: (1) exactly what content goes into each Stitch prompt — the complete earthy palette, spacing scale, component inventory, and per-screen description with all 4 states; (2) exactly what format the `.planning/design/` spec documents must follow to serve as contracts for Phases 18-22; and (3) where the Phase 15 token system is authoritative, including every hex value that a Stitch-generated image might produce that needs reconciling.

Phase 16 has no external tool dependencies from Claude's side. The user operates Stitch; Claude's deliverables are purely text and markdown. The only "wait" in execution is after each Stitch prompt file is created — the user runs Stitch, then the workflow continues with spec annotation. The plan must model this human-in-the-loop handoff explicitly.

**Primary recommendation:** Structure the plan as three screen mini-cycles (prompt file → user runs Stitch → annotated spec) plus one workflow documentation task (CLAUDE.md + post-generation checklist). This maps to 4 plans.

---

## Standard Stack

### Core

| Library / Tool | Version | Purpose | Why Standard |
|----------------|---------|---------|--------------|
| Google Stitch | Web app | UI mockup generation from text prompts + palette inputs | User-selected design oracle (D-09 through D-14) |
| Markdown (`.md`) | N/A | Prompt files and design spec format | Plain text, git-tracked, copy-paste ready, no tooling dependency |
| `.planning/design/` directory | N/A | Storage for annotated screen specs | Consistent with existing `.planning/` conventions across phases |

### No New Flutter Dependencies

Phase 16 adds zero `pubspec.yaml` entries. All work is design artifacts.

### Supporting Assets Already In-Repo

| Asset | Location | Role in Phase 16 |
|-------|----------|------------------|
| `AppColorTokens.earthyLight` | `lib/core/theme/tokens/color_tokens.dart` | Source of truth for all hex values in Stitch prompts |
| `AppSpacingTokens.standard` | `lib/core/theme/tokens/spacing_tokens.dart` | Spacing scale reference for spec documents |
| `AppShadowTokens.standard` | `lib/core/theme/tokens/shadow_tokens.dart` | Shadow/elevation reference |
| `AppColors` facade | `lib/core/theme/app_theme.dart` | Token names used in spec token-mapping tables |
| Shared widget files | `lib/shared/widgets/` | Component inventory for Stitch prompts and spec component hierarchy |

---

## Architecture Patterns

### Recommended Directory Structure

```
.planning/
├── design/
│   ├── home-screen-spec.md          # Annotated visual spec
│   ├── group-detail-spec.md
│   └── event-hub-spec.md
└── phases/
    └── 16-stitch-workflow-design-reference/
        ├── 16-CONTEXT.md
        ├── 16-RESEARCH.md            (this file)
        ├── prompts/
        │   ├── home-screen-prompt.md
        │   ├── group-detail-prompt.md
        │   └── event-hub-prompt.md
        └── post-generation-checklist.md
```

### Pattern 1: Stitch Input Prompt Structure

Every prompt file must include these sections in order for a Stitch prompt to produce a useful mockup:

**Section A — Palette (copy verbatim from tokens)**
```
Palette:
- Primary (terracotta): #CC6B49
- Background (sand): #F2E8D6
- Card surface (warm white): #FFF9F2
- Input fill: #F5EDE1
- Border: #E5D5C0
- Text primary (dark brown): #2C1A0E
- Text secondary: #6B5B4E
- Text muted: #A89888
- Text on primary (white): #FFFFFF
- Success display: #10B981
- Success text (WCAG safe): #047857
- Error display: #EF4444
- Error text (WCAG safe): #B91C1C
- Module Ledger: #CC6B49  |  Module Ledger light: #ECD5C0
- Module Gear: #7A8C5E    |  Module Gear light: #E0DAC4
- Module Logistics: #5B7B8C | Module Logistics light: #DBD7CA
- Module Vault: #8B7355   |  Module Vault light: #E2D6C2
- Module Activity: #A67C5B | Module Activity light: #E6D7C3
- Module Memories: #9B7A5C | Module Memories light: #E4D7C3
- Header gradient start: #2C1A0E  |  end: #3D2B1E
```

**Section B — Spacing scale**
```
Spacing: 4dp, 8dp, 12dp, 16dp (base), 20dp, 24dp, 32dp
Border radii: 12dp (chips/tags), 16dp (buttons/inputs), 20dp (cards/sheets)
Button height: 52dp
Touch targets: minimum 48dp
```

**Section C — Typography**
Plus Jakarta Sans. Weight hierarchy: 800 headings, 700 subtitles, 600 body emphasis, 400 body.

**Section D — Component inventory** (what already exists, to guide generated layout)
```
Existing shared components:
- ModuleHeader: dark gradient header (#2C1A0E → #3D2B1E), white title + subtitle, optional action icons
- AppTabBar: horizontal tabs with gradient pill indicator on active tab
- EmptyStateView: centered icon + title + message + optional CTA button
- SmartModuleCard: list-style card with icon (44×44, colored background), title, subtitle/summary, chevron
- OfflineBanner: thin connectivity indicator strip
- SkeletonLoader: grey placeholder blocks for loading states
```

**Section E — Screen description** (per-screen, specifying all 4 states)

**Section F — Constraints**
```
Target width: ~390px (iPhone 14 / Pixel 7)
Single breakpoint only
Generic placeholder data: "User 1", "User 2", "Group A", "Trip A", "OMR 10.000"
Dense information density: dashboard-style, minimal scrolling for key data
```

### Pattern 2: Annotated Design Spec Structure

Each `.planning/design/{screen}-spec.md` file follows this structure:

```markdown
# [Screen Name] — Visual Specification

**Phase:** 16
**Status:** [Draft / Stitch-reviewed / Final]
**Target:** ~390px width, single breakpoint

## Screen States

### State 1: Loaded (Primary)
[description of layout]

#### Token Mapping
| Visual Area | Token Reference |
|-------------|----------------|
| [area] | AppColors.[token] |

#### Component Hierarchy
[Flutter structure description: Scaffold → Column → ModuleHeader + Expanded(ListView → ...)]

#### Spacing Spec
| Location | Token |
|----------|-------|
| Horizontal padding | AppColors.space24 |
| Card gap | AppColors.space16 |

#### Interaction Notes
| Trigger | Action | Transition |
|---------|--------|-----------|
| Tap group card | Navigate to Group Detail | AppPageRoute (slide-right) |

### State 2: Empty State
[...]

### State 3: Loading/Skeleton
[...]

### State 4: Error State
[...]

## Stitch Image References
[External URLs or descriptions]

## Token Gaps Identified
[Any new tokens needed that are not in AppColorTokens.earthyLight]
```

### Pattern 3: Post-Generation Checklist

The mandatory checklist file (`.planning/phases/16-.../post-generation-checklist.md`) is a reference document used every time Stitch output is reviewed. It contains the 4 mandatory checks from D-16 as a fillable table:

```markdown
# Post-Generation Review Checklist

## Check 1: Color Token Mapping
For every color in the Stitch output:
- [ ] Map to exact AppColors.* constant or AppColorTokens field
- [ ] Flag any color not in the token system
- [ ] Confirm all text-on-background pairs are in the WCAG-verified set

## Check 2: Spacing Consistency
- [ ] All padding/gap values align to 4dp grid
- [ ] Named using token names (space4, space8, space12, space16, space20, space24, space32)
- [ ] No non-token spacing values (e.g., 6dp, 10dp, 15dp)

## Check 3: Component Reuse
- [ ] ModuleHeader used for dark gradient header sections
- [ ] EmptyStateView used for empty states (not custom built)
- [ ] SmartModuleCard used for module list items in Event Hub
- [ ] SkeletonLoader used for loading states
- [ ] OfflineBanner included in error state mockups

## Check 4: Accessibility
- [ ] All body text combinations in WCAG-verified set (13.71:1, 5.35:1, etc.)
- [ ] All interactive elements visually distinct
- [ ] Touch targets ≥ 48dp (per D-16)
- [ ] textMuted (#A89888) used decoratively only — never for functional labels
```

### Pattern 4: CLAUDE.md Workflow Section

The Stitch-to-Flutter workflow documentation added to `CLAUDE.md` covers:
1. The workflow role (design oracle, not code source)
2. What to prepare before running Stitch (prompt file, palette, component inventory)
3. The post-generation checklist file path
4. How to annotate Stitch output into a spec doc
5. Where specs are stored (`.planning/design/`)
6. Token replacement rule: any Stitch color → nearest AppColors token (never the reverse)

---

## Token System State (Phase 15 Complete)

This section is the authoritative token reference for all Stitch prompt content and palette reconciliation.

### Complete Color Token Inventory

| Token Field | Hex Value | AppColors alias | WCAG on sand (4.5:1 body / 3:1 large) |
|-------------|-----------|----------------|----------------------------------------|
| `primary` | #CC6B49 | `AppColors.primary` | N/A as background; textOnPrimary (#FFF) = 3.64:1 (AA large) |
| `scaffoldBackground` | #F2E8D6 | `AppColors.background` | Reference surface |
| `cardSurface` | #FFF9F2 | `AppColors.surface` | Reference surface |
| `inputFill` | #F5EDE1 | `AppColors.surfaceLight` | Reference surface |
| `border` | #E5D5C0 | `AppColors.border` | Decorative only |
| `textPrimary` | #2C1A0E | `AppColors.textPrimary` | 13.71:1 (AAA) |
| `textSecondary` | #6B5B4E | `AppColors.textSecondary` | 5.35:1 (AA) |
| `textMuted` | #A89888 | `AppColors.textMuted` | 2.30:1 (FAIL — decorative only) |
| `textOnPrimary` | #FFFFFF | `AppColors.textOnPrimary` | 3.64:1 on terracotta (AA large) |
| `success` | #10B981 | `AppColors.success` | Display only — use successText for text |
| `successText` | #047857 | `AppColors.success` (use as text) | 4.51:1 (AA body text) |
| `error` | #EF4444 | `AppColors.error` | Display only — use errorText for text |
| `errorText` | #B91C1C | `AppColors.error` (use as text) | 5.33:1 (AA body text) |
| `disabled` | #E5D5C0 | `AppColors.disabled` | Disabled state background |
| `disabledText` | #A89888 | — | Below AA — disabled state only |
| `focusRing` | #CC6B49 | `AppColors.primary` | Focus indicator |
| `selectionFill` | #F5DDD3 | `AppColors.primaryLight` | Selected item background |
| `moduleLedger` | #CC6B49 | `AppColors.mint` / `AppColors.primary` | Module accent |
| `moduleLedgerLight` | #ECD5C0 | — | Module card background tint |
| `moduleGear` | #7A8C5E | `AppColors.accentSecondary` | Module accent |
| `moduleGearLight` | #E0DAC4 | — | Module card background tint |
| `moduleLogistics` | #5B7B8C | `AppColors.sky` | Module accent |
| `moduleLogisticsLight` | #DBD7CA | — | Module card background tint |
| `moduleVault` | #8B7355 | `AppColors.indigo` | Module accent |
| `moduleVaultLight` | #E2D6C2 | — | Module card background tint |
| `moduleActivity` | #A67C5B | — | Module accent |
| `moduleActivityLight` | #E6D7C3 | — | Module card background tint |
| `moduleMemories` | #9B7A5C | `AppColors.mint` (alias) | Module accent |
| `moduleMemoriesLight` | #E4D7C3 | — | Module card background tint |
| `headerGradientStart` | #2C1A0E | `AppColors.surfaceDark` | Dark header gradient |
| `headerGradientEnd` | #3D2B1E | — | Dark header gradient |

**Key constraint:** `textMuted` (#A89888) fails WCAG AA at 2.30:1 and must NEVER appear as functional text in any spec. Document as "decorative only" in every spec it appears.

### Spacing Token Inventory

| Token | Value | AppColors alias |
|-------|-------|----------------|
| `space4` | 4dp | `AppColors.space4` |
| `space8` | 8dp | `AppColors.space8` |
| `space12` | 12dp | `AppColors.space12` |
| `space16` | 16dp | `AppColors.space16` |
| `space20` | 20dp | `AppColors.space20` |
| `space24` | 24dp | `AppColors.space24` |
| `space32` | 32dp | `AppColors.space32` |
| `radiusSmall` | 12dp | `AppColors.radiusSmall` |
| `radiusMedium` | 16dp | `AppColors.radiusMedium` |
| `radiusLarge` | 20dp | `AppColors.radiusLarge` |
| `buttonHeight` | 52dp | — |

---

## Current Screen Audit

Each screen's current state, what it lacks (vs. Phase 16 target), and what the Stitch prompt must describe.

### Home Screen (204 lines — `lib/features/home/screens/home_screen.dart`)

**Current implementation:**
- Header: plain text "Your Groups" with fadeIn animation. No balance hero.
- Body: simple `ListView.builder` of `GroupCard` widgets
- FAB: single `FloatingActionButton` → bottom sheet with Create/Join options
- States: has loaded + empty (`EmptyStateView`) + loading (`SkeletonLoader.groupList`) + error (`EmptyStateView`)
- Missing vs. Phase 18 target: no balance hero (NAV-01), no quick-action FAB tray, no recent activity strip

**What the Stitch prompt must specify for Home (D-06):**
1. Loaded state: balance hero card at top (net balance green/red/gray coded), then scrollable group card list, then activity strip at bottom, FAB tray (Add Expense, Settle Up, Invite, Activity) visible without scroll
2. Empty state: `EmptyStateView` pattern with illustration + "Create your first group" CTA
3. Loading state: hero skeleton + 3 group card skeletons
4. Error state: `EmptyStateView` with error icon + `OfflineBanner` at top

**Token gaps to watch:** Balance hero needs a "balance positive" color (currently no dedicated `balancePositive` token — `successText` #047857 is the nearest). Document in spec whether to use `successText` directly or request a new `balancePositive` token.

### Group Detail Screen (662 lines — `lib/features/groups/screens/group_detail_screen.dart`)

**Current implementation:**
- Header: `ModuleHeader` with dark gradient, group name, settings icon button
- Body: scrollable Column with: stats chips row → balance hero (conditional on first expense) → spending stats → members+balances section → events section → invite code → activity section
- Providers: `groupDetailProvider`, `groupBalancesProvider`
- States: has loaded + loading skeleton (inline Container placeholder) + error ("Error loading group" — plain text, not `EmptyStateView`)

**What the Stitch prompt must specify for Group Detail (D-07):**
Dense dashboard: all key data visible without scrolling on ~390px screen. Layout order:
1. `ModuleHeader` (dark gradient, group name, settings action)
2. Summary strip: member count chip + currency chip (currently space8 gap)
3. Balance hero card: total spent, current user's net balance (green/red), settle-up CTA button
4. Member balances row (compact horizontal or vertical accordion)
5. Event timeline: upcoming + past cards with type-specific accent colors
6. Invite code chip (below events per D-30)
7. Activity strip (recent 3 items)

Empty state per section: events section shows `EmptyStateView`, activity section shows empty state with CTA.

**Token gaps to watch:** Event cards need type-specific color accents. Event types are: Trip, Camping, Day Out, Dinner, Custom. Currently only Trip and Camping have established colors. Research needed: are these mapped to module colors or are separate event-type tokens needed?

### Event Hub (115 lines — `lib/features/events/screens/event_command_center.dart`)

**Current implementation:**
- Header: `ModuleHeader` with event name + "type · group name" subtitle, options icon button
- Body: `EventExpenseHero` (spending card) + `EventModuleList` (SmartModuleCard list)
- Module cards: Ledger (#CC6B49), Gear (#7A8C5E or amber for urgency), Logistics (#5B7B8C), Vault (#8B7355), Memories (#9B7A5C/mint)
- `SmartModuleCard`: already shows live summary or action text
- FAB: add expense shortcut

**Current module color mapping in code (important for D-08):**
| Module | Color used in code | Phase 15 token |
|--------|-------------------|----------------|
| Ledger | `AppColors.accentSecondary` (#7A8C5E) | `moduleGear` — MISMATCH |
| Gear (normal) | `AppColors.accentSecondary` (#7A8C5E) | `moduleGear` |
| Gear (urgent) | `AppColors.amber` (#F59E0B) | No token — outside earthy palette |
| Logistics | `AppColors.sky` (#5B7B8C) | `moduleLogistics` |
| Vault | `AppColors.indigo` (#8B7355) | `moduleVault` |
| Memories | `AppColors.mint` (#CC6B49) | `moduleLedger` — Memories uses Ledger color |

**CRITICAL FINDING:** The current `event_module_list.dart` does NOT use module-specific token colors correctly. Ledger card uses `AppColors.accentSecondary` (olive/gear color, not terracotta). Memories uses `AppColors.mint` (terracotta). The Phase 16 spec must document the CORRECT intended token mapping per D-08 and Phase 15 decisions — implementation phases 20-22 fix this. The Stitch prompt must use the INTENDED colors (from Phase 15 tokens), not the current code colors.

**Correct intended module color mapping (for Stitch prompts and spec):**
| Module | Intended Token | Hex |
|--------|---------------|-----|
| Ledger | `moduleLedger` | #CC6B49 |
| Gear | `moduleGear` | #7A8C5E |
| Logistics | `moduleLogistics` | #5B7B8C |
| Vault | `moduleVault` | #8B7355 |
| Activity | `moduleActivity` | #A67C5B |
| Memories | `moduleMemories` | #9B7A5C |

**What the Stitch prompt must specify for Event Hub (D-08):**
1. `ModuleHeader` with event name, type·group subtitle
2. Expense hero card with total amount (large typography, terracotta)
3. Module card list: each using its correct accent color, with live summary text visible ("3 expenses · OMR 45.500")
4. FAB (add expense)
5. States: loaded (all cards with data), loading (skeleton), empty (no expenses yet, empty module cards), error (OfflineBanner + error EmptyStateView)

---

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| WCAG contrast calculation | Custom ratio formula | Document the Phase 15 WCAG matrix (already in 15-RESEARCH.md) | All relevant pairs already computed; just reference them |
| Design spec template | Ad-hoc format per screen | The standardized spec format in Pattern 2 above | Downstream phases 18-22 all read from the same spec format |
| Token reference table | Re-derive from source | Copy verbatim from `AppColorTokens.earthyLight` in `color_tokens.dart` | Source of truth is the Dart file; no derivation needed |
| Stitch workflow doc | Prose narrative | Structured CLAUDE.md section with numbered steps | Phases 20-22 follow the same workflow; structured format is machine-readable by future Claude sessions |

---

## Common Pitfalls

### Pitfall 1: Stitch Generating Non-Token Colors
**What goes wrong:** Stitch freely interpolates between palette values, producing colors like #D07A58 (slightly lighter terracotta) or #8E6B57 (between textSecondary and textPrimary) that are not in the token system.
**Why it happens:** AI design tools optimize for visual aesthetics, not token compliance.
**How to avoid:** Post-generation checklist Check 1 catches this. Every spec's token-mapping table forces explicit resolution. Rule is: snap to nearest token, never add a new token unless the gap is structural.
**Warning signs:** A color appearing in the spec that is not in the token inventory table above.

### Pitfall 2: textMuted Used as Functional Text
**What goes wrong:** Stitch (or the annotator) uses #A89888 for labels, captions, or UI text that users need to read.
**Why it happens:** textMuted looks reasonable at 100% zoom on a design canvas; WCAG failure (2.30:1) is invisible without measurement.
**How to avoid:** Post-generation checklist Check 4 explicitly flags textMuted. In every spec, annotate it as "decorative only" wherever it appears.
**Warning signs:** "textMuted" appearing in any token mapping table row where the visual area is a label, count, or currency amount.

### Pitfall 3: Spec Format Diverges Across Three Screens
**What goes wrong:** Each screen spec uses a different format — one has a component hierarchy, one doesn't; one has interaction notes, one doesn't. Phases 18-22 cannot reliably reference them.
**Why it happens:** Three separate creation tasks without a template enforced up front.
**How to avoid:** The planner must create all three spec files from the SAME template (Pattern 2 above). Claude's creation of spec files must use the template strictly.
**Warning signs:** A spec missing the "Token Mapping", "Component Hierarchy", or "Interaction Notes" sections.

### Pitfall 4: Module Color Mismatch in Event Hub Spec
**What goes wrong:** Spec documents the current code colors (e.g., Ledger = #7A8C5E) instead of the intended Phase 15 token colors (Ledger = #CC6B49).
**Why it happens:** Reading `event_module_list.dart` current code without checking Phase 15 token decisions.
**How to avoid:** The CORRECT module color mapping is explicitly documented in the Screen Audit section above. The spec and Stitch prompt must use the intended mapping, not the current code mapping.
**Warning signs:** Ledger module shown as olive/green instead of terracotta in the Event Hub spec.

### Pitfall 5: Spec Describes Pixel-Perfect Details Stitch Cannot Guarantee
**What goes wrong:** Spec includes "13pt Plus Jakarta Sans Semibold with -0.3 letter-spacing" level detail that doesn't come from Stitch output.
**Why it happens:** Over-specification at Phase 16 scope; Phase 16 is a visual target, not a pixel-perfect handoff.
**How to avoid:** Keep typography in the spec at the token level: "headlineLarge / titleMedium / bodyMedium from AppTheme.lightTheme". Phase 20-22 implementors read the Flutter TextTheme.
**Warning signs:** Sub-pixel measurements in spec documents.

### Pitfall 6: Human-in-the-Loop Not Modeled in Plan
**What goes wrong:** Plan structure treats all tasks as Claude-executable in sequence, without pause points for the user to run Stitch.
**Why it happens:** Linear plan structure assumes Claude executes everything.
**How to avoid:** Each screen's plan wave must have a task that creates the prompt file, followed by an explicit PAUSE (human runs Stitch), followed by a task that produces the annotated spec. D-12 mandates this hybrid.
**Warning signs:** A plan where all tasks are marked as Claude-executable with no user action steps.

---

## Execution Model (Human-in-the-Loop)

Phase 16 has a fundamentally different execution model from all prior phases. The planner must design for it explicitly.

```
For each screen:
  Wave A (Claude):
    - Create .planning/phases/16-.../prompts/{screen}-prompt.md
    - Pause: User runs Stitch with the prompt file content
  Wave B (Claude — after user provides Stitch output URL or description):
    - Create .planning/design/{screen}-spec.md
    - Run post-generation checklist against Stitch output
    - Annotate spec with token mappings, component hierarchy, interaction notes
    - Flag any token gaps found

Final wave (Claude):
  - Create .planning/phases/16-.../post-generation-checklist.md
  - Update CLAUDE.md with Stitch workflow section
```

The PLAN.md must make the pause points explicit. Tasks in Wave B are blocked until the user completes Stitch generation and shares the output.

---

## Code Examples

### Correct Token Reference Pattern in Spec Tables

From the Phase 15 system, the correct way to reference a token in a spec is:

```markdown
| Background | AppColors.background | #F2E8D6 | Sand |
| Card surface | AppColors.surface | #FFF9F2 | Warm white |
| Primary button | AppColors.primary | #CC6B49 | Terracotta |
| Body text | AppColors.textPrimary | #2C1A0E | Dark brown |
| Header gradient | AppColors.surfaceDark → #3D2B1E | #2C1A0E → #3D2B1E | Dark brown gradient |
```

Both the AppColors name AND the hex value must be in the spec — future Claude sessions may not have app_theme.dart loaded.

### SmartModuleCard Visual Description for Stitch

The correct description for Stitch to generate a SmartModuleCard-equivalent:

```
Module card: horizontal row, 16dp all-side padding, white card surface (#FFF9F2), 20dp corner radius, 1.5dp border (#E5D5C0).
Left: 44×44 circle icon container with 12% module-color fill. Icon is module-accent-color at 22px.
Center: title (dark brown, 15sp, 800 weight), subtitle (secondary text, 13sp, 600 weight).
Right: chevron arrow icon (textMuted).
Card with data has 12% icon opacity (vs 6% empty). Chevron is textSecondary (vs textMuted) when data present.
```

### WCAG Pair Verification (D-25, D-26)

For any new color combination appearing in a Stitch output, the verification formula is:

```
relative luminance L = 0.2126R + 0.7152G + 0.0722B
  (where R/G/B are linearized from 0–1 sRGB)
contrast ratio = (L_lighter + 0.05) / (L_darker + 0.05)
AA body text: ≥ 4.5:1
AA large text/icons: ≥ 3.0:1
```

Pre-computed verified pairs from Phase 15 tests:
- textPrimary (#2C1A0E) on sand (#F2E8D6): **13.71:1** (AAA)
- textSecondary (#6B5B4E) on sand: **5.35:1** (AA)
- successText (#047857) on sand: **4.51:1** (AA body)
- errorText (#B91C1C) on sand: **5.33:1** (AA body)
- textOnPrimary (#FFFFFF) on primary (#CC6B49): **3.64:1** (AA large)

Any Stitch-generated pair not in this list requires manual calculation before entering the spec.

---

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| Design in Figma/Sketch → export assets → hand off | AI design tools (Stitch) generate Flutter-like layouts from text prompts | 2024–2025 | Dramatically reduces design-to-code gap; still requires token enforcement |
| Pixel-perfect specs with redlines | Token-based specs with semantic references | 2022+ (Material You, design tokens adoption) | Specs reference token names, not pixel values — survives design system changes |

---

## Open Questions

1. **Event Type Colors for Group Detail**
   - What we know: 6 event types exist (Trip, Camping, Day Out, Dinner, Custom, plus more TBD). The Group Detail spec (D-07) shows "type-specific color accents" on event cards.
   - What's unclear: Are event type colors mapped to module accent colors, or do they need their own tokens? Phase 15 tokens only define module colors (Ledger, Gear, etc.), not event type colors.
   - Recommendation: Claude's Discretion (per CONTEXT.md). Default approach: map event types to existing tokens (Trip → moduleLedger terracotta, Camping → moduleGear olive, Day Out → moduleLogistics teal, Dinner → moduleVault bronze, Custom → moduleActivity caramel). Document this mapping decision in the Group Detail spec under "Token Gaps Identified". Defer formal token addition to Phase 20.

2. **Gear Urgent State Color**
   - What we know: `event_module_list.dart` uses `AppColors.amber` (#F59E0B) for gear with unclaimed items. This is NOT in the Phase 15 earthy palette and has no token.
   - What's unclear: Should amber stay as an urgency signal, or should it snap to the nearest earthy token?
   - Recommendation: Flag in the Event Hub spec. `AppColors.amber` (#F59E0B) reads as high-urgency but breaks the earthy palette. Nearest earthy urgency signal could be errorText (#B91C1C). Recommend documenting both options in the spec and deferring the decision to Phase 20 where the module card is implemented. The Stitch prompt can use amber for now as a visual placeholder.

3. **Balance Hero "Balanced" (Zero) State Color**
   - What we know: Home screen NAV-01 requires net balance color-coded green/red/gray. Green = successText, Red = errorText. Gray when balanced = ?
   - What's unclear: No "neutral balance" token exists. textSecondary (#6B5B4E) is 5.35:1 AA and reads as warm gray. textMuted is below AA.
   - Recommendation: Use `textSecondary` (#6B5B4E) for the zero-balance state. Document this as the intended token in the Home screen spec. No new token needed.

---

## Environment Availability

Step 2.6: SKIPPED — Phase 16 produces no Flutter code, runs no commands, and has no external runtime dependencies from Claude's side. All deliverables are markdown files authored by Claude. Stitch is operated by the user in their browser.

---

## Validation Architecture

Per `.planning/config.json`, `workflow.nyquist_validation: true`. However, Phase 16 produces exclusively design artifacts (markdown files). There is no executable behavior to test.

### Test Framework

| Property | Value |
|----------|-------|
| Framework | Flutter test (existing) |
| Config file | pubspec.yaml (no separate test config) |
| Quick run command | `flutter test test/unit/design_tokens_test.dart --no-pub` |
| Full suite command | `flutter test --no-pub` |

### Phase Requirements → Test Map

| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| FOUND-03 | Screen mockups exist as visual specs | manual | N/A — visual artifact verification | N/A |

FOUND-03 has no automated test coverage. The "test" is the existence of the three spec files with complete content sections. The verifier for Phase 16 checks file existence and content completeness, not code behavior.

### Wave 0 Gaps

None — no test files need creation. The existing `flutter test` suite (660+ tests) continues to pass unchanged. Phase 16 adds no code.

---

## Sources

### Primary (HIGH confidence)
- `/Users/nasseralbusaidi/Desktop/Personal/Rihla/lib/core/theme/tokens/color_tokens.dart` — all token hex values, field names, earthyLight instance
- `/Users/nasseralbusaidi/Desktop/Personal/Rihla/lib/core/theme/tokens/spacing_tokens.dart` — spacing scale, border radii, button height
- `/Users/nasseralbusaidi/Desktop/Personal/Rihla/lib/core/theme/tokens/shadow_tokens.dart` — shadow elevation levels
- `/Users/nasseralbusaidi/Desktop/Personal/Rihla/lib/core/theme/app_theme.dart` — AppColors facade (all static constants)
- `/Users/nasseralbusaidi/Desktop/Personal/Rihla/.planning/phases/16-stitch-workflow-design-reference/16-CONTEXT.md` — all locked decisions D-01 through D-26
- `/Users/nasseralbusaidi/Desktop/Personal/Rihla/.planning/phases/15-design-token-system/15-VERIFICATION.md` — WCAG ratios (13.71:1, 5.35:1, 4.51:1, 5.33:1, 3.64:1) verified by passing tests
- `/Users/nasseralbusaidi/Desktop/Personal/Rihla/lib/features/events/widgets/event_module_list.dart` — current module color usage (revealing the color mismatch)
- `/Users/nasseralbusaidi/Desktop/Personal/Rihla/lib/shared/widgets/smart_module_card.dart` — SmartModuleCard current implementation

### Secondary (MEDIUM confidence)
- Phase 15 WCAG contrast tests (passing) — contrast ratios cited above verified by `test/unit/design_tokens_test.dart`

### Tertiary (LOW confidence — not needed, all context from codebase)
- None

---

## Metadata

**Confidence breakdown:**
- Token inventory: HIGH — sourced directly from Dart token files (verified by Phase 15 passing tests)
- Screen audit: HIGH — sourced directly from the three screen implementation files
- Stitch prompt structure: HIGH (for palette/spacing sections) / MEDIUM (for prompt wording) — D-11 says user knows Stitch; Claude writes prompt content, not configuration
- Workflow/checklist pattern: HIGH — directly derived from CONTEXT.md decisions D-09 through D-26
- Module color mismatch finding: HIGH — verified by reading event_module_list.dart and comparing to Phase 15 token decisions

**Research date:** 2026-03-28
**Valid until:** 2026-06-01 (token system stable; Stitch is an external tool whose UI may change but Claude's deliverables are prompt content, not Stitch configuration)
