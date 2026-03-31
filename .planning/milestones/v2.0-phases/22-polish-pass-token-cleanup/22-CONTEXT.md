# Phase 22: Polish Pass & Token Cleanup - Context

**Gathered:** 2026-03-31
**Status:** Ready for planning

<domain>
## Phase Boundary

Micro-interactions, motion, texture, and animated feedback bring the app to a premium feel. Haptic feedback on primary write actions, M3 motion patterns for key screen transitions, animated balance counters on home and ledger, paper grain texture on hero cards/scaffold/headers. AppColors facade is deleted and all 1,351 references across 81 files are migrated to AppColorTokens / context.colors.

This phase does NOT add new features, change navigation structure, or redesign screens (all complete in Phases 18-21). Does NOT add dark mode (deferred). Does NOT change animation timings established in Phase 17 (350ms fade, 120ms bounce, 400ms stagger).

</domain>

<decisions>
## Implementation Decisions

### Haptic Feedback
- **D-01:** Scope limited to the 3 required success criteria actions only: add expense, record settlement, join group. HapticService already used in 22 files for other interactions (tab switches, form inputs, etc.) — no additional actions needed
- **D-02:** Use `HapticService.success()` pattern (double medium impact with 100ms gap) for all 3 actions. Satisfying "done" feel
- **D-03:** Fire haptic immediately on button tap, not after async Firestore write completes. Responsive feedback, user connects haptic to their action

### M3 Motion Transitions
- **D-04:** Key transitions only (~8-10 routes changed). ContainerTransform for card→detail, SharedAxis for form steps, keep slide-right for deep navigation
- **D-05:** Full ContainerTransform (OpenContainer) for card→detail transitions: GroupCard→GroupDetailScreen (already done), EventCard→EventCommandCenter, SmartModuleCard→module screens. Card physically expands to fill screen
- **D-06:** SharedAxis vertical for multi-step form flows (create group, create event). Content slides up on advance, down on back. Matches Phase 17's calm motion personality
- **D-07:** FadeThrough for bottom nav tab switches. BottomNavShell currently uses IndexedStack — wrap with FadeThroughTransition for M3 top-level destination standard
- **D-08:** Keep current slide-right (`_slideRightTransition`) for deep navigation routes (ledger→add expense, event→settings, etc.)

### Texture & Grain Overlays
- **D-09:** Paper grain noise overlay — subtle tileable PNG/SVG noise at ~3-5% opacity. Handmade paper feel. Single small tileable asset
- **D-10:** Apply grain to: summary hero cards (all 6 modules + home balance hero) AND scaffold background. Content list cards stay clean/flat. Two-tier visual hierarchy
- **D-11:** Dark gradient ModuleHeaders also get grain at ~2% opacity. Adds leather/canvas depth without competing with white title text
- **D-12:** No frosted glass, no blur effects. Warm and tactile, not digital/cold

### Animated Balance Counters
- **D-13:** Smooth number lerp via TweenAnimationBuilder. Value interpolates frame-by-frame with OMR formatting. 600ms easeOutCubic. Proven pattern already in 3 hero widgets
- **D-14:** Add animated counters to: BalanceHeroCard (home dashboard) and LedgerHeroCard (ledger screen). These are the two screens called out in success criteria. Existing heroes (event_spending_hero, group_balance_hero, event_expense_hero) already covered
- **D-15:** Color also animates when balance sign changes — ColorTween green↔red alongside number Tween when balance crosses zero. Polished financial state change feedback

### AppColors Deletion
- **D-16:** Claude's Discretion — migration strategy for 1,351 AppColors references across 81 files. Researcher and planner determine the optimal bulk migration approach (context.colors.x vs AppColorTokens.light.x static vs other)
- **D-17:** End state: `AppColors` class deleted, zero references remaining. Success criteria #5

### Claude's Discretion
- Grain texture asset format (PNG vs SVG), tile size, and exact opacity values within the 2-5% range
- AppColors→token migration strategy (bulk find-replace approach, file ordering, test impact mitigation)
- ContainerTransform duration and easing (use M3 defaults unless they conflict with Phase 17 motion personality)
- Whether to extract animated counter into a shared widget or keep inline TweenAnimationBuilder per screen

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Design Tokens & Color System
- `lib/core/theme/tokens/color_tokens.dart` — AppColorTokens.light canonical palette. All color migrations target these tokens
- `lib/core/theme/app_theme.dart` — ThemeData builder, AppColors facade (to be deleted), spacing/shadow constants

### Animation Library
- `lib/shared/animations/fade_in_list.dart` — FadeInList widget (Phase 17)
- `lib/shared/animations/staggered_grid.dart` — StaggeredGrid widget (Phase 17)
- `lib/shared/animations/tap_bounce.dart` — TapBounce widget (Phase 17)
- `lib/shared/animations/animations.dart` — Barrel export

### Haptic Service
- `lib/core/services/haptic_service.dart` — HapticService with 5 patterns (lightClick, success, warning, selection, medium)

### Motion & Transitions
- `lib/core/router/app_router.dart` — GoRouter configuration, `_slideRightTransition`, all route definitions
- `lib/features/home/screens/home_screen.dart` — Existing OpenContainer usage on GroupCard (reference implementation)
- `lib/features/home/widgets/bottom_nav_shell.dart` — BottomNavShell with IndexedStack (needs FadeThrough wrap)

### Animated Counters (existing implementations)
- `lib/features/events/screens/event_expense_hero.dart` — TweenAnimationBuilder for animated amounts
- `lib/features/groups/widgets/group_balance_hero.dart` — TweenAnimationBuilder for balance display
- `lib/features/events/widgets/event_spending_hero.dart` — TweenAnimationBuilder for spending totals

### Target Screens for Counter Addition
- `lib/features/home/widgets/balance_hero_card.dart` — Home dashboard balance (needs animated counter)
- `lib/features/ledger/widgets/ledger_hero_card.dart` — Ledger balance hero (needs animated counter)

### Phase 17 Context (Motion Personality)
- `.planning/phases/17-animation-library-loading-states/17-CONTEXT.md` — D-03: "Crisp & confident" motion personality, timing values locked

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `HapticService` — 5 haptic patterns, already wired in 22 files. `.success()` is the pattern for Phase 22 write actions
- `OpenContainer` from `animations: ^2.0.0` — already working on GroupCard→GroupDetail. Extend to EventCard and SmartModuleCard
- `TweenAnimationBuilder<double>` — proven pattern in 3 hero widgets for animating OMR amounts. Copy pattern to BalanceHeroCard and LedgerHeroCard
- `FadeInList`, `StaggeredGrid`, `TapBounce` — shared animation library (Phase 17). Not directly needed but establishes the animation architecture

### Established Patterns
- All routes use `CustomTransitionPage` with `_slideRightTransition` in `app_router.dart`. M3 motion will selectively replace some routes
- `IndexedStack` in `BottomNavShell` for tab state preservation. FadeThrough must maintain state preservation behavior
- Dart 3 switch expression for three-state balance color: `< 0 => errorText, > 0 => successText, _ => textPrimary`. ColorTween needs to work with this pattern
- `AppColors` is a static facade over `AppColorTokens.light` — each getter reads from the token. Deletion means replacing all `AppColors.x` with `AppColorTokens.light.x` or `context.colors.x`

### Integration Points
- `app_router.dart` — ContainerTransform routes need OpenContainer which bypasses GoRouter's page-based navigation. Phase 20 already solved this pattern for GroupCard (URL desync accepted per 20-CONTEXT D-06)
- `bottom_nav_shell.dart` — FadeThrough wrapping IndexedStack. Must preserve tab state and not re-render tabs on switch
- 81 files with AppColors references — bulk migration touches almost every UI file in the codebase

</code_context>

<specifics>
## Specific Ideas

- Motion personality matches Phase 17: "calm, assured, no drama" — not bouncy or playful
- Paper grain texture should feel like premium stationery — warm, handmade, not digital noise
- Animated counter should feel like a premium banking app (smooth, confident number transitions)
- Two-tier texture hierarchy: textured heroes/scaffold vs clean content cards creates depth without clutter

</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope

</deferred>

---

*Phase: 22-polish-pass-token-cleanup*
*Context gathered: 2026-03-31*
