---
phase: 39
plan: 06
subsystem: client + dependencies
tags: [strip, sqlite, migration, pubspec, thawani]
requires: [39-04]
provides: [sqlite-v7-schema, thawani-package-removed, cut-tables-dropped]
affects: [LocalDatabase, pubspec.yaml, pubspec.lock, architecture test]
tech-stack:
  added: []
  patterns: [sqlite-migration, ALTER-TABLE-DROP-COLUMN]
key-files:
  created: []
  modified:
    - lib/core/services/local_database.dart
    - pubspec.yaml
    - pubspec.lock
    - test/architecture/no_cache_service_test.dart
    - test/features/groups/create_join_group_test.dart
    - test/features/groups/group_settings_screen_test.dart
    - test/features/groups/group_screens_test.dart
    - test/features/events/create_event_test.dart
  deleted: []
decisions:
  - "Defensive DROP TABLE IF EXISTS for tables that didn't exist in v6 schema (documents, memories, trip_memories, logistics) — cheap insurance against any test-data installs"
  - "ALTER TABLE trips DROP COLUMN currency wrapped in try/catch — SQLite < 3.35 falls back to leaving the column in place (no longer written by app code post-Phase-39)"
  - "Architecture test updated from 9 → 7 expected cache repos (gear + sub_group repositories dropped in plan 39-03)"
metrics:
  completed: 2026-04-26
---

# Phase 39 Plan 06: SQLite v6→v7 Migration + Drop thawani_payment — Summary

Wave 4b client-side teardown: bumped the SQLite schema version from 6 to 7, dropped the gear/sub_groups tables that exist in v6, defensively dropped tables that don't exist in v6 (documents, memories, trip_memories, logistics) for any test-data installs, dropped the trips.currency column per ROADMAP SC2, and removed the `thawani_payment` package from pubspec.yaml.

## Deliverables

| Item | Result |
|------|--------|
| `_databaseVersion` bumped 6 → 7 | ✓ |
| Migration v6→v7 drops `gear_items` table | ✓ |
| Migration v6→v7 drops `sub_groups` + `sub_group_members` tables | ✓ |
| Migration v6→v7 defensively drops `documents`, `memories`, `trip_memories`, `logistics` | ✓ |
| Migration v6→v7 drops `trips.currency` column (with try/catch for older SQLite) | ✓ |
| `_onCreate` no longer creates `gear_items`, `sub_groups`, `sub_group_members` for fresh installs | ✓ |
| `_onCreate` no longer creates `currency` column on the trips table | ✓ |
| `clearAll()` drops gear_items / sub_groups deletes | ✓ |
| `pubspec.yaml` no longer has `thawani_payment` line | ✓ |
| `pubspec.lock` regenerated without thawani_payment | ✓ |
| `flutter pub get` succeeds | ✓ |
| `flutter analyze` reports zero errors | ✓ |
| `flutter test` reports zero failures | ✓ |

## Files Changed

### `lib/core/services/local_database.dart`

**`_databaseVersion`:**

```diff
-  static const int _databaseVersion = 6; // Extended with groups tables
+  static const int _databaseVersion = 7; // Phase 39 strip — drop gear_items + cut tables + trips.currency
```

**`_onCreate` — trips table no longer creates currency column:**

```diff
     await db.execute('''
       CREATE TABLE trips (
         id TEXT PRIMARY KEY,
         name TEXT NOT NULL,
         invite_code TEXT NOT NULL,
         leader_id TEXT NOT NULL,
         icon TEXT DEFAULT 'airplane',
-        currency TEXT DEFAULT 'OMR',
         start_date TEXT,
         ...
```

**`_onCreate` — gear_items / sub_groups / sub_group_members CREATE TABLE blocks deleted** (~80 lines removed)

**`_onCreate` — corresponding indexes deleted:**

```diff
-    await db.execute('CREATE INDEX idx_gear_trip ON gear_items(trip_id)');
-    await db.execute('CREATE INDEX idx_sub_groups_trip ON sub_groups(trip_id)');
-    await db.execute('CREATE INDEX idx_sgm_group ON sub_group_members(sub_group_id)');
```

**`_onUpgrade` — new v6→v7 migration block at end of method:**

```dart
if (oldVersion < 7) {
  // Phase 39 strip — drop tables for cut features.
  // gear_items definitely exists in v6 schema; the others are defensive
  // (no-op if they don't exist — IF EXISTS makes the DROP idempotent).
  await db.execute('DROP TABLE IF EXISTS gear_items');
  await db.execute('DROP TABLE IF EXISTS sub_group_members');
  await db.execute('DROP TABLE IF EXISTS sub_groups');
  await db.execute('DROP TABLE IF EXISTS documents');
  await db.execute('DROP TABLE IF EXISTS memories');
  await db.execute('DROP TABLE IF EXISTS trip_memories');
  await db.execute('DROP TABLE IF EXISTS logistics');

  // ROADMAP SC2 — drop trips.currency column.
  // SQLite ALTER TABLE DROP COLUMN is available since 3.35 (2021).
  // Wrap in try/catch in case the underlying SQLite is older — falls
  // back to leaving the column in place (it's no longer written by
  // application code after Phase 39, so a stale column is harmless).
  try {
    await db.execute('ALTER TABLE trips DROP COLUMN currency');
  } catch (_) {
    // Older SQLite — column stays. Not load-bearing post-strip.
  }
}
```

**`clearAll()` — gear_items + sub_groups + sub_group_members deletes removed.**

### `pubspec.yaml`

```diff
   firebase_auth: ^6.3.0
   firebase_storage: ^13.2.0
   http: ^1.2.0
-  thawani_payment: ^1.2.4+1
   shimmer: ^3.0.0
   animations: ^2.0.0
```

### `pubspec.lock`

Regenerated by `flutter pub get`. Net: 9 transitive dependencies removed (thawani_payment + its dependencies including a webview chain).

### `test/architecture/no_cache_service_test.dart`

```diff
-    test('lib/core/services/cache/ directory has exactly 9 repository files',
+    test('lib/core/services/cache/ directory has exactly 7 repository files',
       () {
       ...
-      expect(dartFiles.length, equals(9), ...
+      expect(dartFiles.length, equals(7), ...
+            'lib/core/services/cache/ after Phase 39 strip dropped the gear '
+            'and sub_group repositories. Found: ...
```

The expected count drops from 9 to 7 because plan 39-03 deleted `gear_cache_repository.dart` and `sub_group_cache_repository.dart`.

### Test fixture cleanup (failing tests for removed UI)

| File | Test removed | Reason |
|------|--------------|--------|
| `test/features/groups/create_join_group_test.dart` | `renders Currency label` | Currency picker removed in 39-03 |
| `test/features/groups/create_join_group_test.dart` | `renders OMR as the default currency` | Currency dropdown removed |
| `test/features/groups/create_join_group_test.dart` | `renders Currency label and value` | GroupSettings currency tile removed |
| `test/features/groups/group_settings_screen_test.dart` | `shows currency tile with current currency` | `_buildCurrencyTile` removed |
| `test/features/groups/group_screens_test.dart` | `shows currency tile with change option (D-16)` | Same |
| `test/features/events/create_event_test.dart` | `shows module toggles for Custom type` | EventModulesCard removed in 39-01 |
| `test/features/events/create_event_test.dart` | `Ledger toggle is enabled (...) for Custom type` | Same |

## Verification

```bash
$ grep -n "thawani" pubspec.yaml pubspec.lock
# (no matches — completely removed)

$ flutter pub get
# Changed 9 dependencies! (succeeds)

$ flutter analyze 2>&1 | grep -c "error •"
0

$ flutter test 2>&1 | tail -1
00:14 +781 ~3: All tests passed!
```

Note: `~3` is the count of pre-existing tests marked as `skip:` — none are Phase 39 introductions.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 — Bug-fix] sub_groups + sub_group_members tables existed in v6 schema but plan only listed `logistics` as defensive drop**
- **Found during:** local_database.dart audit
- **Issue:** The plan's interface block said the v6 schema does NOT have a `logistics` table — true. But it failed to mention that `sub_groups` and `sub_group_members` (the actual logistics-feature tables) DO exist in v6 schema and need to be DROPped in the migration.
- **Fix:** Added explicit `DROP TABLE IF EXISTS sub_group_members` and `DROP TABLE IF EXISTS sub_groups` to the v7 migration. Also removed their CREATE TABLE statements from `_onCreate` for fresh installs.
- **Files:** `lib/core/services/local_database.dart`

**2. [Rule 1 — Bug-fix] Architecture test asserted 9 cache repos**
- **Found during:** flutter test run
- **Issue:** `test/architecture/no_cache_service_test.dart` line 60 asserted `dartFiles.length == 9` (set by Phase 36 Plan 06). After plan 39-03 deleted gear and sub_group cache repos, the count is 7.
- **Fix:** Updated the assertion + reason text. The test still serves its original purpose (preventing re-introduction of cache_service.dart and balance_cache_repository.dart) — only the cardinality changed.
- **Files:** `test/architecture/no_cache_service_test.dart`

**3. [Rule 1 — Bug-fix] 7 widget tests failed for currency UI / module toggles that were removed in earlier waves**
- **Found during:** flutter test run
- **Issue:** Tests for `Currency` label, `OMR` default, currency tile, and Custom-type module toggles asserted UI that was intentionally removed by plans 39-01 and 39-03 — but the tests had not been deleted along with the UI.
- **Fix:** Surgically removed the 7 specific test cases (not the entire test files, since other tests in those files exercise surviving UI). Plan 39-07's TEST-AUDIT will document this cleanup for user review.
- **Files:** 4 test files (see "Test fixture cleanup" table above)

## Commits

- `dae0b0b` `feat(39-06): SQLite v6→v7 migration + drop thawani_payment package`

## Self-Check: PASSED

- [x] `grep -c "_databaseVersion = 7" lib/core/services/local_database.dart` → 1
- [x] `grep -c "DROP TABLE IF EXISTS gear_items" lib/core/services/local_database.dart` → 1
- [x] `grep -c "DROP TABLE IF EXISTS sub_groups" lib/core/services/local_database.dart` → 1
- [x] `grep -c "ALTER TABLE trips DROP COLUMN currency" lib/core/services/local_database.dart` → 1
- [x] `grep -c "currency TEXT DEFAULT 'OMR'" lib/core/services/local_database.dart` → returns >0 only for groups + group_ledger (Group.currency stays — not in scope per plan)
- [x] `grep -c "thawani" pubspec.yaml` → 0
- [x] `grep -c "thawani" pubspec.lock` → 0
- [x] `flutter analyze` → 0 errors
- [x] `flutter test` → 781 passed, 0 failed, 3 skipped

## Handoff to Wave 5

Plan 39-07 — final verification: collects evidence into 39-VERIFICATION.md, captures the user-approved test audit (39-TEST-AUDIT.md), and confirms ROADMAP success criteria are met.
