# Phase 18: Home Dashboard Redesign - Context

**Gathered:** 2026-03-29
**Status:** Ready for planning

<domain>
## Phase Boundary

Transform the home screen from a simple group list into a single-scroll dashboard that answers "what do I owe across all groups?" at a glance and enables 2-tap access to any module screen. The dashboard includes a balance hero card, quick-action tray, enriched group cards, cross-group activity strip, weekly spending summary, and a bottom navigation shell with placeholder tabs.

This phase builds on the design spec from Phase 16, the token system from Phase 15, and the animation/skeleton components from Phase 17. It does NOT restructure GoRouter routing (Phase 19) or redesign group detail/event hub screens (Phase 20).

</domain>

<decisions>
## Implementation Decisions

### Balance Hero
- **D-01:** Prominent hero card at the top of the dashboard (below title, above quick actions) showing the user's net cross-group balance. Color-coded: red for "You owe OMR X across N groups", green for "You are owed OMR X", gray for "All settled up"
- **D-02:** When all groups are settled, hero shows gray-toned card with checkmark icon and "All settled up" text with "OMR 0.000" and group count. Card remains visible (does not hide)
- **D-03:** Balance hero requires a new cross-group balance aggregation provider — sums the user's personal net balance across all groups. Uses `groupBalancesProvider` per-group results aggregated into a single net number

### Quick-Action Tray
- **D-04:** Horizontal row of 4 icon buttons below the balance hero, above the group list: Add Expense, Settle Up, Invite, Activity
- **D-05:** Context-dependent actions (Add Expense, Settle Up) open a group picker bottom sheet listing the user's groups. User picks a group, then routes to the relevant flow for that group's active event
- **D-06:** Invite opens the existing invite code flow. Activity scrolls to or navigates to the activity section
- **D-07:** Quick-action tray must be visible without scrolling on standard phones (~390px width)

### Group Cards
- **D-08:** Each GroupCard shows the user's personal net balance for that group (not total group spending). "You owe OMR X" in errorText, "You are owed OMR X" in successText, or "Settled" in textSecondary
- **D-09:** GroupCard keeps existing layout (name + member count badge) but replaces `totalSpent` display with personal balance line

### Bottom Navigation
- **D-10:** Phase 18 adds the bottom navigation bar visually with Groups / Activity / Chats / Profile tabs. Groups tab is active with the dashboard content
- **D-11:** Other tabs (Activity, Chats, Profile) show placeholder screens ("Coming soon") — Phase 19 wires real GoRouter routes
- **D-12:** Bottom nav tokens from Phase 16 gap list must be added to AppColorTokens: `bottomNavBackground`, `bottomNavActiveIcon`, `bottomNavInactiveIcon`

### Activity Strip
- **D-13:** Cross-group aggregate activity feed showing the 5 most recent entries from all groups, merged chronologically
- **D-14:** Each row shows: avatar circle, member name + action description, group name tag, relative timestamp (e.g., "2h ago")
- **D-15:** "RECENT ACTIVITY" section overline in textMuted (decorative only, per WCAG rules from Phase 16)

### Weekly Spending Card
- **D-16:** Weekly spending summary card with real data from Firestore expenses aggregated by day. Teal bar chart showing daily spending for the current week
- **D-17:** Card sits below the activity strip at the bottom of the scroll. Uses AppColors.surface background and AppColors.primary for chart bars

### Screen States
- **D-18:** Loading state uses SkeletonLoader.dashboardHero() for the hero area and SkeletonLoader.groupList() for the group cards (from Phase 17)
- **D-19:** Empty state uses EmptyStateView with CTA "Create your first group" — per home-screen-spec.md empty state design
- **D-20:** Error state shows OfflineBanner + EmptyStateView in error configuration with "Retry" and "View Offline Data" CTAs — per home-screen-spec.md error state design

### Layout & Performance
- **D-21:** Dashboard uses CustomScrollView + SliverList.builder for smooth 60fps scrolling (per STATE.md risk note)
- **D-22:** FadeInList from Phase 17 wraps group cards for staggered entrance animation
- **D-23:** TapBounce from Phase 17 wraps all tappable cards and quick-action buttons

### Token Gaps to Close
- **D-24:** Add `offlineBannerBackground: Color(0xFFF59E0B)` to AppColorTokens (Phase 16 structural gap)
- **D-25:** Add `bottomNavBackground`, `bottomNavActiveIcon`, `bottomNavInactiveIcon` tokens to AppColorTokens

### Claude's Discretion
- Chart rendering approach for weekly spending (custom paint, fl_chart package, or simple Container bars)
- Cross-group balance aggregation provider implementation strategy
- Exact skeleton composition for the balance hero section
- Activity row widget internal layout details
- Whether to use SliverAppBar for the title or keep it in a fixed header

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Design Specification
- `.planning/design/home-screen-spec.md` — Full visual spec with 4 screen states, token mappings, component hierarchy, spacing spec, and interaction notes. THIS IS THE PRIMARY VISUAL TARGET.

### Requirements
- `.planning/REQUIREMENTS.md` NAV-01 — Single-scroll dashboard with balance hero, group cards, quick-action tray, and activity strip
- `.planning/REQUIREMENTS.md` NAV-02 — Net cross-group balance color-coded on home screen without tapping
- `.planning/REQUIREMENTS.md` NAV-04 — Any module screen reachable within 2 taps from home
- `.planning/REQUIREMENTS.md` NAV-06 — Empty screens show contextual illustrations with CTA

### Phase Dependencies
- `.planning/phases/15-design-token-system/15-CONTEXT.md` — Token architecture, palette mapping, AppColors facade strategy
- `.planning/phases/16-stitch-workflow-design-reference/16-CONTEXT.md` — Stitch workflow decisions, bottom nav tabs, module accent colors
- `.planning/phases/17-animation-library-loading-states/17-CONTEXT.md` — Animation components and skeleton factories available for use

### Existing Code (migration targets)
- `lib/features/home/screens/home_screen.dart` — Current home screen (204 lines, basic group list). PRIMARY FILE BEING REWRITTEN
- `lib/features/groups/widgets/group_card.dart` — Current GroupCard (shows totalSpent, needs personal balance)
- `lib/features/groups/providers/group_balance_provider.dart` — groupBalancesProvider per-group. Needs cross-group aggregation
- `lib/features/groups/providers/group_provider.dart` — userGroupsProvider (existing, keep)

### Token System
- `lib/core/theme/tokens/color_tokens.dart` — AppColorTokens (add offline banner + bottom nav tokens)
- `lib/core/theme/app_theme.dart` — AppColors facade (spacing, radii, shadows)

### Shared Components (ready to use)
- `lib/shared/widgets/skeleton_loader.dart` — SkeletonLoader.dashboardHero(), .groupList(), .generic()
- `lib/shared/widgets/skeleton_primitives.dart` — SkeletonCircle, SkeletonBar, SkeletonBlock, SkeletonRow, SkeletonCard
- `lib/shared/animations/tap_bounce.dart` — TapBounce (120ms, 0.97, easeInOut)
- `lib/shared/animations/fade_in_list.dart` — FadeInList (350ms, 50ms stagger, easeOutCubic)
- `lib/shared/widgets/empty_state_view.dart` — EmptyStateView with optional CTA
- `lib/shared/widgets/offline_banner.dart` — OfflineBanner (connectivity indicator)

### Roadmap
- `.planning/ROADMAP.md` Phase 18 — Success criteria defining balance visibility, 2-tap reach, empty state, 60fps, quick-action visibility

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `GroupCard` widget — already shows group name + member count. Needs enrichment with personal balance
- `EmptyStateView` — used in current home screen for empty state. Reuse with updated copy
- `OfflineBanner` — already in home screen. Keep as-is, add amber token
- `SkeletonLoader.groupList()` — already called in current home screen loading state
- `GroupActivityService.watchRecentActivity(groupId)` — per-group activity streams, need cross-group aggregation
- `groupBalancesProvider(groupId)` — per-group balance data, need cross-group sum
- `AppFormatters.formatCurrency()` — currency formatting utility

### Established Patterns
- `AsyncValue.when(data:, loading:, error:)` — standard Riverpod pattern for all data states
- `AppColors.*` static facade — 895 references, still valid. New code can use either `AppColors.*` or `context.colors.*`
- `AppPageRoute` (slide-right) and `AppBottomSheetRoute` (slide-up) — use for navigation transitions
- `HomeKeys.*` — semantic keys for home screen widgets (Phase 14)
- `RefreshIndicator` with `ref.invalidate()` — pull-to-refresh pattern in current home screen

### Integration Points
- GoRouter `/home` route — home screen is already a GoRouter route. Bottom nav shell wraps this
- `userGroupsProvider` — existing stream provider for user's groups. Dashboard watches this
- Navigation: group card tap → `context.push('/group/${group.id}')` — existing pattern, keep
- Bottom sheet pattern via `showModalBottomSheet` — already used for FAB menu. Reuse for quick-action group picker

</code_context>

<specifics>
## Specific Ideas

- Balance hero is the core product question — "what do I owe?" answered at a glance without any taps
- Quick-action group picker bottom sheet follows the existing FAB bottom sheet pattern
- Cross-group activity feed merges per-group activity streams chronologically
- Weekly spending card uses real Firestore data, not placeholder
- Bottom nav is visual-only in Phase 18 — placeholder screens for non-Groups tabs

</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope

</deferred>

---

*Phase: 18-home-dashboard-redesign*
*Context gathered: 2026-03-29*
