# Phase 21: Module Screens Redesign - Context

**Gathered:** 2026-03-30
**Status:** Ready for planning

<domain>
## Phase Boundary

Apply the new earthy design language to all six module screens (Ledger, Gear, Logistics, Vault, Memories, Activity), all form flows (create/join group, create event, add expense, settings), and onboarding/splash. Every module uses the unified template: dark gradient ModuleHeader → summary hero card → content list. All forms get earthy token reskin with warm input fields and terracotta buttons. The visual overhaul is complete across the entire app.

This phase does NOT add haptic feedback, texture overlays, M3 motion patterns, or animated balance counters (Phase 22). Does NOT change navigation structure (Phase 19 complete). Does NOT redesign home dashboard (Phase 18 complete) or group detail/event hub (Phase 20 complete).

</domain>

<decisions>
## Implementation Decisions

### Ledger Screen
- **D-01:** Expense cards show full detail: category icon (left), expense title + amount (line 1), payer name · date · participant count (line 2), balance status line (line 3). Three-line card.
- **D-02:** Balance line color-coded via text color only: green (`successText`) for "Owed to you", red (`errorText`) for "You owe", gray (`textSecondary`) for "Settled". Card background stays `surface` (warm white). No accent bars or tinted backgrounds.
- **D-03:** Balance summary hero card above the expense list: YOUR BALANCE (color-coded) + EVENT TOTAL on the first row, expense count + settlement count on the second row, two CTA buttons [+ Add Expense] [Settle Up] on the third row.
- **D-04:** Single scroll layout — no tabs. Hero → mixed chronological timeline of expenses and settlements. Removes current Spending/Balances tab bar.
- **D-05:** Settlements appear in the timeline alongside expenses with distinct visual treatment: checkmark icon, green accent, "Payer → Recipient" format.
- **D-06:** Add Expense button lives inside the hero card (inline CTA), not as a floating action button.
- **D-07:** Tap expense card opens bottom sheet for editing (existing EditExpenseSheet pattern). No swipe actions, no long-press menus. Tap-to-edit only.

### Unified Module Layout Template
- **D-08:** All 6 modules follow the same structure: ModuleHeader (dark gradient) → Summary Hero Card (module stats + primary CTA) → Section overline → Content list/grid. Consistent rhythm across the app.
- **D-09:** All ModuleHeaders use the dark gradient variant (#2C1A0E → #3D2B1E) with white title text. No per-module accent headers (Phase 16 D-80 — per-module color discrimination deferred).
- **D-10:** Standard content card: 16dp padding all sides, 24dp border radius, cardShadow (raised), `AppColors.surface` background, no border.

### Summary Hero Cards Per Module
- **D-11:** Ledger hero: Balance + Total + [Add Expense] [Settle Up]
- **D-12:** Gear hero: Packed X/Y + Priority N items + [Add Item]
- **D-13:** Logistics hero: N groups · M members + unassigned count + [Create Group]
- **D-14:** Vault hero: N files + total size + [Upload]
- **D-15:** Memories hero: N photos + date range + [Add Photo]
- **D-16:** Activity hero: N entries + last update (no CTA — read-only feed)

### Empty States
- **D-17:** Icon + warm gradient circle style: large icon (48dp) centered in a 72dp circle with module accent color gradient, title in dark brown, contextual subtitle, single CTA button.
- **D-18:** Module accent colors for empty state circles: Ledger = terracotta (#CC6B49), Gear = olive (#7A8C5E), Logistics = dusty teal (#5B7B8C), Vault = warm bronze (#8B7355), Memories = desert sand (#9B7A5C), Activity = caramel (#A67C5B). Uses Phase 15 palette.
- **D-19:** Module-specific CTA text: "Add Expense" (Ledger), "Add Gear Item" (Gear), "Create Sub-group" (Logistics), "Upload Document" (Vault), "Add Photo" (Memories), no CTA for Activity ("No activity yet" text only).

### Vault Document Cards
- **D-20:** File type icon card: 52dp icon container (warm bronze accent background) with file type icon (PDF, image, doc), title on line 1, file size · upload date · uploader on line 2. Standard 16dp/24r card style.

### Activity Timeline
- **D-21:** Date-grouped flat list: entries grouped under sticky section headers ("TODAY", "YESTERDAY", "Mar 28"). Each entry card: avatar circle + action text + relative time on line 1, detail context on line 2. No vertical connector line.

### Logistics Sub-group Cards
- **D-22:** Sub-group card with member chips + capacity bar: group name + icon on line 1, capacity progress bar on line 2, member name chips below. Dusty teal accent for card top border.
- **D-23:** Logistics drops tab bar (All/By Group) in favor of the unified single-scroll template: hero card → sub-group card list.

### Memories Layout
- **D-24:** Memories is the exception to card-list template: uses a 3-column photo grid with 8dp gap, 8dp border radius thumbnails. Hero card above the grid with photo count + date range + [Add Photo]. Tap opens full-screen viewer.

### Form Flow Redesign
- **D-25:** Reskin + polish depth: apply earthy tokens to all form fields, buttons, and containers. Keep existing flow logic and step structure unchanged. Add warm card containers around form sections.
- **D-26:** Shared InputDecorationTheme in app_theme.dart: fillColor #F5EDE1 (sand light), border #E5D5C0 (warm gray), focusedBorder #CC6B49 (terracotta), labelStyle #2C1A0E (dark brown), hintStyle #A89888 (sand gray), errorBorder #EF4444 (red), border radius 12dp.
- **D-27:** Add Expense step indicator: three terracotta dots — filled for current, outlined for upcoming, checked for complete. Consistent with onboarding dot pattern.
- **D-28:** Settings screen uses section cards (iOS grouped table style): Profile card, Preferences card, About card. Each card has warm surface background, 24dp radius, ListTile items inside.

### Onboarding & Splash
- **D-29:** Onboarding: keep 3-page structure. Each page gets large icon in warm gradient circle (matching empty state style), title in dark brown, subtitle in warm gray, terracotta dot indicators. Final page CTA in terracotta.
- **D-30:** Splash screen: warm sand (#F2E8D6) background, app logo/name in dark brown centered. Minimal, clean entry point.

### Claude's Discretion
- Exact hero card layout composition (2-column stats vs stacked)
- Skeleton loading variants for modules that currently lack them (Ledger, Memories) — use Phase 17 primitives
- How to implement date-grouped sections in Activity (SliverStickyHeader or custom)
- Gear screen hero card adaptation (progress bar style, priority badge design)
- Whether SearchFilterBar is retained on Gear and Vault screens alongside the new hero card
- Animation choices for card entrance (FadeInList stagger delays, grid fade-in for Memories)
- Photo grid implementation details for Memories (GridView.builder vs SliverGrid)

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Design Specifications
- `.planning/design/group-detail-spec.md` — Visual spec with token mappings. Reference for card style, spacing, and dark header patterns established in Phase 20.
- `.planning/design/event-hub-spec.md` — Module grid layout. Reference for module card summary patterns.
- `.planning/design/home-screen-spec.md` — Dashboard layout. Reference for hero card pattern, activity strip.

### Requirements
- `.planning/REQUIREMENTS.md` SCRN-03 — Ledger screen card-style expense rows with color-coded balance
- `.planning/REQUIREMENTS.md` SCRN-04 — Gear, Logistics, Vault, Memories, Activity redesigned with new tokens
- `.planning/REQUIREMENTS.md` SCRN-05 — Form flows use new design language
- `.planning/REQUIREMENTS.md` SCRN-06 — Onboarding and splash with warm earthy aesthetics

### Prior Phase Context
- `.planning/phases/15-design-token-system/15-CONTEXT.md` — Warm earthy palette, module accent colors, text hierarchy, shadow tokens
- `.planning/phases/16-stitch-workflow-design-reference/16-CONTEXT.md` — Stitch-to-Flutter workflow, palette reconciliation, WCAG constraints
- `.planning/phases/17-animation-library-loading-states/17-CONTEXT.md` — Animation library (FadeInList, TapBounce, StaggeredGrid), skeleton primitives, shimmer theming
- `.planning/phases/18-home-dashboard-redesign/18-CONTEXT.md` — Balance hero pattern, GroupCard, activity strip, bottom nav tokens
- `.planning/phases/20-group-detail-event-hub-redesign/20-CONTEXT.md` — Event card design, stats grid, module grid, ContainerTransform, monochrome+teal language

### Implementation References
- `lib/core/theme/tokens/color_tokens.dart` — AppColorTokens.light canonical palette (primary teal, module accents, semantic colors)
- `lib/core/theme/tokens/spacing_tokens.dart` — AppSpacingTokens (4dp–32dp scale, border radius scale)
- `lib/core/theme/tokens/shadow_tokens.dart` — AppShadowTokens (cardShadow, cardShadowLarge)
- `lib/core/theme/app_theme.dart` — ThemeData, InputDecorationTheme target for D-26
- `lib/shared/widgets/module_header.dart` — ModuleHeader (dark/light variants, back button)
- `lib/shared/widgets/empty_state_view.dart` — EmptyStateView (icon + title + CTA)
- `lib/shared/widgets/skeleton_loader.dart` — SkeletonLoader factories (cardList, documentList, groupList, expenseList, gearList)
- `lib/shared/widgets/search_filter_bar.dart` — SearchFilterBar (used in Gear, Vault)
- `lib/shared/animations/` — FadeInList, TapBounce, StaggeredGrid
- `lib/features/ledger/screens/ledger_screen.dart` — Current Ledger (417 LOC, tab bar, no hero)
- `lib/features/gear/screens/gear_screen.dart` — Current Gear (789 LOC, progress hero, card list)
- `lib/features/logistics/screens/logistics_screen.dart` — Current Logistics (696 LOC, tab bar)
- `lib/features/vault/screens/vault_screen.dart` — Current Vault (485 LOC, card list)
- `lib/features/memories/screens/memories_screen.dart` — Current Memories (475 LOC, custom header)
- `lib/features/activity/screens/activity_feed_screen.dart` — Current Activity (79 LOC, timeline cards)
- `lib/features/ledger/screens/add_expense_screen.dart` — Add Expense 3-step flow (572 LOC)
- `lib/features/groups/screens/create_group_screen.dart` — Create Group (313 LOC)
- `lib/features/groups/screens/join_group_screen.dart` — Join Group (195 LOC)
- `lib/features/events/screens/create_event_screen.dart` — Create Event (519 LOC)
- `lib/features/settings/screens/settings_screen.dart` — Settings (702 LOC)
- `lib/features/onboarding/screens/onboarding_screen.dart` — Onboarding 3-page (383 LOC)

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- **ModuleHeader**: Dark gradient header with title, subtitle, actions, bottom widget. All modules except Memories already use it.
- **EmptyStateView**: Icon + title + message + optional CTA. Needs accent color circle upgrade for D-17/D-18.
- **SkeletonLoader**: Content-aware factories. Gear, Logistics, Vault already have variants. Ledger and Memories need new variants.
- **SearchFilterBar**: Used in Gear and Vault for filtering content lists. Keep alongside hero cards.
- **FadeInList / TapBounce / StaggeredGrid**: Animation library from Phase 17. All modules already use flutter_animate with fadeIn + slideY + stagger.
- **BalanceHeroCard pattern**: From Phase 18 home dashboard. Reusable pattern for Ledger's hero card.
- **EditExpenseSheet**: Existing bottom sheet for editing expenses. Keep as-is, just reskin.

### Established Patterns
- **All 6 modules use 100% AppColors tokens** — no hardcoded colors to migrate
- **Card pattern**: 24dp border radius, surface background, cardShadow elevation is the standard
- **Animation pattern**: flutter_animate with .fadeIn() + .slideY() + staggered delays
- **Provider pattern**: StreamProvider/FutureProvider with AsyncValue for loading/error/data states
- **InputDecoration**: Currently inconsistent across forms — D-26 standardizes this

### Integration Points
- **app_theme.dart**: InputDecorationTheme must be added/updated for D-26
- **empty_state_view.dart**: Needs module accent color parameter for D-17/D-18
- **ModuleHeader**: Memories screen needs migration from custom header to ModuleHeader
- **Ledger tab bar removal**: Current AppTabBar usage in Ledger must be replaced with single scroll
- **Logistics tab bar removal**: Current AppTabBar usage in Logistics must be replaced with single scroll
- **Onboarding screen**: Needs dot indicator widget (terracotta dots) — may extract as shared widget

</code_context>

<specifics>
## Specific Ideas

- Expense cards use the same green/red/gray financial color convention as the Phase 20 event cards and Phase 18 balance hero — universal financial status language across the app
- Memories is the one module that breaks the card-list template — photo grid is more natural for visual content
- Settings adopts iOS grouped-table card sections — familiar pattern for mobile users
- Add Expense step indicator uses the same dot pattern as onboarding — visual language reuse

</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope

</deferred>

---

*Phase: 21-module-screens-redesign*
*Context gathered: 2026-03-30*
