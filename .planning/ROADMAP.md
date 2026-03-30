# Roadmap: Rihla

## Milestones

- **v1.0 Groups, Events & Cross-Event Financials** — Phases 1-13 (shipped 2026-03-28)
- **v2.0 Major UI/UX Overhaul** — Phases 14-22 (active)

## Phases

<details>
<summary>v1.0 Groups, Events & Cross-Event Financials (Phases 1-13) — SHIPPED 2026-03-28</summary>

- [x] Phase 1: Data Foundation (3/3 plans) — completed 2026-03-25
- [x] Phase 2: Groups (4/4 plans) — completed 2026-03-26
- [x] Phase 3: Events (5/5 plans) — completed 2026-03-26
- [x] Phase 4: Firestore Repository Layer (6/6 plans) — completed 2026-03-26
- [x] Phase 5: Cross-Event Financials (7/7 plans) — completed 2026-03-26
- [x] Phase 6: Testing and Coverage (5/5 plans) — completed 2026-03-27
- [x] Phase 7: Data Migration & Supabase Removal (2/2 plans) — completed 2026-03-27
- [x] Phase 8: Integration & Correctness Fixes (2/2 plans) — completed 2026-03-27
- [x] Phase 9: Dead Code Cleanup (1/1 plan) — completed 2026-03-27
- [x] Phase 10: Full Codebase Review (4/4 plans) — completed 2026-03-27
- [x] Phase 11: Gear Write Mutations (1/1 plan) — completed 2026-03-27
- [x] Phase 12: Expense & Logistics Provider Rewiring (2/2 plans) — completed 2026-03-27
- [x] Phase 13: Final Cleanup (1/1 plan) — completed 2026-03-27

Full details: [milestones/v1.0-ROADMAP.md](milestones/v1.0-ROADMAP.md)

</details>

### v2.0 Major UI/UX Overhaul (Phases 14-22)

- [x] **Phase 14: Test Hardening** - Convert structural test assertions to semantic Key identifiers to prevent cascade failures during visual changes (3/3 plans — completed 2026-03-28)
- [x] **Phase 15: Design Token System** - Build the ThemeExtension-based warm earthy token layer that all subsequent screen work depends on (completed 2026-03-28)
- [x] **Phase 16: Stitch Workflow & Design Reference** - Establish Stitch as specification source, finalize palette, and add CI lint rule blocking hardcoded color values (completed 2026-03-29)
- [x] **Phase 17: Animation Library & Loading States** - Build shared animation components and skeleton loading variants before any screen uses them (completed 2026-03-29)
- [ ] **Phase 18: Home Dashboard Redesign** - Deliver the single-scroll dashboard with balance hero, group cards, quick-action tray, and activity strip
- [ ] **Phase 19: Navigation Restructuring** - Migrate 22 Navigator.push calls to GoRouter subroutes so all event-level screens are reachable within 2 taps
- [ ] **Phase 20: Group Detail & Event Hub Redesign** - Redesign the group gateway and event hub with earthy tokens, type-specific color accents, and M3 transitions
- [ ] **Phase 21: Module Screens Redesign** - Apply the new design language to all six module screens with card-style layouts and illustrated empty states
- [ ] **Phase 22: Polish Pass & Token Cleanup** - Add haptic feedback, animated balance counters, texture overlays, M3 motion, and delete legacy AppColors

## Phase Details

### Phase 14: Test Hardening
**Goal**: The existing test suite can survive any label rename or visual structural change without cascade failures
**Depends on**: Nothing (first phase of v2.0)
**Requirements**: FOUND-05
**Success Criteria** (what must be TRUE):
  1. Every interactive widget and structural landmark in the app has a semantic Key identifier
  2. All structural navigation assertions in the test suite use find.byKey() instead of find.text()
  3. Renaming any UI label in the codebase causes zero test failures outside the one test that directly validates that label
  4. The full test suite (624 tests) passes without modification after Keys are added
**Plans**: 3 plans
Plans:
- [x] 14-01-PLAN.md — Key infrastructure + migrate 4 heaviest test files (108 calls)
- [x] 14-02-PLAN.md — Migrate 8 medium-priority test files (115 calls)
- [x] 14-03-PLAN.md — Migrate remaining test files + CI warning + rename verification

### Phase 15: Design Token System
**Goal**: Every color and spacing value in the app flows from a single typed token system; no screen can reference a hardcoded color value
**Depends on**: Phase 14
**Requirements**: FOUND-01, FOUND-02, FOUND-04
**Success Criteria** (what must be TRUE):
  1. App renders with the warm earthy palette (terracotta, sand, olive, dark brown body text) after a hot restart
  2. Every text-on-background combination in the app passes WCAG AA contrast (4.5:1 body, 3:1 large text and icons)
  3. The CI lint step fails on any file outside app_theme.dart that introduces a Color(0xFF...) literal
  4. All 895 existing AppColors references continue to compile and produce warm palette values without any call-site changes
**Plans**: 2 plans
Plans:
- [x] 15-01-PLAN.md — Token classes (AppColorTokens, AppSpacingTokens, AppShadowTokens) + AppColors facade palette swap + ThemeData registration + WCAG tests
- [x] 15-02-PLAN.md — Migrate 15 hardcoded Color(0xFF...) in 6 files to AppColors + CI lint step
**UI hint**: yes

### Phase 16: Stitch Workflow & Design Reference
**Goal**: Screen mockups for the three highest-value screens (Home, Group Detail, Event Hub) exist as visual specifications that all subsequent phases build against
**Depends on**: Phase 15
**Requirements**: FOUND-03
**Success Criteria** (what must be TRUE):
  1. Stitch contains screen mockups for Home, Group Detail, and Event Hub using the finalized earthy palette tokens
  2. Any Stitch-generated Flutter layout code reviewed against a documented post-generation checklist before being committed
  3. Palette hex values from the Stitch output are reconciled with Phase 15 token values (final values update app_tokens.dart if Phase 15 used approximations)
  4. CLAUDE.md documents the Stitch-to-Flutter workflow including the post-generation token replacement step
**Plans**: 2 plans
Plans:
- [x] 16-01-PLAN.md — Stitch input prompts (3 screens) + post-generation checklist
- [x] 16-02-PLAN.md — User runs Stitch + annotated design specs (3 screens) + CLAUDE.md workflow section

### Phase 17: Animation Library & Loading States
**Goal**: Reusable animation components and skeleton loading variants exist as tested shared widgets, ready for any screen to import without reimplementing lifecycle management
**Depends on**: Phase 15
**Requirements**: PLSH-03, NAV-05
**Success Criteria** (what must be TRUE):
  1. Skeleton variant factories (dashboardHero, eventCard, groupList, expenseList, gearList, generic) are tested and ready for drop-in use in the AsyncValue loading: callback of any data-fetching screen
  2. Shared animation components (fade-in list, staggered grid, tap bounce) are available in lib/shared/animations/ with correct AnimationController dispose() calls verified by tests
  3. No AnimationController is instantiated directly inside a screen widget — all animation logic flows through shared components
  4. Skeleton variants (dashboard hero, event card, group list) exist as named constructors and render without data
**Plans**: 2 plans
Plans:
- [x] 17-01-PLAN.md — Skeleton primitives (SkeletonCircle, SkeletonBar, SkeletonBlock, SkeletonRow, SkeletonCard) + 6 named variant factories on SkeletonLoader
- [x] 17-02-PLAN.md — Animation components (TapBounce, FadeInList, StaggeredGrid) + migrate 3 duplicate pressable patterns
**UI hint**: yes

### Phase 18: Home Dashboard Redesign
**Goal**: The home screen surfaces enough information that a user can answer "what do I owe across all groups?" and reach any group's event without a second tap
**Depends on**: Phase 16, Phase 17
**Requirements**: NAV-01, NAV-02, NAV-04, NAV-06
**Success Criteria** (what must be TRUE):
  1. User sees their net cross-group balance color-coded green/red/gray on the home screen immediately after app load (no tap required)
  2. User can tap a group card directly from the home screen and reach an event's module screen within one additional tap (2 taps total from home)
  3. When the home screen has no groups, an illustrated empty state with a single CTA ("Create your first group") appears instead of a blank screen
  4. The dashboard scrolls smoothly at 60fps with no frame exceeding 16ms on a mid-range Android device (validated with DevTools Performance view)
  5. Quick-action tray (Add Expense, Settle Up, Invite, Activity) is visible on the home screen without scrolling
**Plans**: 3 plans
Plans:
- [x] 18-01-PLAN.md — Token additions (color tokens + AppColors facade) + cross-group providers + HomeKeys expansion
- [ ] 18-02-PLAN.md — Dashboard widget components (BalanceHeroCard, QuickActionTray, ActivityRow, WeeklySpendingCard, BottomNavShell)
- [ ] 18-03-PLAN.md — HomeScreen rewrite + GroupCard personal balance + integration tests + visual verification
**UI hint**: yes

### Phase 19: Navigation Restructuring
**Goal**: Every event-level screen is reachable via a GoRouter URL, and all imperative Navigator.push calls across the app are replaced with context.push
**Depends on**: Phase 14
**Requirements**: NAV-03
**Success Criteria** (what must be TRUE):
  1. Typing any event module URL (/group/:groupId/event/:eventId/ledger) into the app router navigates directly to that screen without passing through intermediate screens
  2. The hardware back button navigates correctly at every new screen depth introduced by GoRouter subroutes
  3. All 22 Navigator.push / AppPageRoute calls across the 7 affected files are replaced with context.push calls
  4. CLAUDE.md navigation flow section is updated to reflect the new routing graph in the same commit as the routing code changes
**Plans**: TBD

### Phase 20: Group Detail & Event Hub Redesign
**Goal**: The group detail screen and event hub communicate the financial state and module access visually — users scan rather than read to understand what needs attention
**Depends on**: Phase 17, Phase 19
**Requirements**: SCRN-01, SCRN-02
**Success Criteria** (what must be TRUE):
  1. Group detail event cards show type-specific color accents and inline financial summaries without the user tapping into each event
  2. Past events appear visually distinct from upcoming events (muted/desaturated vs. full color)
  3. Event hub (CommandCenter) renders with the earthy palette and the new design language matching the Phase 16 Stitch mockup
  4. ContainerTransform transition plays when navigating from a group card to the group detail screen
**Plans**: TBD
**UI hint**: yes

### Phase 21: Module Screens Redesign
**Goal**: Every module screen (Ledger, Gear, Logistics, Vault, Memories, Activity) and every form flow uses the new design language — the visual overhaul is complete across the entire app
**Depends on**: Phase 20
**Requirements**: SCRN-03, SCRN-04, SCRN-05, SCRN-06
**Success Criteria** (what must be TRUE):
  1. Ledger screen displays expense rows as cards with color-coded balance amounts (green owed to you, red you owe, gray settled)
  2. Every module screen that can be empty shows a contextual illustrated empty state with a single CTA specific to that screen's context
  3. Gear, Logistics, Vault, Memories, and Activity screens render with earthy palette design tokens replacing all legacy AppColors references
  4. Create/join group, create event, add expense, and settings flows use the new design language with no legacy visual elements remaining
  5. Onboarding flow and splash screen reflect the warm earthy visual identity
**Plans**: TBD
**UI hint**: yes

### Phase 22: Polish Pass & Token Cleanup
**Goal**: Micro-interactions, motion, texture, and animated feedback bring the app to a premium feel; AppColors is deleted and no legacy color debt remains
**Depends on**: Phase 21
**Requirements**: PLSH-01, PLSH-02, PLSH-04, PLSH-05
**Success Criteria** (what must be TRUE):
  1. Adding an expense, recording a settlement, and joining a group each trigger haptic feedback (verified on a physical device)
  2. Screen transitions between major screens use M3 motion patterns (ContainerTransform or SharedAxis) instead of the default slide animation
  3. Balance amounts on the home dashboard and ledger screen animate smoothly when their value changes (no jump cut)
  4. Group cards and surfaces display subtle grain/texture and soft gradient overlays that read as warm and tactile rather than flat
  5. A grep for AppColors in the codebase returns zero results — the class is deleted and no references remain
**Plans**: TBD
**UI hint**: yes

## Progress

| Phase | Plans Complete | Status | Completed |
|-------|----------------|--------|-----------|
| 14. Test Hardening | 3/3 | Complete    | 2026-03-28 |
| 15. Design Token System | 2/2 | Complete    | 2026-03-28 |
| 16. Stitch Workflow & Design Reference | 2/2 | Complete    | 2026-03-29 |
| 17. Animation Library & Loading States | 2/2 | Complete    | 2026-03-29 |
| 18. Home Dashboard Redesign | 1/3 | In Progress|  |
| 19. Navigation Restructuring | 0/? | Not started | - |
| 20. Group Detail & Event Hub Redesign | 0/? | Not started | - |
| 21. Module Screens Redesign | 0/? | Not started | - |
| 22. Polish Pass & Token Cleanup | 0/? | Not started | - |
