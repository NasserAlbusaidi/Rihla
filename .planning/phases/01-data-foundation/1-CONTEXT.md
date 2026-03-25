# Phase 1: Data Foundation - Context

**Gathered:** 2026-03-26
**Status:** Ready for planning

<domain>
## Phase Boundary

Firestore initialized alongside existing Supabase. Security rules deployed and tested. Integer money storage enforced with currency-aware scaling. SQLite schema extended with groups/group_members/group_ledger tables. Firebase anonymous auth active (dual auth with Supabase). No UI deliverables — this phase gates all feature work.

</domain>

<decisions>
## Implementation Decisions

### Money Serialization
- **D-01:** Store monetary values as integer subunits in Firestore (fils for OMR, cents for USD/EUR, units for JPY). No doubles, no strings.
- **D-02:** Currency-aware scaling: OMR = 1000x, USD/EUR = 100x, JPY = 1x. The serializer takes currency code into account.
- **D-03:** Each expense/settlement document carries its own `{amount_fils: int, currency: String}` pair. Self-describing, not inherited from parent.
- **D-04:** `Decimal` package remains for all client-side math. Conversion to/from subunits happens at the Firestore boundary only.

### Auth Transition
- **D-05:** Dual auth in Phase 1. Both Supabase and Firebase anonymous sessions active. Existing features keep talking to Supabase. Firebase auth is initialized and ready for Phase 2 group features.
- **D-06:** `main.dart` bootstrap becomes: Sentry → Firebase (already there) → Firebase anonymous auth → Supabase init → Supabase anonymous session → SharedPreferences → runApp.
- **D-07:** Firebase anonymous auth uses `FirebaseAuth.instance.signInAnonymously()` if no current user. Same silent pattern as Supabase.

### Firestore Emulator
- **D-08:** Firebase Emulator configured for Firestore + Auth. Project root gets a `firebase.json` with emulator config.
- **D-09:** Security rule tests use the official JS `@firebase/rules-unit-testing` SDK for accurate rule validation. Separate from Dart tests.
- **D-10:** Dart tests use `fake_cloud_firestore` for unit/integration tests. No emulator dependency for CI speed.
- **D-11:** Both test ecosystems must pass: JS rule tests verify security, Dart tests verify app logic.

### SQLite Schema Extension
- **D-12:** SQLite version bumps to 6. New tables: `groups`, `group_members`, `group_ledger`. Added in `_onUpgrade` migration.
- **D-13:** Existing tables untouched in this phase. No renaming trips→events yet (that's Phase 3).

### Firestore Security Rules
- **D-14:** Group membership checked via `memberIds` array field on the group document. Rules use `.hasAny([request.auth.uid])` for O(1) lookup.
- **D-15:** Rules deployed to the emulator first. Never deployed to production without passing JS rule tests.

### Claude's Discretion
- Money serializer implementation pattern (utility class vs extension vs repository-internal)
- FirebaseConfig wrapper class design (mirror SupabaseConfig or lighter approach)
- Emulator startup approach (script vs test-integrated)
- Exact SQLite table schemas for groups/group_members/group_ledger
- Firebase package version pinning strategy

</decisions>

<specifics>
## Specific Ideas

No specific requirements — open to standard approaches. The main concern is getting the foundation right so downstream phases don't hit precision bugs or security issues.

</specifics>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Money and Firestore
- `.planning/research/STACK.md` — Firebase package versions, Decimal storage strategy, fake_cloud_firestore version
- `.planning/research/PITFALLS.md` — Pitfall on IEEE 754 doubles, FlutterFire issue #9626, FieldValue.increment bug

### Security Rules
- `.planning/research/ARCHITECTURE.md` — Firestore collection structure, memberIds security pattern, 10-get limit
- `.planning/research/PITFALLS.md` — Pitfall on security rule get() limit, Supabase RLS migration history

### Auth
- `.planning/research/STACK.md` — firebase_auth version, anonymous auth persistence notes
- `.planning/research/PITFALLS.md` — Anonymous UID loss on reinstall, token expiry during offline

### Existing Code
- `lib/core/config/supabase_config.dart` — Current init + anonymous auth pattern to mirror for Firebase
- `lib/core/services/local_database.dart` — SQLite migration pattern (_onCreate, _onUpgrade) to extend
- `lib/features/auth/providers/auth_provider.dart` — Current Supabase auth providers (will need Firebase equivalents)

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `SupabaseConfig` pattern (init + anonymous auth + logging) — mirror for FirebaseConfig
- `LocalDatabase._onUpgrade()` migration chain — extend to v6 for groups tables
- `Decimal` package usage throughout ledger — conversion boundary is well-defined
- `firebase_options.dart` already exists (FCM configured) — Firestore just needs enabling

### Established Patterns
- Provider-throws-then-override pattern (`sharedPreferencesProvider`) — use same for Firebase instances
- Static service classes (`CacheService`, `SyncService`) — FirestoreRepository should follow similar static pattern or be provided via Riverpod
- `_databaseVersion` bump + `_onUpgrade` switch for SQLite migrations

### Integration Points
- `main.dart` bootstrap sequence — Firebase Auth init inserts after Firebase.initializeApp
- `pubspec.yaml` — needs `cloud_firestore`, `firebase_auth` (bump), `fake_cloud_firestore` (dev)
- `config.json` — may no longer need SUPABASE_URL/ANON_KEY long-term but keep for now (dual auth)

</code_context>

<deferred>
## Deferred Ideas

- Renaming `trips` table to `events` in SQLite — Phase 3
- FirestoreRepository class — Phase 4 (this phase only sets up Firestore, doesn't migrate writes)
- Removing SupabaseConfig — Phase 7
- GoRouter upgrade — Phase 2 when adding group routes

</deferred>

---

*Phase: 01-data-foundation*
*Context gathered: 2026-03-26*
