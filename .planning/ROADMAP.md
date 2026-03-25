# Roadmap: Rihla v2 — Groups, Events, and Cross-Event Financial Tracking

## Overview

Rihla v2 evolves the existing Flutter trip-planning app into a persistent group coordination platform, while migrating the backend from Supabase to Firebase Firestore. The build follows a strict dependency chain: data foundation establishes financial precision and security constraints before any feature code exists; groups provide the container layer; events plug into groups with template-driven module selection; the Firestore repository layer migrates all per-event write paths off Supabase; cross-event financials deliver the killer feature (group-level running balances); testing enforces 80%+ coverage; and finally Supabase is removed cleanly. Eight phases. Each one verifiable before the next begins.

## Phases

**Phase Numbering:**
- Integer phases (1, 2, 3): Planned milestone work
- Decimal phases (2.1, 2.2): Urgent insertions (marked with INSERTED)

Decimal phases appear between their surrounding integers in numeric order.

- [x] **Phase 1: Data Foundation** - Firestore initialized, security rules tested, integer money storage enforced, SQLite schema extended (completed 2026-03-25)
- [ ] **Phase 2: Groups** - Users can create and join persistent groups; groups appear on home screen
- [ ] **Phase 3: Events** - Users can create typed events inside groups with template-driven modules and gear presets
- [ ] **Phase 4: Firestore Repository Layer** - All per-event module writes routed through Firestore; SyncService retired
- [ ] **Phase 5: Cross-Event Financials** - Group-level running balances, balance toggle, cross-event settle-up, group dashboard
- [ ] **Phase 6: Testing and Coverage** - 80%+ coverage enforced, offline scenario tests, widget tests, financial unit tests
- [ ] **Phase 7: Data Migration and Supabase Removal** - Existing data migrated via invite-code recovery, Supabase dependency deleted

## Phase Details

### Phase 1: Data Foundation
**Goal**: The backend infrastructure is ready to receive group and financial data with correct precision, security, and schema
**Depends on**: Nothing (first phase)
**Requirements**: DATA-01, DATA-02, DATA-03, DATA-04, DATA-05, DATA-06, TST-03, TST-04
**Success Criteria** (what must be TRUE):
  1. A Firestore write of an OMR expense amount round-trips back to the exact same Decimal value with no floating-point drift
  2. Firebase Emulator runs locally and security rule tests pass, verifying that non-members cannot read or write group documents
  3. Anonymous sign-in via Firebase Auth completes silently on first launch with no login screen shown to the user
  4. SQLite database opens with the extended schema (groups, group_members, group_ledger tables present) without migration errors
  5. All Firebase package versions are consistent and `flutter pub get` succeeds with no version conflicts
**Plans**: 3 plans

Plans:
- [x] 01-01-PLAN.md — Firebase package upgrade + FirebaseConfig + dual-auth bootstrap
- [x] 01-02-PLAN.md — MoneySerializer TDD + SQLite v6 migration + Firestore round-trip test
- [x] 01-03-PLAN.md — Firebase Emulator setup + security rules + JS rule tests

### Phase 2: Groups
**Goal**: Users can create a persistent group, share an invite code, and see all their groups on the home screen
**Depends on**: Phase 1
**Requirements**: GRP-01, GRP-02, GRP-03, GRP-06, GRP-07
**Success Criteria** (what must be TRUE):
  1. User can create a group with a name and immediately share the generated invite code with others
  2. User can join an existing group by entering an invite code and sees the group appear in their home screen group list
  3. User can view all members currently in a group
  4. Groups appear on the home screen and persist across app restarts and reinstalls
  5. A group with no active events still shows in the member's group list (group persists independently of events)
**Plans**: 4 plans

Plans:
- [ ] 02-00-PLAN.md — Wave 0: test stub files for group models, service, join flow, and widget tests
- [ ] 02-01-PLAN.md — Group/GroupMember models, GroupService with atomic create/join, Riverpod providers, CacheService + OfflineRepository extensions
- [ ] 02-02-PLAN.md — GroupCard/GroupMemberTile/InviteCodeDisplay widgets, groups-first HomeScreen, CreateGroupScreen + JoinGroupScreen
- [ ] 02-03-PLAN.md — GroupSettingsScreen, GroupDetailScreen, GoRouter route wiring

### Phase 3: Events
**Goal**: Users can create a typed event inside a group, with the event type controlling module visibility and pre-filling relevant content
**Depends on**: Phase 2
**Requirements**: EVT-01, EVT-02, EVT-03, EVT-04, EVT-05, EVT-06, EVT-07, EVT-08
**Success Criteria** (what must be TRUE):
  1. User can create an event inside a group and sees group members pre-populated as event participants
  2. Selecting "Camping" as the event type shows gear, logistics, and ledger modules; selecting "Night Out" shows only the ledger module
  3. A new Camping event has tent, sleeping bag, and cooler pre-added to the gear list without user input
  4. A Custom event presents a module picker with no preset content
  5. The group event timeline shows all past and upcoming events in chronological order with financial totals per event
**Plans**: TBD

### Phase 4: Firestore Repository Layer
**Goal**: All per-event module writes (expenses, settlements, gear, logistics, vault, memories, activity) flow through Firestore; the SyncService polling loop is gone; offline capability is preserved through Firestore's built-in write queue
**Depends on**: Phase 3
**Requirements**: MIG-01, MIG-02, MIG-03, MIG-04, MIG-05
**Success Criteria** (what must be TRUE):
  1. Adding an expense while offline queues it locally; when connectivity restores, the expense appears in Firestore without any manual sync action
  2. A Firestore snapshot listener update propagates to the UI without polling — changes made on another device appear within seconds on reconnect
  3. The SyncService class and sync_queue SQLite table no longer exist in the codebase
  4. All Firestore reads and writes flow through FirestoreRepository — no direct FirebaseFirestore.instance calls exist outside that class
  5. SQLite still serves structured balance queries; the BalanceCalculator reads from SQLite and produces correct results
**Plans**: TBD

### Phase 5: Cross-Event Financials
**Goal**: The group dashboard shows live running balances across all events; users can see what they owe per event or in total across the group; cross-event settle-up works
**Depends on**: Phase 4
**Requirements**: FIN-01, FIN-02, FIN-03, FIN-04, FIN-05, FIN-06, FIN-07, GRP-04, GRP-05
**Success Criteria** (what must be TRUE):
  1. The group dashboard shows each member's net balance across all events (e.g., "Ahmed owes 45.500 OMR total across 3 events")
  2. User can toggle between per-event balance view and group-level balance view on the ledger screen
  3. "Settle across events" suggests the minimum number of transactions to zero out balances across the group ("You owe Nasser 15.500 across 3 events — settle now?")
  4. After a settlement is recorded, the group-level balance updates to reflect the new net amounts
  5. Group activity log shows group-level events such as "Sara settled with Khalid" and "Ahmed added camping trip"
  6. Group dashboard shows total amount spent across all events and each member's contribution percentage
**Plans**: TBD

### Phase 6: Testing and Coverage
**Goal**: The codebase meets the 80%+ coverage requirement with unit tests for all financial logic, widget tests for key screens, and offline scenario tests
**Depends on**: Phase 5
**Requirements**: TST-01, TST-02, TST-05, TST-06
**Success Criteria** (what must be TRUE):
  1. `flutter test --coverage` reports 80%+ line coverage with no excluded financial calculation files
  2. All BalanceCalculator scenarios (global, subGroup, personal, custom, cross-event aggregation) have passing unit tests
  3. Widget tests for the group dashboard, event creation flow, and balance toggle pass without real Firebase calls (using fake_cloud_firestore)
  4. An offline scenario test writes an expense while offline, disconnects Firestore, verifies SQLite has the pending value, then reconnects and verifies Firestore receives the write
**Plans**: TBD

### Phase 7: Data Migration and Supabase Removal
**Goal**: Existing user data is accessible in the new Firestore-backed app; the supabase_flutter dependency is gone from the codebase
**Depends on**: Phase 6
**Requirements**: MIG-06, MIG-07
**Success Criteria** (what must be TRUE):
  1. A user with existing trip data can recover their data in the new app by entering the trip's invite code — their expenses, gear, and settlements appear correctly
  2. `flutter pub get` succeeds with no supabase_flutter or supabase-dart packages in pubspec.lock
  3. `flutter analyze` reports zero references to Supabase types (SupabaseClient, SupabaseQueryBuilder, etc.) in the codebase
**Plans**: TBD

## Progress

**Execution Order:**
Phases execute in numeric order: 1 → 2 → 3 → 4 → 5 → 6 → 7

| Phase | Plans Complete | Status | Completed |
|-------|----------------|--------|-----------|
| 1. Data Foundation | 3/3 | Complete   | 2026-03-25 |
| 2. Groups | 0/4 | Not started | - |
| 3. Events | 0/TBD | Not started | - |
| 4. Firestore Repository Layer | 0/TBD | Not started | - |
| 5. Cross-Event Financials | 0/TBD | Not started | - |
| 6. Testing and Coverage | 0/TBD | Not started | - |
| 7. Data Migration and Supabase Removal | 0/TBD | Not started | - |
