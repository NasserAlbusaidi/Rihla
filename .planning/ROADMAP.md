# Roadmap: Rihla

## Milestones

- ✅ **v1.0 Groups, Events & Cross-Event Financials** — Phases 1-13 (shipped 2026-03-28)
- ✅ **v2.0 Major UI/UX Overhaul** — Phases 14-22 (shipped 2026-03-31)
- ✅ **v2.1 Home Screen Completion** — Phases 23-24 (shipped 2026-04-01)
- ✅ **v2.2 Profile Page** — Phases 25-27 (shipped 2026-04-02)
- ✅ **v2.3 Groups, Events & Modules** — Phases 28-35 (shipped 2026-04-05)
- 🔄 **v2.4 Technical Debt & Dark Theme** — Phases 36-38 (active)

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

<details>
<summary>✅ v2.2 Profile Page (Phases 25-27) — SHIPPED 2026-04-02</summary>

- [x] Phase 25: Profile Screen Core (2/2 plans) — completed 2026-04-01
- [x] Phase 26: Settings & Support (2/2 plans) — completed 2026-04-01
- [x] Phase 27: Wire Notification Service (1/1 plan) — completed 2026-04-02

Full details: [milestones/v2.2-ROADMAP.md](milestones/v2.2-ROADMAP.md)

</details>

<details>
<summary>✅ v2.3 Groups, Events & Modules (Phases 28-35) — SHIPPED 2026-04-05</summary>

- [x] Phase 28: Group Detail (2/2 plans) — completed 2026-04-02
- [x] Phase 29: Group Management (2/2 plans) — completed 2026-04-02
- [x] Phase 30: Group Settle Up & Activity (4/4 plans) — completed 2026-04-05
- [x] Phase 31: Event Command Center (4/4 plans) — completed 2026-04-05
- [x] Phase 32: Event Creation (3/3 plans) — completed 2026-04-05
- [x] Phase 33: Ledger (3/3 plans) — completed 2026-04-05
- [x] Phase 34: Gear & Logistics (2/2 plans) — completed 2026-04-05
- [x] Phase 35: Vault & Memories (2/2 plans) — completed 2026-04-05

Full details: [milestones/v2.3-ROADMAP.md](milestones/v2.3-ROADMAP.md)

</details>

### v2.4 Technical Debt & Dark Theme

- [x] **Phase 36: Architecture Refactor** (8 plans) — God screens (#15), provider watch explosion (#16), CacheService god class (#18) (completed 2026-04-16)
  - [x] 36-00 — Wave 0 TDD test scaffolding (ARCH-01..04)
  - [x] 36-01 — Decompose group_settle_up_screen.dart (ARCH-01)
  - [x] 36-02 — Decompose edit_expense_screen.dart (ARCH-01)
  - [x] 36-03 — Decompose gear_screen.dart (ARCH-01)
  - [x] 36-04 — Decompose logistics_screen.dart (ARCH-01)
  - [x] 36-05 — Decompose create_event_screen.dart (ARCH-01)
  - [x] 36-06 — Split CacheService + rename BalanceCacheRepository (ARCH-04)
  - [x] 36-07 — Bound dashboard fan-out + Firestore date-range query (ARCH-02, ARCH-03)
- [x] **Phase 37: Dark Theme Migration** — Widget migration to `context.colors`, theme toggle, textMuted contrast (#17, #29, #31, #32) (completed 2026-04-18)
  - **Plans:** 8 plans across 5 waves
  - [x] 37-01 — Theme infrastructure (Wave 1: MaterialApp darkTheme wiring, 5 app_theme bugs, SystemChrome theme-aware) (DARK-01)
  - [x] 37-02 — Shared widgets migration (Wave 2: 13 shared widgets + error_widgets + app_router) (DARK-01, DARK-02, DARK-03, DARK-04)
  - [x] 37-03a — Feature migration: auth/onboarding/settings/home (Wave 3) (DARK-01, DARK-02, DARK-03, DARK-04)
  - [x] 37-03b — Feature migration: groups (Wave 3, largest surface) (DARK-01, DARK-02, DARK-03, DARK-04)
  - [x] 37-03c — Feature migration: events/ledger (Wave 3) (DARK-01, DARK-02, DARK-03, DARK-04)
  - [x] 37-03d — Feature migration: gear/logistics/vault/memories/activity (Wave 3) (DARK-01, DARK-02, DARK-03, DARK-04)
  - [x] 37-04 — Token promotions: group avatars + gradients + category colors (Wave 4) (DARK-02, DARK-04)
  - [x] 37-05 — Settings UX + verification (theme picker, goldens, contrast test, CI guard) (Wave 5) (DARK-02, DARK-03, DARK-05)
- [ ] **Phase 38: Storage Cloud Functions** — Enforce group-membership on Storage access (#1b)

Full details: [milestones/v2.4-ROADMAP.md](milestones/v2.4-ROADMAP.md)

## Progress

| Phase | Milestone | Plans Complete | Status | Completed |
|-------|-----------|----------------|--------|-----------|
| 1-13 | v1.0 | 43/43 | Complete | 2026-03-28 |
| 14-22 | v2.0 | 28/28 | Complete | 2026-03-31 |
| 23-24 | v2.1 | 3/3 | Complete | 2026-04-01 |
| 25-27 | v2.2 | 5/5 | Complete | 2026-04-02 |
| 28-35 | v2.3 | 22/22 | Complete | 2026-04-05 |
| 36-38 | v2.4 | 0/— | Active | — |
