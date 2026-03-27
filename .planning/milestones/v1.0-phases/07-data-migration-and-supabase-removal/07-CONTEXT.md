# Phase 7: Data Migration and Supabase Removal - Context

**Gathered:** 2026-03-27
**Status:** Ready for planning

<domain>
## Phase Boundary

Remove the `supabase_flutter` dependency and all Supabase-related code from the codebase. No data migration — old trip data is abandoned. The app boots with Firebase only. After this phase, `flutter pub get` has no Supabase packages and `flutter analyze` reports zero Supabase type references.

</domain>

<decisions>
## Implementation Decisions

### Data Recovery
- **D-01:** No data recovery flow. Old Supabase trip data is abandoned. Users start fresh with groups+events. MIG-06 is descoped from REQUIREMENTS.md.
- **D-02:** `LazyMigrationService` (lib/core/services/lazy_migration_service.dart) is deleted — it exists solely for Supabase→Firestore migration and is no longer needed.

### Deletion Scope
- **D-03:** Delete `supabase_flutter` from pubspec.yaml and all transitive Supabase packages from pubspec.lock.
- **D-04:** Delete `lib/core/config/supabase_config.dart` entirely (98 lines — Supabase init, anonymous auth, logging extension).
- **D-05:** Delete `supabase/` directory (29 SQL migration files) — no longer needed with Firestore backend.
- **D-06:** Delete `lib/features/trip/` directory — legacy trip screens (create_trip, edit_trip, join_trip, manage_members), trip_provider, shadow_provider, trip_export_service. These are pre-groups-and-events code that is fully superseded.
- **D-07:** Clean Supabase imports from files that remain: main.dart, auth_provider.dart, connectivity_provider.dart, notification_service.dart, thawani_service.dart, receipt_service.dart, category_provider.dart, add_expense_screen.dart, and any model files with Supabase references.

### Boot Sequence
- **D-08:** Remove `SupabaseConfig.initialize()` and `SupabaseConfig.ensureAnonymousSession()` from main.dart. Firebase auth (already active) is the sole auth path. No replacement needed — Firebase anonymous auth already runs before the Supabase init.
- **D-09:** Remove `SUPABASE_URL` and `SUPABASE_ANON_KEY` from config.json requirements. Only `SENTRY_DSN` and Firebase config remain.

### Testing
- **D-10:** Remove any test files that import Supabase types or test Supabase-specific flows. Update integration tests if they reference Supabase configuration.
- **D-11:** Verify `flutter test` passes with zero failures after all removals.
- **D-12:** Verify `flutter analyze` reports zero Supabase references.

### Claude's Discretion
- Order of file deletions (bulk vs incremental commits)
- How to handle files that have both Supabase and non-Supabase code (extract useful code vs rewrite)
- Whether to keep supabase/ directory in git history notes or just delete silently
- ConnectivityNotifier changes — currently pings Supabase to check online status, needs Firebase-based check
- Notification service refactoring — remove Supabase token storage, keep FCM logic
- Thawani/receipt service cleanup — may need Supabase refs replaced or services deleted if unused
- Category provider cleanup — remove Supabase-backed category fetching

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Phase 4 Context (migration patterns)
- `.planning/phases/04-firestore-repository-layer/04-CONTEXT.md` — D-03 (hard cutover), D-08 (delete old files immediately), D-17 (bridge removal)

### Requirements
- `.planning/REQUIREMENTS.md` — MIG-06 (descoped), MIG-07 (active target)

### Current Supabase footprint (11 files with imports)
- `lib/core/config/supabase_config.dart` — DELETE entirely
- `lib/core/services/lazy_migration_service.dart` — DELETE entirely
- `lib/main.dart` — Remove Supabase init lines
- `lib/features/auth/providers/auth_provider.dart` — Remove Supabase imports
- `lib/core/providers/connectivity_provider.dart` — Replace Supabase health check
- `lib/core/services/notification_service.dart` — Remove Supabase token storage
- `lib/features/ledger/services/thawani_service.dart` — Remove Supabase refs
- `lib/features/ledger/services/receipt_service.dart` — Remove Supabase refs
- `lib/features/ledger/providers/category_provider.dart` — Remove Supabase-backed fetch
- `lib/features/trip/providers/shadow_provider.dart` — DELETE with trip directory
- `lib/features/trip/providers/trip_provider.dart` — DELETE with trip directory

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `FirebaseConfig` (lib/core/config/firebase_config.dart) — already handles all Firebase init, replaces SupabaseConfig
- `FirebaseAuthProvider` (lib/features/auth/providers/firebase_auth_provider.dart) — already provides anonymous auth via Firebase
- `ConnectivityNotifier` (lib/core/providers/connectivity_provider.dart) — needs Supabase health check replaced with Firebase-based check

### Established Patterns
- Phase 4 D-03: Hard cutover — delete old code immediately, no deprecation markers
- Phase 4 D-08: Old service files deleted when module migrates
- All active features already use Firestore services (GroupService, EventService, ExpenseService, etc.)

### Integration Points
- `main.dart` bootstrap order — remove Supabase init, keep Firebase → anonymous auth → SharedPreferences → runApp
- `pubspec.yaml` — remove `supabase_flutter: ^2.3.4` dependency
- `config.json` — remove SUPABASE_URL and SUPABASE_ANON_KEY entries
- CI workflow — may reference Supabase secrets that can be removed

</code_context>

<specifics>
## Specific Ideas

No specific requirements — straightforward deletion and cleanup. The user explicitly chose to skip data recovery to keep this phase simple.

</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope.

</deferred>

---

*Phase: 07-data-migration-and-supabase-removal*
*Context gathered: 2026-03-27*
