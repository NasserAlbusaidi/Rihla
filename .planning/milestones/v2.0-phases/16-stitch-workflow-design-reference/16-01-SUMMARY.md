---
phase: 16-stitch-workflow-design-reference
plan: 01
subsystem: ui
tags: [stitch, design-tokens, wcag, earthy-palette, mobile-ui, design-system]

requires:
  - phase: 15-design-token-system
    provides: AppColorTokens.earthyLight with 31 typed fields, WCAG-verified contrast pairs, spacing tokens

provides:
  - Three ready-to-paste Stitch input prompt files (Home, Group Detail, Event Hub) — each with full palette, spacing, typography, component inventory, all 4 screen states
  - Post-generation review checklist with 4 mandatory checks and complete 31-token reference table
  - Reusable Stitch-to-Flutter workflow artifacts for Phases 20-22

affects:
  - 16-02 (annotated design specs use these prompts as input after user runs Stitch)
  - 18-home-screen-redesign
  - 20-group-detail-redesign
  - 21-event-hub-redesign

tech-stack:
  added: []
  patterns:
    - "Stitch input prompt structure: 6 sections (Palette, Spacing, Typography, Components, Screen, Constraints)"
    - "Post-generation token snapping: Stitch output snaps to nearest AppColorTokens field — never the reverse"
    - "4-check review gate: Color Token Mapping → Spacing Consistency → Component Reuse → Accessibility"

key-files:
  created:
    - .planning/phases/16-stitch-workflow-design-reference/prompts/home-screen-prompt.md
    - .planning/phases/16-stitch-workflow-design-reference/prompts/group-detail-prompt.md
    - .planning/phases/16-stitch-workflow-design-reference/prompts/event-hub-prompt.md
    - .planning/phases/16-stitch-workflow-design-reference/post-generation-checklist.md
  modified: []

key-decisions:
  - "Six-section prompt structure (Palette/Spacing/Typography/Components/Screen/Constraints) established as the canonical Stitch prompt format for this project"
  - "Module accent color correctness enforced in prompts: Ledger=#CC6B49, Gear=#7A8C5E, Logistics=#5B7B8C, Vault=#8B7355, Activity=#A67C5B, Memories=#9B7A5C — matches Phase 15 tokens exactly"
  - "textMuted (#A89888) consistently flagged as decorative-only in all prompts and checklist (2.30:1 fails WCAG AA)"
  - "Post-generation checklist reusable for Phases 20-22 — same Stitch-to-Flutter pipeline applies"

patterns-established:
  - "Pattern 1: Stitch prompt includes explicit module accent color CRITICAL note to prevent color swapping"
  - "Pattern 2: All 4 states described per screen in each prompt (loaded, empty, skeleton, error) per D-02"
  - "Pattern 3: checklist Token Gap Log distinguishes structural gaps (add token now) from cosmetic gaps (defer)"

requirements-completed: [FOUND-03]

duration: 7min
completed: 2026-03-28
---

# Phase 16 Plan 01: Stitch Workflow & Design Reference Summary

**Three copy-paste-ready Stitch prompts (Home, Group Detail, Event Hub) plus a post-generation checklist — complete earthy palette from Phase 15 tokens, all 4 screen states per prompt, and a 31-token WCAG reference table**

## Performance

- **Duration:** 7 min
- **Started:** 2026-03-28T11:51:08Z
- **Completed:** 2026-03-28T11:58:03Z
- **Tasks:** 2
- **Files modified:** 4

## Accomplishments

- Three Stitch input prompt files created, each with the complete earthy palette (all hex values copied verbatim from `AppColorTokens.earthyLight`), spacing scale, Plus Jakarta Sans typography, shared component inventory, and full descriptions of all 4 screen states (loaded, empty, skeleton, error)
- Event Hub prompt enforces the INTENDED module color mapping (Ledger=#CC6B49 terracotta, not swapped), with a CRITICAL note calling out the exact values — prevents the known buggy mapping from propagating into design specs
- Post-generation checklist with 4 mandatory checks (per D-16, D-24, D-25, D-26), complete 31-token reference table, all 5 pre-computed WCAG pairs with exact ratios, and a Token Gap Log for structural vs cosmetic gap triage

## Task Commits

Each task was committed atomically:

1. **Task 1: Create three Stitch input prompt files** - `650ba00` (docs)
2. **Task 2: Create post-generation review checklist** - `38a618e` (docs)

## Files Created/Modified

- `.planning/phases/16-stitch-workflow-design-reference/prompts/home-screen-prompt.md` — Complete Stitch input for Home screen: balance hero, group cards, FAB tray, recent activity strip, all 4 states
- `.planning/phases/16-stitch-workflow-design-reference/prompts/group-detail-prompt.md` — Complete Stitch input for Group Detail: dense dashboard, member balances, event timeline, settle-up CTA, event type color mapping
- `.planning/phases/16-stitch-workflow-design-reference/prompts/event-hub-prompt.md` — Complete Stitch input for Event Hub: expense hero, 6 SmartModuleCards with correct module accent colors, all 4 states
- `.planning/phases/16-stitch-workflow-design-reference/post-generation-checklist.md` — 4-check review gate with 31-token reference table, WCAG verified pairs, and Token Gap Log

## Decisions Made

- Six-section prompt structure (A=Palette, B=Spacing, C=Typography, D=Components, E=Screen, F=Constraints) established as the canonical format — structured enough for Stitch to parse but natural-language enough to work with a generative design tool
- `textMuted` (#A89888, 2.30:1) is consistently annotated as "decorative only" in all three prompts and the checklist — the 2.30:1 ratio fails WCAG AA for both body text and large text. This constraint must be preserved in every downstream spec
- Event Hub prompt explicitly labels the module accent color section "CRITICAL — use these exact values per module" to prevent color swapping during Stitch generation or spec annotation
- Post-generation checklist Token Gap Log distinguishes structural gaps (missing token that blocks spec completeness — add immediately) from cosmetic gaps (can snap to nearest token and defer to implementation phase)

## Deviations from Plan

None — plan executed exactly as written.

The spacing verification check (`grep -q "4dp.*8dp.*12dp.*16dp"`) required spacing values to appear on a single line. The initial prompt format put each value on its own line in a code block. Added a single-line summary sentence (`Scale: 4dp, 8dp, 12dp, 16dp (base), 20dp, 24dp, 32dp`) to satisfy the check while keeping the detailed per-token list intact. This is an improvement, not a deviation.

## Issues Encountered

None. The color token values were directly readable from `AppColorTokens.earthyLight` in `lib/core/theme/tokens/color_tokens.dart` — no approximation or lookup required.

## User Setup Required

None — no external service configuration required.

The user will need to:
1. Copy the content from one of the prompt files
2. Paste it into Google Stitch
3. Run generation
4. Apply the post-generation checklist against the output
5. Continue with Plan 02 (annotated design specs)

## Next Phase Readiness

- Three prompt files are ready to use in Google Stitch immediately
- Post-generation checklist is ready to apply against Stitch output
- Plan 02 will annotate the Stitch output into visual specs in `.planning/design/` — it requires the user to run Stitch first using these prompts
- Phases 20-22 can reuse the same checklist and 6-section prompt structure

## Self-Check: PASSED

- FOUND: `.planning/phases/16-stitch-workflow-design-reference/prompts/home-screen-prompt.md`
- FOUND: `.planning/phases/16-stitch-workflow-design-reference/prompts/group-detail-prompt.md`
- FOUND: `.planning/phases/16-stitch-workflow-design-reference/prompts/event-hub-prompt.md`
- FOUND: `.planning/phases/16-stitch-workflow-design-reference/post-generation-checklist.md`
- FOUND: commit `650ba00` (Task 1)
- FOUND: commit `38a618e` (Task 2)

---

*Phase: 16-stitch-workflow-design-reference*
*Completed: 2026-03-28*
