---
gsd_state_version: 1.0
milestone: v1.0
milestone_name: milestone
status: Ready to execute
stopped_at: Completed 05-02-PLAN.md (cross-event balance calculation tests)
last_updated: "2026-03-26T22:03:40.902Z"
progress:
  total_phases: 7
  completed_phases: 4
  total_plans: 25
  completed_plans: 20
---

# Project State

## Project Reference

See: .planning/PROJECT.md (updated 2026-03-26)

**Core value:** Groups persist across events and accumulate financial history — friends settle up across trips, not just within one.
**Current focus:** Phase 05 — cross-event-financials

## Current Position

Phase: 05 (cross-event-financials) — EXECUTING
Plan: 3 of 7

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
| Phase 01-data-foundation P03 | 2 | 2 tasks | 7 files |
| Phase 01 P02 | 5 | 3 tasks | 6 files |
| Phase 02-groups P00 | 3min | 2 tasks | 6 files |
| Phase 02-groups P01 | 7 | 3 tasks | 9 files |
| Phase 02-groups P02 | 5 | 3 tasks | 8 files |
| Phase 02-groups P03 | 8 | 3 tasks | 4 files |
| Phase 03-events P00 | 4 | 2 tasks | 7 files |
| Phase 03-events P01 | 6 | 2 tasks | 6 files |
| Phase 03-events P02 | 5 | 2 tasks | 4 files |
| Phase 03-events P03 | 6 | 2 tasks | 4 files |
| Phase 03-events P04 | 7 | 2 tasks | 6 files |
| Phase 04-firestore-repository-layer P00 | 5 | 2 tasks | 18 files |
| Phase 04-firestore-repository-layer P01 | 8 | 2 tasks | 6 files |
| Phase 04-firestore-repository-layer P02 | 10 | 2 tasks | 11 files |
| Phase 04-firestore-repository-layer P03 | 9 | 2 tasks | 13 files |
| Phase 04 P04 | 90m | 2 tasks | 18 files |
| Phase 04-firestore-repository-layer P05 | 65 | 3 tasks | 25 files |
| Phase 05 P00 | 2 | 2 tasks | 6 files |
| Phase 05 P02 | 3 | 1 tasks | 1 files |

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
- [Phase 01-data-foundation]: memberIds is an array on group document — rules use in operator for O(1) membership check, no cross-document get() for group itself (D-14)
- [Phase 01-data-foundation]: Group delete blocked unconditionally (allow delete: if false) — groups are persistent cross-event constructs
- [Phase 01-data-foundation]: inviteCodes collection is publicly readable for join flow — authenticated write only
- [Phase 01]: decimal v3 division returns Rational not Decimal -- call .toDecimal(scaleOnInfinitePrecision: 10) at the Firestore read boundary
- [Phase 01]: sqflite_common_ffi added as dev dependency to enable in-memory SQLite testing on macOS/Linux/Windows
- [Phase 02-groups]: memberIds stored as List<String> array in Firestore and JSON-encoded in SQLite per D-14
- [Phase 02-groups]: GroupMember role field is String not enum (CREATOR/MEMBER) for forward-compatible Firestore serialization
- [Phase 02-groups]: Home screen fully replaces trip-based layout — no legacy trip UI retained
- [Phase 02-groups]: group/:id detail route registered as scaffold placeholder until Plan 03
- [Phase 02-groups]: Firebase currentUser access wrapped in try-catch for test safety — allows widget tests without Firebase initialization
- [Phase 02-groups]: GoRouter nested routes used for /group/:id/settings — consistent with GoRouter patterns while Navigator.push used within-screen for settings from GroupDetailScreen
- [Phase 03-events]: EventModules constructor does not force ledger=true — preset types enforce via forType(), Custom toggles via copyWith per D-14
- [Phase 03-events]: bridgeTripId falls back to doc.id — Supabase bridge always has valid trip ID for incremental field adoption
- [Phase 03-events]: EventService.withFirestore test constructor sets _skipBridgeInTest=true so gear seeding can be verified without Supabase initialization
- [Phase 03-events]: Supabase isAuthenticated check wrapped in try-catch to handle uninitialized Supabase in test/Firebase-only environments
- [Phase 03-events]: pull-to-refresh uses ref.invalidate(userGroupsProvider) not ref.refresh — invalidate closes and reopens the Firestore stream subscription for fresh fetch
- [Phase 03-events]: Custom event module overrides require optional modules param on EventService.createEvent — service now accepts modules override; null falls back to EventModules.forType(type)
- [Phase 03-events]: EventCard is ConsumerWidget to watch tripExpensesProvider(bridgeTripId) for live financial totals
- [Phase 03-events]: GroupDetailScreen FAB always visible (unconditional) — creating events valid regardless of loading state
- [Phase 03-events]: Trip facade used in EventCommandCenter: event.bridgeTripId as Trip.id, event.modules.vault mapped to TripModules.docs
- [Phase 03-events]: EventModuleList checks event.modules.ledger (not hardcoded) to support Custom type ledger toggle per D-14
- [Phase 04-00]: Expense.currency is a computed getter defaulting to 'OMR' -- existing model has no currency field, avoids breaking change while enabling MoneySerializer
- [Phase 04-00]: Module subcollection security uses nested match /{module}/{docId} under match /events/{eventId} -- functionally equivalent to flat path, Firestore canonical syntax
- [Phase 04-00]: SubGroup.fromFirestore returns members: const [] -- members are in a separate subcollection, not inlined in the document
- [Phase 04-01]: asyncMap used over listen() for SQLite side-write: keeps stream pipeline intact, ensures SQLite writes complete before downstream subscribers receive data
- [Phase 04-01]: CacheService.cacheExpenses/cacheSettlements used as interim until BalanceCacheRepository created in 04-04
- [Phase 04-01]: tripExpensesProvider/tripSettlementsProvider kept as deprecated shims -- screen migration deferred to 04-05
- [Phase 04-02]: EventRef typedef created in plan 04-02 (parallel to 04-01) — both wave-2 plans define identical content; no conflict
- [Phase 04-02]: gear_screen.dart legacy mutations routed to OfflineRepository — screen still on SQLite path, EventRef migration deferred to future plan
- [Phase 04-02]: logistics_screen.dart write operations stubbed with debugPrint — SubGroupService now requires EventRef; screen update deferred to EventRef migration plan
- [Phase Phase 04-03]: Document.fileUrl maps to storagePath in Firestore — backward compat with existing screen code
- [Phase Phase 04-03]: tripDocumentsProvider and tripMemoriesProvider kept as deprecated shims — screen migration deferred to EventRef migration plan
- [Phase Phase 04-03]: LazyMigrationService catches SupabaseConfig.isAuthenticated in try-catch per Phase 03 pattern
- [Phase 04]: BalanceCacheRepository replaces OfflineRepository for balance query path — narrow SQLite wrapper, no stream subscriptions to manage
- [Phase 04]: Firestore Source.server ping replaces Supabase auth.refreshSession for connectivity detection
- [Phase 04]: FirestoreRepository.withFirestore uses @protected so subclasses can call super.withFirestore without lint warnings (MIG-05)
- [Phase 04]: Camping gear seeding is now unconditional (not gated on Supabase bridge success)
- [Phase 04-firestore-repository-layer]: Removed tripBalancesProvider entirely — its only consumers were tests for the deleted Trip-based CommandCenter widget
- [Phase 04-firestore-repository-layer]: expense_provider.dart re-exports event_ref.dart so screens get EventRef transitively without redundant imports
- [Phase 05]: D-06 confirmed: BalanceCalculator handles combined multi-event expense lists without code changes — expense list is scope-agnostic, tripId on Expense is irrelevant to balance math

### Pending Todos

None yet.

### Blockers/Concerns

- Firebase Emulator configuration does not yet exist in the repo (firebase.json, emulator port config) — must be created in Phase 1 before any security rules are written
- GoRouter 13.x to 17.x migration risk is MEDIUM confidence — validate against breaking changes before Phase 2 adds new group/event routes
- Group invite code format (length, collision strategy) needs a product decision before Phase 2 implementation begins
- Dual-cache conflict resolution for offline-written expenses not yet confirmed — needs explicit handling in Phase 4

## Session Continuity

Last session: 2026-03-26T22:03:40.900Z
Stopped at: Completed 05-02-PLAN.md (cross-event balance calculation tests)
Resume file: None
