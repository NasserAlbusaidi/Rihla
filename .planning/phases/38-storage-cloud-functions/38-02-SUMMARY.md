---
phase: 38
plan: 02
subsystem: firebase-functions / authorization
tags:
  - security
  - firebase-functions
  - authorization
  - signed-urls
dependency-graph:
  requires:
    - functions-codebase
    - emulator-config-functions+storage
  provides:
    - assertMemberOfEvent-gate
    - signed-url-issuance
    - storage-path-builders-parser
    - upload-params-validator
    - getSignedUploadUrl-callable
  affects:
    - phase-38-wave-2 (list + delete callables reuse all four libs)
    - phase-38-wave-3 (storage.rules lockdown; Flutter migration to callable)
tech-stack:
  added: []
  patterns:
    - Gate order inside callable — auth → bucket enum → validateUploadParams → assertMemberOfEvent → issueUploadUrl
    - Emulator branch via process.env.FUNCTIONS_EMULATOR inside signing helpers
    - Testable seam — pure functions buildUploadSignOptions/buildDownloadSignOptions exported for unit coverage of the prod branch
    - Server-side path construction via buildDocumentPath/buildMemoryPath/buildReceiptPath — client fileName is sanitised but never used as a raw path
key-files:
  created:
    - functions/src/lib/membership.ts
    - functions/src/lib/paths.ts
    - functions/src/lib/validation.ts
    - functions/src/lib/signing.ts
    - functions/src/callables/getSignedUploadUrl.ts
    - functions/test/lib/membership.test.ts
    - functions/test/lib/paths.test.ts
    - functions/test/lib/validation.test.ts
    - functions/test/lib/signing.test.ts
    - functions/test/callables/getSignedUploadUrl.test.ts
  modified:
    - functions/src/index.ts
    - functions/.gitignore
decisions:
  - Replaced the flaky jest.resetModules + module-override approach for the signing prod-branch test with a pure-function seam — buildUploadSignOptions + buildDownloadSignOptions — exported from signing.ts. Documented in plan's "NOTE to executor" (flaky fallback).
  - Anchored /lib/ in functions/.gitignore so it excludes only the build output (functions/lib/) and no longer swallows the new functions/src/lib/ + functions/test/lib/ source trees.
  - Used OpenJDK 21 (already installed at /opt/homebrew/Cellar/openjdk@21) for firebase emulators; default system Java is 17 which firebase-tools 15.x rejects.
metrics:
  duration: ~25 min
  tasks-completed: 3 of 3
  completed-date: 2026-04-18
  tests-added: 31 (4 membership + 7 paths + 7 validation + 4 signing + 9 callable)
  coverage-statements: 94.94%
  coverage-branches: 91.42%
  coverage-functions: 100%
  coverage-lines: 94.79%
---

# Phase 38 Plan 02: Membership + Signing + getSignedUploadUrl Summary

Build the shared security + signing + path + validation libraries and the first callable (`getSignedUploadUrl`), with 31 passing Jest tests under the Firebase emulator suite and 94.79% line coverage — establishing the membership gate pattern that all remaining Wave 2 callables will reuse.

## What Was Built

### Task 1 — Shared primitives: membership + paths + validation (commit `5b0469d`)

Three library modules + 18 tests.

**`functions/src/lib/membership.ts`** — `assertMemberOfEvent(uid, groupId, eventId)`:
- Parallel Firestore reads: `groups/{groupId}` + `groups/{groupId}/events/{eventId}` via `Promise.all`
- `HttpsError('not-found')` if either doc missing
- `HttpsError('permission-denied')` if `uid` not in `groupSnap.memberIds[]`
- Input guard throws `invalid-argument` on empty uid/groupId/eventId

**`functions/src/lib/paths.ts`** — server-side path builders + reverse parser:
- `buildDocumentPath(eventId, fileName)` → `trip-documents/{eventId}/{Date.now()}-{fileName}`
- `buildMemoryPath(eventId, fileName)` → `trip-memories/{eventId}/{Date.now()}-{fileName}`
- `buildReceiptPath(eventId, expenseId, fileName)` → `receipts/{eventId}/{expenseId}/{Date.now()}-{fileName}`
- `parseStoragePath(storagePath)` → `{bucket, eventId, expenseId?}` — used by Wave 2 delete callable
- Throws `invalid-argument` on unrecognised path shape

**`functions/src/lib/validation.ts`** — upload parameter sanitiser:
- `MAX_FILE_BYTES = 25 * 1024 * 1024` (D-02 constant)
- Filename regex `/^[\w\-. ]{1,128}$/` — rejects slashes, dot-dot, over-length
- `contentType` length bounds 3-127 chars
- `sizeBytes` must be positive number ≤ 25 MB

**`functions/.gitignore` fix** — anchored `lib/` to `/lib/` so it matches only the compiled output directory, not `src/lib/` or `test/lib/` (deviation Rule 3 — blocking issue for staging).

### Task 2 — Signed URL issuance with emulator branch (commit `7c92b9d`)

**`functions/src/lib/signing.ts`**:

| Function | Emulator branch | Prod branch |
|---|---|---|
| `issueUploadUrl(path, contentType)` | `file.publicUrl()` + ISO expiry 15 min out | `file.getSignedUrl(v4, write, expires, contentType, extensionHeaders: {x-goog-content-length-range: '0,26214400'})` |
| `issueDownloadUrl(path)` | `file.publicUrl()` + ISO expiry 60 min out | `file.getSignedUrl(v4, read, expires)` |

The emulator branch is driven by `process.env.FUNCTIONS_EMULATOR` (set in `test/setup.ts`). Rationale: firebase-tools#3400 — the Storage emulator does not implement getSignedUrl; we test the membership gate contract, not signature correctness.

Two exported testable seams: `buildUploadSignOptions(contentType, expiresMs)` + `buildDownloadSignOptions(expiresMs)` — pure functions returning the exact options object passed to `getSignedUrl`. This replaces the plan's fallback jest.resetModules mocking approach (see Deviations).

### Task 3 — getSignedUploadUrl callable + index wire + 9 E2E tests (commit `4fca2fa`)

**`functions/src/callables/getSignedUploadUrl.ts`** — gate order inside the `onCall` handler:

1. `if (!request.auth) throw HttpsError('unauthenticated')` — T-38-01
2. Bucket enum check `['documents','memories','receipts'].includes(bucket)` → `invalid-argument` otherwise
3. `validateUploadParams({fileName, contentType, sizeBytes})` — rejects path-traversal fileName (T-38-07) and oversize (T-38-03)
4. `await assertMemberOfEvent(uid, groupId, eventId)` — the authorisation gate (T-38-02)
5. Build server-side path via `buildDocumentPath` / `buildMemoryPath` / `buildReceiptPath` — for receipts, require `expenseId` or throw `invalid-argument` (T-38-10)
6. `await issueUploadUrl(storagePath, contentType)` → `{uploadUrl, expiresAt}`
7. `logger.info('signed-upload-url issued', {uid, groupId, eventId, bucket, storagePath})` — intentionally omits `uploadUrl` from the log payload (T-38-05)
8. Return `{uploadUrl, storagePath, expiresAt}`

**`functions/src/index.ts`** — added `export { getSignedUploadUrl } from './callables/getSignedUploadUrl';`.

### Behavior Matrix — getSignedUploadUrl

| Input | Expected | Verified by test |
|---|---|---|
| `auth=undefined` | `HttpsError('unauthenticated')` | ✅ "unauthenticated request rejected" |
| `uid='eve'` (not in memberIds) | `HttpsError('permission-denied')` | ✅ "non-member rejected with permission-denied" |
| `bucket='bogus'` | `HttpsError('invalid-argument')` | ✅ "invalid bucket rejected" |
| `fileName='../../evil.pdf'` | `HttpsError('invalid-argument')` | ✅ "path-traversal fileName rejected" |
| `sizeBytes=26 MB` | `HttpsError('invalid-argument')` | ✅ "oversized sizeBytes rejected" |
| Member + `bucket='documents'` | `{uploadUrl: http(s)://…, storagePath: trip-documents/e1/\d+-report.pdf, expiresAt: ISO}` | ✅ "member happy path — documents" |
| Member + `bucket='memories'` | `storagePath: trip-memories/e1/\d+-photo.jpg` | ✅ "member happy path — memories" |
| Member + `bucket='receipts'` + `expenseId='exp1'` | `storagePath: receipts/e1/exp1/\d+-r.png` | ✅ "member happy path — receipts with expenseId" |
| Member + `bucket='receipts'` (no `expenseId`) | `HttpsError('invalid-argument')` | ✅ "receipts without expenseId rejected" |

## Verification Results

| Check | Command | Result |
|---|---|---|
| Build | `npm run build --prefix functions` | exit 0, zero TS errors |
| All tests (emulator suite) | `firebase emulators:exec --only auth,firestore,storage,functions "npx jest --coverage"` | 31/31 passed, 5 test files |
| Membership tests | `npx jest test/lib/membership.test.ts` | 4/4 passed |
| Paths tests | `npx jest test/lib/paths.test.ts` | 7/7 passed |
| Validation tests | `npx jest test/lib/validation.test.ts` | 7/7 passed |
| Signing tests | `npx jest test/lib/signing.test.ts` | 4/4 passed (2 emulator + 2 builders) |
| Callable E2E tests | `npx jest test/callables/getSignedUploadUrl.test.ts` | 9/9 passed |
| Coverage (statements) | `jest --coverage` | 94.94% (floor 70%) ✅ |
| Coverage (branches) | " | 91.42% (floor 70%) ✅ |
| Coverage (functions) | " | 100% (floor 70%) ✅ |
| Coverage (lines) | " | 94.79% (floor 70%) ✅ |
| Log audit (no uploadUrl leaked) | `grep 'logger.info' getSignedUploadUrl.ts` | confirmed: payload is `{uid, groupId, eventId, bucket, storagePath}` — no `uploadUrl` field |

### Per-file coverage snapshot

```
------------------------|---------|----------|---------|---------|-------------------
File                    | % Stmts | % Branch | % Funcs | % Lines | Uncovered Line #s
------------------------|---------|----------|---------|---------|-------------------
All files               |   94.94 |    91.42 |     100 |   94.79 |
 src                    |     100 |      100 |     100 |     100 |
  admin.ts              |     100 |      100 |     100 |     100 |
 src/callables          |     100 |    88.88 |     100 |     100 |
  getSignedUploadUrl.ts |     100 |    88.88 |     100 |     100 | 32 (bucket enum else)
 src/lib                |   92.85 |       92 |     100 |   92.53 |
  membership.ts         |   93.33 |    77.77 |     100 |   93.33 | 11 (uid guard)
  paths.ts              |     100 |      100 |     100 |     100 |
  signing.ts            |   83.33 |      100 |     100 |   83.33 | 73-74,85-86 (prod HTTP)
  validation.ts         |     100 |      100 |     100 |     100 |
------------------------|---------|----------|---------|---------|-------------------
```

The 4 uncovered lines in `signing.ts` are the actual `getSignedUrl` calls on the prod branch — the surrounding sign-option construction IS covered via `buildUploadSignOptions` / `buildDownloadSignOptions` unit tests. The uncovered `membership.ts:11` is the empty-uid guard, not exercised because callers validate beforehand. `getSignedUploadUrl.ts:32` is the bucket-enum rejection branch for a specific `else` fall-through that tests already exercise through `bucket='bogus'`; coverage tool reports it as 88.88% due to the truthy-string check.

## Acceptance Criteria

- [x] `functions/src/lib/membership.ts` contains `memberIds.includes(uid)` and `Promise.all([`
- [x] `functions/src/lib/paths.ts` exports `buildDocumentPath`, `buildMemoryPath`, `buildReceiptPath`, `parseStoragePath`
- [x] `functions/src/lib/validation.ts` exports `validateUploadParams` and `MAX_FILE_BYTES = 25 * 1024 * 1024`
- [x] `functions/src/lib/validation.ts` contains filename regex excluding `/` and `..`
- [x] `functions/src/lib/signing.ts` checks `process.env.FUNCTIONS_EMULATOR`, uses `file.publicUrl()` in emulator branch
- [x] `functions/src/lib/signing.ts` attaches `'x-goog-content-length-range'` → `'0,26214400'` (= `0,${MAX_FILE_BYTES}`)
- [x] `functions/src/lib/signing.ts` uses `version: 'v4'` for upload + download, 15-min upload TTL, 60-min download TTL
- [x] `functions/src/callables/getSignedUploadUrl.ts` has `if (!request.auth)` + `throw new HttpsError('unauthenticated'`
- [x] `functions/src/callables/getSignedUploadUrl.ts` calls `assertMemberOfEvent` AFTER `validateUploadParams` and BEFORE `issueUploadUrl`
- [x] `functions/src/callables/getSignedUploadUrl.ts` handles all three buckets + requires `expenseId` for receipts
- [x] `functions/src/index.ts` exports `getSignedUploadUrl`
- [x] `npm run build --prefix functions` exits 0
- [x] Full test suite passes under emulator: 4 + 7 + 7 + 4 + 9 = 31 tests (plan predicted 29 — we added 2 extra signing builder tests covering the prod branch)
- [x] Coverage ≥ 70% on lib + callables (actual: 92.5–100%)
- [x] Path traversal attempts rejected at `invalid-argument` (T-38-07 mitigated end-to-end)
- [x] Log payload omits `uploadUrl` (T-38-05 mitigated)

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] `functions/.gitignore` lib/ pattern was swallowing src/lib + test/lib**
- **Found during:** Task 1 (`git add` rejected the new files)
- **Issue:** `functions/.gitignore` contained `lib/` which excluded BOTH the tsc build output AND the new `functions/src/lib/` + `functions/test/lib/` directories
- **Fix:** Anchored the pattern to `/lib/` so only `functions/lib/` (the build output at the root of functions/) is excluded
- **Files modified:** `functions/.gitignore`
- **Commit:** `5b0469d` (same commit as Task 1)

**2. [Rule 3 - Blocking] Signing test prod-branch mock approach was flaky**
- **Found during:** Task 2 initial test run
- **Issue:** The plan's `jest.resetModules` + storageModule-override approach hit `GoogleAuth.sign: Cannot sign data without 'client_email'` — the dynamic re-import did not intercept the real admin SDK's auth path; the emulator branch disabled by `delete process.env.FUNCTIONS_EMULATOR` routed straight into the real Google signing stack
- **Fix:** Refactored per the plan's explicit fallback NOTE — added pure-function builders `buildUploadSignOptions(contentType, expiresMs)` and `buildDownloadSignOptions(expiresMs)` that return the exact options object passed to `getSignedUrl`. The signing functions now delegate to these builders, and the builders are unit-tested directly. The critical assertion — `extensionHeaders['x-goog-content-length-range'] === '0,26214400'`, `version === 'v4'`, `action === 'write'` — is preserved, and the test no longer depends on SDK internals.
- **Files modified:** `functions/src/lib/signing.ts` (added 2 exported builders + `SignUploadOptions`/`SignDownloadOptions` interfaces); `functions/test/lib/signing.test.ts` (replaced prod-mocking test with builder unit tests)
- **Commit:** `7c92b9d`

### Notes / Non-deviations

- **Java 21 required for emulator** — firebase-tools 15.8.0 requires JDK ≥ 21. The system default is JDK 17. Used `JAVA_HOME=/opt/homebrew/Cellar/openjdk@21/…` for all emulator runs. No code change; documentation item for the phase. CI will need `actions/setup-java@v3` with `java-version: '21'`.
- **Leftover untracked files** — the worktree inherited a number of unrelated untracked files (`lib/core/config/supabase_config.dart`, etc.) from an old merge base. They are pre-existing and out of scope for this plan. Logged here for awareness; no fix attempted (scope boundary rule).

## Authentication Gates

None. All tests run inside the local Firebase emulator suite; no external auth required.

## Threat Model Coverage

| Threat ID | Status | Evidence |
|---|---|---|
| T-38-01 (Spoofing — caller identity) | Mitigated | `if (!request.auth) throw HttpsError('unauthenticated')` is the FIRST line; test "unauthenticated request rejected" passes |
| T-38-02 (EoP — cross-group) | Mitigated | `assertMemberOfEvent(uid, groupId, eventId)` reads `groups/{groupId}.memberIds`; tests "non-member rejected" + "throws not-found when group missing" + "throws not-found when event missing" all pass |
| T-38-03 (Tampering — oversize) | Mitigated | `validateUploadParams` rejects > 25 MB BEFORE signing; signing attaches `x-goog-content-length-range: 0,26214400` as defense-in-depth |
| T-38-04 (EoP — direct Storage SDK bypass) | Accepted (this plan) | Rules tightening deferred to Plan 04 per CONTEXT D-08 |
| T-38-05 (Info Disclosure — URL leak) | Mitigated | 15-min TTL + log payload explicitly omits `uploadUrl` (audited via grep) |
| T-38-07 (Path traversal via fileName) | Mitigated | Filename regex `/^[\w\-. ]{1,128}$/` rejects slashes + dot-dot; test "path-traversal fileName rejected" passes; callable ALWAYS builds the server-side path via `build*Path` helpers — client fileName never used as a raw path |
| T-38-09 (Content-Type confusion) | Partial | Signed URL binds `contentType`; GCS rejects mismatched PUT. Client-side enforcement is Plan 04's Flutter gateway |
| T-38-10 (Receipts bucket missed) | Mitigated | `bucket: 'receipts'` branch with `expenseId` required; test "receipts without expenseId rejected" passes |

No new threat flags.

## Commits

| Task | Hash | Message |
|---|---|---|
| 1 | `5b0469d` | feat(38-02): add membership + paths + validation libraries with tests |
| 2 | `7c92b9d` | feat(38-02): add signed-URL issuance library with emulator branch + TTLs |
| 3 | `4fca2fa` | feat(38-02): add getSignedUploadUrl callable with auth+membership+validation gates |

## Hand-off Notes for Plan 03

Wave 2 (plan 38-03) will build three more callables — `listDocumentsWithUrls`, `listMemoriesWithUrls`, `deleteStorageObject`. All four libraries from this plan are ready to reuse:

- **`assertMemberOfEvent`** is THE security primitive. Every new callable's gate order must be: auth check → input validation → `assertMemberOfEvent` → action. No shortcuts, no reordering.
- **`issueDownloadUrl(storagePath)`** is ready for list callables — it handles the emulator branch internally. Use it inside a `.map(doc => ({...doc.data(), ...await issueDownloadUrl(doc.data().storagePath)}))` pattern for batched pre-issue (per CONTEXT D-03).
- **`parseStoragePath(storagePath)`** is ready for the delete callable — use it to recover `eventId` from a client-supplied `storagePath`, then feed that into `assertMemberOfEvent`. Wave 2 test must cover the "member of group A requests delete of group B's object" case and verify it returns `permission-denied`.
- **Fixtures** — `seedGroupWithEvent` in `test/fixtures.ts` handles the happy-path setup. For Wave 2 tests that need documents/memories documents in Firestore, extend `fixtures.ts` with `seedDocument({groupId, eventId, storagePath})` and `seedMemory(…)` helpers — do not inline Firestore writes in each test file.
- **Coverage floor** — the 70% jest threshold enforces itself. The pattern established here (test public API through the emulator + unit-test pure seams) keeps coverage above 90% without ceremony.

## Self-Check: PASSED

Files verified on disk:
- FOUND: functions/src/lib/membership.ts
- FOUND: functions/src/lib/paths.ts
- FOUND: functions/src/lib/validation.ts
- FOUND: functions/src/lib/signing.ts
- FOUND: functions/src/callables/getSignedUploadUrl.ts
- FOUND: functions/test/lib/membership.test.ts
- FOUND: functions/test/lib/paths.test.ts
- FOUND: functions/test/lib/validation.test.ts
- FOUND: functions/test/lib/signing.test.ts
- FOUND: functions/test/callables/getSignedUploadUrl.test.ts

Commits verified:
- FOUND: 5b0469d (Task 1)
- FOUND: 7c92b9d (Task 2)
- FOUND: 4fca2fa (Task 3)
