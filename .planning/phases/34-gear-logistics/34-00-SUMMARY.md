---
phase: 34-gear-logistics
plan: "00"
subsystem: testing
tags: [tdd, gear, logistics, offline-banner, red-state]
dependency_graph:
  requires: []
  provides: [GEAR-OFFLINE test stub, LOGISTICS-OFFLINE test stub]
  affects: [test/features/gear_screen_mutations_test.dart, test/features/logistics_screen_mutations_test.dart]
tech_stack:
  added: []
  patterns: [TDD RED state, OfflineBanner widget test]
key_files:
  created: []
  modified:
    - test/features/gear_screen_mutations_test.dart
    - test/features/logistics_screen_mutations_test.dart
decisions:
  - Reused existing setUp/provider override pattern from both test files; no new helper needed
  - New tests added in their own named group for isolation and clarity
metrics:
  duration: "~3 minutes"
  completed: "2026-04-05"
  tasks_completed: 2
  files_modified: 2
---

# Phase 34 Plan 00: Gear & Logistics OfflineBanner Test Stubs Summary

Wave 0 TDD RED stubs: two failing OfflineBanner widget tests added to gear and logistics test files.

## Tasks Completed

| Task | Name | Commit | Files |
|------|------|--------|-------|
| 1 | Add failing OfflineBanner test to gear_screen_mutations_test.dart | d20426c | test/features/gear_screen_mutations_test.dart |
| 2 | Add failing OfflineBanner test to logistics_screen_mutations_test.dart | d20426c | test/features/logistics_screen_mutations_test.dart |

## Verification

Both test files were run after edits:

```
00:01 +14 -2: Some tests failed.
```

- 14 pre-existing tests: PASS
- `GearScreen — OfflineBanner renders in body`: FAIL (Expected 1 OfflineBanner, found 0)
- `LogisticsScreen — OfflineBanner renders in body`: FAIL (Expected 1 OfflineBanner, found 0)

This is the correct RED state. Wave 1 (plan 34-01) adds OfflineBanner to GearScreen and LogisticsScreen to make these tests pass.

## Deviations from Plan

None — plan executed exactly as written.

## Known Stubs

None. The tests are intentionally failing stubs — this is the expected RED state per TDD protocol. They will be resolved in plan 34-01.

## Self-Check: PASSED

- [x] test/features/gear_screen_mutations_test.dart exists and was modified
- [x] test/features/logistics_screen_mutations_test.dart exists and was modified
- [x] Commit d20426c exists
