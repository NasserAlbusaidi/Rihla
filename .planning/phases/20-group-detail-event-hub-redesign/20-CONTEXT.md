# Phase 20: Group Detail & Event Hub Redesign - Context

**Gathered:** 2026-03-30
**Status:** Ready for planning

<domain>
## Phase Boundary

Transform the group detail screen and event hub (CommandCenter) from functional but visually plain screens into information-dense, visually rich interfaces using the monochrome+teal design language. Group detail shows financial state at a glance via a stats grid, event cards with inline summaries, and member balances. Event hub shows module access via a 2x3 grid with live summaries. One ContainerTransform transition (group card → group detail).

This phase does NOT redesign module screens (Phase 21), add haptic feedback or texture overlays (Phase 22), or change any navigation structure (Phase 19 complete).

</domain>

<decisions>
## Implementation Decisions

### Event Card Design
- **D-01:** Event cards show amount + status line inline: personal balance ("You owe OMR 12.500") in errorText/successText, expense count ("· 3 expenses"), and date range. Uses the same color-coding as home dashboard balance hero (red/green/gray).
- **D-02:** Past events render at 60% opacity with the accent bar switching from teal (`AppColors.primary`) to gray (`AppColors.textMuted`). Same card layout, just visually receded. Upcoming/active events render at full color with teal accent bar.
- **D-03:** Event cards retain the left accent bar from the spec. All event types use teal (per Phase 16 D-80 — event-type color discrimination deferred).

### ContainerTransform Transition
- **D-04:** Single ContainerTransform transition only — group card on HomeScreen morphs into GroupDetailScreen. All other transitions remain as `_slideRightTransition`. Phase 22 handles broader M3 motion.
- **D-05:** Use Google's official `animations` package (`OpenContainer` widget) for the ContainerTransform implementation. Handles clipping, elevation, and material motion automatically. New dependency to add.
- **D-06:** The OpenContainer wraps the GroupCard in HomeScreen. The `openBuilder` returns GroupDetailScreen. GoRouter's `context.push('/group/$groupId')` must be reconciled with OpenContainer's navigation — research should investigate how OpenContainer coexists with GoRouter (it may need to bypass GoRouter for the transition and let GoRouter handle the route state).

### Group Detail Data Density
- **D-07:** Above the fold (visible without scrolling on ~390px): dark header with group name/avatar stack/invite code, 2x2 stats grid, and settle-up CTA button. Member balances and events scroll below.
- **D-08:** Stats grid shows 4 tiles: YOUR BALANCE (color-coded), GROUP TOTAL, ACTIVE MEMBERS, EVENTS (count). The spec's "DAYS LEFT" is replaced with event count — always available, always meaningful regardless of group state.
- **D-09:** Section ordering below the fold: Events → Member Balances → Recent Activity. Events come first (what's happening), then member balances (who owes what), then activity (recent changes). This reorders from the spec which had Members before Events.
- **D-10:** Settle-up CTA button: full-width teal button, 52dp height, shown when any balance is non-zero. Hidden when all settled.

### Event Hub Module Grid
- **D-11:** Modules with no data show description text in textMuted (e.g., "Track shared equipment"). Modules with data show live count + key metric summary. SmartModuleCard already supports this description/summary pattern.
- **D-12:** Live summary format per module:
  - Ledger: "N expenses · OMR X.XXX"
  - Gear: "N items · M unchecked"
  - Logistics: "N groups"
  - Vault: "N files"
  - Memories: "N photos"
  - Activity: "N entries"
- **D-13:** 2x3 grid layout in both loaded and empty states (per spec reconciliation). Modules are always visible — never hidden when empty.
- **D-14:** Expense hero card above the module grid showing total expenses with "+ Add Expense" chip button.

### Claude's Discretion
- How to reconcile OpenContainer with GoRouter navigation (may need custom transition page or navigation bypass)
- Whether the expense hero card in event hub uses the same BalanceHeroCard pattern from Phase 18 or a simplified version
- Exact skeleton composition for group detail and event hub loading states
- Activity strip widget layout — can reuse ActivityRow from Phase 18 home dashboard
- How to determine "past" vs "upcoming" events (date-based: endDate < now, or status-based)

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Design Specifications
- `.planning/design/group-detail-spec.md` — Full visual spec with token mappings, component hierarchy, spacing spec, all 4 screen states. PRIMARY VISUAL TARGET for group detail.
- `.planning/design/event-hub-spec.md` — Full visual spec for event hub with module grid layout, token mappings, all 4 screen states. PRIMARY VISUAL TARGET for event hub.

### Requirements
- `.planning/REQUIREMENTS.md` SCRN-01 — Group detail event cards with type-specific accents, inline financial summaries, past/upcoming distinction
- `.planning/REQUIREMENTS.md` SCRN-02 — Event hub with earthy palette and improved information density

### Prior Phase Context
- `.planning/phases/16-stitch-workflow-design-reference/16-CONTEXT.md` — Stitch-to-Flutter workflow, palette reconciliation rules, module accent color decisions
- `.planning/phases/18-home-dashboard-redesign/18-CONTEXT.md` — Balance hero pattern, group card design, activity strip, weekly spending card, bottom nav
- `.planning/phases/19-navigation-restructuring/19-CONTEXT.md` — Full GoRouter route tree, all screens take string IDs, context.push navigation

### Implementation References
- `lib/core/theme/tokens/color_tokens.dart` — AppColorTokens.light canonical palette
- `lib/shared/widgets/module_header.dart` — ModuleHeader with dark gradient, context.pop() back button
- `lib/shared/widgets/smart_module_card.dart` — SmartModuleCard with summary/description states
- `lib/features/home/widgets/` — BalanceHeroCard, GroupCard, ActivityRow, WeeklySpendingCard (Phase 18 patterns to reuse)
- `lib/core/router/app_router.dart` — Full GoRouter route tree with _slideRightTransition helper

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `SmartModuleCard` — Already supports description (empty) and summary (populated) display modes. Module accent colors defined in AppColorTokens.
- `ModuleHeader` — Dark gradient header with context.pop() back button. Used across all module screens.
- `BalanceHeroCard` — Phase 18 cross-group balance hero. Pattern reusable for group-level balance display in stats grid.
- `GroupCard` — Phase 18 enriched group card with personal balance. Will be wrapped in OpenContainer for ContainerTransform.
- `ActivityRow` — Phase 18 activity feed row widget. Reusable for group detail activity strip.
- `FadeInList`, `TapBounce`, `SkeletonLoader` — Phase 17 animation components. Apply to all new sections.
- `EmptyStateView` — Shared empty state with CTA. Used for group detail when no events exist.

### Established Patterns
- Provider lookup in screens: `ref.watch(groupDetailProvider(groupId))` + `ref.watch(eventDetailProvider(...))` — all screens use this pattern since Phase 19.
- Financial display: errorText for amounts owed, successText for amounts owed to you, textSecondary for settled/zero.
- CustomScrollView + Slivers: Phase 18 home dashboard pattern for smooth scrolling.

### Integration Points
- `lib/features/groups/screens/group_detail_screen.dart` (609 lines) — Primary file to redesign. Already takes `groupId` string, uses GoRouter.
- `lib/features/events/screens/event_command_center.dart` (144 lines) — Event hub to redesign. Takes `groupId`/`eventId` strings.
- `lib/features/events/widgets/event_module_list.dart` (336 lines) — Module grid widget. Receives `EventModules?` for visibility.
- HomeScreen GroupCard → needs OpenContainer wrapping for ContainerTransform.

</code_context>

<specifics>
## Specific Ideas

- Event cards: left accent bar (teal for active, gray for past) with personal balance inline — "You owe OMR 12.500 · 3 expenses"
- Past events at 60% opacity — visual recession without hiding content
- Stats grid 4th tile: event count instead of "days left" — universally meaningful
- Section order below fold: Events → Members → Activity (events are the primary content)
- Module summaries use count + key metric format: "3 expenses · OMR 45.500"

</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope

</deferred>

---

*Phase: 20-group-detail-event-hub-redesign*
*Context gathered: 2026-03-30*
