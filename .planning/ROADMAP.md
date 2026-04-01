# Roadmap: Rihla

## Milestones

- ✅ **v1.0 Groups, Events & Cross-Event Financials** — Phases 1-13 (shipped 2026-03-28)
- ✅ **v2.0 Major UI/UX Overhaul** — Phases 14-22 (shipped 2026-03-31)
- 🔄 **v2.1 Home Screen Completion** — Phases 23-24 (active)

## Phases

<details>
<summary>✅ v1.0 Groups, Events & Cross-Event Financials (Phases 1-13) — SHIPPED 2026-03-28</summary>

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

### v2.1 Home Screen Completion

- [x] **Phase 23: Quick Action Fixes** — Wire broken home screen actions to correct destinations (completed 2026-04-01)
- [x] **Phase 24: Visual Density & Polish** — Improve group cards, chart clarity, and layout density (completed 2026-04-01)

## Phase Details

### Phase 23: Quick Action Fixes
**Goal**: All home screen quick actions respond correctly and navigate to the right destination
**Depends on**: Nothing (correctness fixes, no new dependencies)
**Requirements**: ACT-01, ACT-02, ACT-03
**Success Criteria** (what must be TRUE):
  1. Tapping "Invite Friend" opens a native share sheet with a group invite code (not the join-group screen)
  2. When the user belongs to multiple groups, tapping "Invite Friend" first shows a group picker, then the share sheet
  3. Tapping "Activity" navigates to a cross-group activity view with visible content
**Plans**: 1 plan
Plans:
- [x] 23-01-PLAN.md — Wire invite share flow, create cross-group activity screen, fix 0-groups edge cases
**UI hint**: yes

### Phase 24: Visual Density & Polish
**Goal**: The home dashboard feels information-dense, visually differentiated, and clearly structured
**Depends on**: Phase 23
**Requirements**: CARD-01, CARD-02, CHRT-01, CHRT-02, LAYT-01, LAYT-02
**Success Criteria** (what must be TRUE):
  1. Each group card is visually distinct — a color accent, event count badge, or member indicator makes groups distinguishable at a glance
  2. Each group card surfaces meaningful context — last event name, recent activity hint, or total group spend is visible without tapping
  3. The weekly spending chart shows readable values — amount labels on bars or a Y-axis scale are present
  4. The chart title reads "Weekly Spending" with a currency indicator, not just "This Week"
  5. The dashboard has tighter visual rhythm — reduced dead whitespace between sections and a clear header above the group list
**Plans**: 2 plans
Plans:
- [x] 24-01-PLAN.md — GroupCard accent strip and event context line (CARD-01, CARD-02)
- [ ] 24-02-PLAN.md — Chart bar labels, title update, dashboard spacing, section header (CHRT-01, CHRT-02, LAYT-01, LAYT-02)
**UI hint**: yes

## Progress

| Phase | Milestone | Plans Complete | Status | Completed |
|-------|-----------|----------------|--------|-----------|
| 1-13 | v1.0 | 43/43 | Complete | 2026-03-28 |
| 14-22 | v2.0 | 28/28 | Complete | 2026-03-31 |
| 23. Quick Action Fixes | v2.1 | 1/1 | Complete    | 2026-04-01 |
| 24. Visual Density & Polish | v2.1 | 1/2 | Complete    | 2026-04-01 |
