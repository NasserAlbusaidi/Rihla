# Domain Pitfalls

**Domain:** Flutter app — Supabase-to-Firestore migration + groups/events/cross-event financial tracking
**Researched:** 2026-03-26
**Project:** Rihla v2

---

## Critical Pitfalls

Mistakes that cause rewrites, data loss, or security incidents.

---

### Pitfall 1: Treating Firestore Like a Relational Database

**What goes wrong:** Migrating the Supabase schema table-by-table into Firestore collections, keeping normalized joins. Queries that were a single SQL JOIN (`participants!payer_participant_id(*)`) become multiple round-trip document reads with no equivalent of foreign-key traversal.

**Why it happens:** The existing code does joined selects throughout `sync_service.dart`: `expenses.select('*, expense_categories(name, icon), participants!payer_participant_id(*)')`. The instinct is to preserve the same row shape. Firestore has no joins. Every relationship must be resolved in application code or denormalized at write time.

**Consequences:** N+1 document reads on every screen load. Expense list with 30 items and 8 participants becomes 30+ reads. Realtime listeners multiplied across every related subcollection. Costs explode and UI is slow.

**Prevention:**
- Map the full read surface before writing a single Firestore document. For each screen, list what data it needs and how many documents that requires.
- Denormalize: embed `payerName` and `payerParticipantId` directly on the expense document. The name is already display-only and name-based (no profile joins needed — this is already how Rihla works).
- Accept that some data will be duplicated. The alternative is worse.
- Structure document shape around screen requirements, not around avoiding duplication.

**Detection:** If any screen requires more than 2 document reads before it can render, the model is still relational.

**Phase:** Firestore data modeling phase — must be addressed before writing any Firestore service code.

---

### Pitfall 2: Storing Money as Firestore Doubles

**What goes wrong:** Firestore's numeric type is IEEE 754 double-precision floating point. Writing `amount: 15.500` from a Dart `double` loses precision. `FieldValue.increment()` on decimal values produces incorrect sums. This is confirmed as a known Firestore bug (flutterfire issue #9626: "Number field without decimals is integer if posted from web and double from native").

**Why it happens:** The existing codebase uses the `Decimal` package correctly throughout and stores `decimal(12,3)` in Postgres. During migration, the path of least resistance is to call `.toDouble()` on Decimal values before writing to Firestore. OMR uses 3 decimal places — the error accumulates.

**Consequences:** Balance calculations drift over time. Settlements are wrong. This cannot be fixed retroactively without rewriting all financial data.

**Prevention:**
- Store all monetary amounts as integers in Firestore, in the smallest unit (fils for OMR: 1 OMR = 1000 fils).
- Example: OMR 15.500 → stored as integer `15500`.
- `BalanceCalculator` keeps using `Decimal` internally; convert only at Firestore read/write boundary.
- Write a single `MoneySerializer` utility: `toFils(Decimal d)` and `fromFils(int f)`. Every Firestore write/read goes through it. No exceptions.
- Never use `FieldValue.increment()` on monetary fields — always read-then-write in a transaction.

**Detection:** Unit tests that write a known decimal to Firestore and read it back, asserting exact equality. Must pass before any financial code ships.

**Phase:** Foundation/Firestore setup phase — non-negotiable prerequisite.

---

### Pitfall 3: Group-Level Balance as a Single Aggregation Document (Write Hotspot)

**What goes wrong:** The cross-event balance feature — "running balances across all events" — is the killer feature of Rihla v2. The natural implementation is a `groups/{groupId}/balances` document with a map of member-to-member balances. Every expense addition, every settlement, every event creation updates this one document. Firestore's soft limit is 1 sustained write per second per document. Group activities during a trip exceed this easily.

**Why it happens:** Cross-event aggregation feels like a natural fit for a single summary document. It is also how the existing system conceptually works (balance is computed on read from all expenses). Moving to a precomputed balance on write, stored in one document, creates a hotspot.

**Consequences:** Increased write latency. Contention errors. Transactions fail and retry. The more active a group, the worse it gets.

**Prevention:**
- Do not maintain a single pre-aggregated balance document per group.
- Store balance contributions per-event, per-participant pair as separate documents under `groups/{groupId}/events/{eventId}/balanceSummary`.
- Compute group-level net balance client-side by summing event balances cached in SQLite — this is already what `BalanceCalculator` does, just scoped differently.
- If a precomputed group balance document is needed for display, update it lazily (on event close, on settlement) rather than on every expense write.
- Alternatively, use distributed counter shards if real-time aggregation is truly needed.

**Detection:** Any write path that touches more than 2 documents in a transaction when a single expense is added should be redesigned.

**Phase:** Data modeling and group balance design phase.

---

### Pitfall 4: Anonymous Auth UID Is Ephemeral — Data Is Permanently Lost on Reinstall

**What goes wrong:** Firebase anonymous auth creates a UID that persists across app restarts but is permanently destroyed on uninstall. Supabase anonymous auth has the same behavior. However, the migration creates a second risk: existing Supabase anonymous UIDs have no mapping to Firebase anonymous UIDs. Existing users who reinstall after the migration get a new Firebase UID and cannot access their old Supabase-seeded data.

**Why it happens:** The current app already uses anonymous auth (`signInAnonymously()` on first launch). Users have no accounts. There is no email to recover via. The UID is the only identity.

**Consequences:** Existing users who reinstall the app after the Firestore migration lose all their trip history. This is a silent data loss — the app works fine, it just shows no data. Users blame the app update.

**Prevention:**
- The name-based member system partially decouples identity: users pick a name in a group rather than being identified by UID. Lean into this.
- During migration: write a mapping from old Supabase user_id to a stable group invite code. When a user enters an invite code, they recover their participation without needing UID continuity.
- Long-term: the anonymous auth model means accepting data loss on reinstall. Document this in product terms and make "join via code" work well as the recovery path.
- Do not attempt to link Firebase anonymous UID to Supabase UID — there is no reliable way to do this at the client level after the fact.

**Detection:** Test the reinstall flow explicitly during migration QA. Wipe app data, reinstall, verify that joining via group code restores membership.

**Phase:** Auth migration phase — must be designed before Firestore data migration begins.

---

### Pitfall 5: Firestore Security Rules Cannot Do Complex Membership Checks Without Read Costs

**What goes wrong:** The Supabase system used a `SECURITY DEFINER` function `is_trip_member(trip_uuid)` which ran server-side SQL. This avoided expensive joins in RLS policies. Firestore security rules have a hard limit of 10 `get()` calls per rule evaluation. Checking group membership, then event membership, then checking write permission for a specific role — that is already 3+ `get()` calls per rule evaluation. Complex scenarios hit the ceiling.

**Why it happens:** The Supabase migration history shows exactly this pattern: 4 fix migrations for RLS complexity (migrations 021, 023, 029 all fix security rules edge cases). The same instinct to write complex access rules will hit a different hard limit in Firestore.

**Consequences:** Security rules that silently fail to evaluate (too many gets) default to deny, blocking legitimate operations. Or worse: rules are simplified to avoid the limit, creating gaps like the one fixed in migration 023 (any trip member could modify any expense).

**Prevention:**
- Store membership as a map field on the group document: `members: { "uid1": "admin", "uid2": "member" }`. Security rules can check `request.auth.uid in resource.data.members` without a `get()` call — this is an in-document lookup, not a cross-document read.
- Cap group size where this breaks down (maps approach fails around 500 members — irrelevant for Rihla's small-group use case).
- Use Firebase Auth custom claims for roles that need to survive rule evaluation without get() calls. Set claims via Cloud Function when a user joins a group.
- Write security rules tests with Firebase Emulator before deploying. This is mandatory, not optional.

**Detection:** Test every security rule path with the Firebase Emulator. Count `get()` calls in each rule. Deny if any path approaches 5+ gets.

**Phase:** Firestore security rules phase. Do not write production rules without Emulator test coverage.

---

## Moderate Pitfalls

---

### Pitfall 6: Dual-Layer Offline (Firestore Persistence + SQLite) Without a Defined Authority

**What goes wrong:** The plan is to keep SQLite alongside Firestore (PROJECT.md: "Keep SQLite alongside Firestore — Fast local reads, existing offline architecture works well"). Firestore's SDK already has built-in offline persistence. Running both without defining which is the source of truth for a given operation produces split-brain: the UI reads from SQLite, Firestore has already sync'd a conflicting update from another device, neither system wins cleanly.

**Why it happens:** The existing SQLite layer was built because Supabase Realtime was unreliable. Firestore's offline persistence is more robust. The instinct is to keep both "just in case." But two caches with independent invalidation become two databases.

**Consequences:** Expense amounts correct in SQLite, different in Firestore cache. Which does the UI show? Settlement marked paid in Firestore, not yet processed in SQLite sync queue. User sees it as unpaid.

**Prevention:**
- Define a strict authority hierarchy: Firestore SDK cache is the primary offline source for reads. SQLite is used only for: (a) pre-fetched local search indexes, (b) the sync queue for write ordering guarantees, (c) data that Firestore offline cache does not persist across cold app restarts (which is a known limitation on some Android devices).
- Remove the existing `OfflineRepository.notifyChange()` call pattern — Firestore realtime listeners replace this. SQLite writes happen only as a side effect of confirmed Firestore writes, not as the primary write path.
- The existing `SyncService` (`sync_service.dart`) is fully replaced by Firestore SDK. Do not port it; delete it.

**Detection:** Any code path that writes to SQLite and separately writes to Firestore is a sign of dual-primary. Writes should flow: local UI → Firestore SDK (handles offline queue) → SQLite on confirmed write via Firestore listener.

**Phase:** Architecture design phase, before any service migration begins.

---

### Pitfall 7: Subcollection Deletion Does Not Cascade

**What goes wrong:** Deleting a Firestore document does not delete its subcollections. If `groups/{groupId}` is deleted but events were stored as `groups/{groupId}/events/{eventId}/expenses/{expenseId}`, the group document disappears but all child data remains as orphaned documents — accruing storage costs and potentially accessible to anyone who knows the path.

**Why it happens:** Postgres with `ON DELETE CASCADE` handles this automatically (visible in all migrations: `ON DELETE CASCADE` throughout). Firestore has no equivalent. The assumption that deletion cascades is deeply embedded in the Supabase architecture.

**Consequences:** Orphaned expense documents. Stale data reachable if security rules are path-based and the parent document used for membership checks no longer exists.

**Prevention:**
- Never rely on parent document deletion to clean up subcollections.
- All group/event deletion must use a Cloud Function or batch delete that explicitly walks and deletes the subcollection tree.
- Alternatively: use soft deletes (`isDeleted: true`) on all documents and let a scheduled Cloud Function do actual cleanup. This also preserves financial audit history.
- Security rules: check membership at the specific document level, not by assuming the parent document's absence means deny.

**Detection:** Write a test that deletes a group document and verifies subcollection documents still exist (they will). This should trigger the defensive code path that handles orphan cleanup.

**Phase:** Data modeling and group lifecycle design.

---

### Pitfall 8: Firestore Composite Indexes Are Not Auto-Created

**What goes wrong:** Every Firestore query that filters on one field and orders by another requires a composite index. These are not created automatically. The app crashes at runtime with an error message that includes a direct link to create the index — but this only surfaces during testing, and only if that specific query path is exercised.

**Why it happens:** The existing code does multi-column queries throughout: `expenses` filtered by `trip_id` and ordered by `created_at`, `settlements` filtered by `trip_id` and `payer_participant_id`. Each combination that was a SQL `WHERE x AND ORDER BY y` needs a Firestore composite index.

**Consequences:** Queries fail silently in production for users on specific filter combinations. The developer never sees it because local testing hit different code paths.

**Prevention:**
- Build and run the full app against Firebase Emulator with all query paths exercised before deploying. Capture all composite index errors.
- Maintain an `firestore.indexes.json` file in the repository and deploy it with `firebase deploy --only firestore:indexes` before deploying rules or functions.
- For `collectionGroup` queries (querying expenses across all events in a group), collection group indexes must be explicitly defined.

**Detection:** After any new Firestore query is written, run it against a non-empty Emulator dataset and inspect the Flutter console for index-missing errors.

**Phase:** Each feature phase that introduces new query patterns.

---

### Pitfall 9: Cross-Event Settlement Is Not Idempotent Without Careful Transaction Design

**What goes wrong:** When a user settles a cross-event debt ("Khalid pays Nasser OMR 45 across 3 trips"), the settlement must atomically: (1) record the settlement document, (2) reduce the outstanding balance in the affected event summaries, (3) not double-apply if the user retries after a network failure. Firestore transactions use optimistic concurrency and will retry on contention. If a retry writes two settlement documents, balances are wrong.

**Why it happens:** The existing settlement system is per-trip and not designed for cross-event atomicity. The new cross-event balance feature requires composing multiple writes atomically, and offline-first means the user may initiate settlement while offline and sync later.

**Consequences:** Double-counted settlements. Balances show the wrong net amount. This is a financial integrity bug, not just a UI bug.

**Prevention:**
- Generate settlement IDs client-side (UUID v4) before initiating the transaction. Use this as the Firestore document ID. Firestore document creates with a specific ID are idempotent: creating the same document ID twice is either a no-op or a conflict, not a duplicate insert.
- Use Firestore batch writes for settlement + balance update rather than separate writes. If the batch fails, the whole operation is rolled back.
- Include a `clientGeneratedId` field on settlement documents and add a uniqueness check in security rules (`!exists` check for that document) to prevent duplicate submissions.
- Test: simulate network failure mid-settlement and verify re-submission produces exactly one settlement record.

**Phase:** Cross-event ledger design phase.

---

### Pitfall 10: Collection Group Queries on Expenses Require Rules Version 2 and `path=**`

**What goes wrong:** The group dashboard shows expenses across all events. This requires a `collectionGroup("expenses")` query. Collection group queries require security rules version 2 and a `match /{path=**}/expenses/{doc}` rule with `path=**` wildcard. If the rules file uses version 1 or lacks this match pattern, collection group queries are silently denied.

**Why it happens:** Most Firestore security rules tutorials show document-level or collection-level rules. Collection group rules are a separate, non-obvious syntax that is easy to forget.

**Consequences:** Group dashboard shows empty expense history. No error — just empty results. Debugging is non-obvious because the data exists in Firestore.

**Prevention:**
- Set `rules_version = '2';` at the top of `firestore.rules`.
- Add an explicit `match /{path=**}/expenses/{doc}` block alongside the document-scoped rule.
- Test collection group queries against the Emulator with authenticated test users before shipping the group dashboard.

**Phase:** Firestore security rules phase, specifically when adding group-level queries.

---

## Minor Pitfalls

---

### Pitfall 11: Firestore Document IDs That Are Monotonically Increasing Create Hotspots

**What goes wrong:** Using `DateTime.now().millisecondsSinceEpoch.toString()` as a document ID — a common pattern when migrating from timestamp-ordered SQL data — creates a write hotspot because sequential IDs map to sequential storage segments.

**Prevention:** Use `db.collection('x').doc()` (auto-generated ID) or UUID v4. Never use timestamps as primary document IDs.

**Phase:** Any phase writing new Firestore documents.

---

### Pitfall 12: Firestore Offline Persistence Has a Default Cache Size Limit

**What goes wrong:** Firestore's default offline cache is 100MB on mobile. For large groups with many events, expenses, and media references, this fills up. When the cache is full, Firestore starts evicting older documents. The user goes offline and finds their older events are not available.

**Prevention:** Set `settings.cacheSizeBytes = FirebaseFirestore.CACHE_SIZE_UNLIMITED` during initialization, or use the new `PersistentCacheSettings` with an explicit size appropriate for the data volume. Add this to the Firestore initialization in Phase 1.

**Phase:** Firestore setup phase.

---

### Pitfall 13: `FieldValue.serverTimestamp()` Returns `null` Offline

**What goes wrong:** Documents written offline with `FieldValue.serverTimestamp()` have a `null` timestamp until they sync. Code that uses `createdAt` for sorting throws a null reference error when processing offline-written documents.

**Prevention:** Always null-check timestamps when sorting. Use a client-generated `createdAt` (`DateTime.now().toUtc()`) as the primary timestamp, and store `serverTimestamp` as a secondary `syncedAt` field. Sort by the client-generated timestamp for display.

**Phase:** Any feature phase adding new document types.

---

### Pitfall 14: Firestore Security Rules Do Not Catch Type Errors

**What goes wrong:** Security rules validate structure only if you explicitly write type-checking conditions (`is string`, `is number`). Without them, a client can write `amount: "hello"` to an expense document. The existing Supabase schema used `decimal(12,3) NOT NULL` — type enforcement was automatic.

**Prevention:** Write explicit type validation in security rules:
```
allow create: if request.resource.data.amount is int
  && request.resource.data.amount > 0
  && request.resource.data.description is string;
```
Treat security rules as schema enforcement, not just access control.

**Phase:** Firestore security rules phase.

---

## Phase-Specific Warnings

| Phase Topic | Likely Pitfall | Mitigation |
|-------------|---------------|------------|
| Firestore setup & data model design | Relational schema translation (Pitfall 1) | Model around screen reads, not table normalization |
| Firestore setup & data model design | Money stored as doubles (Pitfall 2) | Implement `MoneySerializer` before first Firestore write |
| Firestore setup & data model design | Subcollection orphan on delete (Pitfall 7) | Use soft deletes; never rely on cascade |
| Firestore setup & data model design | Monotonic IDs causing hotspots (Pitfall 11) | Use auto-generated Firestore IDs |
| Firestore setup & data model design | Cache size limit for offline (Pitfall 12) | Set `CACHE_SIZE_UNLIMITED` in init |
| Auth migration | Anonymous UID data loss on reinstall (Pitfall 4) | Make group join-by-code the recovery path |
| Security rules | 10-get limit per rule evaluation (Pitfall 5) | Embed membership in group document as map; avoid cross-document gets in rules |
| Security rules | Rules version 1 blocks collection group queries (Pitfall 10) | Use `rules_version = '2'` from the start |
| Security rules | No type enforcement (Pitfall 14) | Add type validation to all write rules |
| Offline / sync architecture | Dual-layer cache conflict (Pitfall 6) | Define Firestore SDK as read authority; SQLite as write queue only |
| Group balance design | Write hotspot on aggregation document (Pitfall 3) | Compute group balance client-side from per-event summaries |
| Cross-event settlement | Non-idempotent settlement writes (Pitfall 9) | Client-generated settlement IDs + batch writes |
| Group dashboard / queries | Composite index missing (Pitfall 8) | Maintain `firestore.indexes.json`; test all query paths against Emulator |
| Group dashboard / queries | Collection group query denied (Pitfall 10) | Test collection group queries in Emulator before ship |
| Any new document type | serverTimestamp null offline (Pitfall 13) | Client-generated timestamp as primary; serverTimestamp as secondary |

---

## Sources

- Firebase Firestore official docs — best practices: https://firebase.google.com/docs/firestore/best-practices
- Firebase Firestore write throughput and hotspots: https://firebase.google.com/docs/firestore/understand-reads-writes-scale
- Firestore write throughput 101 (Frank van Puffelen): https://puf.io/posts/firestore-write-throughput-101/
- Group-based security rules patterns (Firebase blog): https://medium.com/firebase-developers/patterns-for-security-with-firebase-group-based-permissions-for-cloud-firestore-72859cdec8f6
- Firestore transaction data contention: https://firebase.google.com/docs/firestore/transaction-data-contention
- FlutterFire anonymous auth: https://firebase.flutter.dev/docs/auth/anonymous-auth/
- Firebase best practices for anonymous auth: https://firebase.blog/posts/2023/07/best-practices-for-anonymous-authentication/
- FlutterFire issue #9626 (integer/double type mismatch): https://github.com/firebase/flutterfire/issues/9626
- Firestore FieldValue.increment decimal bug: https://groups.google.com/g/firebase-talk/c/y3KFIELD4ag
- Firestore offline access: https://firebase.google.com/docs/firestore/manage-data/enable-offline
- Collection group queries: https://firebase.blog/posts/2019/06/understanding-collection-group-queries/
- Rihla migration history: supabase/migrations/020–029 (observed RLS fix pattern across 4 migrations)
- Rihla SyncService: lib/core/services/sync_service.dart (join pattern that does not translate to Firestore)
