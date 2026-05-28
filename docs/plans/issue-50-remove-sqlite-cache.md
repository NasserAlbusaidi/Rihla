# Issue #50 — Remove the SQLite cache (decision + removal spec)

**Scope (after Gate Round 1):** PR 1 = the clean removal only. **Closes #50** (decision enacted) and **#49** (vestigial trip-centric FK schema); **mitigates #62** (cache currency column evaporates). **Does NOT close #45** — sealing the cross-UID leak correctly is a separate boot-barrier P0 (PR 2, see Part 6). Supersedes PR #59 (cold-start SQLite barrier) and `docs/plans/2026-05-17-remove-trip-cache-repository.md`'s "trips table is load-bearing" judgment.
**Base:** `main` (c1f708c) — cache code is byte-identical to the shipped artifact (`git diff --stat main -- lib/core/services/cache/ lib/core/services/local_database.dart` is empty), so this applies to production.
**Status:** Round 1 = 5 P1 (against the over-scoped one-PR design) → split #45 to PR 2. Round 2 on this PR-1 scope = 1 P1 (`data_deletion_service_test` missed) + 1 P2 (provider rewire untested), both applied. Round 2 confirmed: no missed importer, "net-neutral vs main" correct, stream collapse preserves output, deps safe to drop. **Round 3 = 0 P1, 0 P2 — CLEARED to implement.**

---

## Part 1 — Decision record (the #50 answer) — CONFIRMED by Gate Round 1

**Question (#50):** Identify any concrete capability SQLite provides over Firestore offline persistence. If none, removing it resolves the cross-UID leak class and trip-centric FK failures.

**Verdict: REMOVE.** No capability is unique to SQLite; Firestore offline persistence subsumes everything the cache does in live code. Codex independently verified the load-bearing facts.

| Capability | SQLite | Firestore offline | Evidence |
|---|---|---|---|
| Cold-start offline read | ❌ no UI reads cache | ✅ | `persistenceEnabled: true, CACHE_SIZE_UNLIMITED` `firebase_config.dart:51-54`; screens watch `.snapshots()` |
| Offline write queue + replay | ❌ | ✅ | all writes go straight to Firestore (`expense_service.dart:141/286/310`, `settlement_service.dart:97`); no custom queue |
| Money path (BalanceCalculator) | ❌ | ✅ | `eventBalancesProvider` watches live streams `expense_provider.dart:121-123`; participants from `Event` fields `:138-147` |
| Relational queries (JOIN/aggregate/FTS) | ❌ none exist | ✅ | every cache read is flat single-table `db.query` |
| Multi-currency split persistence | ❌ no currency col (#62) | ✅ | `expenses` table `local_database.dart:67-86` |

**`uniqueCapabilities = []`.** Reads are dead: the only cache read wired to a provider is `getCachedParticipants` via `tripLogisticsParticipantsProvider` (`trip_provider.dart:21-25`, `@Deprecated`), referenced by nothing; `getExpenses`/`getSettlements`/`getCachedGroups`/etc. are test-only. Writes in `lib/` are only `cacheExpenses`/`cacheSettlements` (`expense_provider.dart:70,96`), pass-through `asyncMap` side-effects in `try{}catch(_){}` documented "non-critical." Codex confirmed: **no missed production SQLite read path.**

**Doc drift to fix:** CLAUDE.md says cache **v8**; constant is **v9** (`local_database.dart:11`).

---

## Part 2 — Scope boundary: why #45 is OUT of PR 1 (read before reviewing)

Gate Round 1 proved that **closing #45 is not a property of deleting SQLite** — it requires sealing the Firestore SDK on-disk cache, which leaks cross-UID via direct-path reads **today, independent of SQLite** (`group_provider.dart:412/432`, `event_provider.dart:38/67`, ledger via fixed `groups/{gid}/events/{eid}` paths `firestore_repository.dart:44` — none UID-scoped, local cache not rule-enforced). That seal needs a real boot-barrier + recovery quiesce + correctly-ordered `clearPersistence()`/`terminate()` — its own P0 (PR 2).

**PR 1 removes the SQLite-wipe plumbing. This is net-neutral vs. today, not a regression:**
- The mid-session SQLite wipe (`UidChangeListener` → `wipeAndReinitialize`) only ever protected the **SQLite** cache. With SQLite deleted there is nothing for it to wipe.
- The Firestore SDK cache is **not** cleared on UID swap today (`grep clearPersistence|terminate( lib/` → none) and is **not** cleared after PR 1 either. PR 1 does not worsen the Firestore-cache posture — it leaves it exactly as `main` ships it.
- Net effect of PR 1 on cross-UID exposure: **SQLite leak class eliminated** (no cache → no SQLite leak, closing #45's filed SQLite scope and #49); **Firestore-cache leak unchanged** (was unprotected, stays unprotected → PR 2).
- `UidChangeListener`, `cacheWipeFnProvider`, and the `data_deletion_service` local wipe all import the deleted `local_database.dart`, so they must change in PR 1 regardless. We remove them (not stub) and rebuild a Firestore-targeted isolation barrier in PR 2.

**Account deletion (#46) coupling:** `DataDeletionService` currently wipes SQLite after the server cascade. The Firestore SDK cache is already not cleared on deletion today, so removing the SQLite wipe leaves the on-device Firestore remnant exactly as `main` ships it. PR 2's clearPersistence work covers both UID-swap and post-deletion local cleanup. PR 1 keeps the server cascade + `signOut()` untouched.

---

## Part 3 — Files to touch (PR 1)

### Delete (source)
- `lib/core/services/cache/` — entire directory (6 repos).
- `lib/core/services/local_database.dart`.
- `lib/features/auth/services/uid_change_listener.dart` — pure SQLite-wipe; no Firestore role. (PR 2 introduces a Firestore-isolation barrier in its place.)

### Edit (source)
- `lib/features/ledger/providers/expense_provider.dart` — drop cache imports (`:6,:8`); collapse `eventExpensesProvider` (`:58-77`) / `eventSettlementsProvider` (`:82-103`) to `return service.watchExpenses(...)` / `watchSettlements(...)` directly (remove `asyncMap` side-write, `cache` reads `:63,:88`, stale D-15 comments).
- `lib/features/auth/services/data_deletion_service.dart` — **remove the local-wipe seam entirely** (Gate R2 P1): delete the `LocalCacheWipe` typedef (`:10`), the `wipeLocalCache` ctor param (`:25`), the `_wipeLocalCache` field (`:30,:34`), the `local_database` import (`:6`), and the `await _wipeLocalCache()` call (`:44`). `deleteAccount()` becomes callable → `signOut()`. (Firestore on-device cleanup on deletion is PR 2, same as today: nothing clears the SDK cache on deletion now.)
- `lib/core/providers/app_bootstrap_provider.dart` — remove `ref.watch(uidChangeListenerProvider)` (`:13`) and the import (listener is deleted).
- `lib/features/trip/providers/trip_provider.dart` — delete the now-orphaned `tripLogisticsParticipantsProvider` (`:21-25`) + its participant-cache import; keep live providers. (Confirm at the Gate it's the only provider freed.)
- `pubspec.yaml` — remove `sqflite: ^2.4.2` (`:58`), `path: ^1.9.1` (`:59`, used only by `local_database.dart`), `sqflite_common_ffi: ^2.3.4` (`:96`, dev). Verify no surviving `package:path/path.dart` import.

### Rewrite / delete (tests)
- `test/architecture/no_cache_service_test.dart` — **RED→GREEN anchor**: replace the "cache dir has exactly 6 files" assertion (`:40-66`) with assertions that `lib/core/services/cache/` and `lib/core/services/local_database.dart` do **not** exist. Keep the `cache_service.dart`/`balance_cache_repository.dart` non-existence checks.
- **Delete** (purpose evaporates): `test/unit/expense_cache_repository_test.dart`, `settlement_cache_repository_test.dart`, `group_cache_repository_test.dart`, `participant_cache_repository_test.dart`, `local_database_wipe_test.dart`, `local_database_migration_test.dart`, `local_database_tombstone_migration_test.dart`, `test/integration/offline_scenario_test.dart`, `test/unit/uid_change_listener_test.dart`.
- **Rewrite** `test/unit/data_deletion_service_test.dart` (Gate R2 P1): drop all `wipeLocalCache:` injections (`:38,:57,:75,:98`); success asserts `['callable','signOut']` (was `['callable','wipe','signOut']`); **delete** the "returns error when local cache wipe fails" test (`:67-84`); signOut-failure asserts `['callable','signOut']`; callable-failure stays `['callable']`.
- **Add** pass-through coverage for the rewired providers (Gate R2 P2): `provider_tests.dart` currently overrides `eventExpensesProvider`/`eventSettlementsProvider` directly (`:121,:363`), bypassing the impl being changed. Add tests that override `expenseServiceProvider`/`settlementServiceProvider` with fake services and assert the default `eventExpensesProvider`/`eventSettlementsProvider` emit exactly the service stream (proves the collapse preserves output, no side-write).
- (PR 2, not here) add Firestore-offline behavior coverage + cross-UID isolation tests.

### Edit (docs)
- `CLAUDE.md` — Database section: SQLite gone; remove "v8"/"SQLite cache only"; keep "Custom sync queue — don't" (true via SDK). Key Invariants: note FR-CACHE-1 cross-UID guarantee is **deferred to PR 2** (Firestore-cache seal), not provided by PR 1.
- `lib/core/README.md`, `docs/ARCHITECTURE.md`, `docs/DEVELOPMENT.md` — remove SQLite cache repos / `local_database.dart` / schema-version sections.
- `lib/features/auth/README.md:10`, `docs/TESTING.md:22`, `docs/PRODUCT.md:17` — remove SQLite/`LocalDatabase` mentions (flagged by Gate P2).
- `docs/ACCOUNT-RECOVERY.md` (+ `docs/design/account-recovery.md:150`) — FR-CACHE-1: state the SQLite per-UID wipe is removed with the cache; the cross-UID guarantee is re-established against the Firestore cache in PR 2 (link the #45 follow-up).

### NOT to touch
- `lib/features/trip/models/trip_model.dart` (`Trip`/`Participant` still used), `security/firestore.rules`, `functions/`, `lib/firebase_options.dart`, goldens. No boot-sequence / `clearPersistence` changes (PR 2).

---

## Part 4 — Implementation order (TDD)
1. **RED:** rewrite `no_cache_service_test.dart` → assert cache dir + `local_database.dart` gone (fails now).
2. **GREEN, rewire:** collapse the two `expense_provider` streams; edit `data_deletion_service`; drop the `app_bootstrap` watch.
3. **GREEN, delete:** remove cache dir, `local_database.dart`, `uid_change_listener.dart`, the obsolete tests; drop deps.
4. `flutter analyze` clean → `flutter test` green → coverage ≥ 80% (measure; deleting tested code moves the ratio).

## Part 5 — Acceptance criteria
- [ ] `lib/core/services/cache/`, `lib/core/services/local_database.dart`, `lib/features/auth/services/uid_change_listener.dart` do not exist.
- [ ] `grep -rn "local_database\|services/cache/\|LocalDatabase\|sqflite\|UidChangeListener\|cacheWipeFn" lib/ test/` → zero (arch test enforces dir absence).
- [ ] `grep -rn "clearPersistence\|terminate(" lib/` → zero (PR 1 adds none; PR 2's job).
- [ ] Ledger renders from Firestore (expense/settlement streams unchanged in output; only the cache side-write removed).
- [ ] `flutter analyze` clean; `flutter test` green; coverage ≥ 80% (measured).
- [ ] PR description states #45 is NOT closed and links the PR-2 follow-up.

## Part 6 — PR 2 (separate, deferred) — the #45 Firestore-cache seal (P0)
Out of scope here; tracked on #45 (to be expanded to name the Firestore SDK cache). Must solve the 5 P1s from Gate Round 1: a real boot-future in `_AuthGate` (auth restore → clear decision → render `SafarApp`); `clearPersistence()` only pre-startup/post-`terminate()`; in-session recovery (`auth_recovery_service.dart:265`) quiesce providers before swap; account-deletion reboot flow; durable `firestorePersistenceDirty` / `lastClearedUid` marker so a clear is never skipped. Note (Gate P2): `clearPersistence()` is not a secure on-disk wipe — scope to user-visible stale reads or disable persistence if forensic disclosure is in the threat model.

## Part 7 — Gate Round 1 (codex, high, 223k tokens) → 5 P1 against the ORIGINAL one-PR design
Round 1 reviewed a one-PR design that bundled the #45 clearPersistence seal. It **confirmed REMOVE** (persistence enabled `firebase_config.dart:51`; no missed live read path; arch test asserts 6 `no_cache_service_test.dart:40`; settlements append-only `firestore.rules:578,737`; byte-identical to main) and rejected the bundled #45 mechanism with 5 P1: (1) mid-session "defer to cold start" never clears + in-session recovery window; (2) "queries are UID-scoped" false — direct-path reads leak; (3) `unawaited` best-effort wipe unfit for a P0 barrier; (4) `clearPersistence()` FAILED_PRECONDITION while Firestore live (`cloud_firestore .../firestore.dart:95,294`); (5) `_AuthGate._bootSequence` does not exist (`main.dart:116` is `initState→ensureAnonymousSession`; `ProviderScope` wraps `_AuthGate` at `:88`) — a claim wrongly sourced from a memory note about PR #59's proposed barrier. **Resolution: split.** Those 5 P1 all live in the #45 seal → moved to PR 2. PR 1 (this spec) carries none of them.

## Part 8 — Risks (PR 1)
- **Round-2 reviewer mistakes the wipe-plumbing removal for a #45 regression** — mitigated by Part 2 (net-neutral vs. today; the wipe only protected SQLite).
- **Coverage drop** from deleting well-covered cache tests — measure locally before claiming green.
- **`expense_provider` rewire** must preserve stream output exactly (only the side-write is removed) — covered by existing ledger/balance tests.

## Non-goals
- The #45 Firestore-cache seal (PR 2). Multi-currency write-path (#61) — `#62` evaporates here; OMR hardcodes stay for #61. Broader Phase-39 dead-provider sweep. Any `functions/`/rules change.

## GSTACK REVIEW REPORT

| Review | Trigger | Why | Runs | Status | Findings |
|--------|---------|-----|------|--------|----------|
| Codex Review | `/codex challenge` | Independent 2nd opinion | 3 | PASS | R1: 5 P1 (→ split #45 to PR 2); R2: 1 P1 + 1 P2 (applied); R3: 0 P1, 0 P2 |

- **CODEX:** REMOVE decision verified against code across 3 rounds. R1's 5 P1 were the bundled #45 seal → moved to PR 2. R2 caught the missed `data_deletion_service_test` (P1) + untested provider rewire (P2), both applied. R3 = clean.
- **UNRESOLVED:** none for PR 1. PR 2 (#45 Firestore-cache seal) tracked separately.
- **VERDICT:** Decision CLEARED (remove) + PR-1 removal CLEARED to implement (R3 ship). #45 deferred to PR 2.
