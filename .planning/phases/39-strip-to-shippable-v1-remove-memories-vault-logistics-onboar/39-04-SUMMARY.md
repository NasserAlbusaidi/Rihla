---
phase: 39
plan: 04
subsystem: trip
tags: [strip, TripModules, back-compat]
requires: [39-03]
provides: [empty-tripmodules-marker]
affects: [Trip model, trip_cache_repository, back-compat fromJson]
tech-stack:
  added: []
  patterns: [empty marker type, back-compat fromJson]
key-files:
  created: []
  modified:
    - lib/features/trip/models/trip_model.dart
  deleted: []
decisions:
  - "TripModules reduced to empty marker class (no fields) — every cut feature flag (docs, gear, itinerary, logistics) was load-bearing only for deleted features"
  - "fromJson signature `TripModules.fromJson(Map<String, dynamic> _)` — underscore parameter signals legacy keys are silently ignored"
  - "Empty class kept (rather than removed) so Trip.modules type stays stable and existing persisted JSON deserializes cleanly"
metrics:
  completed: 2026-04-26
---

# Phase 39 Plan 04: TripModules Class Pruning — Summary

Wave 3b: reduced `TripModules` from a 4-field config object to an empty marker class. Every flag (`docs`, `gear`, `itinerary`, `logistics`) was load-bearing only for features that were removed in Phase 39 — none had any consumer left after plans 39-01 / 39-03.

## Audit (Task 1 result)

```
$ grep -rn "modules\.docs\|modules\.gear\|modules\.itinerary\|modules\.logistics" lib/ test/
# (no matches)
```

No reads of any TripModules flag exist in lib/ or test/. Drop all four. The field `itinerary` defaulted to `false` and was never set true; safe to drop too.

Consumers of the class itself (still needed):

- `lib/features/trip/models/trip_model.dart` — `Trip.modules` field (kept)
- `lib/core/services/cache/trip_cache_repository.dart:64` — `TripModules.fromJson(...)` call (kept; now consumes a no-op fromJson)
- `test/unit/trip_model_back_compat_test.dart` — explicitly asserts back-compat with legacy keys

## Action (Task 2)

Rewrote the `TripModules` class:

```dart
/// Empty after Phase 39 strip — all module flags (docs, gear, itinerary,
/// logistics) belonged to features that were removed. Kept as a marker
/// type so the Trip API and existing Firestore/SQLite documents that may
/// still carry a `modules: {...}` map continue to deserialize cleanly.
class TripModules {
  const TripModules();

  /// Tolerate any keys on persisted data — every legacy flag is silently dropped.
  factory TripModules.fromJson(Map<String, dynamic> _) => const TripModules();

  Map<String, dynamic> toJson() => const <String, dynamic>{};

  TripModules copyWith() => const TripModules();
}
```

Net: 9 insertions, 40 deletions — a 31-line class collapses to a 9-line marker.

## Verification

```bash
$ flutter analyze lib/
# 0 errors

$ flutter test test/unit/trip_model_back_compat_test.dart
00:00 +2: All tests passed!
```

The back-compat test from plan 39-03 explicitly covers this state — `TripModules.fromJson({'gear': true, 'docs': true, 'logistics': true, 'memories': true})` returns `isA<TripModules>()`. After the Task 2 rewrite, the test still passes because the new fromJson ignores all input keys.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 — Bug-fix] Plan suggested keeping `itinerary` if any consumer reads it**
- **Found during:** Task 1 audit
- **Issue:** Audit grep found zero readers of `modules.itinerary` anywhere in `lib/` or `test/`. The flag defaulted to `false` and was never set true.
- **Decision:** Dropped `itinerary` along with the cut feature flags. The plan's interface block left this conditional ("If reads exist, keep it") — audit confirmed they don't.

**2. [Rule 3 — Blocking] No new test file created**
- **Plan called for:** Creating `test/unit/trip_model_back_compat_test.dart`
- **Reality:** Plan 39-03 already created this file with both Trip.fromJson and TripModules.fromJson back-compat tests. Wave 3b only needed to verify the test still passes after the TripModules rewrite — no new test file required.
- **Action:** Re-ran the existing test; both cases pass against the empty marker class.

## Commits

- `e0e6289` `refactor(39-04): prune TripModules to empty marker class`

## Self-Check: PASSED

- [x] `class TripModules` has no field declarations
- [x] `TripModules.fromJson` takes `(Map<String, dynamic> _)` and returns `const TripModules()` regardless of input
- [x] `flutter analyze lib/` → 0 errors
- [x] `flutter test test/unit/trip_model_back_compat_test.dart` → 2 / 2 pass

## Handoff to Wave 4

Plans 39-05 (server-side teardown — Cloud Functions + Firestore rules) and 39-06 (client-side teardown — SQLite migration v6→v7 + thawani_payment package removal) are next.
