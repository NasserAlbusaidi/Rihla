---
gsd_state_version: 1.0
milestone: v2.0
milestone_name: Major UI/UX Overhaul
status: executing
stopped_at: "Completed 21-01-PLAN.md: foundation tokens + shared widget upgrades"
last_updated: "2026-03-30T20:18:14.944Z"
last_activity: 2026-03-30
progress:
  total_phases: 9
  completed_phases: 7
  total_plans: 23
  completed_plans: 18
  percent: 100
---

# Project State

## Project Reference

See: .planning/PROJECT.md (updated 2026-03-28)

**Core value:** Groups persist across events and accumulate financial history — friends settle up across trips, not just within one.
**Current focus:** Phase 21 — module-screens-redesign

## Current Position

Phase: 21 (module-screens-redesign) — EXECUTING
Plan: 2 of 6
Status: Ready to execute
Last activity: 2026-03-30

Progress: [██████████] 100% (Phase 18 complete — 5 of 9 phases done)

## Performance Metrics

| Metric | v1.0 | v2.0 Target |
|--------|------|-------------|
| Tests | 624 | 80%+ coverage maintained |
| Phases | 13 | 9 |
| Requirements | 26 (v1) | 22 (v2) |
| Phase 14-test-hardening P01 | 90 | 2 tasks | 33 files |
| Phase 14-test-hardening P02 | 90 | 2 tasks | 19 files |
| Phase 14-test-hardening P03 | 45 | 2 tasks | 19 files |
| Phase 15-design-token-system P01 | 7 | 3 tasks | 6 files |
| Phase 15-design-token-system P02 | 3 | 2 tasks | 7 files |
| Phase 16-stitch-workflow-design-reference P01 | 7 | 2 tasks | 4 files |
| Phase 16 P02 | 7 | 2 tasks | 4 files |
| Phase 17-animation-library-loading-states P01 | 8 | 2 tasks | 3 files |
| Phase 17-animation-library-loading-states P02 | 8 | 2 tasks | 10 files |
| Phase 18-home-dashboard-redesign P01 | 8 | 2 tasks | 9 files |
| Phase 18 P02 | 10 | 2 tasks | 8 files |
| Phase 18-home-dashboard-redesign P03 | 17 | 4 tasks | 6 files |
| Phase 19-navigation-restructuring P01 | 174 | 2 tasks | 3 files |
| Phase 19-navigation-restructuring P02 | 65 | 3 tasks | 13 files |
| Phase 19-navigation-restructuring P03 | 45 | 2 tasks | 17 files |
| Phase 20-group-detail-event-hub-redesign P01 | 13 | 3 tasks | 8 files |
| Phase 20 P02 | 404 | 3 tasks | 8 files |
| Phase 21-module-screens-redesign P01 | 10 | 2 tasks | 4 files |

## Accumulated Context

### Key Decisions

- v1.0 shipped 2026-03-28: 13 phases, 624 tests, full Supabase → Firestore migration
- Stitch-first design workflow chosen: design in Stitch, extract tokens, implement in Flutter
- Warm earthy palette: terracotta (~#CC6B49), sand (~#F2E8D6), olive (~#7A8C5E), dark brown body text (#2C1A0E)
- AppColors public API preserved throughout migration — 895 call sites never touched
- No StatefulShellRoute / bottom nav — single hierarchy data model (Group → Event → Module)
- Navigation flattening via content surfacing, not structural nav changes
- Phases 14 and 15 are non-negotiable prerequisites before any visual screen work begins
- Phase 19 (Navigation Restructuring) must precede Phase 20 (Group Detail & Event Hub)
- Module screens (Phase 21) last — highest test density, lowest first-impression impact
- Lottie chosen over Rive for Phase 17 — simpler integration, revisit Rive if interactive state machines needed
- Phase 14 complete: find.text() baseline is 135 (plan estimated 70-90; higher due to 30 legitimate content assertions in create_join_group_test and groups/group_settle_up_screen_test out of scope)
- Rename resilience verified: renaming 'Ledger' to 'Treasury' in event_module_list.dart causes zero test failures across 624 tests — Phase 14 success criterion #3 achieved
- Phase 15 P01: Two-color financial tokens — success/error stay display-only; successText/errorText added as WCAG-safe text variants (4.51:1 and 5.33:1 on sand)
- Phase 15 P01: AppColors facade updated in-place, 895 call sites unchanged — migration to context.colors.x deferred to Phases 18-22
- Phase 15 P01: textOnPrimary changed from black to white (#FFFFFF) — white 3.64:1 on terracotta (AA large)
- Phase 16 P01: Six-section Stitch prompt format established (Palette/Spacing/Typography/Components/Screen/Constraints) as canonical Stitch-to-Flutter workflow for Phases 20-22
- Phase 16 P01: textMuted (#A89888, 2.30:1) permanently annotated as decorative-only in all prompts and checklist — never functional text
- Phase 16 P01: Post-generation checklist Token Gap Log distinguishes structural gaps (add token now) from cosmetic gaps (defer to implementation phase)
- Phase 16 P02: Monochrome+teal palette confirmed canonical — earthy palette (terracotta/sand/olive) fully replaced; primary teal locked to #0D7B74 (AppColorTokens.light.primary, WCAG 5.12:1 verified)
- Phase 16 P02: Bottom nav locked to Groups/Activity/Chats/Profile across all screens — Phase 19 must enforce this globally
- Phase 16 P02: Module accent colors — Ledger=teal (#0D7B74), all other modules=gray-500 (#6B7280)
- Phase 16 P02: Event-type color discrimination deferred to Phase 20 — structural gap (no per-type tokens in new system)
- Phase 16 P02: OfflineBanner amber (#F59E0B) is structural token gap — add offlineBannerBackground to AppColorTokens in Phase 18
- Phase 17 P01: Column over ListView.builder in SkeletonLoader.build() — ListView inside unbounded parent produces zero-height; Column is the correct pattern
- Phase 17 P01: Shimmer 3.0.0 does not expose baseColor/highlightColor as public getters — tests verify via gradient.colors list
- Phase 17 P01: Skeleton primitives pattern — SkeletonCircle/Bar/Block/Row/Card are atoms; named loader factories are molecules assembled from atoms
- Phase 18 P02: BalanceHeroCard uses Dart 3 switch expression on net.compareTo(Decimal.zero) for clean three-state balance rendering (owe/owed/settled)
- Phase 18 P02: BottomNavShell uses IndexedStack with BottomNavigationBarType.fixed (not GoRouter) for 4-tab navigation — Phase 19 will wire real routes for Activity/Chats/Profile tabs
- Phase 18 P02: WeeklySpendingCard renders 2dp stub bar for zero-amount days to prevent chart column collapse
- Phase 18 P02: ActivityRow avatar uses deterministic color from hashCode % Colors.primaries.length — same actor always gets same color
- Phase 18 P03: GroupCard uses ref.watch(currentUserIdProvider) instead of FirebaseConfig.currentUser directly — testable via Riverpod overrides
- Phase 18 P03: FadeInList (D-22) takes precedence over SliverList.builder (D-21) for group cards section — FadeInList is a Column, not a Sliver; wrapped in SliverToBoxAdapter per RESEARCH Pitfall 4
- Phase 18 P03: cacheExtent: 2000 on CustomScrollView ensures WeeklySpendingCard always built for widget test discoverability
- Phase 18 P03: BottomNavShell gets scaffoldKey param to allow HomeKeys.screen on outer Scaffold without nesting two Scaffolds
- Phase 18 P03: 743 tests pass after HomeScreen integration — 12 new dashboard tests, 0 regressions
- Phase 19 P01: testRouter() factory with 17 stub routes established as canonical helper for all GoRouter widget tests
- Phase 19 P02: D-14 big-bang migration — all screens take string IDs from GoRouter path params; eventDetailProvider/groupDetailProvider loaded inside screen; no state.extra, deep links work
- Phase 19 P03: EditExpenseSheet → EditExpenseScreen with expenseId string constructor; showModalBottomSheet removed; deferred controller init pattern (_initialized guard) handles async expense lookup
- Phase 19 P03: page_transitions.dart deleted — all transitions now use CustomTransitionPage + _slideRightTransition in app_router.dart; AppPageRoute/AppBottomSheetRoute gone
- Phase 19 P03: Tests wrapping screens that call context.push must use MaterialApp.router (not MaterialApp(home:)) — applied across 9 test files; 744 tests pass
- Phase 20 P01: currentUserIdProvider used in GroupDetailScreen instead of FirebaseConfig.currentUser directly — enables test isolation via Riverpod override without Firebase init
- Phase 20 P01: Stats grid (GroupStatsGrid) always visible per D-08 — no conditional on totalSpent unlike old GroupBalanceHero; zero-state shows zeros
- Phase 20 P01: EventCard accent bar (IntrinsicHeight Row + 3dp Container) replaces 48x48 icon container and type badge chip; teal=active, gray=past
- Phase 20 P01: Dart 3 switch expression for three-state balance color: &lt; 0 =&gt; errorText, &gt; 0 =&gt; successText, _ =&gt; textPrimary
- Phase 20 P02: Activity card always shown in module grid (position 5), regardless of EventModules flags — timeline is a universal event feature
- Phase 20 P02: OpenContainer replaces TapBounce+context.push for GroupCard — ContainerTransform wired, URL desync accepted per D-06
- Phase 20 P02: Module colors use AppColorTokens.light.* directly (no AppColors facade aliases for module* tokens)

### Known Risks

- ~~257 find.text() calls in test suite — Phase 14 complete~~ 135 content-only find.text() calls remain; all structural assertions migrated to find.byKey()
- 895 AppColors.* references — preserved via two-layer system in Phase 15, deleted in Phase 22
- ~~Earthy palette WCAG contrast: terracotta on sand ~2.8:1 — Phase 15 requires contrast validation before any screen code~~ RESOLVED: new monochrome+teal palette with full WCAG verification in AppColorTokens.light
- ~~Dashboard eager render risk~~ RESOLVED: Phase 18 uses CustomScrollView + Slivers with cacheExtent:2000; human-verified on device at 60fps
- ~~Physical device baseline needed for Phase 18 performance validation~~ RESOLVED: Phase 18 Task 4 human-verify checkpoint passed

### Blockers

None currently.

## Session Continuity

Last session: 2026-03-30T20:18:14.941Z
Stopped at: Completed 21-01-PLAN.md: foundation tokens + shared widget upgrades
Next action: Phase 19 complete — proceed to Phase 20 (Group Detail & Event Hub screens with new GoRouter-declarative navigation)
