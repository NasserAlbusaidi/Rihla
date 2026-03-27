---
phase: 07-data-migration-and-supabase-removal
plan: 01
subsystem: infrastructure
tags: [supabase-removal, dependency-cleanup, firebase-migration, dead-code]
dependency_graph:
  requires: []
  provides: [supabase-free-codebase, clean-firebase-boot]
  affects: [pubspec.yaml, lib/main.dart, lib/core/router/app_router.dart]
tech_stack:
  removed: [supabase_flutter, app_links, functions_client, gotrue, postgrest, realtime_client, storage_client, supabase, web_socket_channel]
  patterns: [firebase-only-boot, clean-router]
key_files:
  deleted:
    - lib/core/config/supabase_config.dart
    - lib/core/services/lazy_migration_service.dart
    - lib/features/trip/screens/create_trip_screen.dart
    - lib/features/trip/screens/edit_trip_screen.dart
    - lib/features/trip/screens/join_trip_screen.dart
    - lib/features/trip/screens/manage_members_screen.dart
    - lib/features/trip/services/trip_export_service.dart
    - lib/features/trip/providers/shadow_provider.dart
    - lib/features/trip/models/shadow_profile.dart
    - test/unit/lazy_migration_service_test.dart
    - supabase/ (entire directory with 29 SQL migrations + functions)
  modified:
    - pubspec.yaml
    - pubspec.lock
    - lib/main.dart
    - lib/core/router/app_router.dart
    - .github/workflows/release_android.yml
decisions:
  - "config.json is gitignored — Supabase keys removed locally but file not committed (expected, file is in .gitignore)"
  - "D-02 confirmed complete: LazyMigrationService deleted; Supabase data recovery descoped per D-01"
  - "D-04 confirmed complete: SupabaseConfig static class deleted"
  - "D-05 confirmed complete: supabase/ directory with all 29 SQL migrations deleted"
  - "D-06 confirmed complete: legacy trip screens/services deleted; trip_model.dart and trip_provider.dart preserved as still-active consumers"
metrics:
  duration: 4 minutes
  completed: "2026-03-27"
  tasks: 2
  files_changed: 11
  files_deleted: 48
---

# Phase 07 Plan 01: Supabase Removal Summary

## One-liner

Deleted all Supabase-only files (SupabaseConfig, LazyMigrationService, legacy trip screens, 29 SQL migrations) and removed the supabase_flutter package so the app boots on Firebase only.

## What Was Done

### Task 1: Delete all Supabase-only files and directories

Deleted 10 source files and the entire `supabase/` directory tree (29 SQL migrations, 1 Edge Function):

- `lib/core/config/supabase_config.dart` — SupabaseConfig class + SupabaseLogging extension
- `lib/core/services/lazy_migration_service.dart` — Supabase-to-Firestore migration service (318 lines)
- `lib/features/trip/screens/create_trip_screen.dart` — legacy create trip screen
- `lib/features/trip/screens/edit_trip_screen.dart` — legacy edit trip screen
- `lib/features/trip/screens/join_trip_screen.dart` — legacy join trip screen (two-step flow)
- `lib/features/trip/screens/manage_members_screen.dart` — legacy manage members screen
- `lib/features/trip/services/trip_export_service.dart` — Supabase-based trip export
- `lib/features/trip/providers/shadow_provider.dart` — shadow profile provider
- `lib/features/trip/models/shadow_profile.dart` — shadow profile model
- `test/unit/lazy_migration_service_test.dart` — tests for deleted LazyMigrationService
- `supabase/` — entire directory (29 migration files + .temp/ + functions/)

Preserved as still-active:
- `lib/features/trip/models/trip_model.dart` — Trip, TripModules, Participant models (15+ consumers)
- `lib/features/trip/providers/trip_provider.dart` — trip providers used by expense/events screens

**Commit:** `11e3c4d`

### Task 2: Remove supabase_flutter dependency, clean boot sequence, clean router, update CI

1. **pubspec.yaml** — Removed `supabase_flutter: ^2.3.4` and the `# Backend - Supabase` comment
2. **pubspec.lock** — Regenerated via `flutter pub get`; 17 Supabase-related packages removed from lock (supabase_flutter, supabase, gotrue, realtime_client, postgrest, storage_client, functions_client, app_links, web_socket_channel, etc.)
3. **lib/main.dart** — Removed `import 'core/config/supabase_config.dart'`, removed `SupabaseConfig.initialize()` and `SupabaseConfig.ensureAnonymousSession()` calls, updated comment from "Establish Firebase anonymous auth before Supabase (D-06)" to "Establish Firebase anonymous auth"
4. **lib/core/router/app_router.dart** — Removed `import` statements for `create_trip_screen.dart` and `join_trip_screen.dart`, removed `AppRoutes.createTrip` and `AppRoutes.joinTrip` constants, removed the full `// Create Trip` GoRoute block and `// Join Trip` GoRoute block
5. **.github/workflows/release_android.yml** — Removed `lazy_migration_service.dart` and `supabase_config.dart` from the lcov coverage exclusion list
6. **config.json** (local, gitignored) — Updated to contain only `SENTRY_DSN`; Supabase credentials removed

**Commit:** `4868983`

## Verification Results

All plan verification criteria passed:

- `flutter pub get` succeeds with no errors
- `grep -r "supabase_flutter" pubspec.yaml pubspec.lock` — 0 matches
- `grep -r "SupabaseConfig\|supabase_config" lib/main.dart lib/core/router/` — 0 matches
- `test ! -d supabase` — exits 0
- `test ! -f lib/core/config/supabase_config.dart` — exits 0
- `test ! -f lib/core/services/lazy_migration_service.dart` — exits 0
- `test ! -d lib/features/trip/screens` — exits 0
- `test -f lib/features/trip/models/trip_model.dart` — exits 0 (preserved)

## Deviations from Plan

### config.json not committed

- **Found during:** Task 2
- **Issue:** config.json is in `.gitignore` (expected — contains secrets). The plan mentioned updating it but the file is intentionally not version-controlled.
- **Fix:** Updated the local file as specified (SUPABASE_URL and SUPABASE_ANON_KEY removed). No deviation from plan intent — the file change was made, just not committed.
- **Impact:** None. CI creates config.json from the `CONFIG_JSON` secret at build time.

No other deviations — plan executed exactly as written.

## Known Stubs

None. This plan only deleted code; no stub patterns introduced.

## Self-Check: PASSED

Files created/modified verified:
- `pubspec.yaml` — supabase_flutter removed: CONFIRMED
- `lib/main.dart` — no SupabaseConfig references: CONFIRMED
- `lib/core/router/app_router.dart` — no trip routes: CONFIRMED
- `.github/workflows/release_android.yml` — no supabase references: CONFIRMED
- `lib/features/trip/models/trip_model.dart` — preserved: CONFIRMED
- `lib/features/trip/providers/trip_provider.dart` — preserved: CONFIRMED

Commits verified:
- `11e3c4d` — Task 1: delete Supabase files: CONFIRMED
- `4868983` — Task 2: remove dependency and clean boot/router: CONFIRMED
