---
gsd_state_version: 1.0
milestone: v1.0
milestone_name: milestone
status: unknown
stopped_at: Completed 01-01-PLAN.md (Firebase deps upgrade + dual-auth bootstrap + behavioral tests)
last_updated: "2026-03-25T21:18:37.691Z"
progress:
  total_phases: 7
  completed_phases: 0
  total_plans: 3
  completed_plans: 1
---

# Project State

## Project Reference

See: .planning/PROJECT.md (updated 2026-03-26)

**Core value:** Groups persist across events and accumulate financial history — friends settle up across trips, not just within one.
**Current focus:** Phase 01 — data-foundation

## Current Position

Phase: 01 (data-foundation) — EXECUTING
Plan: 2 of 3

## Performance Metrics

**Velocity:**

- Total plans completed: 0
- Average duration: -
- Total execution time: 0 hours

**By Phase:**

| Phase | Plans | Total | Avg/Plan |
|-------|-------|-------|----------|
| - | - | - | - |

**Recent Trend:**

- Last 5 plans: -
- Trend: -

*Updated after each plan completion*
| Phase 01 P01 | 6 | 3 tasks | 6 files |

## Accumulated Context

### Decisions

Decisions are logged in PROJECT.md Key Decisions table.
Recent decisions affecting current work:

- [Pre-Phase 1]: Store all OMR amounts as integer fils in Firestore (MoneySerializer boundary); no Firestore doubles for money
- [Pre-Phase 1]: Firestore SDK cache is the read authority; SQLite populated as side effect of listener events only — never write to SQLite as the primary write path
- [Pre-Phase 1]: Group membership stored as map field on group document (`members: { uid: role }`) to avoid cross-document get() calls in security rules (10-get limit)
- [Pre-Phase 1]: Riverpod stays on 2.x for this milestone — Riverpod 3.x migration is a separate future milestone
- [Pre-Phase 1]: SyncService is deleted, not ported — Firestore offline persistence replaces the polling sync queue
- [Pre-Phase 1]: Group-level balance computed client-side from per-event summaries in SQLite — no single aggregation document that would create a write hotspot
- [Phase 01]: firebase_messaging bumped to ^16.1.3 — firebase_messaging 15.x is incompatible with firebase_core 4.x (transitive firebase_core_platform_interface conflict)
- [Phase 01]: FirebaseConfig static class mirrors SupabaseConfig pattern — consistent dual-auth config across the app

### Pending Todos

None yet.

### Blockers/Concerns

- Firebase Emulator configuration does not yet exist in the repo (firebase.json, emulator port config) — must be created in Phase 1 before any security rules are written
- GoRouter 13.x to 17.x migration risk is MEDIUM confidence — validate against breaking changes before Phase 2 adds new group/event routes
- Group invite code format (length, collision strategy) needs a product decision before Phase 2 implementation begins
- Dual-cache conflict resolution for offline-written expenses not yet confirmed — needs explicit handling in Phase 4

## Session Continuity

Last session: 2026-03-25T21:18:37.689Z
Stopped at: Completed 01-01-PLAN.md (Firebase deps upgrade + dual-auth bootstrap + behavioral tests)
Resume file: None
