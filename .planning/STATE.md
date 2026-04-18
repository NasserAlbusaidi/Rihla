---
gsd_state_version: 1.0
milestone: v2.4
milestone_name: Technical Debt & Dark Theme
status: executing
stopped_at: Phase 38 context gathered
last_updated: "2026-04-18T11:33:33.968Z"
last_activity: 2026-04-18
progress:
  total_phases: 17
  completed_phases: 15
  total_plans: 47
  completed_plans: 48
  percent: 100
---

# Project State

## Project Reference

See: .planning/PROJECT.md (updated 2026-04-01)

**Core value:** Groups persist across events and accumulate financial history — friends settle up across trips, not just within one.
**Current focus:** Phase 37 — dark-theme-migration

## Current Position

Milestone: v2.4 Technical Debt & Dark Theme — ACTIVE
Phase: 38
Plan: Not started
Status: Ready to execute
Last activity: 2026-04-18

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

### Quick Tasks Completed

| # | Description | Date | Commit | Directory |
|---|-------------|------|--------|-----------|
| 260414-smu | Fix all 5 critical Firestore/Storage security vulnerabilities | 2026-04-14 | d068f6c | [260414-smu-fix-all-5-critical-firestore-storage-sec](./quick/260414-smu-fix-all-5-critical-firestore-storage-sec/) |
| 260414-t2d | Fix 7 financial/ledger bugs — split rounding, currency, edit expense, double-tap, settle-up validation | 2026-04-14 | d8c4328 | [260414-t2d-fix-7-financial-ledger-bugs-split-roundi](./quick/260414-t2d-fix-7-financial-ledger-bugs-split-roundi/) |
| 260415-9to | Fix 5 group management bugs — duplicate join, balance-gated leave/delete, awaited deletes, tab auto-select | 2026-04-15 | c07b2d4 | [260415-9to-fix-5-group-management-bugs](./quick/260415-9to-fix-5-group-management-bugs/) |
| 260415-ers | Fix 4 auth/infrastructure bugs — rethrow auth, DB init hang, lifecycle connectivity, GoRouter nav | 2026-04-15 | 6223691 | [260415-ers-fix-4-auth-infrastructure-bugs](./quick/260415-ers-fix-4-auth-infrastructure-bugs/) |
| 260415-g20 | Fix memory photos never displaying — resolve Firebase Storage download URLs in eventMemoriesProvider | 2026-04-15 | bba1a31 | [260415-g20-fix-memory-photos-never-displaying-resol](./quick/260415-g20-fix-memory-photos-never-displaying-resol/) |

## Session Continuity

Last activity: 2026-04-15 - Completed quick task 260415-g20: Fix memory photos never displaying
Stopped at: Phase 38 context gathered
Next action: Continue with remaining review items or update 05-broken-features.md
