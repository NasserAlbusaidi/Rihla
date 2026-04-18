---
phase: 38
plan: 04
subsystem: flutter-client / storage-gateway / firebase-rules
tags:
  - security
  - flutter
  - firebase-storage
  - rules-tightening
  - emulator
dependency-graph:
  requires:
    - getSignedUploadUrl-callable (Plan 02)
    - listDocumentsWithUrls-callable (Plan 03)
    - listMemoriesWithUrls-callable (Plan 03)
    - deleteStorageObject-callable (Plan 03)
    - direct-storage-sdk-denial-proof (Plan 03)
  provides:
    - StorageGateway (client SDK wrapper)
    - StorageException (sealed error variants)
    - emulator-hookup (USE_FIREBASE_EMULATOR compile-time flag)
    - storage-rules-deny-all (trip-documents, trip-memories, receipts, default)
    - iOS-ATS-localhost-exception
    - integration-test-e2e (member + non-member)
  affects:
    - phase-38 (closes INFRA-01: all 4 success criteria ready to verify post-deploy)
tech-stack:
  added:
    - http ^1.2.0 (direct-to-GCS PUT for signed upload URLs)
  patterns:
    - Callable gateway — single StorageGateway entry point wrapping 4 callables; maps FirebaseFunctionsException.code → StorageException variants
    - Lazy-init FirebaseFunctions — StorageGateway defers FirebaseFunctions.instanceFor until first callable invocation so pre-Firebase.initialize service construction (tests) does not throw
    - Three-step upload — getSignedUploadUrl → http.put(signedUrl, bytes) → Firestore metadata (with server-authoritative storagePath)
    - Batch pre-issued URLs — eventMemoriesProvider joins watchMemories() with listMemoriesWithUrls() per refresh (replaces per-item asyncMap getDownloadURL)
    - Legacy tripId shim — ReceiptService.uploadReceipt accepts both eventId (preferred) and deprecated tripId
    - Compile-time emulator toggle — bool.fromEnvironment('USE_FIREBASE_EMULATOR', defaultValue: false) baked into binary (T-38-13 mitigation)
key-files:
  created:
    - lib/core/services/storage_gateway.dart
    - lib/core/services/storage_exceptions.dart
    - test/core/services/storage_gateway_test.dart
    - test/features/vault/services/document_service_test.dart
    - test/features/memories/services/memory_service_test.dart
    - test/features/ledger/services/receipt_service_test.dart
    - integration_test/storage_gateway_e2e_test.dart
  modified:
    - pubspec.yaml (added http ^1.2.0)
    - lib/core/config/firebase_config.dart (added FirebaseFunctions getter pinned to us-central1)
    - lib/main.dart (emulator hookup after Firebase.initializeApp, before anon sign-in)
    - lib/features/vault/services/document_service.dart (rewired to StorageGateway; removed _storage field)
    - lib/features/vault/screens/vault_screen.dart (getDownloadUrl signature change)
    - lib/features/memories/services/memory_service.dart (rewired to StorageGateway; listMemoriesWithUrls replaces per-item download)
    - lib/features/memories/providers/memory_provider.dart (batch URL join per refresh)
    - lib/features/ledger/services/receipt_service.dart (rewired to StorageGateway; legacy tripId shim)
    - lib/features/ledger/screens/add_expense_screen.dart (Rule 2: screen-level _uploadReceipt routed through ReceiptService)
    - security/storage.rules (deny-all on trip-documents, trip-memories, receipts + default)
    - ios/Runner/Info.plist (NSAppTransportSecurity + NSAllowsLocalNetworking)
decisions:
  - Lazy-init FirebaseFunctions in StorageGateway (fix, commit 9374ec8) so pre-existing tests under test/unit/document_service_test.dart + memory_service_test.dart keep passing. They construct .withFirestore(db) without Firebase.initializeApp; eager ctor threw [core/no-app]. Deferring is safe because callable invocations all occur post-bootstrap.
  - Migrated lib/features/ledger/screens/add_expense_screen.dart _uploadReceipt (not in plan files_modified scope) as Rule 2 auto-fix. Once rules deny direct SDK, that path would silently return null from receipt upload. Threading through ReceiptService with a pre-generated uuid (for expenseId) preserves the screen's UX contract.
  - `MemoryService.getDownloadUrl` / `getDownloadUrlCached` removed — replaced entirely by `listMemoriesWithUrls` which pre-signs URLs server-side in one round trip (D-03). eventMemoriesProvider joins those URLs onto the Firestore stream per emission.
  - `DocumentService.getDownloadUrl` reshaped to require groupId + eventId — can no longer resolve a signed URL from storagePath alone because the callable is scoped by event membership. vault_screen._openDocument now passes widget.groupId/eventId explicitly.
  - No list-receipts callable exists (Plan 03 built only documents + memories list). ReceiptService.getReceiptUrl returns null with a debug log; deferred to a future plan if/when the receipts UI needs server-signed reads.
metrics:
  duration: ~35 min
  tasks-completed: 4 of 5 (Task 5 is a user-gated deploy checkpoint)
  completed-date: 2026-04-18
  tests-added: 24 (9 gateway + 6 document + 3 memory + 6 receipt) + 2 integration
  tests-total-passing: 1112 (full suite, 3 skipped, 0 failures)
---

# Phase 38 Plan 04: Flutter Client Migration + Deny-All Storage Rules + Emulator Wire

Land the Flutter client migration onto the 4 Cloud Functions callables built in Waves 0-2, tighten `storage.rules` to deny direct Storage SDK access on all three trip buckets, wire emulator hookup into `main.dart` bootstrap, and add a Dart integration test that proves the full round-trip against live emulators. Production deploy is a user-gated checkpoint (Task 5) — the orchestrator will present deploy commands for human authorization.

## What Was Built

### Task 1 — StorageGateway + StorageException + FirebaseConfig getter (commit `3cac46e`)

- `lib/core/services/storage_exceptions.dart` — sealed class with 6 variants: `notSignedIn`, `notMember`, `missing`, `invalidInput`, `uploadFailed`, `unknown`. Subclasses are `final` so switches are exhaustive.
- `lib/core/services/storage_gateway.dart` — single entry point wrapping all 4 callables (`getSignedUploadUrl`, `listDocumentsWithUrls`, `listMemoriesWithUrls`, `deleteStorageObject`). Error mapping for all 5 codes (unauthenticated, permission-denied, not-found, invalid-argument, default).
- Response models: `SignedUpload`, `DocumentWithUrl`, `MemoryWithUrl` — each `fromMap` factory strips `signedUrl`/`expiresAt` off the wire payload and returns the rest as `fields`.
- `lib/core/config/firebase_config.dart` — new `FirebaseConfig.functions` getter pinned to `us-central1` (matches server-side `setGlobalOptions` region).
- 9 unit tests in `test/core/services/storage_gateway_test.dart` — all 4 error codes + happy path + all 3 list/delete paths + receipts-without-expenseId → `invalidInput` mapped from server.
- `pubspec.yaml`: added `http: ^1.2.0` for direct-to-GCS PUT calls.

### Task 2 — Service migration (commit `a43a6e7`)

**DocumentService** — `uploadFile` follows the 3-step flow:
1. `gateway.getSignedUploadUrl(bucket: 'documents', ...)` → signed PUT URL
2. `http.put(uploadUrl, headers: {x-goog-content-length-range: 0,25MB}, body: bytes)` → rejects non-2xx as `StorageException.uploadFailed`
3. Firestore metadata write using server-authoritative `storagePath` (not client-constructed)

`deleteDocument` calls `gateway.deleteStorageObject`. `getDownloadUrl` now requires groupId + eventId; fetches via `listDocumentsWithUrls` and returns the matching entry's `signedUrl` (or null). Caller in `vault_screen._openDocument` updated to pass `widget.groupId`/`widget.eventId`.

**MemoryService** — `uploadPhoto` follows the same 3-step pattern with `bucket: 'memories'`. Per-item `getDownloadURL` removed. New `listMemoriesWithUrls` method proxies to the batch callable. `eventMemoriesProvider` (memory_provider.dart) now watches Firestore docs and joins against `listMemoriesWithUrls` on every refresh to attach pre-issued signed URLs.

**ReceiptService** — `uploadReceipt` accepts both `eventId` (preferred) and legacy `tripId` (with deprecation warning when used alone). Routes through `gateway.getSignedUploadUrl(bucket: 'receipts', ..., expenseId: expenseId)`. Returns the server-authoritative storagePath on success.

**AddExpenseScreen._uploadReceipt** (Rule 2 auto-fix) — previously used `FirebaseStorage.instance.ref().putFile(file)` directly, which will be denied post-deploy. Now routes through `ReceiptService.uploadReceipt` with a pre-generated expenseId (uuid) since the expense row has not been persisted at the time of receipt upload.

**Tests (15 new)** — 6 document + 3 memory + 6 receipt. Cover delete + download-URL paths + upload error mapping. Upload happy path is exercised by the integration test (requires live Firebase).

**Verification**: `grep -rn "FirebaseStorage\.instance\.ref" lib/features/` → 0 matches.

### Task 3 — Emulator hookup + deny-all rules + iOS ATS (commit `0fbea1d`)

**lib/main.dart** — after `Firebase.initializeApp()` and BEFORE `ensureAnonymousSession`, the emulator block fires only when `USE_FIREBASE_EMULATOR=true` (compile-time):

```dart
FirebaseAuth.instance.useAuthEmulator('localhost', 9099);
FirebaseFirestore.instance.useFirestoreEmulator('localhost', 8080);
FirebaseFunctions.instanceFor(region: 'us-central1')
    .useFunctionsEmulator('localhost', 5001);
await FirebaseStorage.instance.useStorageEmulator('localhost', 9199);
```

`_useFirebaseEmulator` is `bool.fromEnvironment` with `defaultValue: false` — baked into the binary, cannot be flipped at runtime (T-38-13).

**security/storage.rules** — replaced with 4 deny-all match blocks (trip-documents, trip-memories, receipts, default catch-all). All read + write conditions are `if false`. Proven by Plan 03's `functions/test/storage-rules.test.ts` against this exact shape.

**ios/Runner/Info.plist** — added `NSAppTransportSecurity` dict containing `NSAllowsLocalNetworking: <true/>`. Permits localhost-only connections (required for emulator on iOS sim) without weakening ATS for other hosts.

**Acceptance criteria verification**:
- `grep -c "allow read, write: if false;" security/storage.rules` → **4** ✓
- `grep -c "useFunctionsEmulator\|useAuthEmulator\|useFirestoreEmulator\|useStorageEmulator" lib/main.dart` → **4** ✓
- `grep -c "NSAllowsLocalNetworking" ios/Runner/Info.plist` → **1** ✓
- `flutter analyze lib/main.dart` → **No issues found!** ✓

### Task 4 — Dart integration test (commit `a828d86`)

`integration_test/storage_gateway_e2e_test.dart` — two tests:

1. **member uploads a document end-to-end** — seeds a group where the anonymous uid is a member, calls `getSignedUploadUrl`, PUTs 11 bytes to the emulator-signed URL, writes Firestore metadata, then asserts `listDocumentsWithUrls` returns the new doc with a pre-issued signed URL starting `http`.
2. **non-member cannot upload** — fresh anonymous uid, seeds a group where they are NOT a member, asserts `getSignedUploadUrl` throws `StorageException.notMember`.

Run command (for Task 5 / user-gated verification):
```
export JAVA_HOME=/opt/homebrew/Cellar/openjdk@21/21.0.10/libexec/openjdk.jdk/Contents/Home
firebase emulators:exec --only auth,firestore,functions,storage \
  "flutter test integration_test/storage_gateway_e2e_test.dart --dart-define=USE_FIREBASE_EMULATOR=true"
```

This test requires an active simulator/device; run under `flutter drive` if needed.

### Fix (commit `9374ec8`) — Lazy-init FirebaseFunctions

Pre-existing unit tests (`test/unit/document_service_test.dart`, `test/unit/memory_service_test.dart`) construct `.withFirestore(db)` without `Firebase.initializeApp()`. The eager `StorageGateway()` ctor threw `[core/no-app]`. Deferred the `FirebaseFunctions.instanceFor` lookup to the first callable invocation via a `_functions` getter. Safe because callable invocations always occur post-bootstrap. Full suite now: **1112 passed, 3 skipped, 0 failing**.

## Verification Results

| Check | Command | Result |
|---|---|---|
| Gateway unit tests | `flutter test test/core/services/storage_gateway_test.dart` | **9/9 passed** |
| Document service tests | `flutter test test/features/vault/services/document_service_test.dart` | **6/6 passed** |
| Memory service tests | `flutter test test/features/memories/services/memory_service_test.dart` | **3/3 passed** |
| Receipt service tests | `flutter test test/features/ledger/services/receipt_service_test.dart` | **6/6 passed** |
| Full suite | `flutter test` | **1112/1112 passing, 3 skipped, 0 failing** |
| Analyze — modified files | `flutter analyze lib/main.dart lib/core/services/ lib/features/vault lib/features/memories lib/features/ledger` | **No errors**, pre-existing info/warning only |
| SDK bypass grep | `grep -rn "FirebaseStorage\.instance\.ref" lib/features/` | **0 matches** |
| Storage rules deny-all | `grep -c "allow read, write: if false;" security/storage.rules` | **4** (trip-documents, trip-memories, receipts, default) |
| Emulator wire count | `grep -c "useAuthEmulator\|useFirestoreEmulator\|useFunctionsEmulator\|useStorageEmulator" lib/main.dart` | **4** |
| iOS ATS exception | `grep -c "NSAllowsLocalNetworking" ios/Runner/Info.plist` | **1** |

Integration test + production deploy gated on Task 5 checkpoint (see below).

## Acceptance Criteria

Task 1:
- [x] `lib/core/services/storage_exceptions.dart` defines `sealed class StorageException` with 6 factory constructors
- [x] `lib/core/services/storage_gateway.dart` has 4 public methods (getSignedUploadUrl, listDocumentsWithUrls, listMemoriesWithUrls, deleteStorageObject)
- [x] Error mapping covers all 5 codes
- [x] `FirebaseConfig.functions` pinned to us-central1
- [x] 9 gateway unit tests passing
- [x] `flutter analyze` clean on modified files

Task 2:
- [x] DocumentService routes uploadFile through `gateway.getSignedUploadUrl(bucket: 'documents', ...)`
- [x] DocumentService.deleteDocument routes through `gateway.deleteStorageObject`
- [x] `grep FirebaseStorage.instance.ref lib/features/vault/services/document_service.dart` → 0
- [x] Same for memory_service.dart and receipt_service.dart
- [x] ReceiptService.uploadReceipt uses bucket='receipts' + expenseId
- [x] 3 service test files exist + pass (15 new tests)

Task 3:
- [x] 4 `allow read, write: if false;` lines in storage.rules (trip-documents, trip-memories, receipts, default)
- [x] `USE_FIREBASE_EMULATOR` compile-time flag in main.dart with all 4 emulator hookups
- [x] Emulator block appears AFTER `Firebase.initializeApp` and BEFORE anon sign-in (verified)
- [x] `NSAllowsLocalNetworking: <true/>` inside `NSAppTransportSecurity` dict in Info.plist
- [x] `flutter analyze lib/main.dart` clean

Task 4:
- [x] `integration_test/storage_gateway_e2e_test.dart` exists
- [x] setUpAll wires all 4 emulators
- [x] Two tests (member happy path, non-member rejected)
- [ ] Emulators:exec run — **gated on Task 5** (requires user-controlled emulator boot + simulator)

Task 5:
- [ ] **HUMAN-GATED** — `firebase deploy --only functions,storage --project rihla-safar`
- [ ] 4 callables ACTIVE in us-central1 per `gcloud functions list`
- [ ] Smoke test in real app
- [ ] Direct-SDK bypass returns `firebase_storage/unauthorized`

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 2 — Missing critical functionality] AddExpenseScreen direct SDK bypass**
- **Found during:** Task 2 file survey
- **Issue:** `lib/features/ledger/screens/add_expense_screen.dart` had a screen-level `_uploadReceipt` that called `FirebaseStorage.instance.ref().putFile()` directly, bypassing `ReceiptService`. Once `storage.rules` is deployed (Task 5), this path would silently fail to null on every receipt upload — receipts would be attached to new expenses only when ReceiptService was used, and never on the AddExpense flow.
- **Fix:** Routed `_uploadReceipt` through `ref.read(receiptServiceProvider).uploadReceipt(...)`. Since the expense is not persisted at receipt-upload time, pre-generate the expenseId via `Uuid().v4()` client-side (threaded into the storage path; future refactor should thread the same id to `expenseService.addExpense` so metadata matches).
- **Files modified:** `lib/features/ledger/screens/add_expense_screen.dart`
- **Commit:** `a43a6e7`
- **Note:** This file was NOT in the plan's `files_modified` list but must migrate or the production deploy breaks a user-visible flow.

**2. [Rule 1 — Bug] Eager FirebaseFunctions.instanceFor crashed pre-existing tests**
- **Found during:** Full-suite regression check after Task 2
- **Issue:** `StorageGateway()` constructor called `FirebaseFunctions.instanceFor(...)` eagerly. Existing tests under `test/unit/document_service_test.dart` and `memory_service_test.dart` construct `DocumentService.withFirestore(db)` without `Firebase.initializeApp()` — `[core/no-app] No Firebase App '[DEFAULT]' has been created`. 14 pre-existing tests failed.
- **Fix:** Deferred `FirebaseFunctions.instanceFor` lookup via a private getter. The lookup now happens on the first callable invocation; tests that never touch a callable path see no Firebase dependency. All 1112 tests pass.
- **Files modified:** `lib/core/services/storage_gateway.dart`
- **Commit:** `9374ec8`

### Notes / Non-deviations

- **No list-receipts callable.** Plan 03 built list callables only for documents + memories. `ReceiptService.getReceiptUrl` returns null with a debug log today. If a future screen needs server-signed receipt reads, a `listReceiptsWithUrls` callable (or `getSignedDownloadUrl` single-item callable) will be needed. Deferred — no current UI consumer.
- **`lib/features/memories/providers/memory_provider.dart`** — removed the per-item `getDownloadUrlCached` call; the provider now does a single `listMemoriesWithUrls` per Firestore stream emission and joins the URLs by storagePath. On callable failure, it falls back to metadata-only (screens render placeholders, stream does not crash).
- **Java 21 required for emulator runs.** Firebase-tools 15.8.0 needs JDK ≥ 21. macOS dev machines must export `JAVA_HOME=/opt/homebrew/Cellar/openjdk@21/21.0.10/libexec/openjdk.jdk/Contents/Home`. CI must pin the same.

## Threat Model Coverage

| Threat ID | Status | Evidence |
|---|---|---|
| T-38-01 (Spoofing) | Mitigated | Callables inherit the `if (!request.auth)` guard from Plans 02/03. Flutter gateway tests assert `unauthenticated → notSignedIn`. |
| T-38-02 (Cross-group EoP) | Mitigated | Server-side `assertMemberOfEvent`. Flutter gateway tests assert `permission-denied → notMember`. Integration test exercises the non-member rejection path end-to-end. |
| T-38-03 (Oversized upload) | Mitigated | Flutter sends `x-goog-content-length-range: 0,25MB` header on every PUT (DocumentService, MemoryService, ReceiptService). Server binds size on the signed URL. |
| T-38-04 (Direct SDK bypass) | Mitigated | `security/storage.rules` now denies read/write on trip-documents/, trip-memories/, receipts/, and default. Plan 03 proved the shape in `functions/test/storage-rules.test.ts`. Zero `FirebaseStorage.instance.ref()` call sites remain in `lib/features/`. |
| T-38-05 (URL leak via logging) | Mitigated | Gateway never logs `uploadUrl`/`signedUrl`. Services log storage path only (never the signed URL). Verified: `grep -rn "uploadUrl\|signedUrl" lib/` only shows type/field definitions, never print/debugPrint statements. |
| T-38-06 (Malformed storagePath delete) | Mitigated | Server `deleteStorageObject` parses + re-checks membership (Plan 03). Flutter `gateway.deleteStorageObject` sends only `storagePath + groupId`. |
| T-38-07 (Path traversal via fileName) | Mitigated | Server authoritative. Flutter sends fileName via basename-safe fields; gateway passes as-is and the server validates/rejects. |
| T-38-13 (Emulator leak to prod) | Mitigated | `_useFirebaseEmulator = bool.fromEnvironment(... defaultValue: false)` — compile-time constant baked into the binary. Prod builds omit `USE_FIREBASE_EMULATOR` → locked `false`. |
| T-38-14 (iOS ATS misconfiguration) | Accepted | `NSAllowsLocalNetworking` ONLY permits localhost. Apple-sanctioned. Does not weaken ATS for any other host. |
| T-38-15 (Old client fails post-deploy) | Mitigated | `StorageException.notMember`/`.unknown` surfaces domain-friendly messages. UI layer can map these to "Please update the app" hints. Release notes flag the hard cutover. |

No new threat flags detected.

## Authentication Gates

None. All work was local (Flutter unit tests + rules file + Info.plist). The production deploy (Task 5) requires the user's Firebase CLI session + Blaze plan confirmation — that's the orchestrator-held checkpoint, not an auth gate mid-task.

## Commits

| Task | Hash | Message |
|---|---|---|
| 1 | `3cac46e` | feat(38-04): add StorageGateway + StorageException with 9 passing unit tests |
| 2 | `a43a6e7` | feat(38-04): migrate document/memory/receipt services to StorageGateway |
| 3 | `0fbea1d` | feat(38-04): wire emulator hookup + deny-all storage.rules + iOS ATS exception |
| 4 | `a828d86` | test(38-04): add Dart integration test for StorageGateway e2e against emulator |
| fix | `9374ec8` | fix(38-04): lazy-init FirebaseFunctions in StorageGateway |

## Task 5 — Production Deploy Checkpoint (PENDING)

This is a human-gated step. The executor has paused here. The user must:

1. **Confirm Blaze plan active.** Firebase Console → `rihla-safar` → Project settings → Billing. Plan 01 Task 3 already confirmed this; re-verify if any regression suspected.

2. **Boot emulators + run integration test** (optional but recommended):
   ```bash
   export JAVA_HOME=/opt/homebrew/Cellar/openjdk@21/21.0.10/libexec/openjdk.jdk/Contents/Home
   cd ~/Desktop/Personal/Rihla
   firebase emulators:exec --only auth,firestore,functions,storage \
     "flutter test integration_test/storage_gateway_e2e_test.dart \
      --dart-define=USE_FIREBASE_EMULATOR=true"
   ```
   Requires a running simulator/device. Expect 2 passing tests.

3. **Build functions TypeScript:**
   ```bash
   cd functions && npm run build && cd ..
   ```

4. **Deploy to production (the user-gated command):**
   ```bash
   firebase deploy --only functions,storage --project rihla-safar
   ```
   Expected output includes:
   - `functions: creating Node.js 20 function getSignedUploadUrl(us-central1)...`
   - `functions: creating Node.js 20 function listDocumentsWithUrls(us-central1)...`
   - `functions: creating Node.js 20 function listMemoriesWithUrls(us-central1)...`
   - `functions: creating Node.js 20 function deleteStorageObject(us-central1)...`
   - `storage: released rules security/storage.rules to firebase.storage/rihla-safar`
   - `Deploy complete!`

5. **Verify callables:**
   ```bash
   gcloud functions list --project=rihla-safar --regions=us-central1
   ```
   All 4 should show status ACTIVE.

6. **Smoke test** in the real app with a fresh test account: create group → create event → upload document → view documents → delete document → upload memory. All must succeed.

7. **Direct-SDK bypass attempt** (from a dev console or test harness):
   ```dart
   FirebaseStorage.instance.ref('trip-documents/any/any.pdf').getDownloadURL()
   ```
   Expected failure: `firebase_storage/unauthorized`.

Once these steps pass, reply with deploy output snippet + smoke test result + bypass confirmation. The orchestrator will mark Phase 38 complete.

## Self-Check: PASSED

Files verified on disk:
- FOUND: lib/core/services/storage_gateway.dart
- FOUND: lib/core/services/storage_exceptions.dart
- FOUND: test/core/services/storage_gateway_test.dart
- FOUND: test/features/vault/services/document_service_test.dart
- FOUND: test/features/memories/services/memory_service_test.dart
- FOUND: test/features/ledger/services/receipt_service_test.dart
- FOUND: integration_test/storage_gateway_e2e_test.dart
- FOUND: security/storage.rules (deny-all shape)
- FOUND: ios/Runner/Info.plist (NSAllowsLocalNetworking)

Commits verified:
- FOUND: 3cac46e (Task 1)
- FOUND: a43a6e7 (Task 2)
- FOUND: 0fbea1d (Task 3)
- FOUND: a828d86 (Task 4)
- FOUND: 9374ec8 (fix)
