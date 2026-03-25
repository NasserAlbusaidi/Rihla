# Project Research Summary

**Project:** Rihla v2 — Groups, Events, and Cross-Event Financial Tracking
**Domain:** Offline-first mobile expense coordination app with Supabase-to-Firestore migration
**Researched:** 2026-03-26
**Confidence:** HIGH (stack and architecture), MEDIUM (dual-cache integration specifics)

## Executive Summary

Rihla v2 is a phased migration and feature expansion on an existing Flutter/Riverpod codebase. The primary work is replacing Supabase (PostgreSQL + Realtime) with Firebase Firestore as the cloud backend, while simultaneously introducing a persistent groups layer above the existing trip/event architecture. The codebase already has Firebase initialized for FCM, which means this migration is additive rather than a rewrite — but it is still large in scope, touching every service layer and the entire security model. The recommended approach is a strict layer-by-layer build order: data foundation first (schema, Firestore init, security rules), then groups, then events, then module migration, then cross-event financials, then final Supabase removal. This ordering respects the hard dependency chain and avoids partial migrations where both backends are live simultaneously for long periods.

The defining architectural decision for this milestone is the dual-cache strategy. Firestore's built-in offline persistence handles write queuing and auto-sync, eliminating the existing `SyncService` polling loop. SQLite is retained specifically for structured queries that power balance calculations — Firestore's cache cannot perform SQL aggregates, and the greedy min-transactions algorithm needs fast indexed reads. These two caches serve different roles and must have a defined authority hierarchy: Firestore SDK cache is the read authority; SQLite is populated as a side effect of confirmed Firestore listener events and provides the structured query layer. Any design that treats them as co-equals will produce data inconsistency.

The key risks are financial precision (OMR amounts must be stored as integers in fils, never as Firestore doubles), write hotspots on the cross-event group balance document (use per-event balance summaries aggregated client-side, not a single group-level aggregation document), and Firestore security rules complexity (the 10-get limit per rule evaluation means membership must be embedded in the group document as a map field, not resolved via cross-document lookups). These three risks are non-negotiable prerequisites that must be addressed in the foundation phase before any feature work begins.

---

## Key Findings

### Recommended Stack

The Firestore migration requires upgrading `firebase_core` from `^3.12.1` to `^4.6.0` — this is mandatory because `cloud_firestore ^6.2.0` requires it. All other FlutterFire packages (`firebase_auth ^6.3.0`, `firebase_storage ^13.2.0`, `firebase_messaging`) align on `firebase_core` 4.x. Riverpod must stay on 2.x for this milestone: Riverpod 3.0 shipped September 2025 with breaking changes to every provider type, and mixing a Riverpod major-version migration with a Firestore migration creates compounding risk. Plan Riverpod 3.x as a separate future milestone. GoRouter should be upgraded from `^13.2.0` to `^17.1.0` to support the new `/groups`, `/groups/:id`, and `/groups/:id/events/:eventId` route structure.

**Core technologies:**
- `cloud_firestore ^6.2.0`: Primary cloud database — NoSQL with built-in offline persistence, real-time listeners, and collection group queries for cross-event aggregation. Replaces Supabase PostgreSQL + Realtime.
- `firebase_auth ^6.3.0`: Anonymous auth — same `signInAnonymously()` UX, Firestore security rules replace Supabase RLS.
- `firebase_storage ^13.2.0`: Document vault and memories — replaces Supabase Storage buckets; `getDownloadURL()` replaces signed URL generation.
- `firebase_core ^4.6.0`: Mandatory upgrade; current 3.x is incompatible with Firestore 6.x.
- `sqflite ^2.4.2` (keep): Structured local reads for balance calculations — cannot be replaced by Firestore's offline cache.
- `decimal ^3.2.4` (keep): OMR amounts stored as integer fils in Firestore, deserialized to Decimal at the boundary via a `MoneySerializer` utility.
- `fake_cloud_firestore ^4.1.0+1` (dev): In-memory Firestore for unit tests; inject `FirebaseFirestore` as constructor parameter into all repositories so tests can pass `FakeFirebaseFirestore()`.
- `go_router ^17.1.0`: Upgraded from 13.x for new group/event top-level routes; `Navigator.push` stays for per-event module screens within the group shell.
- `flutter_riverpod ^2.4.9` (stay): Riverpod 3.x migration is a separate milestone.

### Expected Features

The market gap Rihla v2 fills is well-documented: Splitwise users have repeatedly asked for "events inside groups" (persistent friend circle containing multiple trips) and received no resolution. No mainstream app does this well. Group-level running balances are the killer feature — almost all differentiating capabilities build on top of this, making it the central architectural dependency.

**Must have (table stakes for v2):**
- Persistent group with member list — the entire new layer; without it nothing else works
- Create event from group (members pre-populated) — eliminates re-inviting the same people per trip
- Group event timeline — chronological list of past and upcoming events
- Group-level running balance per member across all events — the core value proposition
- Per-event vs. group balance toggle — the feature Splitwise users have been asking for for years
- Group join via shareable link — extends existing trip invite flow to groups
- All existing per-event features must not regress (offline capability, expense splitting, settlement, activity feed, push notifications)

**Should have (competitive differentiators):**
- Event type templates with gear presets — "Camping" pre-fills gear list, no competitor does this
- Template-driven module visibility — trip type controls which CommandCenter cards appear
- Cross-event settle-up suggestion — "You owe Nasser 15.500 across 3 events — settle now?"
- Group activity log — group-level narrative of all write operations
- Group event history with financial totals — each past event shows inline total spend

**Defer to post-v2:**
- Group spending stats and analytics dashboard — feature theatre for this use case
- Complex member permissions (admin/editor/viewer) — flat membership is correct for friend groups
- Web/desktop version — mobile-first
- In-app chat, AI expense categorization, recurring expenses — all anti-features for this domain

### Architecture Approach

The architecture introduces `FirestoreRepository` as a new component that is the sole point of contact with `FirebaseFirestore.instance`. Everything above it — providers, UI, business logic — continues to operate through `OfflineRepository` which serves reactive SQLite streams. Firestore snapshot listeners populate SQLite as a side effect, replacing the existing pull-based `SyncService` with a push-based listener pipeline. The `SyncService` and `sync_queue` SQLite table are retired entirely. The group ledger cross-event balance uses write-time aggregation via Firestore transactions (settlement write atomically updates the `groupLedger` subcollection) to avoid expensive read-time aggregation across all events.

**Major components:**
1. `FirestoreRepository` — sole Firestore contact; generic document write/read/listen, document-to-SQLite mapping, snapshot listener lifecycle
2. `OfflineRepository` — reactive SQLite streams, notify-on-change; unchanged role, now fed by Firestore listeners instead of `SyncService` pulls
3. `GroupRepository` — group CRUD, invite code generation and resolution, member management; built on `FirestoreRepository`
4. `EventRepository` — event CRUD, template seeding (maps event type to default modules + gear presets), module configuration
5. `LedgerService` — expense and settlement writes including atomic group ledger transaction update; cross-event settlement idempotency via client-generated IDs
6. `BalanceCalculator` — unchanged pure logic; reads from SQLite, not Firestore
7. Firestore Security Rules — replace Supabase RLS; membership encoded as `members: { uid: role }` map on group document to avoid `get()` calls in rule evaluation

**Firestore collection structure:**
```
/groups/{groupId}
  /members/{memberId}
  /events/{eventId}
    /expenses/{expenseId}
    /settlements/{settlementId}
    /gearItems/{itemId}
    /subGroups/{subGroupId}
    /activityLogs/{logId}
    /categories/{categoryId}
  /groupLedger/{entryId}
/inviteCodes/{code}
```

### Critical Pitfalls

1. **Firestore doubles for money** — OMR has 3 decimal places; IEEE 754 doubles lose precision. Store all amounts as integer fils (1 OMR = 1000 fils). Write `MoneySerializer.toFils()` and `fromFils()` before the first Firestore write. No exceptions.

2. **Relational schema translation** — The existing `SyncService` does joined selects (`expenses.select('*, participants!payer_participant_id(*)')`). Firestore has no joins. Denormalize `payerName` directly onto expense documents. Model document shape around screen read requirements, not around avoiding duplication.

3. **Write hotspot on group balance document** — A single `groups/{groupId}/balances` document updated on every expense write exceeds Firestore's 1-write-per-second soft limit for active groups. Compute group-level net balance client-side by aggregating per-event balance summaries from SQLite. The `groupLedger` subcollection stores net amounts per member pair; the dashboard reads O(members^2) ledger entries, not every expense.

4. **Security rules 10-get limit** — Supabase used a `SECURITY DEFINER` SQL function for membership checks. Firestore rules have a hard limit of 10 `get()` calls per rule evaluation. Store group membership as a map field (`members: { "uid": "LEADER" }`) on the group document so rules can check `request.auth.uid in resource.data.members` without a cross-document `get()`.

5. **Dual-cache authority ambiguity** — Running Firestore SDK cache and SQLite simultaneously without a defined authority produces split-brain. Define the hierarchy explicitly: Firestore SDK cache handles write queuing and auto-sync; SQLite is populated only as a side effect of Firestore listener events and provides structured query access. Never write to SQLite as the primary write path.

---

## Implications for Roadmap

Based on research, the dependency chain is strict and the suggested phase structure follows directly from it.

### Phase 1: Data Foundation and Firestore Setup

**Rationale:** Everything downstream depends on a correct data model and working security rules. Financial precision (integer fils storage) must be established before any expense write code exists. Security rules must be validated before any data is written to production. This phase has no UI deliverables but sets the constraints that all later phases must respect.

**Delivers:** Working Firestore project with anonymous auth, correct collection structure, security rules tested against Firebase Emulator, `MoneySerializer` utility, SQLite schema migration (add `groups`, `group_ledger` tables; rename `trips` to `events`; add `groupId` columns), `firestore.indexes.json` scaffolded, Firestore offline cache configured with `CACHE_SIZE_UNLIMITED`.

**Addresses:** All table stakes that require backend to exist before they can be built.

**Avoids:** Pitfall 2 (money as doubles), Pitfall 5 (security rules get limit), Pitfall 10 (rules version 1 blocking collection group queries), Pitfall 12 (cache size default), Pitfall 14 (no type enforcement in rules).

**Research flag:** Standard patterns — well-documented Firebase setup process. Skip research-phase.

### Phase 2: Groups Feature

**Rationale:** Groups are the new container layer. Nothing in v2 (events, cross-event balances, group timeline) can be built without a working group data structure, join flow, and member list. This phase establishes the social foundation.

**Delivers:** Group creation, join-via-invite-link flow, group member list, groups appearing on the home screen. `GroupRepository`, `groupsProvider`, `groupMembersProvider`, groups UI screens.

**Addresses:** "Persistent group with member list" (table stakes), "Group join via shareable link" (table stakes), "Group member list" (table stakes).

**Avoids:** Pitfall 4 (anonymous UID data loss on reinstall — make join-by-code the recovery path), Pitfall 7 (subcollection orphan deletion — use soft deletes from the start), Pitfall 11 (monotonic document IDs — use auto-generated Firestore IDs).

**Research flag:** Standard patterns. Group CRUD with Firestore is well-documented.

### Phase 3: Events Feature

**Rationale:** Events (formerly trips) are the unit of activity inside a group. Once groups exist, events can be attached to them with group members pre-populated. The template engine (event type → default modules + gear presets) is a differentiator that should be built here, not bolted on later, because it affects the event creation flow and `modules` map schema.

**Delivers:** Create event from group (with type selection), event template engine, template-driven module visibility, group event timeline (chronological list), CommandCenter adapted to work inside the group/event hierarchy. `EventRepository`, `groupEventsProvider`, `eventProvider`.

**Addresses:** "Create event from group" (table stakes), "Group event timeline" (table stakes), "Event type templates with gear presets" (differentiator), "Template-driven module visibility" (differentiator).

**Avoids:** Pitfall 1 (relational schema translation — event documents are denormalized at creation time), Pitfall 8 (composite indexes — add indexes for event queries to `firestore.indexes.json` as they are written), Pitfall 13 (serverTimestamp null offline — use client-generated `createdAt`).

**Research flag:** Template engine (event type → gear presets) has no direct comparable — will need product-level decisions on preset contents. May benefit from a quick research-phase pass on gear list standards for common trip types.

### Phase 4: Module Migration (Supabase to Firestore)

**Rationale:** The existing ledger, gear, logistics, and vault modules still write to Supabase. This phase migrates each module's write path to Firestore and sets up snapshot listeners that populate SQLite from Firestore events (replacing `SyncService` pull behavior). The `SyncService` is retired here.

**Delivers:** All per-event module writes (expenses, gear items, settlements, logistics, vault) routed through `FirestoreRepository`. Firestore snapshot listeners populating SQLite. `SyncService` and `sync_queue` table retired. Offline capability preserved through Firestore SDK write queue. `LedgerService` updated for Firestore writes.

**Addresses:** "Offline capability must not regress" (hard constraint), all existing per-event features continue working.

**Avoids:** Pitfall 6 (dual-cache authority ambiguity — SQLite writes happen only via Firestore listener side effects from this point forward), Pitfall 9 (non-idempotent settlement writes — client-generated settlement IDs).

**Research flag:** Moderate complexity. Firestore listener-to-SQLite pipeline is the key new pattern. May benefit from a focused research-phase pass on the write path architecture before implementation.

### Phase 5: Cross-Event Financial Layer

**Rationale:** This is the killer feature and the hardest part. Cross-event balances build on working per-event financials (Phase 4). The `groupLedger` aggregation must be designed carefully to avoid write hotspots. Settlement across events requires idempotent batch writes.

**Delivers:** Group-level running balance per member (reads from `groupLedger` subcollection), per-event vs. group balance toggle in UI, cross-event settle-up suggestion ("settle OMR 45 across 3 events"), group activity log. `LedgerService` extended with group ledger transaction writes. `watchGroupLedger()` in `OfflineRepository`.

**Addresses:** "Group-level running balance" (table stakes), "Per-event vs. group balance toggle" (table stakes), "Cross-event settle-up suggestion" (differentiator), "Group activity log" (differentiator), "Group event history with financial totals" (differentiator).

**Avoids:** Pitfall 3 (write hotspot on aggregation document — group balance computed client-side from per-event summaries), Pitfall 9 (non-idempotent settlement writes — Firestore batch writes with client-generated IDs).

**Research flag:** HIGH complexity. Cross-event settlement atomicity and group ledger design need careful specification before implementation. Recommend research-phase on Firestore transaction patterns and distributed aggregation.

### Phase 6: Data Migration and Supabase Removal

**Rationale:** Final cleanup phase. The existing user base is small and uses anonymous auth (no identity continuity required across the migration). Data migration is a one-time operation, not an ongoing concern. Supabase is removed only after the migration is verified.

**Delivers:** Existing Supabase data exported and imported into Firestore. `supabase_flutter` dependency removed. Collection group indexes finalized in `firestore.indexes.json`. Full regression test pass.

**Addresses:** "Existing users should not lose data" (implicit constraint).

**Avoids:** Pitfall 4 (anonymous UID data loss — migration relies on group invite codes, not UID continuity; users rejoin via code).

**Research flag:** Data migration scripting for anonymous-auth Supabase to Firestore is non-standard. Will need a research-phase pass on migration tooling and the invite-code recovery strategy.

---

### Phase Ordering Rationale

The order is driven by three hard constraints discovered in research:

1. **Financial precision before any expense code** — `MoneySerializer` must exist before Phase 4. Building it in Phase 1 prevents it being forgotten.
2. **Groups before events before modules** — The Firestore collection structure is `/groups/{g}/events/{e}/expenses/{id}`. Each level must exist before the next can be built.
3. **Per-event financials before cross-event financials** — The `groupLedger` aggregation is written by `LedgerService` when settlements are recorded. `LedgerService` must already be migrated to Firestore (Phase 4) before the group ledger update logic (Phase 5) can be added.

The architecture research explicitly defines this as a 6-layer build order. That maps directly to 6 phases.

---

### Research Flags

**Phases needing deeper research during planning:**
- **Phase 5 (Cross-Event Financial Layer):** Firestore transaction contention under concurrent writes, distributed aggregation alternatives to write-time group ledger, idempotent cross-event settlement implementation. This is the most technically novel part of the build.
- **Phase 6 (Data Migration):** Supabase anonymous auth export format, Firestore batch import tooling, invite-code recovery path for existing users.
- **Phase 3 (Template Engine — gear presets):** Content decisions (what goes in Camping vs. Day Out presets) are product-level, not technical. Needs a product pass, not a tech research pass.

**Phases with standard patterns (can skip research-phase):**
- **Phase 1 (Firestore Setup):** Firebase initialization, anonymous auth, security rules with emulator — all well-documented official patterns.
- **Phase 2 (Groups Feature):** Group CRUD with Firestore subcollections is a standard Firebase pattern with extensive documentation.
- **Phase 4 (Module Migration):** Swapping Supabase write calls for Firestore write calls is mechanical, guided by existing code structure.

---

## Confidence Assessment

| Area | Confidence | Notes |
|------|------------|-------|
| Stack | HIGH | Package versions verified on pub.dev 2026-03-24. Riverpod 2.x stay recommendation is the only MEDIUM item (Riverpod 3.x community reports of early bugs, not official). |
| Features | HIGH | Market gap analysis is grounded in documented Splitwise user feedback. Anti-features list is well-established from competitor analysis. |
| Architecture | HIGH for Firestore data model; MEDIUM for dual-cache integration specifics | Firestore collection structure and security rules patterns are from official Firebase docs. The SQLite+Firestore dual-cache authority hierarchy is principled but untested at this specific integration point. |
| Pitfalls | HIGH | Critical pitfalls are grounded in documented Firebase issues (FlutterFire issue #9626, Firestore write throughput docs) and observed patterns in existing Rihla migration history (4 RLS fix migrations). |

**Overall confidence:** HIGH for phase structure and technical decisions. MEDIUM for dual-cache integration specifics and cross-event settlement design.

### Gaps to Address

- **Firestore emulator test setup:** Research files assume Firebase Emulator will be used for security rules testing. The project has no emulator configuration yet (`firebase.json`, emulator port config). This must be set up in Phase 1 before any security rules are written.
- **Group invite code format:** The architecture defines an `/inviteCodes/{code}` top-level collection but does not specify code format, length, or collision strategy. Needs a product decision in Phase 2.
- **Dual-cache conflict resolution:** The architecture defines Firestore SDK as the read authority, but does not specify what happens when a Firestore listener fires with data that contradicts an in-flight SQLite write (offline-written expense not yet confirmed). The write path research covers the happy path but not the conflict case. Needs explicit handling in Phase 4.
- **GoRouter 13.x to 17.x migration risk:** STACK.md rates this MEDIUM confidence. The existing `GoRouter` configuration needs validation against 17.x breaking changes before Phase 2 adds new routes.

---

## Sources

### Primary (HIGH confidence)
- [cloud_firestore pub.dev](https://pub.dev/packages/cloud_firestore) — version 6.2.0 confirmed 2026-03-24
- [firebase_auth pub.dev](https://pub.dev/packages/firebase_auth) — version 6.3.0 confirmed 2026-03-24
- [firebase_core pub.dev](https://pub.dev/packages/firebase_core) — version 4.6.0, mandatory upgrade for Firestore 6.x
- [fake_cloud_firestore pub.dev](https://pub.dev/packages/fake_cloud_firestore) — version 4.1.0+1, cloud_firestore 6.x compatibility confirmed
- [FlutterFire Firestore Usage](https://firebase.flutter.dev/docs/firestore/usage/) — offline persistence config, listener patterns
- [Firebase Firestore Offline Docs](https://firebase.google.com/docs/firestore/manage-data/enable-offline) — 40 MB default cache, eviction policy
- [Firestore Write-time Aggregations](https://firebase.google.com/docs/firestore/solutions/aggregation) — group ledger update strategy
- [Firestore Transactions and Batched Writes](https://firebase.google.com/docs/firestore/manage-data/transactions) — atomic multi-document writes, 500 document limit
- [Firestore best practices](https://firebase.google.com/docs/firestore/best-practices) — write throughput, hotspot prevention
- [Firebase Group-based Security Rules](https://medium.com/firebase-developers/patterns-for-security-with-firebase-group-based-permissions-for-cloud-firestore-72859cdec8f6) — membership rule patterns
- [Splitwise user feedback: events inside groups](https://feedback.splitwise.com/forums/162446-general/suggestions/13100073-add-a-trip-or-event-feature-inside-a-group-among) — market gap validation

### Secondary (MEDIUM confidence)
- [Riverpod 3.0 What's New](https://riverpod.dev/docs/whats_new) — breaking changes documented; stay on 2.x recommendation
- [go_router pub.dev](https://pub.dev/packages/go_router) — version 17.1.0 confirmed; migration risk from 13.x is LOW for standard route definitions
- [FlutterFire issue #9626](https://github.com/firebase/flutterfire/issues/9626) — integer/double type mismatch in Firestore
- [Offline-First Architecture in Flutter](https://dev.to/anurag_dev/implementing-offline-first-architecture-in-flutter-part-1-local-storage-with-conflict-resolution-4mdl) — dual-cache write-through strategy

### Tertiary (referenced, not independently verified)
- Rihla migration history `supabase/migrations/020-029` — observed RLS fix pattern across 4 migrations; confirms security rule complexity risk
- [Firebase Anonymous Auth Best Practices](https://firebase.blog/posts/2023/07/best-practices-for-anonymous-authentication/) — UID ephemerality and reinstall behavior

---

*Research completed: 2026-03-26*
*Ready for roadmap: yes*
