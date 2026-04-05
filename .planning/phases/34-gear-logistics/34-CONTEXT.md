# Phase 34: Gear & Logistics - Context

**Gathered:** 2026-04-05
**Status:** Ready for planning

<domain>
## Phase Boundary

Visual refresh of GearScreen and LogisticsScreen to earthy design language. Both screens are fully built and production-ready. This phase updates styling to v2.x AppColorTokens and ensures consistency with the hub screen patterns established in Phases 28-33.

</domain>

<decisions>
## Implementation Decisions

### Gear Screen
- Dark ModuleHeader ("Gear" + event name subtitle) — if not already present
- Refresh gear item cards with earthy color tokens
- SkeletonLoader loading states (replace any CircularProgressIndicator)
- Keep existing add/claim/filter functionality unchanged

### Logistics Screen
- Dark ModuleHeader ("Logistics" + event name subtitle) — if not already present
- Refresh sub-group cards with earthy tokens
- SkeletonLoader loading states
- Keep existing create/manage sub-group functionality unchanged

### Claude's Discretion
- All implementation details — this is a token refresh following the established Phase 28-33 pattern

</decisions>

<code_context>
## Existing Code Insights

### Established Pattern (Phases 28-33)
- Dark ModuleHeader for all module screens
- AppColorTokens for all colors
- SkeletonLoader for loading states (no CircularProgressIndicator as full-page loading)
- Staggered fade+slide entrance animations
- Card-section layout

</code_context>

<specifics>
## Specific Ideas

No specific requirements — follow the established visual refresh pattern from prior phases.

</specifics>

<deferred>
## Deferred Ideas

None

</deferred>
