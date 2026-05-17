# Task: Remove orphaned TripCacheRepository

## Context

`lib/core/services/cache/trip_cache_repository.dart` is fully unreferenced and one of its methods is also broken at runtime. The investigation chain that surfaced this:

1. Dead-code audit (2026-05-17) flagged `TripCacheRepository` as a removal candidate.
2. Independent re-verification confirmed every public symbol has zero callers in `lib/`:
   - `tripCacheRepositoryProvider` — 0 `ref.watch` / `ref.read` / `ref.listen` matches.
   - `cacheTrip()` — no Firestore stream side-writes to it (the `asyncMap` cache-write pattern documented in `CLAUDE.md` flows through `ExpenseCacheRepository`, `SettlementCacheRepository`, `GroupCacheRepository`, etc. — never this one).
   - `getCachedTrips()` — nothing reads the cached trips.
   - `deleteTrip()` — no callers; also **provably broken**.
3. A focused repro test (`test/unit/delete_trip_repro_test.dart`, currently untracked on this branch) proved `deleteTrip()` throws `DatabaseException: no such table: gear_items` on the current v9 schema. The `gear_items`, `sub_groups`, and `sub_group_members` tables were dropped in the v7 Phase 39 migration; `deleteTrip` was never updated and still issues DELETE statements against all three.
4. Cache-wipe and account-recovery flows do not depend on this repo: `UidChangeListener` invokes `LocalDatabase.wipeAndReinitialize()` which deletes the database file atomically, and `LocalDatabase.clearAll()` issues raw SQL against `trips` directly without going through the repository.
5. The class doc comment at `trip_cache_repository.dart:21` claims "schema version 6" and lists the dropped tables in the cascade — confirming the file has been stale since Phase 39.

The `Trip` model itself is alive (still imported by ledger and groups for the `Participant` class), so this PR does NOT touch `trip_model.dart` or `trip_provider.dart`. The remaining dead symbols inside `trip_provider.dart` (`tripLogisticsParticipantsProvider`, `currentParticipantProvider`, `userGroupsForParticipantProvider`) are a separate, broader cleanup tracked outside this spec — folding them in here would dilute the focus.

## Goal

Delete the `TripCacheRepository` file and the repro test, fix the three doc files that reference it or the surrounding schema. Net: one source file removed, one test removed, three doc edits. Behavior change: none. Risk: minimal — verified no production callers.

## Constraints

### Scope is exactly the unreferenced repository
- Delete the file in full. Do not preserve any methods "just in case."
- The repro test exists only to prove `deleteTrip()` is dead. Its purpose is fulfilled — delete it with the file.

### Schema is out of scope — the `trips` table is load-bearing for FK validity, not vestigial
- The `trips` SQLite table stays in `_onCreate` (`local_database.dart:51-64`) and stays in `clearAll()` at `:540`. This is not cosmetic deferral: five active tables declare `FOREIGN KEY (trip_id) REFERENCES trips (id) ON DELETE CASCADE` against it — `expenses:84`, `settlements:102`, `participants:118`, `activity_logs:137`, `categories:149`. Dropping `trips` would orphan all five FK declarations and require either rewriting those table schemas or accepting invalid foreign-key references.
- A v10 migration to drop `trips` is therefore a schema redesign (touching the five cache tables that still use `trip_id` as their partition key), not a one-line table drop. Out of scope.
- `clearAll()` continues to issue `await db.delete('trips')` against a real-but-empty table. Correct as-is. (If the table were ever removed, this line would crash with "no such table" — it does NOT silently no-op. Future schema work must remove this line in the same diff that drops the table.)
- `test/unit/local_database_wipe_test.dart` inserts into `trips` directly via raw SQL as a generic wipe fixture — also unaffected.

### Related dead code is out of scope
- `lib/features/trip/providers/trip_provider.dart` has 3 dead Riverpod providers AND 1 live provider (`currentEventParticipantProvider`, consumed by `add_expense_screen.dart` and `expense_editor_body.dart`). Selectively pruning that file belongs in the broader "Phase 39 dead code sweep" PR, not here.
- `lib/features/activity/services/activity_service.dart` has two deprecated `trip*` providers with removal target "04-05" — same broader sweep.

### Doc accuracy fold-in
- While editing `lib/core/README.md` to drop the `trip_cache_repository.dart` bullet, also correct two adjacent stale facts in the same file (same edit, same area, low marginal cost):
  - "v8" mentioned at the section header for cache repositories (line 37) should read "v9" (matches the constant in `local_database.dart:11`).
  - The `local_database.dart` table list (line 34) includes `gear_items` (with a misleading "(legacy, retained for SQLite compatibility)" parenthetical), `sub_groups`, and `sub_group_members` — all dropped in v7. Remove them from the listed tables.
- `docs/ARCHITECTURE.md` and `docs/DEVELOPMENT.md` carry the same staleness from Phase 39 and the v7→v8→v9 bumps. Fold those in too — same class of error, low cost:
  - `docs/ARCHITECTURE.md:264` — "schema **version 8**" → "schema **version 9**".
  - `docs/ARCHITECTURE.md:270-280` (table) — remove the `gear_items` row (line 273), the `sub_groups / sub_group_members` row (line 275), and edit the `trips` row to drop "Legacy trip cache" framing in favour of language consistent with the FK justification above (trips persists as an FK target for the active cache tables; no longer a write surface).
  - `docs/ARCHITECTURE.md:282` — drop the "legacy `gear_items`" mention from the soft-delete sentence.
  - `docs/DEVELOPMENT.md:280` — "Current version is **8**" → "Current version is **9**".
  - `docs/DEVELOPMENT.md:285-287` — remove `gear_items`, `sub_groups`, `sub_group_members` from the inline table list.
  - `docs/DEVELOPMENT.md:290` — drop the `gear_items` mention from the soft-delete sentence.

## Files to touch

### Delete
- `lib/core/services/cache/trip_cache_repository.dart` — entire file (109 lines)
- `test/unit/delete_trip_repro_test.dart` — entire file (currently untracked; remove from disk before commit so it never enters git history on this branch)

### Edit
- `lib/core/README.md`
  - Remove the `trip_cache_repository.dart` bullet (line 41, under "Domain Cache Repositories").
  - Change "(`safar_cache.db` v8)" → "(`safar_cache.db` v9)" in the same section's intro line (line 37).
  - In the `local_database.dart` description at line 34, remove `gear_items`, `sub_groups`, `sub_group_members` from the listed tables and drop the "(legacy, retained for SQLite compatibility)" parenthetical.
- `docs/ARCHITECTURE.md`
  - Line 264: schema version 8 → version 9.
  - Lines 273, 275: remove `gear_items` row and `sub_groups / sub_group_members` row.
  - Line 270: rewrite the `trips` row to reflect its current role (FK target for active cache tables; no write surface).
  - Line 282: drop "legacy `gear_items`" from the soft-delete sentence.
- `docs/DEVELOPMENT.md`
  - Line 280: "Current version is **8**" → "Current version is **9**".
  - Lines 285-287: remove `gear_items`, `sub_groups`, `sub_group_members` from the inline list.
  - Line 290: drop `gear_items` from the soft-delete sentence.

## Files NOT to touch

- `lib/core/services/local_database.dart` — schema, `_onCreate`, `_onUpgrade`, `clearAll()`, `wipeAndReinitialize()` all stay. The `trips` table stays in the schema.
- `lib/features/trip/models/trip_model.dart` — `Trip` and `TripModules` classes still imported via barrel by ledger/groups features for `Participant`.
- `lib/features/trip/providers/trip_provider.dart` — has live `currentEventParticipantProvider`; selective pruning is a separate PR.
- `lib/features/activity/services/activity_service.dart` — deprecated providers stay (separate PR).
- `test/unit/local_database_wipe_test.dart` — uses the `trips` table as a wipe fixture; since the table stays, this test stays.
- `security/firestore.rules` — server-side, unrelated.
- `pubspec.yaml`, `lib/firebase_options.dart`, goldens — unrelated.

## Acceptance criteria

### File state
- [ ] `lib/core/services/cache/trip_cache_repository.dart` does not exist on disk.
- [ ] `test/unit/delete_trip_repro_test.dart` does not exist on disk and is not in git history on this branch.
- [ ] `lib/core/README.md` has no remaining reference to `TripCacheRepository`, `trip_cache_repository`, `gear_items`, `sub_groups`, or `sub_group_members`. The cache section header reads `v9` not `v8`.
- [ ] `docs/ARCHITECTURE.md` reads "version 9" and contains no references to `gear_items`, `sub_groups`, or `sub_group_members`.
- [ ] `docs/DEVELOPMENT.md` reads "version is **9**" and contains no references to `gear_items`, `sub_groups`, or `sub_group_members`.

### Reachability
- [ ] `grep -rn "TripCacheRepository\|tripCacheRepositoryProvider\|trip_cache_repository" lib/ test/` returns zero matches.
- [ ] `grep -rn "gear_items\|sub_groups\|sub_group_members" docs/ lib/core/README.md` returns matches only in `docs/plans/archive/` and `docs/plans/` planning artifacts (never in canonical docs like ARCHITECTURE.md or DEVELOPMENT.md).

### Behavior preservation
- [ ] `LocalDatabase._onCreate` still creates the `trips` table.
- [ ] `LocalDatabase.clearAll()` still calls `await db.delete('trips')` at the existing line.
- [ ] `LocalDatabase.wipeAndReinitialize()` is unchanged.
- [ ] `UidChangeListener` is unchanged.

### Tests
- [ ] `flutter analyze` — clean. No new warnings, no unused-import errors triggered by the deletion.
- [ ] `flutter test` — full suite passes. Coverage stays ≥ 80% (current CI gate per `release_android.yml` and `readiness_check.yml`).
- [ ] `test/unit/local_database_wipe_test.dart` still passes — proves the `trips` table is intact and wipeable.
- [ ] `test/unit/expense_cache_repository_test.dart`, `test/unit/group_cache_repository_test.dart`, `test/unit/participant_cache_repository_test.dart`, `test/unit/settlement_cache_repository_test.dart` all still pass — these are the live cache repositories.

### Verification commands

```bash
# From repo root
flutter analyze
flutter test
grep -rn "TripCacheRepository\|tripCacheRepositoryProvider\|trip_cache_repository" lib/ test/
grep -rn "version 8\|gear_items\|sub_groups\|sub_group_members" docs/ARCHITECTURE.md docs/DEVELOPMENT.md lib/core/README.md
ls lib/core/services/cache/trip_cache_repository.dart 2>&1 | grep -q "No such file"  # expect: silent success
```

## Risks and mitigations

- **Risk:** Some indirect runtime usage missed by grep (e.g., reflection, dynamic provider key).
  **Mitigation:** Riverpod doesn't use reflection. Dart has no string-based provider lookup. The grep is exhaustive.
- **Risk:** A future feature wants trip caching back.
  **Mitigation:** Cheap to rewrite from `expense_cache_repository.dart` template if ever needed. The current file is broken anyway — its presence is a liability, not an asset.
- **Risk:** Coverage drops below the 80% gate because the deleted code was contributing executed lines via the wipe path.
  **Mitigation:** The file has no callers, so it contributes no executed lines. The deletion should keep or marginally improve coverage. If CI flags a drop, re-run locally first to rule out flake.

## Non-goals

- Dropping the `trips` table from the SQLite schema.
- Pruning dead providers in `trip_provider.dart` or `activity_service.dart`.
- Updating `CLAUDE.md` (it doesn't mention `TripCacheRepository` directly).
- Auditing or removing the `Trip` / `TripModules` model classes.
- Any change to `functions/`, security rules, or Firestore.
