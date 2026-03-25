# Architecture Patterns

**Domain:** Group + event coordination app with cross-event financial ledger
**Researched:** 2026-03-26
**Overall confidence:** HIGH (Firestore data modeling) / MEDIUM (dual-cache integration specifics)

---

## Context: What We're Replacing and Why

The current architecture is a manual sync pipeline:

```
Supabase (PostgreSQL + RLS) ← SyncService → SQLite → OfflineRepository → Riverpod Providers → UI
```

The pain points driving migration: RLS needed 4 fix migrations, Supabase Realtime subscriptions proved unreliable, and there is no concept of a persistent group above the trip level.

Firebase Firestore fixes all three: path-based security rules are simpler than row-level SQL predicates, Firestore's built-in snapshot listeners are the canonical realtime mechanism with no separate Realtime product to manage, and the document model naturally expresses groups that contain events.

---

## Recommended Architecture

### System Overview

```
Firebase Firestore ←→ Firestore SDK (offline cache, listeners) ←→ FirestoreRepository
                                                                         ↓
                                                                   SQLiteCache (structured local reads)
                                                                         ↓
                                                                   OfflineRepository (reactive streams)
                                                                         ↓
                                                                   Riverpod Providers
                                                                         ↓
                                                                          UI
```

Two caches exist simultaneously:
- **Firestore SDK cache** (LevelDB-backed, 40 MB default): handles write queuing offline, auto-sync on reconnect, Firestore listener continuity
- **SQLite** (existing safar_cache.db): provides structured, queryable local reads for balance calculations, settlement logic, and fast initial renders without waiting for Firestore listeners

The Firestore SDK cache is not a replacement for SQLite — they serve different roles. Firestore's cache does not support arbitrary SQL queries, aggregate functions, or indexed lookups across collections. SQLite fills that gap.

---

## Firestore Collection Structure

### Top-Level Collections

```
/groups/{groupId}
/users/{userId}
```

Everything except user profiles lives under groups. There is no top-level events or trips collection — events are always scoped to a group.

### Group Document

```
/groups/{groupId}
  id:           string
  name:         string
  inviteCode:   string            -- short code for joining
  createdBy:    string            -- Firebase UID of creator
  memberIds:    string[]          -- Firebase UIDs, used in security rules
  currency:     string            -- default 'OMR'
  createdAt:    Timestamp
  updatedAt:    Timestamp
```

`memberIds` is the security rule anchor. Every read/write to any subcollection under a group checks `resource.data.memberIds.contains(request.auth.uid)` — or for subcollections, uses `get(/databases/$(database)/documents/groups/$(groupId)).data.memberIds.contains(request.auth.uid)`. This is the replacement for Supabase RLS.

### Members Subcollection

```
/groups/{groupId}/members/{memberId}
  id:           string            -- participant record ID (not Firebase UID)
  userId:       string?           -- Firebase UID if claimed, null if unclaimed
  displayName:  string
  role:         string            -- 'LEADER' | 'MEMBER'
  joinedAt:     Timestamp
  isShadow:     bool              -- unclaimed slot
```

This preserves the existing name-based participant model. `userId` is null until someone joins and claims the slot. Members subcollection is the source of truth for who's in the group; `memberIds` on the parent document is a denormalized index for security rules and fast membership checks.

### Events Subcollection

```
/groups/{groupId}/events/{eventId}
  id:             string
  name:           string
  type:           string          -- 'TRIP' | 'CAMPING' | 'DAY_OUT' | 'NIGHT_OUT' | 'TRAVEL' | 'CUSTOM'
  icon:           string
  currency:       string
  startDate:      Timestamp?
  endDate:        Timestamp?
  modules:        map             -- { ledger: bool, gear: bool, logistics: bool, vault: bool, ... }
  templateApplied: bool           -- whether template presets have been seeded
  status:         string          -- 'UPCOMING' | 'ACTIVE' | 'COMPLETED'
  createdBy:      string
  createdAt:      Timestamp
  updatedAt:      Timestamp
```

Events replace what is currently called `trips`. The `modules` map drives which CommandCenter cards appear — same concept as `TripModules` today. The `type` field determines which template presets are seeded when the event is first created.

### Event Subcollections (Module Data)

All live under `/groups/{groupId}/events/{eventId}/`:

```
expenses/{expenseId}
  id:                   string
  eventId:              string
  groupId:              string     -- denormalized for collection group queries
  payerMemberId:        string
  amount:               string     -- stored as string, Decimal precision
  description:          string?
  categoryId:           string?
  categoryName:         string?
  scope:                string     -- 'GLOBAL' | 'SUB_GROUP' | 'PERSONAL' | 'CUSTOM'
  subGroupId:           string?
  isDeleted:            bool
  deletedAt:            Timestamp?
  createdAt:            Timestamp

settlements/{settlementId}
  id:                   string
  eventId:              string
  groupId:              string     -- denormalized
  payerMemberId:        string
  recipientMemberId:    string
  amount:               string
  currency:             string
  note:                 string?
  isDeleted:            bool
  deletedAt:            Timestamp?
  settledAt:            Timestamp

gearItems/{itemId}
  id:                   string
  itemName:             string
  assignedTo:           string?
  assignedToName:       string?
  isPacked:             bool
  sequenceId:           int
  isHighPriority:       bool
  isDeleted:            bool
  deletedAt:            Timestamp?
  createdAt:            Timestamp

subGroups/{subGroupId}
  id:                   string
  name:                 string
  type:                 string     -- 'CAR'
  capacity:             int
  memberIds:            string[]   -- participant IDs in this sub-group
  createdAt:            Timestamp

categories/{categoryId}
  id:                   string
  name:                 string
  icon:                 string?

activityLogs/{logId}
  id:                   string
  actorId:              string?
  actorName:            string?
  category:             string
  eventType:            string
  logText:              string
  metadata:             map?
  createdAt:            Timestamp
```

### Group-Level Ledger (Cross-Event Balances)

This is the killer feature — running balances that accumulate across all events in a group.

```
/groups/{groupId}/groupLedger/{entryId}
  memberId:         string
  counterpartyId:   string
  netAmount:        string      -- positive = counterparty owes member, negative = member owes counterparty
  currency:         string
  lastUpdatedAt:    Timestamp
  eventId:          string      -- which event generated the last change
```

**Implementation approach:** Write-time aggregation using Firestore transactions. When a settlement is recorded at the event level, a transaction atomically writes the settlement document AND updates the relevant `groupLedger` entries for the two participants. This avoids expensive read-time aggregation across all events' settlements.

The group ledger does NOT duplicate individual expense records — it only maintains the net balance between each pair of members. Balance calculation (the greedy min-transactions algorithm) runs locally against the group ledger entries, not against raw expenses.

### Invite Codes Index (Top-Level)

```
/inviteCodes/{code}
  groupId:    string
  createdAt:  Timestamp
```

Flat collection at root level. Used to resolve invite codes to group IDs without requiring a collection group query or a full scan. Joiners look up their code here, then access the group. Security rules allow unauthenticated reads (invite code lookup is intentionally public; the group itself is private).

---

## Security Rules Structure

Rules replace Supabase RLS entirely. The pattern is path-based:

```
match /databases/{database}/documents {

  // Invite codes are public for lookup
  match /inviteCodes/{code} {
    allow read: if true;
    allow write: if request.auth != null;
  }

  match /groups/{groupId} {
    // Helper function: is the caller a member of this group?
    function isMember() {
      return request.auth != null &&
             request.auth.uid in resource.data.memberIds;
    }

    allow read: if isMember();
    allow create: if request.auth != null;
    allow update: if isMember();
    allow delete: if false; // groups don't get deleted

    // All subcollections use group-level membership
    match /{subcollection}/{docId} {
      allow read, write: if request.auth != null &&
        get(/databases/$(database)/documents/groups/$(groupId))
          .data.memberIds.contains(request.auth.uid);
    }
  }
}
```

**Performance note:** The `get()` call in subcollection rules costs one extra read per operation. This is unavoidable when membership data lives on the parent document. The alternative (duplicating `memberIds` into every subcollection document) creates consistency hazards when membership changes. Accept the extra read; Firestore caches the result within a single rule evaluation batch.

---

## SQLite Cache Mapping

The existing `LocalDatabase` tables map directly to the new Firestore structure. The migration adds two new tables and renames one concept:

| Existing SQLite Table | New Name / Status | Maps to Firestore Path |
|-----------------------|-------------------|------------------------|
| `trips` | rename to `events`, add `groupId` + `eventType` columns | `/groups/{g}/events/{e}` |
| `expenses` | add `groupId` column | `/groups/{g}/events/{e}/expenses/{id}` |
| `settlements` | add `groupId` column | `/groups/{g}/events/{e}/settlements/{id}` |
| `gear_items` | unchanged | `/groups/{g}/events/{e}/gearItems/{id}` |
| `participants` | rename to `members`, add `userId` column | `/groups/{g}/members/{id}` |
| `sub_groups` | unchanged | `/groups/{g}/events/{e}/subGroups/{id}` |
| `sub_group_members` | unchanged | embedded in `subGroups.memberIds` |
| `activity_logs` | unchanged | `/groups/{g}/events/{e}/activityLogs/{id}` |
| `categories` | unchanged | `/groups/{g}/events/{e}/categories/{id}` |
| `sync_queue` | **remove** | replaced by Firestore SDK write queue |
| — | **add** `groups` | `/groups/{g}` |
| — | **add** `group_ledger` | `/groups/{g}/groupLedger/{id}` |

**Why keep SQLite at all?** Firestore's built-in offline cache (40 MB default, LevelDB-backed) does not support arbitrary SQL queries. The balance calculator runs SQL aggregate queries against SQLite. Settlement optimization reads all expenses and settlements for an event in one structured query. Fetching raw Firestore documents and doing balance math in-memory every render would be slower and harder to test. SQLite remains the structured query layer; Firestore's cache handles write buffering and sync.

**Cache population:** Firestore snapshot listeners write incoming documents into SQLite. The `FirestoreRepository` (new class) owns this pipeline — it sets up listeners, maps Firestore documents to SQLite rows, and calls `OfflineRepository.notifyChange()` to trigger reactive stream re-emission. This is the same pattern as the current `SyncService._pull*()` methods, but driven by push (Firestore listeners) rather than pull (manual downloads).

---

## Data Flow

### Read Path (Online or Offline)

```
1. Provider subscribes to OfflineRepository.watch*()
2. OfflineRepository emits current SQLite data immediately (no latency)
3. In parallel, FirestoreRepository has active snapshot listener on Firestore
4. Firestore listener fires (from server or SDK cache)
5. FirestoreRepository writes document to SQLite
6. FirestoreRepository calls repo.notifyChange(table, contextId)
7. OfflineRepository re-emits updated data from SQLite
8. Provider updates, UI rebuilds
```

When offline, steps 4-7 still happen — the Firestore SDK serves the listener from its local LevelDB cache. SQLite always has the most recent data that was loaded by any listener since app install (subject to Firestore's 40 MB eviction limit — see Pitfalls).

### Write Path (Online)

```
1. User action → OfflineRepository.save*(record)
2. OfflineRepository writes to SQLite immediately
3. OfflineRepository calls FirestoreRepository.write(document)
4. FirestoreRepository calls FirebaseFirestore.instance.collection(...).set(doc)
5. Firestore SDK queues write (auto-syncs when online)
6. notifyChange() fires → UI updates from SQLite immediately
7. When Firestore confirms write, snapshot listener fires again (no-op if unchanged)
```

### Write Path (Offline)

```
1. User action → OfflineRepository.save*(record)
2. SQLite write → immediate UI update
3. FirestoreRepository.write() → Firestore SDK queues write in its own queue
4. No sync_queue entry needed — Firestore handles this
5. On reconnect, Firestore SDK drains its queue automatically
```

The existing `sync_queue` SQLite table is retired. The Firestore SDK's offline write queue replaces it. This eliminates the `SyncService.syncPendingChanges()` polling loop.

**Auth token expiration risk:** If the device goes offline for an extended period, the Firebase anonymous auth token may expire. On reconnect, queued writes will fail with permission errors until `signInAnonymously()` re-authenticates. Mitigation: call `FirebaseAuth.instance.currentUser?.reload()` when the app foregrounds, and handle auth-refresh before enabling network.

### Cross-Event Balance Data Flow

```
Settlement recorded (event-level write):
  1. User confirms settlement in UI
  2. Firestore transaction begins:
     a. Write settlement to /groups/{g}/events/{e}/settlements/{id}
     b. Read current groupLedger entry for (payerMemberId, recipientMemberId) pair
     c. Update netAmount on groupLedger entry (atomic)
  3. Both writes complete or both fail (transaction)
  4. Snapshot listeners fire for settlements AND groupLedger
  5. SQLite updates for both tables
  6. GroupDashboard provider re-emits updated cross-event balances
```

---

## Component Boundaries

| Component | Responsibility | Communicates With |
|-----------|---------------|-------------------|
| `FirestoreRepository` | Firestore reads/writes, snapshot listener setup, document-to-SQLite mapping | Firestore SDK, `LocalDatabase`, `OfflineRepository` |
| `OfflineRepository` | Reactive SQLite streams, notify-on-change, write coordination | `LocalDatabase`, `CacheService`, `FirestoreRepository` |
| `LocalDatabase` | SQLite schema, migrations, raw db access | sqflite |
| `CacheService` | Batch read/write helpers for SQLite tables | `LocalDatabase` |
| `GroupRepository` | Group CRUD, invite code resolution, member management | `FirestoreRepository` |
| `EventRepository` | Event CRUD, template seeding, module configuration | `FirestoreRepository` |
| `LedgerService` | Expense + settlement writes (with group ledger transaction) | `FirestoreRepository`, `OfflineRepository` |
| `BalanceCalculator` | Pure logic, reads from SQLite via queries | `LocalDatabase` |
| `SyncService` | **Retire** — replaced by Firestore SDK offline queue | — |
| Riverpod Providers | Consume `OfflineRepository.watch*()` streams | `OfflineRepository` |

**Key boundary:** `FirestoreRepository` is the only component that touches `FirebaseFirestore.instance` directly. Everything above it operates through `OfflineRepository` (reactive streams from SQLite). This keeps Firestore out of providers and UI, and makes the entire state layer testable by mocking `OfflineRepository` without any Firebase dependency.

---

## Suggested Build Order

Dependencies flow strictly top-down. Each layer must be stable before the next is built.

### Layer 1 — Data Foundation (no dependencies on new features)
1. **SQLite schema migration** — add `groups`, `group_ledger` tables; add `groupId` + `eventType` to `events` (was `trips`); rename `members` table
2. **Firestore project setup** — add `cloud_firestore` package, configure `FirebaseOptions`, verify anonymous auth works with Firestore rules
3. **`FirestoreRepository`** — generic document write/read/listen, no business logic
4. **Security rules** — deploy group membership rules, test with Firebase emulator

### Layer 2 — Groups Feature (depends on Layer 1)
5. **`GroupRepository`** — create group, generate invite code, resolve invite code, join group (claim member slot), fetch group + members
6. **Group providers** — `groupsProvider`, `groupMembersProvider` using `OfflineRepository.watchGroups()`
7. **Groups UI** — group list (home screen), create group, join group flow

### Layer 3 — Events Feature (depends on Layer 2)
8. **`EventRepository`** — create event with template seeding, fetch events for group, update event modules
9. **Template engine** — maps event type to default modules + gear presets
10. **Event providers** — `groupEventsProvider`, `eventProvider`
11. **Events UI** — event list in group dashboard, create event screen, CommandCenter adapted for events

### Layer 4 — Module Migration (depends on Layer 3)
12. **`LedgerService`** — expense writes route through Firestore (replacing Supabase), settlement writes include group ledger transaction
13. **Gear, logistics, vault** — migrate each module's write path from Supabase to Firestore
14. **`FirestoreRepository` listeners** — set up per-event snapshot listeners for expenses, settlements, gear items

### Layer 5 — Cross-Event Ledger (depends on Layer 4)
15. **`groupLedger` read path** — `watchGroupLedger(groupId)` in `OfflineRepository`
16. **Cross-event balance display** — group dashboard showing running balances
17. **Cross-event settlement flow** — settle up across all events, not just one

### Layer 6 — Migration + Hardening
18. **Data migration** — export existing Supabase data, import into Firestore (user base is small, anonymous auth means no identity continuity required)
19. **Remove Supabase** — remove `supabase_flutter` dependency, retire `SyncService`, clean up `sync_queue` table
20. **Collection group query indexes** — create composite indexes for cross-group expense queries if needed

---

## Firestore Collection Group Queries

Querying expenses across all events in a group requires a collection group query:

```dart
// All non-deleted expenses in a group, across all events
FirebaseFirestore.instance
  .collectionGroup('expenses')
  .where('groupId', isEqualTo: groupId)
  .where('isDeleted', isEqualTo: false)
  .orderBy('createdAt', descending: true)
  .snapshots();
```

This requires:
1. A composite index on `(groupId, isDeleted, createdAt)` in the `expenses` collection group
2. Security rules using `match /{path=**}/expenses/{expenseId}` syntax (rules version 2)

The `groupId` field is why it gets denormalized into every expense document even though expenses are nested under an event — the collection group query needs a filterable field.

---

## Anti-Patterns to Avoid

### Anti-Pattern 1: Storing Members Only as an Array in the Group Document

**What:** Putting all member data (name, role, join date) into a `members: []` array on the group document instead of a `members` subcollection.

**Why bad:** Firestore documents have a 1 MiB size limit. Groups with many events and accumulating member history will hit this. Array updates require read-modify-write which is not atomic without a transaction. Security rules cannot filter individual array elements.

**Instead:** Use the `members/{memberId}` subcollection for member records, and keep only `memberIds: string[]` (UIDs only) on the group document for rule evaluation.

### Anti-Pattern 2: Replacing SQLite with Firestore SDK Cache Entirely

**What:** Disabling SQLite and relying solely on Firestore's 40 MB LevelDB cache for all offline reads.

**Why bad:** Firestore's cache does not support SQL queries. The balance calculator performs multi-table joins and aggregate sums. These would require loading all documents into memory and doing arithmetic in Dart, which is slower and untestable without Firestore. The eviction policy can remove old documents that are needed for balance history.

**Instead:** Maintain both caches. SQLite for structured queries and balance calculations; Firestore SDK cache for write buffering and auto-sync.

### Anti-Pattern 3: Computing Cross-Event Balances at Read Time

**What:** On the group dashboard, query all expenses and settlements from all events and compute net balances in the UI layer.

**Why bad:** An active group with 10 events and 30 participants generates hundreds of expense documents. Reading all of them on every dashboard load is expensive in both Firestore reads (billed per document) and latency.

**Instead:** Maintain the `groupLedger` subcollection as a write-time aggregation. When a settlement is recorded, a transaction updates the ledger atomically. The dashboard reads O(members^2) ledger entries, not O(all expenses).

### Anti-Pattern 4: One Firestore Listener Per Screen

**What:** Each screen sets up its own `snapshots()` listener on the same collection, then cancels it on dispose.

**Why bad:** Multiple listeners on the same path multiply Firestore reads. Teardown and re-setup on navigation causes data flicker.

**Instead:** Keep listeners alive at the `FirestoreRepository` level, scoped to the current group/event context. Providers consume the reactive SQLite streams via `OfflineRepository`, which do not involve Firestore directly.

---

## Scalability Considerations

| Concern | At 10 members | At 50 members | Notes |
|---------|---------------|---------------|-------|
| Group ledger entries | 45 pairs (n*(n-1)/2) | 1225 pairs | Manageable at both scales |
| Firestore reads per session | ~100 | ~500 | Dominated by initial listener hydration |
| SQLite query time (balance) | <5ms | <20ms | Indexed by groupId |
| Security rule get() calls | 1 per write | 1 per write | Cached within evaluation context |
| Firestore SDK cache size | Well under 40 MB | Likely under 40 MB | Large groups may need `CACHE_SIZE_UNLIMITED` |

For the target market (Oman-focused, small friend groups), scalability above 50 members per group is not a concern. The architecture handles it anyway.

---

## Sources

- [Cloud Firestore Data Model — Firebase](https://firebase.google.com/docs/firestore/data-model) — subcollection model
- [Writing conditions for Firestore Security Rules — Firebase](https://firebase.google.com/docs/firestore/security/rules-conditions) — `get()` for cross-document checks, array membership
- [Access data offline — Firebase](https://firebase.google.com/docs/firestore/manage-data/enable-offline) — 40 MB default cache, eviction policy, write queue behavior
- [Transactions and batched writes — Firebase](https://firebase.google.com/docs/firestore/manage-data/transactions) — atomic multi-document writes, 500 document limit
- [Write-time aggregations — Firebase](https://firebase.google.com/docs/firestore/solutions/aggregation) — group ledger update strategy
- [Collection group queries — Firebase blog](https://firebase.googleblog.com/2019/06/understanding-collection-group-queries.html) — cross-subcollection expense queries
- [Cloud Firestore FlutterFire — snapshot listeners](https://firebase.flutter.dev/docs/firestore/usage/) — listener patterns, offline persistence configuration
- [Secure data access for users and groups — Firebase](https://firebase.google.com/docs/firestore/solutions/role-based-access) — membership-based rule patterns
- [Offline-First Architecture in Flutter — DEV Community](https://dev.to/anurag_dev/implementing-offline-first-architecture-in-flutter-part-1-local-storage-with-conflict-resolution-4mdl) — dual-cache write-through strategy
- [GitHub discussion: Firestore cache eviction](https://github.com/firebase/firebase-ios-sdk/discussions/12277) — eviction behavior, auth token expiry risk during offline periods
