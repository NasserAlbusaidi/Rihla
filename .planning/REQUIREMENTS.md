# Requirements: Rihla v2

**Defined:** 2026-03-26
**Core Value:** Groups persist across events and accumulate financial history — friends settle up across trips, not just within one.

## v1 Requirements

### Data Foundation

- [x] **DATA-01**: All monetary values stored as integer fils (not doubles) in Firestore, with Decimal conversion at the boundary
- [x] **DATA-02**: Firestore security rules enforce group membership via `memberIds` map on group document
- [x] **DATA-03**: Firebase Emulator configured for local development and security rule testing
- [x] **DATA-04**: SQLite schema extended with `groups`, `group_members`, `group_ledger` tables
- [x] **DATA-05**: Firebase anonymous auth replaces Supabase anonymous auth with same frictionless UX
- [x] **DATA-06**: `firebase_core` bumped to 4.6.0+, all Firebase dependencies updated

### Groups

- [x] **GRP-01**: User can create a group with a name and invite code
- [x] **GRP-02**: User can join a group via invite link or code
- [x] **GRP-03**: User can see all members in a group
- [ ] **GRP-04**: Group dashboard shows total spent across all events, member count, and per-member running balances
- [ ] **GRP-05**: Group activity log shows group-level events ("Ahmed added camping trip", "Sara settled with Khalid")
- [x] **GRP-06**: User can view list of groups they belong to on home screen
- [x] **GRP-07**: Group persists independently of events — members remain even when no active event

### Events

- [ ] **EVT-01**: User can create an event inside a group
- [x] **EVT-02**: Event creation offers type selection: Trip, Camping, Travel, Night/Day Out, Custom
- [x] **EVT-03**: Event type controls which modules are visible (Trip = all modules, Night Out = ledger only, etc.)
- [ ] **EVT-04**: Event type pre-fills relevant content (Camping adds tent/sleeping bag/cooler to gear list)
- [x] **EVT-05**: Custom events let user pick modules manually with no preset content
- [ ] **EVT-06**: Group members are pre-populated as event participants (user can add/remove)
- [ ] **EVT-07**: Event timeline in group shows chronological list of past and upcoming events with financial totals
- [ ] **EVT-08**: Existing trip functionality (ledger, gear, logistics, vault, activity, memories) works within events

### Cross-Event Financials

- [ ] **FIN-01**: Per-event balance shows what each member owes/is owed within that event
- [ ] **FIN-02**: Group-level balance shows net balance per member across ALL events in the group
- [ ] **FIN-03**: User can toggle between per-event and group-level balance view
- [ ] **FIN-04**: Cross-event settle-up: "You owe Nasser 15.500 across 3 events — settle now?"
- [ ] **FIN-05**: Group-level balance updates via write-time aggregation when settlements or expenses change
- [ ] **FIN-06**: Group spending stats: total spent across all events, per-member contribution breakdown
- [ ] **FIN-07**: Settlement optimization works at both event and group level

### Firestore Migration

- [ ] **MIG-01**: All per-event writes (expenses, settlements, gear, etc.) go through Firestore instead of Supabase
- [ ] **MIG-02**: Firestore realtime listeners replace Supabase Realtime subscriptions
- [ ] **MIG-03**: Firestore offline persistence replaces manual sync queue (`SyncService` deleted, not ported)
- [ ] **MIG-04**: SQLite retained for fast local reads and balance computation queries
- [ ] **MIG-05**: `FirestoreRepository` is the single Firestore contact point — all access flows through it
- [ ] **MIG-06**: Existing trip data migrated from Supabase to Firestore via invite-code recovery flow
- [ ] **MIG-07**: `supabase_flutter` dependency completely removed

### Testing

- [ ] **TST-01**: Unit tests for all financial calculations (balance, settlement optimization, cross-event aggregation)
- [ ] **TST-02**: Widget tests for group dashboard, event creation, balance toggle
- [x] **TST-03**: Integration tests using `fake_cloud_firestore` — no real Firebase calls in tests
- [x] **TST-04**: Firestore security rules tested via Firebase Emulator
- [ ] **TST-05**: 80%+ code coverage enforced
- [ ] **TST-06**: Offline scenario tests (write while offline, verify sync on reconnect)

## v2 Requirements

### Enhancements

- **ENH-01**: Riverpod 3.x upgrade (after Firestore migration is stable)
- **ENH-02**: GoRouter upgrade from 13.x to latest
- **ENH-03**: Deep linking into group/event screens
- **ENH-04**: Group-level push notifications (new event, balance change)
- **ENH-05**: Export group financial summary as PDF

## Out of Scope

| Feature | Reason |
|---------|--------|
| In-app chat/messaging | Complexity trap — let WhatsApp handle messaging, Rihla does money |
| Complex roles/permissions | Friend groups don't think in org charts — member/non-member is enough |
| Analytics/spending insights | Feature theatre — no one opens an expense app for spending insights |
| Social reactions on expenses | Users found this creepy on financial transactions (Splitwise tried, pulled back) |
| Real-time collaborative editing | Conflict resolution rabbit hole — last-write-wins is fine for expenses |
| Web app / desktop | Mobile-first — coordination happens in the field |
| Recurring expenses | Relevant for household apps, not event-based groups |
| AI expense categorization | Requires ML infra, degrades offline reliability, poor OMR merchant accuracy |

## Traceability

| Requirement | Phase | Status |
|-------------|-------|--------|
| DATA-01 | Phase 1 | Complete |
| DATA-02 | Phase 1 | Complete |
| DATA-03 | Phase 1 | Complete |
| DATA-04 | Phase 1 | Complete |
| DATA-05 | Phase 1 | Complete |
| DATA-06 | Phase 1 | Complete |
| TST-03 | Phase 1 | Complete |
| TST-04 | Phase 1 | Complete |
| GRP-01 | Phase 2 | Complete |
| GRP-02 | Phase 2 | Complete |
| GRP-03 | Phase 2 | Complete |
| GRP-06 | Phase 2 | Complete |
| GRP-07 | Phase 2 | Complete |
| EVT-01 | Phase 3 | Pending |
| EVT-02 | Phase 3 | Complete |
| EVT-03 | Phase 3 | Complete |
| EVT-04 | Phase 3 | Pending |
| EVT-05 | Phase 3 | Complete |
| EVT-06 | Phase 3 | Pending |
| EVT-07 | Phase 3 | Pending |
| EVT-08 | Phase 3 | Pending |
| MIG-01 | Phase 4 | Pending |
| MIG-02 | Phase 4 | Pending |
| MIG-03 | Phase 4 | Pending |
| MIG-04 | Phase 4 | Pending |
| MIG-05 | Phase 4 | Pending |
| FIN-01 | Phase 5 | Pending |
| FIN-02 | Phase 5 | Pending |
| FIN-03 | Phase 5 | Pending |
| FIN-04 | Phase 5 | Pending |
| FIN-05 | Phase 5 | Pending |
| FIN-06 | Phase 5 | Pending |
| FIN-07 | Phase 5 | Pending |
| GRP-04 | Phase 5 | Pending |
| GRP-05 | Phase 5 | Pending |
| TST-01 | Phase 6 | Pending |
| TST-02 | Phase 6 | Pending |
| TST-05 | Phase 6 | Pending |
| TST-06 | Phase 6 | Pending |
| MIG-06 | Phase 7 | Pending |
| MIG-07 | Phase 7 | Pending |

**Coverage:**
- v1 requirements: 41 total
- Mapped to phases: 41
- Unmapped: 0 ✓

---
*Requirements defined: 2026-03-26*
*Last updated: 2026-03-26 after roadmap creation (traceability updated to match 7-phase roadmap)*
