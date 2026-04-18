---
phase: 38
plan: 03
subsystem: firebase-functions / authorization
tags:
  - security
  - firebase-functions
  - authorization
  - signed-urls
  - storage-rules
dependency-graph:
  requires:
    - assertMemberOfEvent-gate (Plan 02)
    - issueDownloadUrl (Plan 02)
    - parseStoragePath (Plan 02)
  provides:
    - listDocumentsWithUrls-callable
    - listMemoriesWithUrls-callable
    - deleteStorageObject-callable
    - direct-storage-sdk-denial-proof
  affects:
    - phase-38-plan-04 (Flutter gateway migration + storage.rules lockdown — all 4 callables wired in main.dart)
tech-stack:
  added: []
  patterns:
    - Batch URL pre-issue via Promise.all inside the callable handler (D-03) — one Firestore round-trip + parallel sign per call
    - Delete-with-re-verify — parseStoragePath(path) BEFORE assertMemberOfEvent, membership re-checked against (groupId, parsed.eventId) (T-38-06)
    - Inline-rules proof test — @firebase/rules-unit-testing initializeTestEnvironment with a TIGHTENED_RULES string that mirrors Plan 04's planned rules file; test proves rule behavior before the file swap lands
    - Log payload hygiene — logger.info includes {uid, groupId, eventId, bucket, storagePath, count}; NEVER includes signedUrl/uploadUrl (T-38-05)
key-files:
  created:
    - functions/src/callables/listDocumentsWithUrls.ts
    - functions/src/callables/listMemoriesWithUrls.ts
    - functions/src/callables/deleteStorageObject.ts
    - functions/test/callables/listDocumentsWithUrls.test.ts
    - functions/test/callables/listMemoriesWithUrls.test.ts
    - functions/test/callables/deleteStorageObject.test.ts
    - functions/test/storage-rules.test.ts
  modified:
    - functions/src/index.ts
    - functions/test/fixtures.ts
decisions:
  - Extended clearFirestore in fixtures.ts to purge documents + memories subcollections before deleting the parent event doc; otherwise seeded docs from a prior test bled into the next test's snapshot count.
  - For the storage-rules test, wrapped ref.putString() in an async IIFE to satisfy assertFails's Promise<any> signature (UploadTask is thenable but not a Promise instance — TS 5.3 rejected it as Promise<any>).
  - Kept the tightened rules string inline in the test rather than reading security/storage.rules — Plan 04 will swap the live file; this test is specifically designed to prove the target behavior independently of that swap.
metrics:
  duration: ~20 min
  tasks-completed: 3 of 3
  completed-date: 2026-04-18
  tests-added: 20 (5 documents + 4 memories + 7 delete + 4 storage-rules)
  tests-total: 51
  coverage-statements: 93.93%
  coverage-branches: 83.01%
  coverage-functions: 100%
  coverage-lines: 93.82%
---

# Phase 38 Plan 03: List + Delete Callables + Storage Rules Denial Proof

Implement the remaining three Cloud Functions callables — `listDocumentsWithUrls`, `listMemoriesWithUrls`, `deleteStorageObject` — plus a `@firebase/rules-unit-testing` suite that proves direct Storage SDK access is denied under the tightened rules (INFRA-01 success criterion #3). All four Wave-2 callables are now wired into `functions/src/index.ts`, and the full Jest suite (31 prior + 20 new = 51 tests) passes under the Firebase emulator at 93.82% line coverage.

## What Was Built

### Task 1 — `listDocumentsWithUrls` + `listMemoriesWithUrls` with batch pre-issued URLs (commit `d7749c7`)

Two nearly-identical callables that mirror the gate order established in Plan 02:

1. `if (!request.auth) throw HttpsError('unauthenticated')` — T-38-01
2. `{groupId, eventId}` validation → `invalid-argument` if empty
3. `await assertMemberOfEvent(uid, groupId, eventId)` — T-38-02 (runs BEFORE any Firestore query)
4. Firestore subcollection query
   - documents: `.where('isDeleted', '==', false)` — filters soft-deletes server-side
   - memories: no filter — memories collection has no soft-delete flag yet
5. `Promise.all(snap.docs.map(async d => ({ ...d.data(), id: d.id, ...(await issueDownloadUrl(d.data().storagePath)) })))` — D-03 batch pre-issue
6. `logger.info(...)` with count but no URLs — T-38-05

**Output contracts** exactly as specified in the plan: `{ documents: DocumentWithUrl[] }` and `{ memories: MemoryWithUrl[] }`, each item carrying its Firestore fields plus `signedUrl` and `expiresAt` (ISO).

**Fixture extensions** (`functions/test/fixtures.ts`):
- `DocSeed` + `MemorySeed` interfaces + `seedDocuments()` + `seedMemories()` helpers so test files don't inline Firestore writes.
- `clearFirestore()` upgraded to also purge `documents` and `memories` subcollections per event before deleting the event/group docs — prevents test-to-test contamination.

### Task 2 — `deleteStorageObject` with path-parse + re-check membership (commit `cc41b63`)

Critical T-38-06 mitigation is the ordering inside the handler:

```
1. auth check
2. { storagePath, groupId } validation
3. parseStoragePath(storagePath) -> { bucket, eventId, expenseId? }    // throws invalid-argument on garbage
4. assertMemberOfEvent(uid, groupId, parsed.eventId)                   // uses parsed eventId, NOT client-claimed
5. file.delete({ ignoreNotFound: true })                               // idempotent
6. logger.info('delete-storage-object succeeded', { uid, groupId, storagePath, bucket })
```

Key security property: a caller claiming `groupId: 'g1'` but supplying `storagePath: 'trip-documents/e-other/x.pdf'` cannot escape to a foreign group's object. `parseStoragePath` extracts `eventId='e-other'`, and `assertMemberOfEvent('alice', 'g1', 'e-other')` throws `not-found` because event `e-other` does not exist in group `g1` (test 7 covers this).

**`functions/src/index.ts`** now exports all four Wave-2 callables:
```typescript
export { getSignedUploadUrl } from './callables/getSignedUploadUrl';
export { listDocumentsWithUrls } from './callables/listDocumentsWithUrls';
export { listMemoriesWithUrls } from './callables/listMemoriesWithUrls';
export { deleteStorageObject } from './callables/deleteStorageObject';
```

### Task 3 — Direct Storage SDK denial proof (commit `1b5e942`)

`functions/test/storage-rules.test.ts` uses `@firebase/rules-unit-testing` v5.0.0's `initializeTestEnvironment({ storage: { rules: TIGHTENED_RULES, host, port } })` to load an inline deny-all rules string matching Plan 04's target shape, then runs four direct-SDK access patterns against it:

| # | Context | Operation | Path | Expected |
|---|---|---|---|---|
| 1 | unauthenticated | getDownloadURL | `trip-documents/e1/x.pdf` | `assertFails` |
| 2 | authenticatedContext('alice') | putString | `trip-memories/e1/y.jpg` | `assertFails` |
| 3 | authenticatedContext('alice') | delete | `receipts/e1/exp1/z.png` | `assertFails` |
| 4 | authenticatedContext('alice') | getDownloadURL | `other/random/file` (catch-all) | `assertFails` |

This suite is independent of the live `security/storage.rules` file — Plan 04 will re-run the same four assertions against the real file and against the live emulator.

## Verification Results

| Check | Command | Result |
|---|---|---|
| Build | `npm run build --prefix functions` | exit 0, zero TS errors |
| All tests (emulator) | `firebase emulators:exec --only auth,firestore,storage,functions --project rihla-safar-test "cd functions && npx jest --runInBand --coverage"` | **51/51 passed** (9 test files) |
| Plan 03 test count | listDocuments:5 + listMemories:4 + deleteStorageObject:7 + storage-rules:4 | **20 new passing** (plan predicted 20) |
| Prior plan count preserved | Plan 02 tests still green | 31/31 (membership 4, paths 7, validation 7, signing 4, getSignedUploadUrl 9) |
| Coverage (statements) | jest --coverage | 93.93% (floor 70%) ✓ |
| Coverage (branches) | " | 83.01% (floor 70%) ✓ |
| Coverage (functions) | " | 100% (floor 70%) ✓ |
| Coverage (lines) | " | 93.82% (floor 70%) ✓ |
| Log audit — no signedUrl leak | `rg 'logger\.info' functions/src/callables` | all 4 callables log only `{uid, groupId, eventId, ...}` plus `bucket` / `count` / `storagePath`; zero `signedUrl` or `uploadUrl` in log payload |

### Per-file coverage

```
---------------------------|---------|----------|---------|---------|-------------------
File                       | % Stmts | % Branch | % Funcs | % Lines | Uncovered Line #s
---------------------------|---------|----------|---------|---------|-------------------
All files                  |   93.93 |    83.01 |     100 |   93.82 |
 src/callables             |   94.56 |    74.07 |     100 |   94.56 |
  deleteStorageObject.ts   |   86.36 |    66.66 |     100 |   86.36 | 26,40-46 (internal catch)
  getSignedUploadUrl.ts    |     100 |    88.88 |     100 |     100 | 32 (bucket enum else)
  listDocumentsWithUrls.ts |   95.45 |    66.66 |     100 |   95.45 | 38 (?? fallback)
  listMemoriesWithUrls.ts  |   95.45 |    66.66 |     100 |   95.45 | 34 (?? fallback)
 src/lib                   |   92.85 |       92 |     100 |   92.53 |
  paths.ts                 |     100 |      100 |     100 |     100 |
  signing.ts               |   83.33 |      100 |     100 |   83.33 | 73-74,85-86 (prod HTTP)
  validation.ts            |     100 |      100 |     100 |     100 |
  membership.ts            |   93.33 |    77.77 |     100 |   93.33 | 11 (uid guard)
---------------------------|---------|----------|---------|---------|-------------------
```

The uncovered lines in `deleteStorageObject.ts` lines 40-46 are the `try { ... } catch { throw internal }` branch around `file.delete()` — not reachable in the emulator without a forced fault injection. The `?? ({} as ...)` fallback branches on each callable (lines 34/38) cover the case where `request.data` itself is undefined — happens only in malformed RPC frames that `firebase-functions-test.wrap` doesn't model.

## Acceptance Criteria

Task 1:
- [x] `functions/src/callables/listDocumentsWithUrls.ts` contains `assertMemberOfEvent(uid, groupId, eventId)` BEFORE the Firestore query
- [x] `functions/src/callables/listDocumentsWithUrls.ts` contains `.where('isDeleted', '==', false)`
- [x] `functions/src/callables/listDocumentsWithUrls.ts` uses `Promise.all(` for parallel pre-issue (D-03)
- [x] `functions/src/callables/listMemoriesWithUrls.ts` contains `assertMemberOfEvent(...)` BEFORE query
- [x] `functions/src/callables/listMemoriesWithUrls.ts` uses `Promise.all(`
- [x] `functions/src/index.ts` exports both list callables
- [x] `functions/test/fixtures.ts` exports `seedDocuments` + `seedMemories`
- [x] Test command passes: `jest test/callables/listDocumentsWithUrls.test.ts test/callables/listMemoriesWithUrls.test.ts` — 9/9

Task 2:
- [x] `functions/src/callables/deleteStorageObject.ts` calls `parseStoragePath(storagePath)` BEFORE `assertMemberOfEvent`
- [x] Uses `assertMemberOfEvent(uid, groupId, parsed.eventId)` — parsed, not client-claimed
- [x] Uses `file.delete({ ignoreNotFound: true })`
- [x] `functions/src/index.ts` exports all 4 callables
- [x] `jest test/callables/deleteStorageObject.test.ts` — 7/7
- [x] `npm run build --prefix functions` — exit 0

Task 3:
- [x] `functions/test/storage-rules.test.ts` imports `initializeTestEnvironment` + `assertFails` from `@firebase/rules-unit-testing`
- [x] Rules string contains match blocks for `trip-documents/`, `trip-memories/`, `receipts/` all with `allow read, write: if false;`
- [x] 4 test cases: anonymous read / authenticated write / authenticated delete / default-deny
- [x] `jest test/storage-rules.test.ts` — 4/4

Phase-level:
- [x] All 51 tests pass under emulator
- [x] Coverage ≥ 70% on src/callables + src/lib
- [x] Log payloads contain no `signedUrl` / `uploadUrl` (T-38-05 preserved across new callables)

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 — Blocking] `assertFails(ref.putString(...))` TypeScript error**
- **Found during:** Task 3 initial test run
- **Issue:** `@firebase/rules-unit-testing`'s `assertFails<T>(pr: Promise<T>)` requires a `Promise` instance. Firebase Storage SDK's `ref.putString()` returns `UploadTask`, which is thenable but not a `Promise` subtype. TS 5.3 rejected with `TS2345: Type 'UploadTask' is missing finally, [Symbol.toStringTag]`.
- **Fix:** Wrapped `ref.putString('hello')` in an async IIFE (`const upload = (async () => ref.putString('hello'))();`) — the async function wrapper produces a real Promise that awaits the thenable correctly.
- **Files modified:** `functions/test/storage-rules.test.ts`
- **Commit:** `1b5e942`

**2. [Rule 3 — Blocking] `clearFirestore` leaving orphan subcollection docs**
- **Found during:** Task 1 test authoring (before running)
- **Issue:** Plan 02's `clearFirestore` only deleted `groups/*` and `groups/*/events/*` docs. Once tests started seeding `groups/*/events/*/documents/*` and `groups/*/events/*/memories/*`, those subcollection docs would survive across tests, polluting the "zero documents returns empty array" test.
- **Fix:** Extended `clearFirestore` to walk events -> collection('documents').listDocuments() + collection('memories').listDocuments() and delete each before removing the event. This is anticipatory (would have failed on Test 3 of `listDocumentsWithUrls.test.ts`).
- **Files modified:** `functions/test/fixtures.ts`
- **Commit:** `d7749c7`

### Notes / Non-deviations

- **Java 21 still required** — firebase-tools 15.8.0 needs JDK ≥ 21. All emulator runs used `JAVA_HOME=/opt/homebrew/Cellar/openjdk@21/21.0.10/libexec/openjdk.jdk/Contents/Home`. CI must export the same.
- **Node version warning** — firebase emulator logs `"node" version "20" doesn't match global version "25"`. Harmless for emulator testing; deploy environment is fixed at Node 20 by `engines.node` in `functions/package.json`.
- **Worktree diff backlog** — as in Plan 02, the worktree inherited a number of unrelated untracked/modified files from an earlier merge base (CLAUDE.md, lib/core/..., journal.md, etc.). Out of scope; not touched.

## Threat Model Coverage

| Threat ID | Status | Evidence |
|---|---|---|
| T-38-01 (Spoofing — unauth caller) | Mitigated | All three callables start with `if (!request.auth) throw HttpsError('unauthenticated')`. Tests: "unauthenticated rejected" pass on all three |
| T-38-02 (EoP — cross-group) | Mitigated | `assertMemberOfEvent(uid, groupId, eventId)` runs BEFORE any Firestore query / GCS op. Tests: "non-member rejected with permission-denied" pass on all three |
| T-38-04 (EoP — direct Storage SDK bypass) | Mitigated (proof only; rules file swap in Plan 04) | `functions/test/storage-rules.test.ts` proves 4 direct-access patterns (read-unauth, write-auth, delete-auth, default-deny) all return permission-denied under the TIGHTENED_RULES string. Plan 04 applies the same rules to the live `security/storage.rules`. |
| T-38-05 (Info Disclosure — URL leak in logs) | Mitigated | `rg 'logger\.info' functions/src/callables` confirmed payloads contain `{uid, groupId, eventId, bucket, storagePath, count}` — zero `signedUrl` / `uploadUrl` fields. 60-min TTL on download URLs (issueDownloadUrl) limits window |
| T-38-06 (EoP — malformed storagePath) | Mitigated | `deleteStorageObject.ts` calls `parseStoragePath` (throws `invalid-argument` on garbage) BEFORE `assertMemberOfEvent`. Test "eventId-mismatch rejected" proves the caller cannot claim `groupId=g1` with `storagePath=trip-documents/e-other/...` |
| T-38-11 (DoS — large subcollection) | Accepted | No pagination at v2.4 scale; Firebase invocation quotas cap runaway. `isDeleted==false` filter keeps documents query bounded |
| T-38-12 (Info Disclosure — `uploadedBy` uid in list response) | Accepted | Feature, not leak — uids are anonymous FirebaseAuth uids, not PII |

No new threat flags detected in files created/modified.

## Authentication Gates

None. Entire suite runs inside the local Firebase emulator (auth, firestore, storage, functions) with `functionsTest({ projectId: 'rihla-safar-test' })` and `initializeTestEnvironment({ projectId: 'rihla-safar-rules-test' })`. No external credentials required.

## Commits

| Task | Hash | Message |
|---|---|---|
| 1 | `d7749c7` | feat(38-03): add listDocumentsWithUrls + listMemoriesWithUrls with batch pre-issued URLs |
| 2 | `cc41b63` | feat(38-03): add deleteStorageObject callable with path-parse + re-check membership |
| 3 | `1b5e942` | test(38-03): add direct Storage SDK access denial proof (INFRA-01 #3) |

## Hand-off Notes for Plan 04

Plan 04 is Wave 3 — Flutter gateway migration + rules tightening + `main.dart` wire. Inputs ready from this plan:

- **All 4 callables are deployed into `functions/src/index.ts`**. Plan 04's Flutter gateway will call each via `FirebaseFunctions.instance.httpsCallable(name)`:
  - `getSignedUploadUrl({ bucket, groupId, eventId, fileName, contentType, sizeBytes, expenseId? })` -> `{ uploadUrl, storagePath, expiresAt }`
  - `listDocumentsWithUrls({ groupId, eventId })` -> `{ documents: DocumentWithUrl[] }`
  - `listMemoriesWithUrls({ groupId, eventId })` -> `{ memories: MemoryWithUrl[] }`
  - `deleteStorageObject({ storagePath, groupId })` -> `{ deleted: true }`
- **Rule shape for Plan 04's storage.rules swap** is captured verbatim in `functions/test/storage-rules.test.ts`'s `TIGHTENED_RULES` constant — copy that shape into `security/storage.rules`, then update the test to read the live file (replace the inline string with `fs.readFileSync(path.join(__dirname, '../../security/storage.rules'), 'utf8')`).
- **Flutter SDK choice** — `cloud_functions ^5.x` is already in pubspec.yaml (per Plan 01). Use `FirebaseFunctions.instanceFor(region: 'us-central1')` because `setGlobalOptions` on the server pins the region.
- **Member happy-path TTL** — downloads expire 60 min after issuance. The Flutter gateway should either (a) re-call the list callable on every screen entry, or (b) cache with an expiry-aware wrapper that re-issues on staleness. Per CONTEXT D-03, option (a) is acceptable for v2.4.
- **Error-code mapping** — callables throw `HttpsError` with codes the Flutter SDK surfaces as `FirebaseFunctionsException.code`:
  - `unauthenticated` -> surface as "Please re-sign in" dialog
  - `permission-denied` -> surface as "Not a member of this group" (should be rare; normally the UI already filters)
  - `invalid-argument` -> developer error; log + crash in debug, toast in release
  - `not-found` -> same as permission-denied for user-facing purposes (avoid leaking existence)
  - `internal` -> "Something went wrong — try again"
- **Offline queue** — deletes should queue locally when offline (matches existing SyncService pattern). The callable is idempotent (`ignoreNotFound: true`), so replay safety is guaranteed.

## Self-Check: PASSED

Files verified on disk:
- FOUND: functions/src/callables/listDocumentsWithUrls.ts
- FOUND: functions/src/callables/listMemoriesWithUrls.ts
- FOUND: functions/src/callables/deleteStorageObject.ts
- FOUND: functions/test/callables/listDocumentsWithUrls.test.ts
- FOUND: functions/test/callables/listMemoriesWithUrls.test.ts
- FOUND: functions/test/callables/deleteStorageObject.test.ts
- FOUND: functions/test/storage-rules.test.ts

Commits verified:
- FOUND: d7749c7 (Task 1)
- FOUND: cc41b63 (Task 2)
- FOUND: 1b5e942 (Task 3)
