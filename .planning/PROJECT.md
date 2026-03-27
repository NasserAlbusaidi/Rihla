# Rihla v2 — Groups & Events

## What This Is

Rihla is a Flutter mobile app for group coordination and event planning. Users create or join persistent groups (friend circles, travel crews), then spin up events inside those groups — trips, camping weekends, day outs, dinners, or custom events. Each event type comes with a template that unlocks relevant modules and pre-fills content. The app tracks finances at both the event level and the group level, maintaining running balances across all events ("you still owe me from 3 trips ago").

This is an evolution of the existing Rihla trip-planning app, adding a groups layer on top while migrating the backend from Supabase to Firebase Firestore.

## Core Value

Groups persist across events and accumulate financial history — friends settle up across trips, not just within one.

## Requirements

### Validated

These exist in the current codebase and work:

- ✓ Offline-first with Firestore built-in persistence + SQLite balance cache — Phase 4
- ✓ Expense tracking with Decimal precision (OMR, 3 decimal places) — existing
- ✓ Balance calculation across four scopes (global, subGroup, personal, custom) — existing
- ✓ Settlement optimization (greedy min-transactions) — existing
- ✓ Gear checklist with assignment and priority — existing
- ✓ Sub-group logistics (car assignments, capacity) — existing
- ✓ Name-based members (no profile table joins) — existing
- ✓ Anonymous auth via Firebase — Phase 1
- ✓ Activity feed per trip — existing
- ✓ Document vault with signed URLs — existing
- ✓ Trip memories (photo/media uploads) — existing
- ✓ Onboarding flow — existing
- ✓ FCM push notifications — existing
- ✓ Multi-currency support — existing

### Active

- [ ] Persistent groups — create/join a group, reuse across events
- [ ] Group dashboard — member list, running balances across all events, group stats
- [ ] Cross-event balance tracking — net balances accumulate at the group level
- [ ] Event types with templates — Trip, Camping, Travel, Night/Day Out, Custom
- [ ] Template-driven modules — event type controls which modules appear (ledger, gear, logistics, vault, etc.)
- [ ] Template presets — event type pre-fills relevant content (camping adds tent/sleeping bag to gear)
- [ ] Custom events — user picks modules manually, no preset content
- ✓ Supabase → Firestore migration — supabase_flutter fully removed, Firebase-only — Phase 7
- ✓ Firestore security rules — replace RLS with path-based Firestore rules — Phase 1
- ✓ Firestore realtime listeners — replace unreliable Supabase Realtime — Phase 4
- [ ] Strict test coverage — TDD enforcement, 80%+ coverage, unit/widget/integration tests
- [ ] Event timeline in group — chronological list of past/upcoming events

### Out of Scope

- Chat/messaging — high complexity, not core to coordination value
- OAuth/social login — anonymous auth works, adding login adds friction
- Web app — mobile-first, Flutter only
- Payment processing beyond Thawani — OMR-focused market
- AI/ML features — keep it simple and focused

## Context

- **Existing codebase**: ~100 Dart files, feature-first architecture (auth, trip, ledger, gear, logistics, vault, activity, home, settings, memories, onboarding)
- **Current architecture**: Riverpod 2.x state management, GoRouter + Navigator.push routing, SQLite offline cache, Firebase Firestore backend (Supabase fully removed in Phase 7)
- **Pain points driving change**: Supabase RLS complexity (4 fix migrations), unreliable Realtime subscriptions, no persistent group concept — all resolved by Firebase migration
- **Firebase fully initialized**: firebase_core 4.x, cloud_firestore 6.x, firebase_auth 6.x, firebase_storage 13.x. Firebase-only auth (anonymous). Emulator configured (Firestore:8080, Auth:9099)
- **Offline-first architecture**: OfflineRepository → CacheService → SyncService pipeline. SQLite v6 extended with groups/group_members/group_ledger tables. Firestore offline persistence coexists alongside SQLite
- **Financial precision**: All money math uses `Decimal` package, currency is OMR (3 decimal places). This must not regress during migration
- **User base**: Small, Oman-focused. Anonymous auth means no user accounts to migrate — just data

## Constraints

- **Tech stack**: Flutter + Firebase (Firestore, Auth, FCM, Storage). Keep SQLite for fast local reads
- **Testing**: TDD mandatory. 80%+ coverage. No shipping without tests
- **Financial precision**: Decimal package for all money. OMR 3 decimal places. No floating point
- **Offline-first**: App must work without connectivity. Firestore offline persistence + SQLite cache
- **Migration complete**: Supabase fully removed (Phase 7). Old trip data abandoned per D-01; users start fresh with groups+events
- **Anonymous auth**: Keep frictionless entry. Firebase anonymous auth replaces Supabase anonymous auth

## Key Decisions

| Decision | Rationale | Outcome |
|----------|-----------|---------|
| Groups wrap trips (not replace) | Preserves existing trip experience, adds layer on top | — Pending |
| Firestore over Realtime DB | Better querying, offline support, scales well | Validated in Phase 01 |
| Both event-level and group-level ledger | Cross-event balances are the killer feature | — Pending |
| Fine-grained phases | Complex migration + new features need careful sequencing | Validated in Phase 01 |
| Keep SQLite alongside Firestore | Fast local reads, existing offline architecture works well | Validated in Phase 01 |
| Integer subunits for Firestore money | Store amounts as integer fils/cents, not strings or floats | Decided in Phase 01 — MoneySerializer uses currency-aware scaling |
| Dual-auth bootstrap | Firebase anon auth runs alongside Supabase during migration | Decided in Phase 01 — completed in Phase 07: Supabase removed, Firebase-only |
| Abandon old trip data (D-01) | Recovery flow adds scope without user value; users start fresh | Decided in Phase 07 — MIG-06 descoped |

## Evolution

This document evolves at phase transitions and milestone boundaries.

**After each phase transition** (via `/gsd:transition`):
1. Requirements invalidated? → Move to Out of Scope with reason
2. Requirements validated? → Move to Validated with phase reference
3. New requirements emerged? → Add to Active
4. Decisions to log? → Add to Key Decisions
5. "What This Is" still accurate? → Update if drifted

**After each milestone** (via `/gsd:complete-milestone`):
1. Full review of all sections
2. Core Value check — still the right priority?
3. Audit Out of Scope — reasons still valid?
4. Update Context with current state

---
*Last updated: 2026-03-27 after Phase 08 (integration-correctness-fixes) completion — custom split participants fixed (EVT-08), settle-up event names fixed (FIN-04), trip_id column documentation added*
