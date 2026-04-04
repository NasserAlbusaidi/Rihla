# Phase 30: Group Settle Up & Activity - Context

**Gathered:** 2026-04-04
**Status:** Ready for planning

<domain>
## Phase Boundary

Visual overhaul + functional fixes for the existing GroupSettleUpScreen and GroupActivityScreen. Both screens are already fully implemented with models, services, providers, and routes. This phase redesigns them to match v2.0 design system and fixes known functional bugs (balance sign flip, settlement history, activity logging gaps).

</domain>

<decisions>
## Implementation Decisions

### Settle-up screen design
- **D-01:** Replace custom header with ModuleHeader (dark gradient) for consistency with other v2.0 screens
- **D-02:** Replace 3-section layout (YOUR ACTIONS / WAITING FOR OTHERS / OTHERS SETTLING) with a tabbed view using AppTabBar — tabs: "You Owe" / "Owed to You" / "Between Others"
- **D-03:** Add a "History" tab showing completed/recorded settlements with dates, amounts, and participants
- **D-04:** Settlement tiles redesigned as card-style — rounded cards with avatar initials, prominent amount, collapsible per-event breakdown
- **D-05:** Record Settlement bottom sheet gets token polish — card-style input fields, consistent spacing, gradient CTA button. Same fields (amount + note), no new fields
- **D-06:** "All settled" empty state stays as-is — green checkmark circle, current copy is fine

### Activity feed design
- **D-07:** Replace custom header with ModuleHeader (dark gradient), same as settle-up
- **D-08:** Switch from flat list to date-grouped sections with section headers ("Today", "Yesterday", "Mar 28") — match the pattern from event-level ActivityFeedScreen
- **D-09:** Rich activity tiles — avatar/initials circle, actor name, description text, relative timestamp, type-specific icon (money for settlements, calendar for events, people for member actions)
- **D-10:** Add horizontal scrollable filter chips below header: All, Settlements, Events, Members
- **D-11:** Replace manual "Load more" button with infinite scroll (auto-load next page when scrolling near bottom)

### Functional fixes
- **D-12:** FIX: Balance sign flip bug — group-level balance shows user is owed X, but event-level shows user owes X. The group balance aggregation is inverting payer/recipient. Root cause investigation and fix required
- **D-13:** FIX: Settlement history — currently no way to view past/completed settlements. The History tab (D-03) addresses this
- **D-14:** FIX: Activity logging audit — some actions appear missing from the group activity feed. Audit all action types that should log (expense CRUD, settlement recording, event creation/deletion, member join/leave) and ensure each has a working logging call

### GroupDetail integration
- **D-15:** Keep existing CTA entry points — gradient "Settle Up" button and "View All" on activity section. Ensure they navigate correctly to redesigned screens
- **D-16:** Keep 5-item activity preview on GroupDetailScreen. Update tile rendering to match new rich tile design from D-09

### Claude's Discretion
- Exact spacing and padding within new card-style settlement tiles
- Skeleton/loading state design for tabbed settle-up view
- Filter chip visual styling (colors, selected state)
- Date section header typography and spacing
- Infinite scroll threshold distance

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Settle-up screens
- `lib/features/groups/screens/group_settle_up_screen.dart` — Current full implementation to redesign
- `lib/features/groups/widgets/group_settlement_summary.dart` — Summary card widget
- `lib/features/groups/widgets/group_settlement_tile.dart` — Current tile widget to redesign as cards
- `lib/features/groups/services/group_settlement_service.dart` — Settlement CRUD service
- `lib/features/ledger/providers/expense_provider.dart` — BalanceCalculator with optimal settlement algorithm

### Activity screens
- `lib/features/groups/screens/group_activity_screen.dart` — Current full implementation to redesign
- `lib/features/groups/widgets/group_activity_tile.dart` — Current tile widget to redesign as rich tiles
- `lib/features/groups/services/group_activity_service.dart` — Activity logging + pagination service
- `lib/features/groups/models/group_activity_log_model.dart` — Activity log model with 5 action types
- `lib/features/activity/screens/activity_feed_screen.dart` — Event-level feed with date-grouped pattern to replicate

### Balance calculation (bug investigation)
- `lib/features/groups/providers/group_balance_provider.dart` — Group balance aggregation (likely sign flip source)
- `lib/features/ledger/providers/expense_provider.dart` — BalanceCalculator class
- `lib/features/groups/screens/group_detail_screen.dart` — Where group-level balances display

### Shared widgets
- `lib/shared/widgets/module_header.dart` — ModuleHeader for both screens
- `lib/shared/widgets/app_tab_bar.dart` — AppTabBar for settle-up tabs
- `lib/shared/widgets/empty_state_view.dart` — Empty states
- `lib/core/theme/tokens/color_tokens.dart` — AppColorTokens
- `lib/core/theme/tokens/shadow_tokens.dart` — AppShadowTokens

### Navigation
- `lib/core/router/app_router.dart` — Route definitions for /group/:gid/settle-up and /group/:gid/activity

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `ModuleHeader` — dark gradient header, drop-in replacement for both custom headers
- `AppTabBar` — gradient pill tab bar, use for settle-up tabs (You Owe / Owed to You / Between Others / History)
- `EmptyStateView` — consistent empty states for each tab and activity feed
- `InitialsCircle` — avatar widget for activity tiles and settlement cards
- `GroupSettlementSummaryCard` — summary card at top of settle-up, keep and polish
- `ActivityHeroCard` / `ActivityEntryCard` — event-level widgets, reference for date-grouped pattern
- `SearchFilterBar` — has filter chip pattern, may be adaptable for activity type filters

### Established Patterns
- Section layout: card containers with `cardSurface` bg, `shadowRaised`, `borderRadius: 24` (Phase 26, 29)
- Staggered entrance animations: `.animate().fadeIn(delay: Nms).slideY(begin: 0.1)` (all recent phases)
- Fire-and-forget activity logging: `logGroupEvent()` returns void, errors logged not thrown (D-33)
- Client-side timestamps: ISO 8601 strings, not FieldValue.serverTimestamp()
- Cursor-based pagination: `fetchActivityPageRaw()` with DocumentSnapshot cursor

### Integration Points
- GroupDetailScreen → settle-up: via `/group/:gid/settle-up` route with optional `?memberId=` query param
- GroupDetailScreen → activity: via `/group/:gid/activity` route
- GroupDetailScreen activity preview: `groupActivityProvider(groupId)` stream (5 recent items)
- Settlement recording: `GroupSettlementService.addGroupSettlement()` + `GroupActivityService.logGroupEvent()`
- Balance data: `groupBalancesProvider(groupId)` → `GroupBalances` record with per-event breakdown

</code_context>

<specifics>
## Specific Ideas

- Balance sign flip bug: user sees "owed 4 OMR" at group level but "owes 4 OMR" in the event that sourced the transaction. Likely a sign convention mismatch between event-level and group-level balance aggregation
- Activity feed should feel like a timeline of the group's life — events created, money settled, members coming and going
- Settlement history tab gives visibility into what's been resolved, not just what's pending

</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope

</deferred>

---

*Phase: 30-group-settle-up-activity*
*Context gathered: 2026-04-04*
