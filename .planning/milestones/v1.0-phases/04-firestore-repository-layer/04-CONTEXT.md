# Phase 4: Firestore Repository Layer - Context

**Gathered:** 2026-03-26
**Status:** Ready for planning

<domain>
## Phase Boundary

All per-event module writes (expenses, settlements, gear, logistics, vault, memories, activity) flow through Firestore. The SyncService polling loop and sync_queue are deleted. Offline capability is preserved through Firestore's built-in write queue. SQLite is retained narrowly for BalanceCalculator queries. The Supabase bridge pattern is removed. Existing event data is lazily migrated from Supabase on first access.

</domain>

<decisions>
## Implementation Decisions

### Migration Strategy
- **D-01:** Module-by-module migration. Each module is a self-contained migration step, not a big-bang rewrite.
- **D-02:** Financial-first order: Expenses -> Settlements -> Gear -> SubGroups -> Vault -> Memories -> Activity. Hardest modules (money math + offline) first, then simpler modules.
- **D-03:** Hard cutover per module. When a module migrates, the old Supabase service code is deleted immediately. No dual-write period, no deprecated files. Git history preserves the old code.
- **D-04:** SyncService and sync_queue are deleted only after ALL modules are migrated, as a final cleanup step. Any module still on Supabase during migration can still use SyncService.

### Repository Abstraction
- **D-05:** Per-feature Firestore services with a shared FirestoreRepository base class. Each module gets its own service (e.g., ExpenseService) that extends/uses FirestoreRepository. The base class owns the FirebaseFirestore instance, satisfying MIG-05.
- **D-06:** Existing GroupService and EventService refactored to use the same FirestoreRepository base class for consistency.
- **D-07:** Services keep existing names (ExpenseService, GearService, etc.) — rewired internally to Firestore. Providers and screens don't change their imports.
- **D-08:** Old Supabase service files deleted immediately when a module migrates. No renaming or deprecation markers.
- **D-09:** Firestore services live inside feature folders (e.g., `lib/features/ledger/services/expense_service.dart`), matching existing codebase structure. Base class in `lib/core/services/firestore_repository.dart`.

### Firestore Data Model
- **D-10:** Module data stored as subcollections under events: `groups/{groupId}/events/{eventId}/expenses/{expenseId}`. Natural hierarchy, security rules inherit event membership check.
- **D-11:** Security rules: any event participant can read and write module data. Same trust model as current Supabase RLS. No finer-grained creator/payer restrictions.
- **D-12:** Money serialization follows Phase 1 decisions: integer fils in Firestore, Decimal conversion at the boundary. Each document carries `{amountFils: int, currency: String}`.

### Provider Migration
- **D-13:** Providers switch from SQLite-backed streams (OfflineRepository.watch*) to Firestore snapshot listeners. Real-time updates, no SQLite intermediary for reads. Matches existing GroupService/EventService pattern.

### SQLite Role
- **D-14:** SQLite retained narrowly for BalanceCalculator queries only. All other reads come from Firestore snapshots.
- **D-15:** Firestore snapshot listeners for expenses and settlements write to SQLite as a side effect, keeping BalanceCalculator data fresh.
- **D-16:** OfflineRepository slimmed down to balance-related SQLite queries only. All watch*()/save*() methods removed. Renamed to reflect its narrow purpose (e.g., BalanceCacheRepository).

### Bridge Teardown
- **D-17:** Supabase bridge removed in this phase. Once all modules use Firestore, bridge trip creation is deleted from EventService. The bridgeTripId field is removed from EventModel.
- **D-18:** Existing events with Supabase data are lazily migrated on access. When a user opens an event, if module data doesn't exist in Firestore, pull from Supabase via bridgeTripId and write to Firestore. Only migrates data that's actually used.

### Claude's Discretion
- FirestoreRepository base class design (abstract class, mixin, or utility)
- Firestore snapshot listener implementation details (stream transformers, error handling)
- SQLite write strategy from Firestore listeners (batch vs individual inserts)
- Lazy migration implementation (migration service, error handling, progress tracking)
- Security rule implementation details for module subcollections
- BalanceCalculator interface changes (if any) to work with new SQLite schema
- ConnectivityNotifier changes (currently pings Supabase to check online status)
- CacheService cleanup scope (which methods to keep/remove)
- Exact order within the financial cluster (expenses before settlements, or together)

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Phase 1 decisions (money + auth + testing)
- `.planning/phases/01-data-foundation/1-CONTEXT.md` — Money serialization (D-01..D-04), dual auth (D-05..D-07), emulator config (D-08..D-11), security rules (D-14..D-15)

### Phase 3 decisions (events + bridge)
- `.planning/phases/03-events/03-CONTEXT.md` — Event creation flow, Supabase bridge pattern (D-22), Firestore data model for events (D-29..D-33), offline behavior (D-37..D-38)

### Migration requirements
- `.planning/REQUIREMENTS.md` lines 48-56 — MIG-01 through MIG-07 acceptance criteria

### Existing Supabase services (to be migrated)
- `lib/features/ledger/providers/expense_provider.dart` — ExpenseService with Supabase CRUD
- `lib/features/ledger/services/settlement_service.dart` — SettlementService with Supabase CRUD
- `lib/features/gear/providers/gear_provider.dart` — GearService with Supabase CRUD
- `lib/features/logistics/providers/sub_group_provider.dart` — SubGroupService with Supabase CRUD
- `lib/features/vault/providers/document_provider.dart` — DocumentService with Supabase Storage
- `lib/features/memories/services/memory_service.dart` — MemoryService with Supabase Storage
- `lib/features/activity/services/activity_service.dart` — ActivityService with Supabase CRUD

### Existing Firestore services (to be refactored to base class)
- `lib/features/groups/providers/group_provider.dart` — GroupService using Firestore directly
- `lib/features/events/services/event_service.dart` — EventService using Firestore directly + bridge

### Sync infrastructure (to be removed)
- `lib/core/services/sync_service.dart` — SyncService with queue-based upload/download
- `lib/core/services/offline_repository.dart` — OfflineRepository with reactive SQLite streams
- `lib/core/services/cache_service.dart` — CacheService for batch SQLite reads/writes

### Balance computation (to be preserved)
- `lib/features/ledger/services/balance_calculator.dart` or equivalent — BalanceCalculator reads from SQLite

### Security rules
- `security/firestore.rules` — Existing Firestore rules for groups and events

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `FirebaseConfig` (`lib/core/config/firebase_config.dart`): Already provides `FirebaseConfig.firestore` singleton — base class can use this
- `EventService`: Established pattern for Firestore service with test constructor (`withFirestore`), `_db` field, and fire-and-forget bridge — template for all new services
- `GroupService`: Another working Firestore service pattern with batch writes
- `MoneySerializer` (from Phase 1): Integer fils conversion at Firestore boundary — reuse for all financial module writes
- `fake_cloud_firestore`: Test infrastructure established in Phase 1 — all new services get the same testing pattern

### Established Patterns
- **Feature-first structure**: Services live inside `lib/features/{name}/services/` or `lib/features/{name}/providers/`
- **Riverpod providers**: `StreamProvider.family<T, String>` for per-trip/event data streams — same pattern works with Firestore snapshots
- **Firestore offline persistence**: Already enabled in Phase 1 — writes queue automatically when offline
- **Test constructor pattern**: `ServiceName.withFirestore(db)` for injecting FakeFirebaseFirestore in tests

### Integration Points
- **Providers**: Each migrated module's StreamProvider switches from `offlineRepositoryProvider.watch*()` to Firestore snapshot stream
- **BalanceCalculator**: Continues reading from SQLite — Firestore listeners write expense/settlement data to SQLite as side effect
- **EventCommandCenter**: Currently uses `bridgeTripId` to pass to module screens — after migration, module screens use event ID to query Firestore subcollections directly
- **ConnectivityNotifier**: Currently pings Supabase — needs to switch to Firestore-based connectivity check

</code_context>

<specifics>
## Specific Ideas

No specific requirements — open to standard approaches. The key concern is maintaining financial precision through the migration (integer fils, Decimal at boundary) and ensuring offline writes work seamlessly via Firestore's built-in queue.

</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope.

</deferred>

---

*Phase: 04-firestore-repository-layer*
*Context gathered: 2026-03-26*
