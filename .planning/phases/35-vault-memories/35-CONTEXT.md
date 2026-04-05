# Phase 35: Vault & Memories - Context

**Gathered:** 2026-04-05
**Status:** Ready for planning

<domain>
## Phase Boundary

Visual refresh of VaultScreen and MemoriesScreen to earthy design language. Both screens are fully built and production-ready. This phase updates styling to v2.x AppColorTokens and ensures consistency with the hub screen patterns established in Phases 28-34.

</domain>

<decisions>
## Implementation Decisions

### Vault Screen
- Dark ModuleHeader ("Vault" / "Documents" + event name subtitle) — if not already present
- Refresh document cards with earthy color tokens
- SkeletonLoader loading states (replace any CircularProgressIndicator)
- Keep existing upload/view/delete functionality unchanged

### Memories Screen
- Dark ModuleHeader ("Memories" + event name subtitle) — if not already present
- Refresh photo grid/timeline with earthy tokens
- SkeletonLoader loading states
- Keep existing upload/view functionality unchanged

### Claude's Discretion
- All implementation details — this is a token refresh following the established Phase 28-34 pattern

</decisions>

<code_context>
## Existing Code Insights

### Established Pattern (Phases 28-34)
- Dark ModuleHeader for all module screens
- AppColorTokens for all colors
- SkeletonLoader for loading states
- Staggered fade+slide entrance animations

</code_context>

<specifics>
## Specific Ideas

No specific requirements — follow the established visual refresh pattern from prior phases.

</specifics>

<deferred>
## Deferred Ideas

None

</deferred>
