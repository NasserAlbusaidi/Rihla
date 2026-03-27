---
phase: 01-data-foundation
plan: 01
subsystem: auth
tags: [firebase, firebase-auth, firebase-core, cloud-firestore, anonymous-auth, riverpod, dual-auth]

# Dependency graph
requires: []
provides:
  - firebase_core 4.x and cloud_firestore 6.x available in the project
  - firebase_auth 6.x available for anonymous authentication
  - FirebaseConfig wrapper class with initialize(), ensureAnonymousSession(), auth/firestore getters
  - Dual-auth bootstrap in main.dart (Firebase then Supabase)
  - firebaseAuthStateProvider and firebaseCurrentUserProvider Riverpod providers
  - Automated behavioral tests proving Firebase anonymous auth contract (DATA-05)
affects: [01-02, 01-03, all-downstream-plans-in-phase-01]

# Tech tracking
tech-stack:
  added:
    - firebase_core ^4.6.0 (upgraded from ^3.12.1)
    - cloud_firestore ^6.2.0 (new)
    - firebase_auth ^6.3.0 (new)
    - firebase_messaging ^16.1.3 (upgraded from ^15.2.4 — forced by firebase_core 4.x compatibility)
    - fake_cloud_firestore ^4.1.0+1 (new dev dep)
    - firebase_auth_mocks ^0.15.1 (new dev dep — bumped from ^0.14.0 for firebase_core 4.x compat)
  patterns:
    - "FirebaseConfig mirrors SupabaseConfig: static class with initialize(), ensureAnonymousSession(), getters, log()"
    - "Dual-auth bootstrap order: Sentry -> Firebase init -> Firebase anon auth -> Supabase init -> Supabase anon auth -> SharedPreferences -> runApp"
    - "Firebase auth providers use firebase_auth prefix to avoid collision with Supabase User type"
    - "Firestore settings (persistenceEnabled, cacheSizeBytes) set in initialize() before any other Firestore call"

key-files:
  created:
    - lib/core/config/firebase_config.dart
    - lib/features/auth/providers/firebase_auth_provider.dart
    - test/integration/firebase_auth_test.dart
  modified:
    - pubspec.yaml
    - pubspec.lock
    - lib/main.dart

key-decisions:
  - "firebase_messaging bumped to ^16.1.3 — firebase_messaging 15.x is incompatible with firebase_core 4.x (transitive dependency conflict on firebase_core_platform_interface)"
  - "firebase_auth_mocks bumped to ^0.15.1 — version 0.14.0 requires firebase_core ^3.x which conflicts with firebase_core ^4.6.0"
  - "All other dependencies (flutter_riverpod, go_router, etc.) kept at original versions — Riverpod 3.x migration is a separate future milestone per locked decision"
  - "FirebaseConfig.initialize() sets Firestore persistence settings before any other Firestore call — required to avoid 'settings immutable' runtime error"

patterns-established:
  - "FirebaseConfig static class pattern: mirrors SupabaseConfig for consistency across dual-auth setup"
  - "firebase_auth prefix import: avoids User type collision between firebase_auth and supabase_flutter"

requirements-completed: [DATA-06, DATA-05]

# Metrics
duration: 6min
completed: 2026-03-25
---

# Phase 01 Plan 01: Firebase Dependencies & Anonymous Auth Summary

**Firebase packages upgraded to 4.x/6.x with dual anonymous auth (Firebase + Supabase) wired in bootstrap and 4 passing behavioral tests proving the anonymous auth contract**

## Performance

- **Duration:** 6 min
- **Started:** 2026-03-25T21:09:56Z
- **Completed:** 2026-03-25T21:16:24Z
- **Tasks:** 3
- **Files modified:** 6 (pubspec.yaml, pubspec.lock, lib/main.dart, lib/core/config/firebase_config.dart, lib/features/auth/providers/firebase_auth_provider.dart, test/integration/firebase_auth_test.dart)

## Accomplishments

- Firebase packages upgraded atomically: firebase_core 3.x -> 4.x, cloud_firestore 6.x and firebase_auth 6.x added, test packages added
- FirebaseConfig class created mirroring SupabaseConfig pattern, wired into main.dart dual-auth bootstrap (D-05, D-06, D-07)
- Firestore offline persistence settings configured at initialization time before any Firestore call
- Firebase auth Riverpod providers (firebaseAuthStateProvider, firebaseCurrentUserProvider) ready for downstream features
- All 4 Firebase anonymous auth behavioral tests pass — automated proof of DATA-05 satisfaction

## Task Commits

Each task was committed atomically:

1. **Task 1: Upgrade Firebase packages** - `b8737aa` (chore)
2. **Task 2: Create FirebaseConfig + wire dual-auth bootstrap** - `986e8e2` (feat)
3. **Task 3: Firebase anonymous auth behavioral tests** - `3afe11f` (test)

## Files Created/Modified

- `pubspec.yaml` — Firebase deps upgraded, cloud_firestore/firebase_auth/test packages added
- `pubspec.lock` — Resolved dependency graph with firebase_core 4.x and cloud_firestore 6.x
- `lib/core/config/firebase_config.dart` — FirebaseConfig static class (initialize, ensureAnonymousSession, getters, log)
- `lib/main.dart` — Bootstrap updated: Firebase init -> Firebase anon auth -> Supabase init -> Supabase anon auth
- `lib/features/auth/providers/firebase_auth_provider.dart` — firebaseAuthStateProvider + firebaseCurrentUserProvider
- `test/integration/firebase_auth_test.dart` — 4 behavioral tests for anonymous auth contract

## Decisions Made

- Bumped `firebase_messaging ^15.2.4` to `^16.1.3` (forced by firebase_core 4.x transitive conflict; plan said "do not change" but this was a blocking dependency incompatibility)
- Bumped `firebase_auth_mocks ^0.14.0` to `^0.15.1` (0.14.0 requires firebase_core ^3.x which conflicts with ^4.6.0)
- Kept all other packages at original versions (Riverpod 2.x, go_router 13.x, etc.) per locked decision D-Riverpod-2x

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] firebase_messaging bumped to ^16.1.3**
- **Found during:** Task 1 (dependency resolution)
- **Issue:** `flutter pub get` failed — firebase_messaging ^15.x depends on firebase_core_platform_interface ^5.x, but cloud_firestore ^6.x requires firebase_core_platform_interface ^6.x. These are mutually exclusive.
- **Fix:** Bumped firebase_messaging to ^16.1.3 as recommended by pub solver. firebase_messaging 16.x is compatible with firebase_core 4.x.
- **Files modified:** pubspec.yaml, pubspec.lock
- **Verification:** `flutter pub get` exits 0 with no conflicts
- **Committed in:** b8737aa (Task 1 commit)

**2. [Rule 3 - Blocking] firebase_auth_mocks bumped to ^0.15.1**
- **Found during:** Task 1 (dependency resolution)
- **Issue:** `firebase_auth_mocks ^0.14.0` requires `firebase_core ^3.0.0` which conflicts with `firebase_core ^4.6.0`. Version solving failed.
- **Fix:** Bumped to ^0.15.1 (the version compatible with firebase_core 4.x, determined by pub solver suggestion).
- **Files modified:** pubspec.yaml, pubspec.lock
- **Verification:** `flutter pub get` exits 0 with no conflicts; all tests pass
- **Committed in:** b8737aa (Task 1 commit)

---

**Total deviations:** 2 auto-fixed (both Rule 3 - Blocking)
**Impact on plan:** Both fixes were necessary for the dependency graph to resolve. All other package constraints kept as specified. No scope creep.

## Issues Encountered

- `flutter pub upgrade --major-versions` (run to diagnose compatible firebase_auth_mocks version) inadvertently bumped flutter_riverpod to 3.x and go_router to 17.x — immediately reverted to preserve the locked Riverpod 2.x constraint and other unchanged versions.

## User Setup Required

None - no external service configuration required. Firebase is already configured in the repo (firebase_options.dart exists, google-services.json configured).

## Next Phase Readiness

- Firebase packages available, Firestore and Auth SDKs ready to use
- Dual-auth bootstrap running: Firebase anonymous UID available alongside Supabase session
- firebaseAuthStateProvider ready for downstream features (Phase 2 group creation)
- Plan 02 (MoneySerializer) and Plan 03 (SQLite schema + emulator) can now proceed

---
*Phase: 01-data-foundation*
*Completed: 2026-03-25*

## Self-Check: PASSED

- FOUND: lib/core/config/firebase_config.dart
- FOUND: lib/features/auth/providers/firebase_auth_provider.dart
- FOUND: test/integration/firebase_auth_test.dart
- FOUND: .planning/phases/01-data-foundation/01-01-SUMMARY.md
- FOUND commit: b8737aa (Task 1)
- FOUND commit: 986e8e2 (Task 2)
- FOUND commit: 3afe11f (Task 3)
- All 4 firebase_auth_test.dart tests pass
