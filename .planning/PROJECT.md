# Rihla v2 — Groups & Events

## What This Is

Rihla is a Flutter mobile app for group coordination and event planning. Users create or join persistent groups (friend circles, travel crews), then spin up events inside those groups — trips, camping weekends, day outs, dinners, or custom events. Each event type comes with a template that unlocks relevant modules and pre-fills content. The app tracks finances at both the event level and the group level, maintaining running balances across all events ("you still owe me from 3 trips ago").

This is an evolution of the existing Rihla trip-planning app, adding a groups layer on top while migrating the backend from Supabase to Firebase Firestore.

## Core Value

Groups persist across events and accumulate financial history — friends settle up across trips, not just within one.

## Requirements

### Validated

- ✓ Offline-first with Firestore built-in persistence + SQLite balance cache — v1.0 Phase 4
- ✓ Expense tracking with Decimal precision (OMR, 3 decimal places) — pre-v1.0
- ✓ Balance calculation across four scopes (global, subGroup, personal, custom) — pre-v1.0
- ✓ Settlement optimization (greedy min-transactions) — pre-v1.0
- ✓ Gear checklist with assignment and priority — v1.0 Phase 11
- ✓ Sub-group logistics (car assignments, capacity) — v1.0 Phase 12
- ✓ Name-based members (no profile table joins) — pre-v1.0
- ✓ Anonymous auth via Firebase — v1.0 Phase 1
- ✓ Activity feed per event — pre-v1.0
- ✓ Document vault with signed URLs — pre-v1.0
- ✓ Trip memories (photo/media uploads) — pre-v1.0
- ✓ Onboarding flow — pre-v1.0
- ✓ FCM push notifications — pre-v1.0
- ✓ Multi-currency support — pre-v1.0
- ✓ Persistent groups — create/join a group, reuse across events — v1.0 Phase 2
- ✓ Group dashboard — member list, running balances across all events, group stats — v1.0 Phase 5
- ✓ Cross-event balance tracking — net balances accumulate at the group level — v1.0 Phase 5
- ✓ Event types with templates — Trip, Camping, Travel, Night/Day Out, Custom — v1.0 Phase 3
- ✓ Template-driven modules — event type controls which modules appear — v1.0 Phase 3
- ✓ Template presets — camping adds tent/sleeping bag to gear — v1.0 Phase 3
- ✓ Custom events — user picks modules manually, no preset content — v1.0 Phase 3
- ✓ Supabase → Firestore migration — supabase_flutter fully removed, Firebase-only — v1.0 Phase 7
- ✓ Firestore security rules — replace RLS with path-based Firestore rules — v1.0 Phase 1
- ✓ Firestore realtime listeners — replace unreliable Supabase Realtime — v1.0 Phase 4
- ✓ Strict test coverage — 80%+ coverage, CI-enforced, 624 tests — v1.0 Phase 6
- ✓ Event timeline in group — chronological list of past/upcoming events — v1.0 Phase 3
- ✓ Cross-event settle-up with optimization — v1.0 Phase 5
- ✓ Group activity log — v1.0 Phase 5

## Current Milestone: v2.0 Major UI/UX Overhaul

**Goal:** Transform Rihla from a functional but visually barren app into an eye-catching, richly designed experience with flatter navigation and rethought screen layouts.

**Target features:**
- Design system via Google Stitch — warm, earthy palette (terracotta, sand, olive), light theme only
- Rich dashboard home — single-scroll with balance summary, inline group cards, recent activity, quick actions
- Flatter navigation — reduce 3-4 tap depth, key content accessible sooner
- Full screen redesign — every screen gets the new visual language
- UX flow rethink — screen layouts, information density, interaction patterns
- Visual richness — illustrations, color, texture, micro-interactions
- Stitch-first workflow: design in Stitch → extract design tokens → implement in Flutter

### Active

(Requirements being defined — see REQUIREMENTS.md)

### Out of Scope

- Chat/messaging — high complexity, not core to coordination value
- OAuth/social login — anonymous auth works, adding login adds friction
- Web app — mobile-first, Flutter only
- Payment processing beyond Thawani — OMR-focused market
- AI/ML features — keep it simple and focused

## Context

- **Codebase**: 24,895 LOC Dart across ~130 files, feature-first architecture (auth, trip, ledger, gear, logistics, vault, activity, home, settings, memories, onboarding, groups, events)
- **Architecture**: Riverpod 2.x state management, GoRouter declarative routing (all navigation via context.push/go, zero Navigator.push except FullScreenPhoto overlay), SQLite offline cache, Firebase Firestore backend (Supabase fully removed)
- **Backend**: Firebase-only — firebase_core 4.x, cloud_firestore 6.x, firebase_auth 6.x, firebase_storage 13.x. Anonymous auth. Emulator configured (Firestore:8080, Auth:9099)
- **Data layer**: FirestoreRepository base class → 9 services. asyncMap SQLite side-write pipeline. BalanceCacheRepository for fast local balance queries
- **Financial precision**: All money math uses `Decimal` package, stored as integer fils in Firestore via MoneySerializer. Currency is OMR (3 decimal places)
- **Testing**: 752 tests, 80%+ coverage CI-enforced, fake_cloud_firestore for integration tests
- **User base**: Small, Oman-focused. Anonymous auth (no user accounts)
- **v1.0 shipped**: 2026-03-28 — groups, events, cross-event financials, full Firestore migration

## Constraints

- **Tech stack**: Flutter + Firebase (Firestore, Auth, FCM, Storage). Keep SQLite for fast local reads
- **Testing**: TDD mandatory. 80%+ coverage. No shipping without tests
- **Financial precision**: Decimal package for all money. OMR 3 decimal places. No floating point
- **Offline-first**: App must work without connectivity. Firestore offline persistence + SQLite cache
- **Migration complete**: Supabase fully removed (v1.0 Phase 7). Old trip data abandoned per D-01; users start fresh with groups+events
- **Anonymous auth**: Keep frictionless entry. Firebase anonymous auth replaces Supabase anonymous auth

## Key Decisions

| Decision | Rationale | Outcome |
|----------|-----------|---------|
| Groups wrap trips (not replace) | Preserves existing trip experience, adds layer on top | Validated v1.0 — Trip facade bridges events to trip-based module screens |
| Firestore over Realtime DB | Better querying, offline support, scales well | Validated v1.0 — 9 services on Firestore, realtime listeners working |
| Both event-level and group-level ledger | Cross-event balances are the killer feature | Validated v1.0 — groupBalancesProvider aggregates across all events |
| Fine-grained phases | Complex migration + new features need careful sequencing | Validated v1.0 — 13 phases, each independently verifiable |
| Keep SQLite alongside Firestore | Fast local reads, existing offline architecture works well | Validated v1.0 — BalanceCacheRepository serves balance queries from SQLite |
| Integer subunits for Firestore money | Store amounts as integer fils/cents, not strings or floats | Validated v1.0 — MoneySerializer uses currency-aware scaling, zero drift |
| Dual-auth bootstrap | Firebase anon auth runs alongside Supabase during migration | Completed v1.0 Phase 7 — Supabase removed, Firebase-only |
| Abandon old trip data (D-01) | Recovery flow adds scope without user value; users start fresh | Decided v1.0 Phase 7 — MIG-06 descoped |
| asyncMap SQLite side-write | Keep SQLite in sync via Firestore snapshot pipeline | Validated v1.0 Phase 4 — reliable side-write, offline tests pass |
| Riverpod 2.x (defer 3.x) | Breaking changes compound risk with Firestore migration | Validated v1.0 — stable throughout; 3.x upgrade deferred to future milestone |
| ThemeExtension token system | Typed tokens over raw static constants; enables future theme switching | Validated v2.0 Phase 15 — AppColorTokens, AppSpacingTokens, AppShadowTokens wired into ThemeData |
| Earthy palette (terracotta/sand/olive) | Warm, distinctive identity replacing generic neon-mint | Validated v2.0 Phase 15 — WCAG AA compliant, CI lint enforces token usage |
| Dashboard-first home screen | Single-scroll dashboard with balance hero, quick actions, group cards, activity, spending chart | Validated v2.0 Phase 18 — NAV-01, NAV-02, NAV-04, NAV-06 satisfied, 743 tests |
| Group detail stats grid + event hub grid | Scannable dashboards: 2x2 stats grid on group detail, 2x3 module grid on event hub, corrected module colors | Validated v2.0 Phase 20 — SCRN-01, SCRN-02 satisfied, 752 tests |

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
*Last updated: 2026-03-28 — Phase 14 (Test Hardening) complete. 12 key class files, 127 find.byKey() calls, CI regression gate. Ready for Phase 15 (Design Token System).*
