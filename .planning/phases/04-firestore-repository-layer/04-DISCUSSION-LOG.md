# Phase 4: Firestore Repository Layer - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-03-26
**Phase:** 04-firestore-repository-layer
**Areas discussed:** Migration Strategy, Repository Abstraction, SQLite Role, Bridge Teardown

---

## Migration Strategy

| Option | Description | Selected |
|--------|-------------|----------|
| Module-by-module | Migrate one module at a time. Lower risk, testable at each step. | ✓ |
| Big-bang rewrite | Rewrite all services in one pass. Faster but riskier. | |
| Domain clusters | Group related modules into 3 migration waves. | |

**User's choice:** Module-by-module
**Notes:** None

### Migration Order

| Option | Description | Selected |
|--------|-------------|----------|
| Financial first | Expenses → Settlements → Gear → SubGroups → Vault → Memories → Activity | ✓ |
| Simplest first | Activity → Memories → Vault → Gear → SubGroups → Settlements → Expenses | |
| You decide | Claude picks optimal order | |

**User's choice:** Financial first

### Cutover Approach

| Option | Description | Selected |
|--------|-------------|----------|
| Hard cutover per module | Delete old Supabase code immediately when module migrates | ✓ |
| Dual-write transition | Write to both Supabase and Firestore during migration | |
| You decide | Claude picks per module | |

**User's choice:** Hard cutover per module

### SyncService Removal Timing

| Option | Description | Selected |
|--------|-------------|----------|
| Delete after all modules done | SyncService stays until last module migrates | ✓ |
| Incremental removal | Remove sync_queue entries per module | |
| You decide | Claude decides | |

**User's choice:** Delete after all modules done

---

## Repository Abstraction

### Firestore Access Structure

| Option | Description | Selected |
|--------|-------------|----------|
| Single FirestoreRepository class | One class with all module methods | |
| Per-feature services + shared base | Per-feature services extend FirestoreRepository base | ✓ |
| Facade over per-feature services | Thin facade delegating to per-feature services | |

**User's choice:** Per-feature services + shared base

### Existing Service Refactoring

| Option | Description | Selected |
|--------|-------------|----------|
| Refactor to use base | GroupService and EventService get FirestoreRepository base | ✓ |
| Leave as-is | Only new module services use the base | |
| You decide | Claude decides | |

**User's choice:** Refactor to use base

### Provider Pattern

| Option | Description | Selected |
|--------|-------------|----------|
| Firestore snapshot streams | Providers listen to Firestore snapshots directly | ✓ |
| Keep SQLite-backed streams | Firestore writes populate SQLite, providers read from SQLite | |
| You decide | Claude picks per module | |

**User's choice:** Firestore snapshot streams

### File Structure

| Option | Description | Selected |
|--------|-------------|----------|
| Inside feature folders | Services in lib/features/{name}/services/, base in lib/core/ | ✓ |
| Centralized in core | All Firestore services in lib/core/services/firestore/ | |
| You decide | Claude picks | |

**User's choice:** Inside feature folders

### Old Service Cleanup

| Option | Description | Selected |
|--------|-------------|----------|
| Delete immediately | Remove old Supabase service when module migrates | ✓ |
| Keep deprecated until Phase 7 | Rename to _deprecated, remove in Phase 7 | |

**User's choice:** Delete immediately

### Firestore Data Model

| Option | Description | Selected |
|--------|-------------|----------|
| Subcollections under events | groups/{gId}/events/{eId}/expenses/{xId} | ✓ |
| Top-level collections | expenses/{xId} with eventId field | |
| You decide | Claude picks | |

**User's choice:** Subcollections under events

### Security Rules

| Option | Description | Selected |
|--------|-------------|----------|
| Any participant can write | Same trust model as current Supabase RLS | ✓ |
| Creator + payer only write | Finer-grained restrictions | |
| You decide | Claude decides | |

**User's choice:** Any participant can write

### Service Naming

| Option | Description | Selected |
|--------|-------------|----------|
| Keep same names | ExpenseService stays ExpenseService, rewired to Firestore | ✓ |
| New names | ExpenseFirestoreService replaces ExpenseService | |

**User's choice:** Keep same names

---

## SQLite Role

### Purpose After Migration

| Option | Description | Selected |
|--------|-------------|----------|
| BalanceCalculator only | SQLite only powers balance queries | ✓ |
| BalanceCalculator + full read cache | SQLite as parallel read cache for all modules | |
| Remove SQLite entirely | Drop SQLite, rewrite BalanceCalculator | |

**User's choice:** BalanceCalculator only

### Sync Method

| Option | Description | Selected |
|--------|-------------|----------|
| Listener side-effect | Firestore listener writes to SQLite on every update | ✓ |
| On-demand rebuild | BalanceCalculator fetches and caches on demand | |
| You decide | Claude picks | |

**User's choice:** Listener side-effect

### OfflineRepository Future

| Option | Description | Selected |
|--------|-------------|----------|
| Slim down and keep | Remove watch*/save*, keep balance queries, rename | ✓ |
| Remove entirely | Delete, BalanceCalculator reads via CacheService | |
| You decide | Claude decides | |

**User's choice:** Slim down and keep

---

## Bridge Teardown

### Removal Timing

| Option | Description | Selected |
|--------|-------------|----------|
| Remove in this phase | Delete bridge once all modules use Firestore | ✓ |
| Keep until Phase 7 | Bridge stays as fallback until Supabase fully removed | |
| Remove writes, keep field | Stop creating bridge trips, keep bridgeTripId field | |

**User's choice:** Remove in this phase

### Existing Event Data

| Option | Description | Selected |
|--------|-------------|----------|
| Migrate on access | Lazy migration — pull from Supabase when user opens event | ✓ |
| Batch migrate all | Eager migration on app update | |
| Defer to Phase 7 | Existing data stays in Supabase | |

**User's choice:** Migrate on access

---

## Claude's Discretion

- FirestoreRepository base class design
- Firestore snapshot listener implementation details
- SQLite write strategy from listeners
- Lazy migration implementation
- Security rule details for module subcollections
- BalanceCalculator interface adjustments
- ConnectivityNotifier migration
- CacheService cleanup scope

## Deferred Ideas

None — discussion stayed within phase scope.
