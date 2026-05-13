---
gsd_state_version: 1.0
milestone: v2.4
milestone_name: Technical Debt & Dark Theme
status: Ready for launch
stopped_at: context exhaustion at 100% (2026-05-12)
last_updated: "2026-05-12T17:04:06.281Z"
last_activity: 2026-05-02
progress:
  total_phases: 2
  completed_phases: 2
  total_plans: 11
  completed_plans: 11
  percent: 100
---

# Project State

## Project Reference

See: .planning/PROJECT.md (updated 2026-04-01)

**Core value:** Groups persist across events and accumulate financial history — friends settle up across trips, not just within one.
**Current focus:** v1 launch — all milestones shipped, post-launch follow-up TBD

## Current Position

Milestone: v2.4 Technical Debt & Dark Theme — SHIPPED
Phase: 39 — Strip to Shippable v1 (COMPLETE) + 4 launch UX fixes (codex/publish-readiness-fixes)
Plan: 7 / 7 (all plans landed)
Status: Ready for launch
Last activity: 2026-05-02

```
v1.0 Phases 1-13  [██████████] 100%
v2.0 Phases 14-22 [██████████] 100%
v2.1 Phases 23-24 [██████████] 100%
v2.2 Phases 25-27 [██████████] 100%
v2.3 Phases 28-35 [██████████] 100%
```

## Performance Metrics

| Milestone | Phases | Plans | Tests | Timeline |
|-----------|--------|-------|-------|----------|
| v1.0 | 13 | 43 | 624 | 91 days |
| v2.0 | 9 | 28 | 767 | 4 days |
| v2.1 | 2 | 3 | 789 | 1 day |
| v2.2 | 3 | 5 | — | 1 day |
| v2.3 | 8 | 22 | — | 3 days |
| Phase 36-architecture-refactor P02 | 20 | 3 tasks | 7 files |
| Phase 36-architecture-refactor P04 | 20 | 3 tasks | 7 files |
| Phase 36-architecture-refactor P06 | 25 | 4 tasks | 18 files |
| Phase 36-architecture-refactor P07 | 10 | 3 tasks | 4 files |

## Accumulated Context

### Key Decisions

(Archived to PROJECT.md Key Decisions table at v2.1 milestone completion)

**Phase 25 P02 decisions:**

- Deleted settings_screen.dart; Phase 26 patterns preserved in phase-26-handoff.md — Phase 26 rebuilds preferences/about sections inside ProfileScreen
- sharedPreferencesProvider must be overridden in ALL HomeScreen widget tests — header now watches settingsProvider for deviceName
- Profile entry points: header avatar (context.push /profile) and bottom nav tab 3 — both render ProfileScreen

**Phase 26 P01 decisions:**

- onChanged/onTap must be synchronous for test compatibility: pumpAndSettle cannot await async callbacks; fire-and-forget haptics, synchronous state updates
- FirebaseMessaging.instance wrapped in try/catch in widget build for test-safe permission hydration
- Compact tile padding (8dp vertical) and section spacing (10-16dp) needed to fit 800x600 test viewport
- ProfileNotificationsSection only calls setPushNotificationsEnabled() — appBootstrapProvider handles FCM per updated D-05

**Phase 30 P01 decisions:**

- Activity logging call sites wrapped in try/catch (not just unawaited) — FirebaseConfig.currentUser can throw in test environments; catch ensures logging failure never crashes the trigger flows
- Balance direction label uses same valueColor as amount for visual consistency; no separate muted color
- event_deleted logging deferred — no UI call site exists; will be added with deletion UI in Phase 31+

### Known Risks

- Display name propagation (IDENT-03) writes to all group participant records — scope depends on how many groups a user belongs to; Firestore batch write needed.
- FCM token management for NOTIF-02 — toggling push off requires unregistering the FCM token or storing a local preference; confirm approach during planning.

### Blockers

None.

### Roadmap Evolution

- 2026-04-26: Phase 39 added — Strip to Shippable v1: remove memories, vault, logistics, onboarding, gear, multi-currency/Thawani. See `.planning/phases/39-strip-to-shippable-v1-remove-memories-vault-logistics-onboar/39-CONTEXT.md` for the cut spec.

### Quick Tasks Completed

| # | Description | Date | Commit | Directory |
|---|-------------|------|--------|-----------|
| 260414-smu | Fix all 5 critical Firestore/Storage security vulnerabilities | 2026-04-14 | d068f6c | [260414-smu-fix-all-5-critical-firestore-storage-sec](./quick/260414-smu-fix-all-5-critical-firestore-storage-sec/) |
| 260414-t2d | Fix 7 financial/ledger bugs — split rounding, currency, edit expense, double-tap, settle-up validation | 2026-04-14 | d8c4328 | [260414-t2d-fix-7-financial-ledger-bugs-split-roundi](./quick/260414-t2d-fix-7-financial-ledger-bugs-split-roundi/) |
| 260415-9to | Fix 5 group management bugs — duplicate join, balance-gated leave/delete, awaited deletes, tab auto-select | 2026-04-15 | c07b2d4 | [260415-9to-fix-5-group-management-bugs](./quick/260415-9to-fix-5-group-management-bugs/) |
| 260415-ers | Fix 4 auth/infrastructure bugs — rethrow auth, DB init hang, lifecycle connectivity, GoRouter nav | 2026-04-15 | 6223691 | [260415-ers-fix-4-auth-infrastructure-bugs](./quick/260415-ers-fix-4-auth-infrastructure-bugs/) |
| 260415-g20 | Fix memory photos never displaying — resolve Firebase Storage download URLs in eventMemoriesProvider | 2026-04-15 | bba1a31 | [260415-g20-fix-memory-photos-never-displaying-resol](./quick/260415-g20-fix-memory-photos-never-displaying-resol/) |

## Session Continuity

Last activity: 2026-04-26 - Phase 39 complete (Strip to Shippable v1) — 7 plans, 5 waves landed across 17 commits; ~9k lines deleted; flutter analyze clean; flutter test 781/781 passing
Stopped at: context exhaustion at 100% (2026-05-12)
Next action: Release prep — manual smoke test on clean device install, firebase deploy rules+functions, JDK 21 install for rules-unit-test in CI
