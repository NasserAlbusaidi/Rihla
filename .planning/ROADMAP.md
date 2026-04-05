# Roadmap: Rihla

## Milestones

- ✅ **v1.0 Groups, Events & Cross-Event Financials** — Phases 1-13 (shipped 2026-03-28)
- ✅ **v2.0 Major UI/UX Overhaul** — Phases 14-22 (shipped 2026-03-31)
- ✅ **v2.1 Home Screen Completion** — Phases 23-24 (shipped 2026-04-01)
- [ ] **v2.2 Profile Page** — Phases 25-27
- [ ] **v2.3 Groups, Events & Modules** — Phases 28-35

## Phases

<details>
<summary>✅ v1.0 Groups, Events & Cross-Event Financials (Phases 1-13) — SHIPPED 2026-03-28</summary>

- [x] Phase 1: Data Foundation (3/3 plans) — completed 2026-03-25
- [x] Phase 2: Groups (4/4 plans) — completed 2026-03-26
- [x] Phase 3: Events (5/5 plans) — completed 2026-03-26
- [x] Phase 4: Firestore Repository Layer (6/6 plans) — completed 2026-03-26
- [x] Phase 5: Cross-Event Financials (7/7 plans) — completed 2026-03-26
- [x] Phase 6: Testing and Coverage (5/5 plans) — completed 2026-03-26
- [x] Phase 7: Data Migration & Supabase Removal (2/2 plans) — completed 2026-03-27
- [x] Phase 8: Integration & Correctness Fixes (2/2 plans) — completed 2026-03-27
- [x] Phase 9: Dead Code Cleanup (1/1 plan) — completed 2026-03-27
- [x] Phase 10: Full Codebase Review (4/4 plans) — completed 2026-03-27
- [x] Phase 11: Gear Write Mutations (1/1 plan) — completed 2026-03-27
- [x] Phase 12: Expense & Logistics Provider Rewiring (2/2 plans) — completed 2026-03-27
- [x] Phase 13: Final Cleanup (1/1 plan) — completed 2026-03-27

Full details: [milestones/v1.0-ROADMAP.md](milestones/v1.0-ROADMAP.md)

</details>

<details>
<summary>✅ v2.0 Major UI/UX Overhaul (Phases 14-22) — SHIPPED 2026-03-31</summary>

<<<<<<< Updated upstream
- [x] Phase 14: Test Hardening (3/3 plans) — completed 2026-03-28
- [x] Phase 15: Design Token System (2/2 plans) — completed 2026-03-28
- [x] Phase 16: Stitch Workflow & Design Reference (2/2 plans) — completed 2026-03-29
- [x] Phase 17: Animation Library & Loading States (2/2 plans) — completed 2026-03-29
- [x] Phase 18: Home Dashboard Redesign (3/3 plans) — completed 2026-03-30
- [x] Phase 19: Navigation Restructuring (3/3 plans) — completed 2026-03-30
- [x] Phase 20: Group Detail & Event Hub Redesign (2/2 plans) — completed 2026-03-30
- [x] Phase 21: Module Screens Redesign (6/6 plans) — completed 2026-03-30
- [x] Phase 22: Polish Pass & Token Cleanup (5/5 plans) — completed 2026-03-31

Full details: [milestones/v2.0-ROADMAP.md](milestones/v2.0-ROADMAP.md)

</details>

<details>
<summary>✅ v2.1 Home Screen Completion (Phases 23-24) — SHIPPED 2026-04-01</summary>

- [x] Phase 23: Quick Action Fixes (1/1 plan) — completed 2026-04-01
- [x] Phase 24: Visual Density & Polish (2/2 plans) — completed 2026-04-01

Full details: [milestones/v2.1-ROADMAP.md](milestones/v2.1-ROADMAP.md)

</details>

### v2.2 Profile Page

- [x] **Phase 25: Profile Screen Core** - Profile screen with identity management and cross-group stats (completed 2026-04-01)
- [x] **Phase 26: Settings & Support** - Notification toggles, app info, and support section (completed 2026-04-01)
- [x] **Phase 27: Wire Notification Service** - Connect appBootstrapProvider to widget tree so FCM toggle works end-to-end (completed 2026-04-02)

### v2.3 Groups, Events & Modules

- [x] **Phase 28: Group Detail** - Main group screen — stats, events list, member balances (completed 2026-04-02)
- [x] **Phase 29: Group Management** - Settings, invite flow, member management (completed 2026-04-02)
- [x] **Phase 30: Group Settle Up & Activity** - Group-level settlement, activity feed (completed 2026-04-05)
- [x] **Phase 31: Event Command Center** - Event hub — header, module grid, event settings (completed 2026-04-05)
- [ ] **Phase 32: Event Creation** - Type picker, create form, templates
- [ ] **Phase 33: Ledger** - Expenses, add/edit, settle up
- [ ] **Phase 34: Gear & Logistics** - Equipment inventory, sub-groups
- [ ] **Phase 35: Vault & Memories** - Documents, photo timeline
=======
- [x] **Phase 14: Test Hardening** - Convert structural test assertions to semantic Key identifiers to prevent cascade failures during visual changes (3/3 plans — completed 2026-03-28)
- [ ] **Phase 15: Design Token System** - Build the ThemeExtension-based warm earthy token layer that all subsequent screen work depends on
- [ ] **Phase 16: Stitch Workflow & Design Reference** - Establish Stitch as specification source, finalize palette, and add CI lint rule blocking hardcoded color values
- [ ] **Phase 17: Animation Library & Loading States** - Build shared animation components and skeleton loading variants before any screen uses them
- [ ] **Phase 18: Home Dashboard Redesign** - Deliver the single-scroll dashboard with balance hero, group cards, quick-action tray, and activity strip
- [ ] **Phase 19: Navigation Restructuring** - Migrate 22 Navigator.push calls to GoRouter subroutes so all event-level screens are reachable within 2 taps
- [ ] **Phase 20: Group Detail & Event Hub Redesign** - Redesign the group gateway and event hub with earthy tokens, type-specific color accents, and M3 transitions
- [ ] **Phase 21: Module Screens Redesign** - Apply the new design language to all six module screens with card-style layouts and illustrated empty states
- [ ] **Phase 22: Polish Pass & Token Cleanup** - Add haptic feedback, animated balance counters, texture overlays, M3 motion, and delete legacy AppColors
>>>>>>> Stashed changes

## Phase Details

### Phase 25: Profile Screen Core
**Goal**: Users can view and manage their identity and see their cross-group stats in a new profile screen
**Depends on**: Nothing (new screen, no existing phase dependencies within v2.2)
**Requirements**: IDENT-01, IDENT-02, IDENT-03, STATS-01, STATS-02, STATS-03
**Success Criteria** (what must be TRUE):
  1. User can navigate to a profile screen and see their current display name
  2. User can tap to edit their display name and save it — the new name appears across all groups they belong to
  3. User can see their total group count, event count, and total spending in OMR on the profile screen
**Plans**: 2 plans
Plans:
<<<<<<< Updated upstream
- [x] 25-01-PLAN.md — Data layer + profile screen UI (keys, initials circle, stats provider, name propagation, screen, bottom sheet, tests)
- [x] 25-02-PLAN.md — Navigation wiring (route /profile, home header avatar, bottom nav tab, delete old settings screen)
=======
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
**Plans**: TBD
>>>>>>> Stashed changes
**UI hint**: yes

### Phase 26: Settings & Support
**Goal**: Users can manage notification preferences and access app info and support options from the profile screen
**Depends on**: Phase 25
**Requirements**: NOTIF-01, NOTIF-02, INFO-01, INFO-02, INFO-03, SUPP-01
**Success Criteria** (what must be TRUE):
  1. User can see their current push notification status (enabled/disabled) on the profile screen
  2. User can toggle push notifications on or off and the preference persists across app restarts
  3. User can see the app version number on the profile screen
  4. User can tap a feedback/support link that opens an external URL
  5. User can tap to open the open-source licenses screen, and a "Buy me a coffee" placeholder section is visible on the profile screen
**Plans**: 2 plans
Plans:
- [x] 26-01-PLAN.md — Section widgets (notifications toggle, about info, support placeholder) + wire into ProfileScreen
- [x] 26-02-PLAN.md — Widget tests for all Phase 26 requirements (NOTIF-01/02, INFO-01/02/03, SUPP-01)
**UI hint**: yes

### Phase 27: Wire Notification Service
**Goal**: Notification toggle actually controls FCM — appBootstrapProvider activated in widget tree
**Depends on**: Phase 26
**Requirements**: NOTIF-02
**Gap Closure**: Closes gaps from v2.2 milestone audit
**Success Criteria** (what must be TRUE):
  1. `appBootstrapProvider` is watched in SafarApp so its `ref.listen` fires on preference changes
  2. Toggling push notifications on/off calls `NotificationService.initialize()` / `removeToken()` respectively
**Plans**: 1 plan
Plans:
- [x] 27-01-PLAN.md — Wire appBootstrapProvider into SafarApp.build() + integration test

### Phase 28: Group Detail
**Goal**: Visual refresh and provider cleanup of GroupDetailScreen — earthy design language, animations, pull-to-refresh, inline error handling
**Depends on**: Nothing (existing screen rebuild)
**Success Criteria** (what must be TRUE):
  1. Group detail screen displays group stats, events list, and member balances with the v2.x design language
  2. Invite code section removed (deferred to Phase 29)
  3. Pull-to-refresh triggers Firestore re-fetch
  4. Event cards animate in with staggered fade-in
  5. Error state is inline with retry, not full-screen replacement
**Plans**: 2 plans
Plans:
- [x] 28-01-PLAN.md — Screen cleanup: remove invite code, provider rebuild isolation, CTA gradient, FAB fix, spacing polish, test updates
- [x] 28-02-PLAN.md — New behaviors: RefreshIndicator, FadeInList, inline error state, member card polish, new widget tests
**UI hint**: yes

### Phase 29: Group Management
**Goal**: Visual refresh of GroupSettingsScreen with ProfileScreen design pattern, member management with creator badge and remove capability, and leave/delete group actions with confirmation dialogs
**Depends on**: Phase 28
**Success Criteria** (what must be TRUE):
  1. GroupSettingsScreen follows ProfileScreen layout pattern (card containers, stagger animations, no AppBar)
  2. Members section shows member list with creator badge and remove capability (balance-gated)
  3. Leave group (any member) and delete group (creator-only) work with confirmation dialogs
**Plans**: 2 plans
Plans:
- [x] 29-01-PLAN.md — Service methods (leaveGroup, removeMember, deleteGroup), test keys, test scaffold
- [x] 29-02-PLAN.md — Section widgets (GroupInfoSection, GroupMembersSection, GroupDangerSection), screen refactor, test updates
**UI hint**: yes

### Phase 30: Group Settle Up & Activity
**Goal**: Visual overhaul of settle-up and activity screens with tabbed layout, card tiles, date-grouped timeline, filter chips, infinite scroll, and functional bug fixes (balance sign, activity logging gaps)
**Depends on**: Phase 28
**Success Criteria** (what must be TRUE):
  1. Settle-up screen shows 4 tabs (You Owe / Owed to You / Between Others / History) with card-style settlement tiles
  2. Activity feed displays date-grouped timeline with filter chips and infinite scroll
  3. Balance sign bug fixed — YOUR BALANCE shows directional label
  4. Activity logging covers all 5 action types (was only 1)
**Plans**: 4 plans
Plans:
- [x] 30-00-PLAN.md — Wave 0: failing test stubs for settle-up, activity, and activity service
- [x] 30-01-PLAN.md — Balance sign fix (D-12), activity logging gaps (D-14), Phase 30 test keys
- [x] 30-02-PLAN.md — Settle-up screen redesign: ModuleHeader, 4-tab AppTabBar, card tiles, History tab, bottom sheet polish, tests
- [x] 30-03-PLAN.md — Activity screen redesign: ModuleHeader, date-grouped list, filter chips (Settlements/Events/Members), infinite scroll, rich tiles, D-15 CTA verification, tests
**UI hint**: yes

### Phase 31: Event Command Center
**Goal**: Visual refresh of EventCommandCenter (gear icon, date range header, earthy tokens) plus new EventSettingsScreen with editable event fields and balance-gated delete
**Depends on**: Phase 28
**Requirements**: ECC-01, ECC-02
**Success Criteria** (what must be TRUE):
  1. Event command center header shows gear settings icon with date range and navigates to settings
  2. Event settings screen allows editing name, dates, description and deleting the event (creator-only, balance-gated)
**Plans**: 4 plans
Plans:
- [x] 31-00-PLAN.md — Wave 0: failing test stubs for ECC-01/ECC-02 + _wrapEventHub settings route stub
- [x] 31-01-PLAN.md — Event.description model extension, EventCommandCenter refresh (gear icon, date range, SkeletonLoader), AppRoutes.eventSettings + placeholder route
- [x] 31-02-PLAN.md — EventSettingsScreen + EventInfoSection + EventDangerSection + complete test file + wire real screen into router
- [x] 31-03-PLAN.md — EventExpenseHero member count display + earthy token audit + EventModuleList ordering verification
**UI hint**: yes

### Phase 32: Event Creation
**Goal**: Full-stack event creation — type picker, form, templates per event type
**Depends on**: Phase 31
**Success Criteria** (what must be TRUE):
  1. Users can pick an event type and create an event with pre-filled template content
  2. Event creation persists to backend and appears in group detail
**Plans**: TBD

### Phase 33: Ledger
**Goal**: Full-stack ledger module — expenses, add/edit, settle up
**Depends on**: Phase 31
**Success Criteria** (what must be TRUE):
  1. Expense list, add, edit, and delete work end-to-end
  2. Event-level settle up calculates and records settlements correctly
**Plans**: TBD

### Phase 34: Gear & Logistics
**Goal**: Full-stack gear inventory and logistics (sub-groups) modules
**Depends on**: Phase 31
**Success Criteria** (what must be TRUE):
  1. Gear items can be added, claimed, and filtered
  2. Logistics sub-groups (carpool/lodging) can be created and managed
**Plans**: TBD

### Phase 35: Vault & Memories
**Goal**: Full-stack vault (documents) and memories (photos) modules
**Depends on**: Phase 31
**Success Criteria** (what must be TRUE):
  1. Documents can be uploaded, viewed, and deleted
  2. Photos can be uploaded and viewed in timeline/grid layout
**Plans**: TBD

## Progress

| Phase | Milestone | Plans Complete | Status | Completed |
|-------|-----------|----------------|--------|-----------|
| 1-13 | v1.0 | 43/43 | Complete | 2026-03-28 |
| 14-22 | v2.0 | 28/28 | Complete | 2026-03-31 |
| 23-24 | v2.1 | 3/3 | Complete | 2026-04-01 |
| 25 | v2.2 | 2/2 | Complete    | 2026-04-01 |
| 26 | v2.2 | 2/2 | Complete    | 2026-04-01 |
| 27 | v2.2 | 1/1 | Complete    | 2026-04-02 |
| 28 | v2.3 | 2/2 | Complete    | 2026-04-02 |
| 29 | v2.3 | 2/2 | Complete    | 2026-04-02 |
| 30 | v2.3 | 4/4 | Complete    | 2026-04-05 |
| 31 | v2.3 | 4/4 | Complete   | 2026-04-05 |
| 32 | v2.3 | 0/0 | Pending     | — |
| 33 | v2.3 | 0/0 | Pending     | — |
| 34 | v2.3 | 0/0 | Pending     | — |
| 35 | v2.3 | 0/0 | Pending     | — |
