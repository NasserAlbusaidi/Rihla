# Phase 28: Group Detail - Context

**Gathered:** 2026-04-02
**Status:** Ready for planning

<domain>
## Phase Boundary

Visual refresh and provider cleanup of the existing GroupDetailScreen (built in Phase 20). Same layout structure and data model — improved spacing, typography, consistency with earthy design language, micro-interactions, and provider efficiency. Invite code section removed (deferred to Phase 29 group settings).

</domain>

<decisions>
## Implementation Decisions

### Redesign Scope
- **D-01:** Visual refresh + provider cleanup. No layout restructure or functional additions.
- **D-02:** Touch widgets, spacing, styling, animations, and refactor providers for efficiency (unnecessary rebuilds, missing caching).
- **D-03:** All sections get the earthy design language polish pass — spacing, density, consistency, micro-interactions.

### Section Layout & Hierarchy
- **D-04:** Keep current section order: Header → Stats Grid → Settle-Up CTA (conditional) → Events → Members & Balances → Activity.
- **D-05:** Remove invite code section from this screen. Invite code display moves to Phase 29 (Group Management/Settings).
- **D-06:** Stats grid stays as 2x2 layout: YOUR BALANCE (color-coded), GROUP TOTAL, ACTIVE MEMBERS, EVENTS. Visual refresh only.

### Event Card Presentation
- **D-07:** Keep type-specific card design from Phase 20. Polish spacing, shadows, typography.
- **D-08:** Add staggered fade-in entrance animations on event cards using FadeInList pattern (already used elsewhere in the app via flutter_animate).

### Balance & Member Display
- **D-09:** Keep accordion pattern for member balance cards (tap to expand per-event breakdown). Visual refresh on card styling, colors, typography.
- **D-10:** Settle-up CTA stays conditional — only shows when user has non-zero balance.

### Loading & Error States
- **D-11:** Skeleton loading on initial load (existing pattern). Add pull-to-refresh to force re-fetch from Firestore.
- **D-12:** Inline error state with retry button when group data fails to load. Keep screen structure visible — don't replace with full-screen error.

### Header Design
- **D-13:** Keep dark gradient ModuleHeader with group name and creation date. Polish typography, spacing, and ensure grain texture is present.

### FAB & Navigation
- **D-14:** Keep FloatingActionButton as primary "Create Event" entry point. Visual refresh on FAB styling.
- **D-15:** Navigation transitions to sub-screens: Claude's discretion. Evaluate whether OpenContainer (card → detail) or slide-right is more appropriate per navigation type.

### Claude's Discretion
- Navigation transition type per sub-screen (D-15) — Claude evaluates OpenContainer vs slide-right based on context
- Specific provider refactoring decisions (which providers to optimize, caching strategy)
- Exact spacing/density values within the earthy design token system

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Design System
- `lib/core/theme/tokens/color_tokens.dart` — AppColorTokens.light palette (all colors must come from here)
- `lib/core/theme/tokens/spacing_tokens.dart` — AppSpacingTokens.standard spacing scale
- `lib/core/theme/tokens/shadow_tokens.dart` — AppShadowTokens elevation system
- `lib/core/theme/app_theme.dart` — Theme configuration, spacing constants, border radii

### Group Feature
- `lib/features/groups/screens/group_detail_screen.dart` — Current screen to refresh (Phase 20 implementation)
- `lib/features/groups/providers/group_provider.dart` — Group providers (groupDetailProvider, groupMembersProvider, userGroupsProvider)
- `lib/features/groups/providers/group_balance_provider.dart` — Balance aggregation (groupBalancesProvider, groupSettlementsProvider, groupActivityProvider)
- `lib/features/groups/widgets/group_stats_grid.dart` — 2x2 stats grid widget
- `lib/features/groups/widgets/group_member_balance_card.dart` — Accordion balance cards
- `lib/features/groups/widgets/group_activity_tile.dart` — Activity entry display
- `lib/features/groups/widgets/invite_code_display.dart` — Widget being removed from this screen (D-05)

### Shared Widgets
- `lib/shared/widgets/module_header.dart` — Dark/light gradient header
- `lib/shared/widgets/skeleton_loader.dart` — Loading skeleton patterns
- `lib/shared/widgets/empty_state_view.dart` — Empty state component

### Routing
- `lib/core/router/app_router.dart` — GoRoute definition for /group/:gid and nested routes

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `GroupStatsGrid` widget — 2x2 stats grid, needs visual refresh but structure is solid
- `GroupMemberBalanceCard` — accordion expand/collapse with per-event breakdown
- `GroupActivityTile` — activity entry display
- `ModuleHeader` — dark gradient header with SafeArea and back button
- `SkeletonLoader` — eventCard and groupList skeleton variants
- `EmptyStateView` — consistent empty states with optional CTA
- `FadeInList` pattern from flutter_animate — staggered entrance animations used in other screens

### Established Patterns
- Riverpod `Provider.family` / `StreamProvider.family` for parameterized data fetching
- `groupBalancesProvider` aggregates across events using BalanceCalculator (complex, well-tested — don't touch logic)
- `ConsumerStatefulWidget` for screens with local UI state (accordion expansion)
- AppColorTokens for all colors, AppSpacingTokens for spacing — CI-enforced

### Integration Points
- GroupDetailScreen receives `groupId` from GoRouter path parameter
- Data flows: Firestore streams → providers → widget tree
- FAB navigates to `/group/$groupId/create-event` via GoRouter
- Settle-up CTA navigates to `/group/$groupId/settle-up`
- Events section cards navigate to `/group/$groupId/event/$eventId`
- Activity "See all" navigates to `/group/$groupId/activity`

</code_context>

<specifics>
## Specific Ideas

- Staggered fade-in on event cards should use existing FadeInList pattern for consistency
- Pull-to-refresh should trigger Firestore re-fetch, not just local cache read
- Provider cleanup should focus on eliminating unnecessary rebuilds (e.g., if balance provider causes full screen rebuild when only one member's balance changes)

</specifics>

<deferred>
## Deferred Ideas

- **Invite code display** — Moves to Phase 29 (Group Management/Settings screen) per D-05
- No other scope creep during discussion

</deferred>

---

*Phase: 28-group-detail*
*Context gathered: 2026-04-02*
