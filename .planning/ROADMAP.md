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
- [ ] **Phase 27: Wire Notification Service** - Connect appBootstrapProvider to widget tree so FCM toggle works end-to-end

### v2.3 Groups, Events & Modules

- [ ] **Phase 28: Group Detail** - Main group screen — stats, events list, member balances
- [ ] **Phase 29: Group Management** - Settings, invite flow, member management
- [ ] **Phase 30: Group Settle Up & Activity** - Group-level settlement, activity feed
- [ ] **Phase 31: Event Command Center** - Event hub — header, module grid, event settings
- [ ] **Phase 32: Event Creation** - Type picker, create form, templates
- [ ] **Phase 33: Ledger** - Expenses, add/edit, settle up
- [ ] **Phase 34: Gear & Logistics** - Equipment inventory, sub-groups
- [ ] **Phase 35: Vault & Memories** - Documents, photo timeline

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
- [x] 25-01-PLAN.md — Data layer + profile screen UI (keys, initials circle, stats provider, name propagation, screen, bottom sheet, tests)
- [x] 25-02-PLAN.md — Navigation wiring (route /profile, home header avatar, bottom nav tab, delete old settings screen)
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
- [ ] 27-01-PLAN.md — Wire appBootstrapProvider into SafarApp.build() + integration test

### Phase 28: Group Detail
**Goal**: Full-stack group detail screen — UI/UX, data layer, and backend for stats, events list, and member balances
**Depends on**: Nothing (existing screen rebuild)
**Success Criteria** (what must be TRUE):
  1. Group detail screen displays group stats, events list, and member balances with the v2.x design language
  2. Data layer correctly fetches and caches group detail data
**Plans**: TBD

### Phase 29: Group Management
**Goal**: Full-stack group settings, invite flow, and member management
**Depends on**: Phase 28
**Success Criteria** (what must be TRUE):
  1. Users can manage group settings (name, modules)
  2. Invite flow works end-to-end (create code, share, join)
  3. Member management (add/remove) functions correctly
**Plans**: TBD

### Phase 30: Group Settle Up & Activity
**Goal**: Full-stack group-level settlement and activity feed
**Depends on**: Phase 28
**Success Criteria** (what must be TRUE):
  1. Group-level settle up shows cross-event balances and generates optimized settlements
  2. Activity feed displays group-wide actions in chronological order
**Plans**: TBD

### Phase 31: Event Command Center
**Goal**: Full-stack event hub — header, module grid, event settings
**Depends on**: Phase 28
**Success Criteria** (what must be TRUE):
  1. Event command center displays event info, module grid, and quick actions
  2. Event settings are accessible and functional
**Plans**: TBD

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
| 27 | v2.2 | 0/1 | Planned     | — |
| 28 | v2.3 | 0/0 | Pending     | — |
| 29 | v2.3 | 0/0 | Pending     | — |
| 30 | v2.3 | 0/0 | Pending     | — |
| 31 | v2.3 | 0/0 | Pending     | — |
| 32 | v2.3 | 0/0 | Pending     | — |
| 33 | v2.3 | 0/0 | Pending     | — |
| 34 | v2.3 | 0/0 | Pending     | — |
| 35 | v2.3 | 0/0 | Pending     | — |
