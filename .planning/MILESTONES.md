# Milestones

## v1.0 Groups, Events & Cross-Event Financials (Shipped: 2026-03-28)

**Phases:** 13 | **Plans:** 43 | **Tasks:** 78
**Timeline:** 91 days (2025-12-27 → 2026-03-28)
**Codebase:** 24,895 LOC Dart | 624 tests | 80%+ coverage | 411 commits

**Delivered:** Evolved the Rihla trip-planning app into a persistent group coordination platform with cross-event financial tracking, while fully migrating the backend from Supabase to Firebase Firestore.

**Key accomplishments:**

1. **Firebase backend migration** — Supabase fully removed; all reads/writes through Firestore with security rules (22 JS tests), offline persistence, and realtime listeners
2. **Persistent groups** — Create/join groups with invite codes; groups persist across events and app restarts; groups-first home screen
3. **Typed events with templates** — 5 event types (Trip, Camping, Travel, Night/Day Out, Custom) with template-driven module selection and gear presets
4. **Cross-event financials** — Group-level running balances across all events, cross-event settle-up with optimization, group spending stats and activity log
5. **FirestoreRepository architecture** — Single Firestore contact point for all 9 services, asyncMap SQLite side-write pipeline, BalanceCacheRepository for fast local reads
6. **80%+ test coverage** — CI-enforced coverage gate, offline scenario tests, Firestore model round-trip tests, exhaustive BalanceCalculator tests across all 4 scopes

**Tech debt carried forward:**
- Event edit/delete UI deferred (EventService methods exist but no UI caller)
- Category CRUD stubs (custom categories deferred)
- Nyquist validation gaps on 9 phases (documentation, not functional)

---
