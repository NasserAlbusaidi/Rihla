---
phase: 01-data-foundation
plan: 02
subsystem: core/services
tags: [money-serialization, sqlite-migration, firestore, tdd, precision]
dependency_graph:
  requires: ["01-01"]
  provides: ["MoneySerializer", "SQLite v6 schema with groups tables"]
  affects: ["all Firestore financial writes", "Phase 2 group offline caching"]
tech_stack:
  added: ["sqflite_common_ffi ^2.3.4 (dev)"]
  patterns: ["integer subunit serialization at Firestore boundary", "toDecimal(scaleOnInfinitePrecision: 10) for Rational->Decimal conversion", "sqflite_common_ffi for in-memory SQLite testing on macOS/Linux"]
key_files:
  created:
    - lib/core/services/money_serializer.dart
    - test/unit/money_serializer_test.dart
    - test/unit/local_database_migration_test.dart
    - test/integration/firebase_money_roundtrip_test.dart
  modified:
    - lib/core/services/local_database.dart
    - pubspec.yaml
decisions:
  - "decimal v3 division returns Rational not Decimal -- call .toDecimal(scaleOnInfinitePrecision: 10) at the Firestore read boundary to get back to Decimal"
  - "sqflite_common_ffi added as dev dependency to enable in-memory SQLite testing on macOS/Linux/Windows without a device/emulator"
  - "LocalDatabase migration tests extract SQL into test-local helper functions (not testing LocalDatabase class directly) to avoid device path dependency"
metrics:
  duration: "5 minutes"
  completed: "2026-03-26"
  tasks_completed: 3
  files_created: 4
  files_modified: 2
---

# Phase 01 Plan 02: MoneySerializer + SQLite v6 Migration Summary

**One-liner:** TDD MoneySerializer with currency-aware integer subunit conversion (OMR=1000, USD=100, JPY=1) and SQLite v6 schema with groups/group_members/group_ledger tables, proven by a FakeFirestore end-to-end round-trip integration test.

## What Was Built

### Task 1: MoneySerializer (TDD)

`lib/core/services/money_serializer.dart` — static class that converts `Decimal` amounts to integer subunits for Firestore storage and back.

- `toSubunits(Decimal amount, String currency)` -> int: multiplies by currency scale, converts via `.toBigInt().toInt()` — no floating point
- `fromSubunits(int subunits, String currency)` -> Decimal: divides and calls `.toDecimal(scaleOnInfinitePrecision: 10)` because `decimal` v3's `/` operator returns `Rational` not `Decimal`
- Currency scale map: OMR=1000, USD=100, EUR=100, GBP=100, SAR=100, AED=100, JPY=1, KWD=1000, BHD=1000, QAR=100
- Case-insensitive lookup, `ArgumentError` on unsupported currencies

15 tests pass: OMR/USD/JPY round-trips, zero amounts, small amounts (0.001), case insensitivity, error cases.

### Task 2: SQLite v6 Migration (TDD)

`lib/core/services/local_database.dart` — bumped `_databaseVersion` from 5 to 6, added three new tables:

- `groups`: id, name, invite_code, created_by, member_ids (JSON TEXT), currency, created_at, updated_at, synced_at
- `group_members`: id, group_id, user_id, display_name, role, is_shadow, joined_at, synced_at
- `group_ledger`: id, group_id, member_id, counterparty_id, net_amount_subunits (INTEGER), currency, last_updated_at, event_id, synced_at

Tables added to both `_onCreate` (fresh install) and `_onUpgrade` (upgrade from v5). Indexes added for invite_code, group_id lookups, and the (group_id, member_id, counterparty_id) composite for balance queries. `clearAll()` updated to delete group_ledger, group_members, groups before trip tables.

8 migration tests pass using `sqflite_common_ffi` in-memory database: column presence, INTEGER type for net_amount_subunits, existing tables untouched.

### Task 3: Firestore Round-trip Integration Test

`test/integration/firebase_money_roundtrip_test.dart` — proves the full DATA-01 contract using `FakeFirebaseFirestore`.

5 tests pass: OMR 10.500, USD 9.99, JPY 1000 individual round-trips; multi-currency batch (OMR, USD, JPY, OMR small amount); runtime type verification (amount_fils stored as `int`, not `double` or `String`).

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] `decimal` v3 division returns `Rational` not `Decimal`**
- **Found during:** Task 1 GREEN phase
- **Issue:** The research pattern shows `Decimal.fromInt(subunits) / Decimal.fromInt(scale)` but `decimal` v3's division operator returns `Rational` (to avoid forcing precision decisions on non-terminating decimals like 1/3). The type mismatch causes a compile error.
- **Fix:** Chained `.toDecimal(scaleOnInfinitePrecision: 10)` after division in `fromSubunits`. 10 digits of scale is well above the maximum needed for any supported currency (OMR=3, USD=2, JPY=0).
- **Files modified:** lib/core/services/money_serializer.dart
- **Commit:** 3c01059

**2. [Rule 3 - Blocking] `sqflite_common_ffi` not in pubspec**
- **Found during:** Task 2 RED phase — migration test uses `databaseFactoryFfi` which requires the FFI package
- **Issue:** The plan specifies using `inMemoryDatabasePath` for testing but `sqflite_common_ffi` was not in dev_dependencies
- **Fix:** Added `sqflite_common_ffi: ^2.3.4` to pubspec dev_dependencies, ran `flutter pub get`
- **Files modified:** pubspec.yaml, pubspec.lock
- **Commit:** 756c3b9

## Known Stubs

None. All MoneySerializer functionality is fully implemented. SQLite schema is fully implemented. Firestore round-trip test is self-contained and complete.

## Verification Results

```
flutter test test/unit/money_serializer_test.dart       15/15 passed
flutter test test/unit/local_database_migration_test.dart 8/8 passed
flutter test test/integration/firebase_money_roundtrip_test.dart 5/5 passed
flutter analyze                                         0 errors, 133 infos (pre-existing)
```

All truths from must_haves verified:
- OMR Decimal round-trips through MoneySerializer with zero precision loss: confirmed (10.500 -> 10500 -> 10.500)
- Currency-aware scaling: OMR 1000x, USD 100x, JPY 1x all correct
- SQLite opens at version 6 with groups, group_members, and group_ledger tables: confirmed
- fake_cloud_firestore write of integer amount reads back identically: confirmed

## Self-Check: PASSED
