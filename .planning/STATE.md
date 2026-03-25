# Project State

## Project Reference

See: .planning/PROJECT.md (updated 2026-03-26)

**Core value:** Groups persist across events and accumulate financial history — friends settle up across trips, not just within one.
**Current focus:** Phase 1 — Data Foundation

## Current Position

Phase: 1 of 7 (Data Foundation)
Plan: 0 of TBD in current phase
Status: Ready to plan
Last activity: 2026-03-26 — Roadmap created; 7 phases derived from 41 v1 requirements

Progress: [░░░░░░░░░░] 0%

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

### Pending Todos

None yet.

### Blockers/Concerns

- Firebase Emulator configuration does not yet exist in the repo (firebase.json, emulator port config) — must be created in Phase 1 before any security rules are written
- GoRouter 13.x to 17.x migration risk is MEDIUM confidence — validate against breaking changes before Phase 2 adds new group/event routes
- Group invite code format (length, collision strategy) needs a product decision before Phase 2 implementation begins
- Dual-cache conflict resolution for offline-written expenses not yet confirmed — needs explicit handling in Phase 4

## Session Continuity

Last session: 2026-03-26
Stopped at: Roadmap created; ready to plan Phase 1
Resume file: None
