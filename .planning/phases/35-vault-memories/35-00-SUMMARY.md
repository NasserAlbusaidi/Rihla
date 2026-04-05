---
phase: 35-vault-memories
plan: "00"
subsystem: testing
tags: [flutter, tdd, widget-tests, offline-banner, vault, memories]

# Dependency graph
requires:
  - phase: 34-gear-logistics
    provides: OfflineBanner test stub pattern (gear_screen_mutations_test.dart, logistics_screen_mutations_test.dart)
provides:
  - Failing OfflineBanner widget test for VaultScreen (RED state)
  - Failing OfflineBanner widget test for MemoriesScreen (RED state)
affects:
  - 35-01 (Wave 1 implementation — must turn these tests green)

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "TDD RED stub: create failing test asserting OfflineBanner renders before adding OfflineBanner to screen"
    - "Minimal wrapper helper: ProviderScope with only the providers the screen directly watches"

key-files:
  created:
    - test/features/vault_screen_mutations_test.dart
    - test/features/memories_screen_mutations_test.dart
  modified: []

key-decisions:
  - "No connectivityProvider override needed in test wrapper — OfflineBanner watches it internally and the screen does not yet render OfflineBanner, so it never fires"
  - "documentLoadingProvider must be overridden in VaultScreen wrapper to prevent StateProvider initialization issues"
  - "MemoriesScreen wrapper needs only eventDetailProvider + eventMemoriesProvider — no service mock required"

patterns-established:
  - "Vault/Memories test wrapper pattern: eventDetailProvider + data provider + optional loading provider"

requirements-completed:
  - VAULT-OFFLINE
  - MEMORIES-OFFLINE

# Metrics
duration: 2min
completed: 2026-04-05
---

# Phase 35 Plan 00: Vault & Memories — OfflineBanner Failing Test Stubs

**Two TDD RED-state test stubs asserting OfflineBanner renders in VaultScreen and MemoriesScreen bodies (Wave 0 before implementation)**

## Performance

- **Duration:** 2 min
- **Started:** 2026-04-05T12:09:57Z
- **Completed:** 2026-04-05T12:11:06Z
- **Tasks:** 2
- **Files modified:** 2

## Accomplishments

- Created `test/features/vault_screen_mutations_test.dart` with one failing test (VaultScreen — OfflineBanner renders in body)
- Created `test/features/memories_screen_mutations_test.dart` with one failing test (MemoriesScreen — OfflineBanner renders in body)
- Both tests compile, fail correctly with "Found 0 widgets with type OfflineBanner", establishing RED state for Wave 1

## Task Commits

Each task was committed atomically:

1. **Task 1: vault_screen_mutations_test.dart failing OfflineBanner stub** - `2847667` (test)
2. **Task 2: memories_screen_mutations_test.dart failing OfflineBanner stub** - `5edf69d` (test)

## Files Created/Modified

- `test/features/vault_screen_mutations_test.dart` - Failing test asserting OfflineBanner renders in VaultScreen body
- `test/features/memories_screen_mutations_test.dart` - Failing test asserting OfflineBanner renders in MemoriesScreen body

## Decisions Made

- No `connectivityProvider` override in test wrappers: OfflineBanner watches it internally, but since OfflineBanner doesn't exist in either screen yet, the provider is never referenced during the test. This matches the gear_screen_mutations_test.dart pattern (no connectivityProvider override there either).
- `documentLoadingProvider.overrideWith((ref) => false)` added to VaultScreen wrapper to avoid StateProvider initialization issues (VaultScreen directly watches this provider).
- MemoriesScreen wrapper is minimal (eventDetailProvider + eventMemoriesProvider) — no service mock needed for a stub test.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] Worktree was 712 commits behind main before tests could run**
- **Found during:** Task 1 setup
- **Issue:** The worktree branched from the old Supabase-based codebase (commit c06e4c3). The plan was written for the current Firebase-based v2.x codebase. Providers like `eventDetailProvider`, `eventDocumentsProvider`, `eventMemoriesProvider`, and `EventRef` type did not exist in the worktree.
- **Fix:** Merged `main` into the worktree branch (`git merge main --no-edit`) to bring it up to the current state.
- **Files modified:** All 700+ files that had accumulated on main since the worktree was created
- **Verification:** After merge, vault_screen.dart uses `groupId/eventId` string params and watches `eventDetailProvider`/`eventDocumentsProvider`; memories_screen.dart watches `eventDetailProvider`/`eventMemoriesProvider`
- **Committed in:** Pre-existing merge commit (not part of task commits)

---

**Total deviations:** 1 auto-fixed (1 blocking)
**Impact on plan:** Blocking fix required before any test work could proceed. No scope creep — merge only brought worktree up to date.

## Issues Encountered

None during test authoring — once codebase was current, both tests were straightforward port of the gear/logistics test stub pattern.

## Known Stubs

Both test files contain intentionally failing assertions — these are the stubs Wave 1 will resolve by adding OfflineBanner to the screen bodies. They are tracked here:

| File | Line | Stub | Resolved By |
|------|------|------|-------------|
| test/features/vault_screen_mutations_test.dart | 67 | `find.byType(OfflineBanner)` FAILS | Plan 35-01 adds OfflineBanner to VaultScreen |
| test/features/memories_screen_mutations_test.dart | 67 | `find.byType(OfflineBanner)` FAILS | Plan 35-01 adds OfflineBanner to MemoriesScreen |

These stubs are intentional — RED state is the goal of Plan 00.

## Next Phase Readiness

- Both test files exist and fail correctly — Wave 1 (Plan 35-01) can proceed
- Wave 1 must add `const OfflineBanner()` after ModuleHeader in both screen bodies and replace hardcoded `Color(0xFF...)` gradients with AppColorTokens
- No blockers

---
*Phase: 35-vault-memories*
*Completed: 2026-04-05*
