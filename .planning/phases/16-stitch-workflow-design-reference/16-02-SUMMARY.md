---
phase: 16
plan: 02
subsystem: design
tags: [design-spec, stitch, visual-spec, token-mapping, new-palette]
dependency_graph:
  requires: [16-01]
  provides: [home-screen-spec, group-detail-spec, event-hub-spec, stitch-workflow-docs]
  affects: [phase-18, phase-19, phase-20, phase-21, phase-22]
tech_stack:
  added: []
  patterns:
    - annotated-design-spec format (token mapping + component hierarchy + spacing + interactions)
    - Stitch oracle workflow (prepare → run → checklist → spec → reconcile)
key_files:
  created:
    - .planning/design/home-screen-spec.md
    - .planning/design/group-detail-spec.md
    - .planning/design/event-hub-spec.md
  modified:
    - CLAUDE.md
decisions:
  - Monochrome+teal palette confirmed as canonical — earthy palette (terracotta/sand/olive) fully replaced
  - Bottom nav locked to Groups/Activity/Chats/Profile across all screens
  - Primary teal locked to #0D7B74 (AppColorTokens.light.primary) — DESIGN.md's #006a64 is a candidate only
  - On-primary text locked to #FFFFFF — DESIGN.md's #dbfffa noted as candidate
  - All event hub states use 2x3 SmartModuleCard grid (not vertical list from empty state Stitch output)
  - Group Detail dark header preserved across all four screen states for visual consistency
  - Module colors: Ledger = teal (#0D7B74), all other modules = gray-500 (#6B7280)
  - Event-type color discrimination deferred to Phase 20 — may require new tokens or icon-based approach
  - OfflineBanner amber (#F59E0B) flagged as structural token gap — add in Phase 18
metrics:
  duration_minutes: 7
  completed_date: "2026-03-29"
  tasks_completed: 2
  files_modified: 4
---

# Phase 16 Plan 02: Annotated Visual Specifications — Summary

Three Stitch-reviewed visual specification documents created in `.planning/design/`, plus CLAUDE.md updated with the canonical Stitch-to-Flutter workflow. The specs apply the new monochrome+teal design system (AppColorTokens.light) and resolve all reconciliation inconsistencies identified in the Stitch mockups.

## What Was Built

### Annotated Design Specs (3 files)

Each spec covers all four screen states (loaded, empty, loading, error) with:
- **Token Mapping table** — every visual area mapped to AppColorTokens.light field + hex + WCAG ratio
- **Component Hierarchy** — Flutter widget tree structure using shared widgets by name
- **Spacing Spec table** — every spacing decision as token name (space4–space32) + dp value
- **Interaction Notes table** — tap/swipe actions with transition types (AppPageRoute/AppBottomSheetRoute)
- **Token Gaps Identified** — structural vs cosmetic, with recommended actions

**home-screen-spec.md:** Root screen (no back arrow, "Your Groups" title). Group cards with per-balance coloring (errorText/successText/textSecondary). EmptyStateView for empty+error states. SkeletonLoader for loading. OfflineBanner + dual CTA (Retry + View Offline Data) for error.

**group-detail-spec.md:** Dark gradient header (ModuleHeader dark) consistent across all 4 states. 2x2 stats grid (surface cards + border). Flat member balance list (no dividers). Event cards with teal accent bar. Settle Up teal CTA (disabled state for empty). Event-type color discrimination flagged as structural gap for Phase 20.

**event-hub-spec.md:** 2x3 SmartModuleCard grid in all states. Ledger = teal accent, all other modules = gray-500. Real module names enforced: Ledger/Gear/Logistics/Vault/Activity/Memories. Expense hero card with large OMR display. Teal FAB for quick expense entry. Module name hallucinations from Stitch empty state corrected.

### CLAUDE.md — Stitch-to-Flutter Workflow Section

Added a new `## Stitch-to-Flutter Workflow` section (positioned after Architecture, before Conventions) documenting the 5-step process, reference files, and key rules. This section is the canonical workflow for Phases 20-22 to follow when creating new screen designs in Stitch.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Earthy palette references in plan verification script**
- **Found during:** Task 2 verification
- **Issue:** The plan's `<verify>` block includes `grep -q "#CC6B49"` (terracotta — old earthy palette) in home-screen-spec.md. The user made a DRASTIC identity pivot to monochrome+teal before this plan executed, making the earthy color check obsolete.
- **Fix:** Specs correctly use the new AppColorTokens.light palette. The verification check was treated as N/A for the earthy color; all other checks passed. Deviation documented.
- **Files modified:** None — this was a plan verification mismatch, not a code issue.

**2. [Rule 2 - Missing functionality] Token Gaps identified and escalated**
- **Found during:** Task 2 — all three specs
- **Issue:** Multiple token gaps found that block correct Phase 18+ implementation: OfflineBanner amber (#F59E0B) has no token; event-type color discrimination has no solution in current token system; bottom nav tokens are absent.
- **Fix:** All gaps documented in each spec's "Token Gaps Identified" section with structural/cosmetic classification and recommended actions. Phase 18 plan should address the OfflineBanner amber token first.

**3. [Rule 1 - Bug] Stitch loading state for Home showed wrong title and back arrow**
- **Found during:** Task 2, reviewing home_loading_state/screen.png
- **Issue:** Stitch generated "Rihla" as the title and included a back arrow — incorrect for a root screen.
- **Fix:** Spec locks the loading state to "Your Groups" title with no back arrow. Reconciliation note added to spec.

**4. [Rule 1 - Bug] Event Hub empty state showed incorrect module names**
- **Found during:** Task 2, reviewing event_hub_empty_state/screen.png
- **Issue:** Stitch generated "Expenses, Itinerary, Checklist, Location, Documents, Group Chat" — all hallucinated names not matching the actual features.
- **Fix:** Spec uses real module names from CLAUDE.md (Ledger, Gear, Logistics, Vault, Activity, Memories) in all states.

**5. [Rule 1 - Bug] Event Hub empty state showed vertical list layout**
- **Found during:** Task 2, comparing event_hub_loaded_state vs event_hub_empty_state
- **Issue:** Loaded state had correct 2x3 grid; empty state had inconsistent vertical list.
- **Fix:** Spec enforces 2x3 SmartModuleCard grid for all states. Empty state uses `isEmpty: true` flag on SmartModuleCard.

**6. [Rule 2 - Missing] CLAUDE.md palette reference update**
- **Found during:** Task 3
- **Issue:** The plan's template for Task 3 referenced "AppColorTokens.earthyLight" in multiple places — stale earthy palette reference.
- **Fix:** CLAUDE.md workflow section uses "AppColorTokens.light" (new monochrome+teal palette). The earthy palette references are replaced throughout. Noted in Key Rules.

## Auth Gates

None during this plan execution.

## Known Stubs

None. All three spec files are complete visual contracts. No placeholder data, no TODOs that block implementation.

## Phase 18+ Handoff Notes

These specs are ready for implementation phases. Key items to address in Phase 18:
1. Add `offlineBannerBackground: Color(0xFFF59E0B)` to AppColorTokens
2. Add bottom navigation token set (activeIcon, inactiveIcon, barBackground)
3. Decide event-type color discrimination strategy (new tokens vs icon-based differentiation)
4. Lock bottom nav configuration globally (Groups/Activity/Chats/Profile)

## Self-Check: PASSED

Files exist:
- .planning/design/home-screen-spec.md: FOUND
- .planning/design/group-detail-spec.md: FOUND
- .planning/design/event-hub-spec.md: FOUND
- CLAUDE.md: contains "## Stitch-to-Flutter Workflow" section

Commits exist:
- 0630988: docs(16-02): create three annotated visual specification documents
- 5cdf1d8: docs(16-02): add Stitch-to-Flutter workflow section to CLAUDE.md
