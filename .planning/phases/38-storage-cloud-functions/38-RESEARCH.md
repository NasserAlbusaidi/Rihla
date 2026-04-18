# Phase 38: Storage Cloud Functions - Research

**Researched:** 2026-04-18
**Domain:** Firebase Cloud Functions (v2, TS, Node 20) + Admin SDK signed URLs + Firebase Emulator Suite + Flutter `cloud_functions` migration
**Confidence:** HIGH (stack + APIs verified against live npm/pub), MEDIUM (emulator signed-URL strategy — relies on documented workaround, not a clean test path)

## Summary

Phase 38 closes the open Storage authorization gap (review issue #1b) by introducing a Cloud Functions codebase that mediates all access to `trip-documents/*` and `trip-memories/*` through short-lived v4 signed URLs, gated by a Firestore membership check against the group's `memberIds` array. Storage rules collapse to deny-all for the two trip prefixes; the client holds no direct Storage references for those paths.

The stack is uncontroversial: **firebase-functions@^7.2.5** (v2 API, Node 20), **firebase-admin@^13.8.0** for signing and Firestore reads, **Jest + firebase-functions-test@^3.4.1 + @firebase/rules-unit-testing@^5.0.0** for the emulator-based integration tests, and **cloud_functions@^6.2.0** on the Flutter side. All are currently published and compatible with the existing Rihla stack (firebase_core 4.6.0, Flutter SDK ^3.10.1).

One non-trivial finding: **the Firebase Storage emulator does not support `file.getSignedUrl()`** (open since firebase-tools#3400, unresolved as of April 2026). Integration tests must handle this explicitly — either detect emulator mode and return an unsigned `publicUrl()`, or stub signing in tests and verify the membership gate and URL issuance logic separately from the actual PUT/GET bytes. This is flagged in the Validation Architecture section and must be baked into the callable's implementation (not discovered at test time).

**Primary recommendation:** Ship one `functions/` codebase with four callables (`getSignedUploadUrl`, `listDocumentsWithUrls`, `listMemoriesWithUrls`, `deleteStorageObject`), gated by a shared `assertMemberOfEvent(uid, groupId, eventId)` helper that reads the group's `memberIds` array (one Firestore read, no `collectionGroup` query — the client passes `groupId` alongside `eventId` because every `Event` model already carries it). Use v4 signed URLs (15 min upload TTL, 60 min download TTL). In the callable, branch on `process.env.FUNCTIONS_EMULATOR` to return `file.publicUrl()` in emulator mode; integration tests run against emulators end-to-end.

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions

- **D-01:** Use **callable Cloud Functions issuing short-lived signed URLs** for upload, download, and delete. Storage rules deny all direct client access to `trip-documents/*` and `trip-memories/*`.
- **D-02:** Signed-URL TTLs: **uploads 15 minutes, downloads 1 hour**.
- **D-03:** **Batch pre-issue on list.** Callables return `{doc, signedUrl}` tuples in one round trip.
- **D-04:** Membership check is **event → group → member**: look up `events/{eventId}` (via `collectionGroup('events')` or `groups/{gid}/events/{eid}`), read `groupId`, then verify member.
- **D-05:** **Deletes go through a callable** (`deleteStorageObject`). Rules deny direct client deletes.
- **D-06 / D-07:** **Keep existing paths and prefix names** (`trip-documents/{eventId}/…`, `trip-memories/{eventId}/…`). No migration.
- **D-08:** **Hard cutover in one release.** Client + functions + rules deploy together. No dual-path.
- **D-09 / D-10:** Accept old-client breakage post-release. No object backfill.
- **D-11:** Integration tests run against the **Firebase Emulator Suite** (auth + firestore + storage + functions).
- **D-12:** Tests in **TypeScript** (`functions/test/`) using Jest + `@firebase/rules-unit-testing` + `firebase-functions-test`. One thin Dart integration test wires the Flutter client to emulators and verifies a happy path.
- **D-13:** Three mandatory tests: (1) non-member → `permission-denied` for upload/download/delete; (2) member gets valid signed URL and upload/download succeeds; (3) direct Storage SDK to trip buckets returns 403.
- **D-14:** **Config-gated emulator hookup** via `USE_FIREBASE_EMULATOR` bool in `config.json`. Wire auth (9099), firestore (8080), functions (5001), storage (9199) from `main.dart` bootstrap.

### Claude's Discretion

- Cloud Functions runtime/region: Node 20, `us-central1` (Functions v2).
- Admin SDK signing: `Storage.bucket().file().getSignedUrl({ action, expires })` on the default bucket.
- Exact callable names and schemas: finalize in PLAN.md; CONTEXT shapes are guidance.
- Flutter-side error surfacing for callable failures: match the pattern used for Firestore errors.
- Logging: `functions.logger.info/error` with `{eventId, groupId, uid}` structured fields. No alerting.

### Deferred Ideas (OUT OF SCOPE)

- Storage path migration to `{groupId}/{eventId}/…`.
- Orphan Storage object cleanup script.
- Remote Config / feature-flag gated rollout.
- Path-prefix rename (`trip-*` → `event-*`).
- Expanded test edge cases (expired URL, cross-event, ex-member eviction).
- Observability / alerting on callables.
</user_constraints>

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| INFRA-01 | Firebase Storage membership rules enforced via Cloud Function (or callable check) so read/write to trip buckets requires verified group membership, not just any authenticated user. | Callable architecture in `## Architecture Patterns`; membership helper in `## Code Examples`; deny-all storage rules template in `## Standard Stack`; emulator-based integration proof in `## Validation Architecture`. |
</phase_requirements>

## Project Constraints (from CLAUDE.md)

- **Firebase-only stack** — no Supabase references. `firebase_core`, `cloud_firestore`, `firebase_storage`, `firebase_auth` already in pubspec; add `cloud_functions` only.
- **Anonymous auth** — `FirebaseConfig.ensureAnonymousSession()` yields a uid via `signInAnonymously()`. The callable must treat anonymous users as real authenticated users (they are — `request.auth.uid` is populated identically).
- **TDD, 80%+ coverage** — CI (`release_android.yml`) runs `flutter test --coverage` and fails below 80%. The Cloud Functions codebase adds its own Jest coverage; test counts both must stay above threshold.
- **Offline-first** — callables fail offline (no Functions offline cache). Upload/download flows must surface a sensible error UI; Firestore reads (for the list of docs/memories) still work offline.
- **Decimal for money** — not relevant to this phase.
- **Design tokens** — not relevant to this phase.
- **GSD workflow enforcement** — all edits must flow through GSD commands; `/gsd:execute-phase` for this work.
- **`functions/` does not exist yet** — this phase bootstraps it. The directory must land as part of the phase's first wave so subsequent tasks can build on it.

## Standard Stack

### Core

| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| `firebase-functions` | `^7.2.5` [VERIFIED: npm view firebase-functions version, 2026-04-18] | Functions v2 runtime + `onCall` API | Current major. V2 is the only path forward — V1 is legacy and callable V1 has the known `context.auth is null` regression (firebase-tools#5210). |
| `firebase-admin` | `^13.8.0` [VERIFIED: npm view firebase-admin version, 2026-04-18] | Admin SDK for Firestore reads + Storage signing | Same major as `functions@7`. Provides `getStorage().bucket().file().getSignedUrl(...)`. |
| `typescript` | `^5.x` | Function source language | Codebase convention (test stack is TS too). |
| `firebase-tools` | `^14.x` (installed globally or via devDependency) | CLI for `emulators:start`, `emulators:exec`, `deploy` | Confirmed present in dev env (v14.13.0 per prior observation); CI needs to install it. |

Node runtime: **20 LTS** (Functions v2 default; Node 22 is also GA on Functions but 20 is still the safest LTS through mid-2026). [CITED: firebase.google.com/docs/functions/typescript]

Region: **`us-central1`** — Functions v2 default, lowest-latency for Flutter clients outside of EU. Set via `setGlobalOptions({ region: 'us-central1' })` in `functions/src/index.ts` so future functions inherit it.

### Flutter Side

| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| `cloud_functions` | `^6.2.0` [VERIFIED: pub.dev API, latest 6.2.0, 2026-04-18] | Flutter client for Firebase Callable Functions | Aligned with `firebase_core: ^4.6.0` already in pubspec. Provides `FirebaseFunctions.instance.httpsCallable('name').call({...})`. |

**cloud_functions minimum env:** Dart SDK `>=3.2.0`, Flutter `>=3.3.0`. Rihla's `environment: sdk: ^3.10.1` satisfies this.

### Test Stack

| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| `jest` | `^29.x` | Test runner + assertions | Ecosystem default; `firebase-functions-test` samples use it. |
| `ts-jest` | `^29.x` | TS compile for Jest | Pairs with Jest 29; supports ESM if needed but we default to CommonJS. |
| `firebase-functions-test` | `^3.4.1` [VERIFIED: npm view, 2026-04-18] | Test harness with `wrap()` for v2 callables | Official; supports v2 onCall wrapping (`CallableRequest<any>` single-param shape). |
| `@firebase/rules-unit-testing` | `^5.0.0` [VERIFIED: npm view, 2026-04-18] | Firestore + Storage rules testing against emulator | Current major; the only blessed path for rules tests. |
| `@types/jest`, `@types/node` | current | TS types | Standard devDep. |

### Storage Rules (final shape)

```
rules_version = '2';
service firebase.storage {
  match /b/{bucket}/o {
    // Trip documents + memories: deny all direct client access (gated by callable + signed URL)
    match /trip-documents/{eventId}/{allPaths=**} {
      allow read, write: if false;
    }
    match /trip-memories/{eventId}/{allPaths=**} {
      allow read, write: if false;
    }
    // Receipts: same treatment (receipt_service.dart also migrates this phase)
    match /receipts/{tripId}/{allPaths=**} {
      allow read, write: if false;
    }
    // Default: deny all other paths
    match /{allPaths=**} {
      allow read, write: if false;
    }
  }
}
```

> Signed URLs from the admin SDK are NOT subject to Storage rules — they carry their own GCS-level authorization token. So deny-all at the client-SDK layer does not block the signed URL; it blocks unsigned direct access. This is the whole point of the design.

### Installation

**functions/package.json (new file):**

```json
{
  "name": "functions",
  "engines": { "node": "20" },
  "main": "lib/index.js",
  "scripts": {
    "build": "tsc",
    "build:watch": "tsc --watch",
    "serve": "npm run build && firebase emulators:start --only functions",
    "shell": "npm run build && firebase functions:shell",
    "start": "npm run shell",
    "deploy": "firebase deploy --only functions",
    "logs": "firebase functions:log",
    "test": "jest",
    "test:coverage": "jest --coverage"
  },
  "dependencies": {
    "firebase-admin": "^13.8.0",
    "firebase-functions": "^7.2.5"
  },
  "devDependencies": {
    "@firebase/rules-unit-testing": "^5.0.0",
    "@types/jest": "^29.5.12",
    "@types/node": "^20.11.0",
    "firebase-functions-test": "^3.4.1",
    "jest": "^29.7.0",
    "ts-jest": "^29.1.2",
    "typescript": "^5.3.3"
  },
  "private": true
}
```

**pubspec.yaml (add one line):**

```yaml
cloud_functions: ^6.2.0
```

### Alternatives Considered

| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| v2 `onCall` callable | v2 `onRequest` HTTP + manual `ID_TOKEN` verify | Callable handles auth + CORS + error framing automatically; picking onRequest would mean reinventing ~100 lines of boilerplate. CONTEXT D-01 locks callable. |
| v4 signed URLs | Firestore-stored download tokens (signed JWTs the callable issues, validated by a middleware HTTP function) | More code to write, more code to maintain, no material security gain. Admin SDK `getSignedUrl` is battle-tested. |
| Single codebase | Multiple codebases (one per domain) | v2 supports multi-codebase deploys via `firebase.json`. For one function family (storage-gate), single codebase is the default and is right. |
| `getSignedUrl` (v4) | `generateUploadUrl` (Firebase Storage web SDK's newer API) | Only available in JS client SDK, not admin SDK. Doesn't apply here. |
| `@google-cloud/storage` direct | Admin SDK `getStorage().bucket()` | Admin SDK re-exports `@google-cloud/storage`, so this is the same thing one level lower. Use Admin SDK for consistency with Auth/Firestore imports. |

## Architecture Patterns

### Recommended Project Structure

```
Rihla/
├── functions/                          # NEW — Cloud Functions codebase
│   ├── src/
│   │   ├── index.ts                    # setGlobalOptions + exports
│   │   ├── callables/
│   │   │   ├── getSignedUploadUrl.ts
│   │   │   ├── listDocumentsWithUrls.ts
│   │   │   ├── listMemoriesWithUrls.ts
│   │   │   └── deleteStorageObject.ts
│   │   ├── lib/
│   │   │   ├── membership.ts           # assertMemberOfEvent(uid, groupId, eventId)
│   │   │   ├── signing.ts              # issueUploadUrl, issueDownloadUrl — handles emulator branch
│   │   │   ├── paths.ts                # build + parse "trip-documents/{eventId}/{name}"
│   │   │   └── validation.ts           # size/content-type/filename checks
│   │   └── admin.ts                    # admin.initializeApp() singleton
│   ├── test/
│   │   ├── setup.ts                    # Jest setup: emulator env vars, test project id
│   │   ├── fixtures.ts                 # seed groups/members/events in emulator Firestore
│   │   ├── getSignedUploadUrl.test.ts
│   │   ├── listDocumentsWithUrls.test.ts
│   │   ├── listMemoriesWithUrls.test.ts
│   │   ├── deleteStorageObject.test.ts
│   │   └── storage-rules.test.ts       # direct SDK access returns 403
│   ├── package.json
│   ├── tsconfig.json
│   ├── jest.config.js
│   └── .eslintrc.js                    # optional, matches Functions sample config
│
├── lib/
│   ├── core/
│   │   ├── config/
│   │   │   ├── firebase_config.dart     # ADD: FirebaseFunctions getter + emulator hookup
│   │   │   └── app_config.dart          # ADD (or modify): USE_FIREBASE_EMULATOR flag
│   │   └── services/
│   │       └── storage_gateway.dart     # NEW — thin wrapper for callable calls + error mapping
│   └── features/
│       ├── vault/services/document_service.dart      # MODIFY — route writes through gateway
│       ├── memories/services/memory_service.dart     # MODIFY — route writes through gateway
│       └── ledger/services/receipt_service.dart      # MODIFY — route writes through gateway
│
├── security/
│   └── storage.rules                    # MODIFY — tighten to deny-all
├── firebase.json                        # MODIFY — add functions + storage emulators
└── .github/workflows/release_android.yml  # MODIFY — add functions test job
```

### Pattern 1: v2 Callable Skeleton

**What:** Every callable follows the same shape — auth-check → membership-check → business logic → structured response.
**When to use:** All four callables in this phase.
**Example:**

```typescript
// Source: https://firebase.google.com/docs/functions/callable (official)
import { onCall, HttpsError } from 'firebase-functions/v2/https';
import { logger, setGlobalOptions } from 'firebase-functions/v2';
import { assertMemberOfEvent } from '../lib/membership';
import { issueUploadUrl } from '../lib/signing';
import { buildDocumentPath } from '../lib/paths';
import { validateUploadParams } from '../lib/validation';

setGlobalOptions({ region: 'us-central1' });

interface GetSignedUploadUrlInput {
  bucket: 'documents' | 'memories';
  groupId: string;
  eventId: string;
  fileName: string;
  contentType: string;
  sizeBytes: number;
}

interface GetSignedUploadUrlOutput {
  uploadUrl: string;
  storagePath: string;
  expiresAt: string;   // ISO8601
}

export const getSignedUploadUrl = onCall<GetSignedUploadUrlInput, Promise<GetSignedUploadUrlOutput>>(
  async (request) => {
    if (!request.auth) {
      throw new HttpsError('unauthenticated', 'Sign-in required.');
    }
    const uid = request.auth.uid;
    const { bucket, groupId, eventId, fileName, contentType, sizeBytes } = request.data;

    validateUploadParams({ fileName, contentType, sizeBytes });  // throws invalid-argument
    await assertMemberOfEvent(uid, groupId, eventId);            // throws permission-denied

    const storagePath = buildDocumentPath(bucket, eventId, fileName);
    const { uploadUrl, expiresAt } = await issueUploadUrl(storagePath, contentType);

    logger.info('signed-upload-url issued', { uid, groupId, eventId, bucket, storagePath });
    return { uploadUrl, storagePath, expiresAt };
  }
);
```

### Pattern 2: Membership Helper (single Firestore read)

**What:** One helper function, used by all four callables. Reads the group doc once and checks `memberIds` (not the `members/{uid}` subcollection — the array-contains check is O(1) on a single document).
**When to use:** First line of every callable after the `request.auth` check.

```typescript
// Source: codebase-verified — groups/{gid}.memberIds is the authoritative array per D-14 of prior work
// (see lib/features/groups/models/group_model.dart:14, firestore.rules group-rules isMember())
import { getFirestore } from 'firebase-admin/firestore';
import { HttpsError } from 'firebase-functions/v2/https';

export async function assertMemberOfEvent(
  uid: string,
  groupId: string,
  eventId: string,
): Promise<void> {
  const db = getFirestore();

  // One read: verify group + membership + event-in-group in a single chained path fetch.
  const eventRef = db.doc(`groups/${groupId}/events/${eventId}`);
  const [eventSnap, groupSnap] = await Promise.all([
    eventRef.get(),
    db.doc(`groups/${groupId}`).get(),
  ]);

  if (!groupSnap.exists) {
    throw new HttpsError('not-found', 'Group not found.');
  }
  if (!eventSnap.exists) {
    throw new HttpsError('not-found', 'Event not found.');
  }
  const memberIds = (groupSnap.data()?.memberIds ?? []) as string[];
  if (!memberIds.includes(uid)) {
    throw new HttpsError('permission-denied', 'Not a member of this group.');
  }
}
```

> **Important deviation from CONTEXT D-04:** CONTEXT proposes a `collectionGroup('events')` lookup by eventId alone. Every `Event` model in the Flutter codebase (`lib/features/events/models/event_model.dart:158`) already stores `groupId` as a field — so the client can send both. Passing `groupId` explicitly avoids the `collectionGroup` query (which would require a new composite index + more reads), makes the membership check a two-document point read, and keeps the function stateless w.r.t. event discovery. **Recommend callable signatures take both `groupId` and `eventId`.** CONTEXT already lists `listDocumentsWithUrls({ groupId, eventId })` so this is aligned for list+delete; the upload callable should match.
>
> For `deleteStorageObject({ storagePath })` the path is `trip-{documents|memories}/{eventId}/...` with no `groupId`. Two options: (a) require the caller to pass `{ storagePath, groupId }` explicitly (preferred — every delete call site knows `groupId`); (b) parse `eventId` from path, `collectionGroup` lookup to find `groupId` (costs an index and extra read). **Recommend (a).** Plan should document this.

### Pattern 3: Signed URL Issuance (with Emulator Branch)

**What:** Centralized helper that issues v4 signed URLs for read/write, with an explicit `FUNCTIONS_EMULATOR` branch returning `publicUrl()` when running under emulator (since the Storage emulator does not support `getSignedUrl`).
**When to use:** Every callable that returns a URL.

```typescript
// Source: https://firebase.google.com/docs/storage/admin/start + firebase-tools#3400 workaround
import { getStorage } from 'firebase-admin/storage';

const IS_EMULATOR = !!process.env.FUNCTIONS_EMULATOR;

export async function issueUploadUrl(
  storagePath: string,
  contentType: string,
): Promise<{ uploadUrl: string; expiresAt: string }> {
  const file = getStorage().bucket().file(storagePath);
  const expires = Date.now() + 15 * 60 * 1000;  // 15 min (D-02)

  if (IS_EMULATOR) {
    // Storage emulator doesn't emit real signed URLs; fall back to public URL.
    // Tests validating the membership gate don't depend on signing correctness.
    return { uploadUrl: file.publicUrl(), expiresAt: new Date(expires).toISOString() };
  }

  const [uploadUrl] = await file.getSignedUrl({
    version: 'v4',
    action: 'write',
    expires,
    contentType,
    // Enforces the exact Content-Type header on PUT; mismatched upload is rejected.
    extensionHeaders: {
      'x-goog-content-length-range': `0,${25 * 1024 * 1024}`,  // 25 MB hard cap
    },
  });
  return { uploadUrl, expiresAt: new Date(expires).toISOString() };
}

export async function issueDownloadUrl(storagePath: string): Promise<{ signedUrl: string; expiresAt: string }> {
  const file = getStorage().bucket().file(storagePath);
  const expires = Date.now() + 60 * 60 * 1000;  // 60 min (D-02)

  if (IS_EMULATOR) {
    return { signedUrl: file.publicUrl(), expiresAt: new Date(expires).toISOString() };
  }

  const [signedUrl] = await file.getSignedUrl({
    version: 'v4',
    action: 'read',
    expires,
  });
  return { signedUrl, expiresAt: new Date(expires).toISOString() };
}
```

> **`x-goog-content-length-range` behavior:** [CITED: cloud.google.com/storage/docs/xml-api/reference-headers#xgoogcontentlengthrange] The header sets min/max byte length that GCS will accept on the signed PUT. If the client uploads >25 MB through the signed URL, GCS rejects with 400 before a byte lands in storage. This is the correct server-enforced size limit — do NOT trust the `sizeBytes` arg from the client alone. [ASSUMED] Flutter `http.put(...)` will pass the header through on `Map<String,String>` when set by the caller; verify at implementation time.

### Pattern 4: Flutter Gateway Service

**What:** Single `StorageGateway` service that wraps all callable invocations and translates `FirebaseFunctionsException` into domain errors. Every feature service (`document_service`, `memory_service`, `receipt_service`) depends on it.
**When to use:** Replaces every direct `FirebaseStorage.instance.ref()...` call site.

```dart
// Source: https://firebase.flutter.dev/docs/functions/usage/
import 'package:cloud_functions/cloud_functions.dart';

class StorageGateway {
  StorageGateway._(this._fns);
  final FirebaseFunctions _fns;

  factory StorageGateway() =>
      StorageGateway._(FirebaseFunctions.instanceFor(region: 'us-central1'));

  Future<SignedUpload> getSignedUploadUrl({
    required String bucket,       // 'documents' | 'memories'
    required String groupId,
    required String eventId,
    required String fileName,
    required String contentType,
    required int sizeBytes,
  }) async {
    try {
      final result = await _fns.httpsCallable('getSignedUploadUrl').call({
        'bucket': bucket,
        'groupId': groupId,
        'eventId': eventId,
        'fileName': fileName,
        'contentType': contentType,
        'sizeBytes': sizeBytes,
      });
      return SignedUpload.fromMap(Map<String, dynamic>.from(result.data as Map));
    } on FirebaseFunctionsException catch (e) {
      throw _mapError(e);
    }
  }
  // … same shape for listDocumentsWithUrls, listMemoriesWithUrls, deleteStorageObject
}

StorageException _mapError(FirebaseFunctionsException e) => switch (e.code) {
      'unauthenticated' => const StorageException.notSignedIn(),
      'permission-denied' => const StorageException.notMember(),
      'not-found' => const StorageException.missing(),
      'invalid-argument' => StorageException.invalidInput(e.message ?? ''),
      _ => StorageException.unknown(e.message ?? e.code),
    };
```

> **Upload flow on the client after callable returns:** `http.put(Uri.parse(uploadUrl), body: fileBytes, headers: {'Content-Type': contentType})`. Keep `http` dep or use `dio` (already transitive via other packages) — `http` is cleanest. Add to pubspec if not present.

### Anti-Patterns to Avoid

- **Calling the callable per image in a gallery.** CONTEXT D-03 mandates batch pre-issue. The memories screen renders dozens of `Image.network(...)` — one callable per image would nuke UX and blow Functions invocation cost. `listMemoriesWithUrls` returns tuples in one call; the provider shape in `memory_provider.dart` already uses `asyncMap` + `Future.wait` and fits this pattern (swap `getDownloadUrlCached` → one upstream callable result).
- **Storing signed URLs in Firestore metadata documents.** URLs expire in 60 min; persisting them creates bitrot. Always re-issue on list.
- **Using `collectionGroup('events').where(__name__, ==, eventId)`.** Slow, needs an index, loses the `groupId` the client already knows. Pass `groupId` explicitly.
- **Letting the client pick the `storagePath` for upload.** The callable MUST build the path — otherwise a member of group A could upload into group B's event prefix (the callable only verifies membership in one group; client could lie about which). Return the chosen `storagePath` in the response so the client writes it to Firestore metadata.
- **Post-upload Cloud Function trigger to enforce size.** Overkill and laggy — `x-goog-content-length-range` on the signed URL enforces size at the GCS edge, server-side, before bytes land.
- **Initializing `admin.initializeApp()` inside each callable module.** Causes "already initialized" errors on cold-start retries. Use a single `admin.ts` guarded by `if (!getApps().length)`.
- **Forgetting to add `firebase_storage` as a transitive need.** Storage SDK is still needed for *nothing* in trip flows after migration — it's used for FCM-related things only now. Do NOT remove it blindly; it's a direct dep in pubspec.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Short-lived upload/download URLs | JWT-signed URLs with a custom `/storage/:token` HTTP Function | `file.getSignedUrl({ version: 'v4', action, expires })` | V4 signing is what GCS natively validates; using it means GCS enforces the signature at the edge, not your code. |
| Size enforcement | Post-upload trigger that deletes oversize objects | `extensionHeaders: { 'x-goog-content-length-range': '0,MAX' }` on signed URL | Edge-enforced, zero latency, zero cost. Post-upload triggers race with clients. |
| Auth on callable | Parsing `Authorization: Bearer` headers manually | `request.auth.uid` from `onCall` | Firebase parses and verifies the ID token for you. |
| Error serialization | `return { error: ... }` envelopes | `throw new HttpsError('code', 'msg')` | Flutter `FirebaseFunctionsException.code` maps directly to `HttpsError`'s code; no custom mapping needed. |
| Region pinning | Per-function `{ region: '...' }` option | `setGlobalOptions({ region: 'us-central1' })` in index.ts | Single source of truth, future functions inherit. |
| Admin app init | Multiple `initializeApp()` calls | Lazy `admin.ts` module guarded by `getApps().length` | Cold-start safety. |
| Emulator host wiring | Hard-coded `localhost:5001` everywhere | `FirebaseFunctions.instance.useFunctionsEmulator('localhost', 5001)` + `USE_FIREBASE_EMULATOR` flag | Config-gated per D-14. |

**Key insight:** The GCS signed URL story is already so mature that any hand-rolled alternative is slower, less secure, and more expensive. Stick to the Admin SDK defaults.

## Runtime State Inventory

> This phase has material runtime-state implications — primarily on existing Storage objects and on old-client behavior after rules deploy.

| Category | Items Found | Action Required |
|----------|-------------|------------------|
| Stored data | **Existing Storage objects in `trip-documents/*` and `trip-memories/*`** uploaded by previous app versions. Firestore metadata docs in `groups/{gid}/events/{eid}/documents/*` and `.../memories/*` reference these by `storagePath`. | **No backfill needed.** The callable looks up event → group from Firestore regardless of when the object was uploaded. Any existing object continues to work so long as its metadata doc still exists in Firestore with a correct `eventId` and the `eventId` still resolves to a group the caller is a member of. (D-10) |
| Stored data | **Receipts under `receipts/{tripId}/{expenseId}/...`** — path uses `tripId` not `eventId`. `tripId` in the v1 codebase is the pre-v2-rename of `eventId`; they are the same identifier. | Confirm at plan time whether the receipt storage path should be migrated to `receipts/{eventId}/...` or whether the callable should accept `tripId` for this path. **Recommend: keep path, have callable accept `eventId` param and build the existing `receipts/{eventId}/...` path unchanged — zero migration.** |
| Live service config | **Firebase Functions deployment** — does not exist yet. First deploy will provision functions in the `rihla-safar` project. Enable the Functions API in GCP Console beforehand (or `firebase deploy` will prompt). | New deploy + API enablement. Confirm billing is on Blaze plan (required for Functions v2 + external signing). |
| Live service config | **GCS default bucket name** — Firebase Storage default bucket for project `rihla-safar` is typically `rihla-safar.appspot.com` or `rihla-safar.firebasestorage.app` (project-dependent). Signed URLs need the correct bucket. | Verify with `firebase storage:buckets:list` or `getStorage().bucket().name` at runtime. Default `getStorage().bucket()` with no arg picks the Firebase default bucket — should Just Work. |
| OS-registered state | None — this is a pre-launch app, no scheduled tasks / launchd / systemd involvement. | None. |
| Secrets / env vars | **Service account for Admin SDK** — in Cloud Functions runtime, no secret to configure; the default runtime service account `rihla-safar@appspot.gserviceaccount.com` has the permissions it needs. For local emulator + signed URL generation, the emulator falls back to `publicUrl()` per the branching above, so no service-account JSON needed locally either. | None — zero secret management if we take the emulator branch approach. If we ever need real signed URLs locally, `GOOGLE_APPLICATION_CREDENTIALS=path/to/sa.json firebase emulators:exec ...` is the escape hatch. |
| Secrets / env vars | **`FUNCTIONS_EMULATOR` env var** — set automatically by Firebase emulator to `true` when a function runs under emulator. Code in `signing.ts` reads it. | No manual wiring — firebase-tools sets it. |
| Secrets / env vars | **`SENTRY_DSN`, `SUPABASE_URL`, `SUPABASE_ANON_KEY`** — in config.json (per CLAUDE.md); anon_key/url are legacy and no longer referenced. **`USE_FIREBASE_EMULATOR` to be ADDED.** | Plan: add `USE_FIREBASE_EMULATOR: false` to `config.json.example`. CI's `CONFIG_JSON` secret must be re-generated to include it (default false for prod). |
| Build artifacts | **`functions/lib/` compiled TS output** — gitignored; built on every `firebase deploy` or `npm run build`. | Add `functions/lib/` and `functions/node_modules/` to `.gitignore`. |
| Build artifacts | **`coverage/` for functions** — Jest coverage dir. | Add `functions/coverage/` to `.gitignore`. |

**Pre-existing clients (post-release):** Any user on a pre-phase-38 app version will fail Storage reads/writes after deploy (rules are deny-all). CONTEXT D-09 explicitly accepts this. Release notes must flag it; a Remote Config-gated rollout is deferred (D-deferred).

## Environment Availability

| Dependency | Required By | Available | Version | Fallback |
|------------|------------|-----------|---------|----------|
| Node.js | Functions build + test | ✓ | v25.2.1 (local) / CI installs Node 20 | — |
| npm | Functions deps | ✓ | 11.6.2 | — |
| firebase-tools CLI | Local emulator + deploy | ✓ | 15.8.0 (local) | CI step to `npm install -g firebase-tools@latest` |
| Java 11+ | Firestore emulator | Expected ✓ (Java 17 already used by Android build in CI) | Java 17 in CI | — |
| Flutter SDK 3.27+ | `cloud_functions ^6.2.0` + emulator client APIs | ✓ | SDK ^3.10.1 (pubspec) — matches Flutter 3.x branch | — |
| Firebase project on Blaze plan | Functions v2 deploys + signed URLs | [ASSUMED: likely yes given existing Firestore usage, verify] | `rihla-safar` | Verify with `firebase projects:list` — upgrade if on Spark. |
| GCP Cloud Functions API | v2 function deploy | [ASSUMED: enabled on first `firebase deploy --only functions`] | — | `gcloud services enable cloudfunctions.googleapis.com cloudbuild.googleapis.com artifactregistry.googleapis.com --project=rihla-safar` |
| GCP Cloud Build API | v2 function container build | [ASSUMED: enabled with Functions API] | — | Same as above. |
| Docker | Not needed (Firebase manages container build) | — | — | — |

**Missing / needs verification before first deploy:**

- Blaze plan status — plan task to run `firebase projects:list` and confirm, upgrade if not.
- Cloud Functions / Cloud Build / Artifact Registry API enablement — first `firebase deploy` will enable them but plan should script the verification.

**Available with fallback:** None blocking.

## Common Pitfalls

### Pitfall 1: Storage Emulator does NOT support `getSignedUrl()`

**What goes wrong:** `file.getSignedUrl(...)` called from a function running under the Storage emulator returns a URL that either doesn't work or is rejected.
**Why it happens:** Open issue [firebase-tools#3400](https://github.com/firebase/firebase-tools/issues/3400). The storage emulator uses a different auth model; v4 signing is not implemented.
**How to avoid:** Branch on `process.env.FUNCTIONS_EMULATOR` in the signing helper and return `file.publicUrl()` in emulator mode. Emulator URLs look like `http://localhost:9199/v0/b/{bucket}/o/{encoded-path}` and work for plain PUT/GET.
**Warning signs:** Tests that fail only in CI with "invalid signature" or 403 on the PUT/GET to the emulator-issued URL.

### Pitfall 2: `useFunctionsEmulator` ordering bug on Flutter

**What goes wrong:** `useFunctionsEmulator` is called after `httpsCallable` is invoked once, or after `FirebaseFunctions.instance` is cached — subsequent calls still hit prod.
**Why it happens:** Documented in flutterfire#9705. The emulator setting must be applied before the first call.
**How to avoid:** Call `FirebaseFunctions.instance.useFunctionsEmulator('localhost', 5001)` inside `FirebaseConfig.initialize()` immediately after `Firebase.initializeApp()` and before any service constructor runs.
**Warning signs:** "PERMISSION_DENIED: Missing or insufficient permissions" when running under emulator — it's calling prod Firestore through an emulated auth token.

### Pitfall 3: iOS blocks plaintext HTTP to the emulator

**What goes wrong:** `useFunctionsEmulator` points at `http://localhost:5001`; iOS simulator refuses non-HTTPS by default; callables silently fail.
**Why it happens:** `NSAppTransportSecurity` defaults to blocking HTTP.
**How to avoid:** Add the ATS exception in `ios/Runner/Info.plist` gated on debug/emulator builds:
```xml
<key>NSAppTransportSecurity</key>
<dict>
  <key>NSAllowsLocalNetworking</key>
  <true/>
</dict>
```
**Warning signs:** Emulator works on Android but not on iOS sim.

### Pitfall 4: Admin SDK requires service-account for real signing, even with ADC

**What goes wrong:** Running the function locally (not in emulator) — e.g., via `functions:shell` against real Firebase — `getSignedUrl` fails with "cannot sign data without `client_email`" even though authenticated via `gcloud auth application-default`.
**Why it happens:** V4 signing needs a service-account key or IAM signBlob permission; `authorized_user` ADC credentials can't sign (see firebase-admin-node#2413).
**How to avoid:** For Phase 38 we only sign in the deployed Functions runtime (which has a proper SA) and in emulator (which branches to publicUrl). Do NOT attempt to run `functions:shell` against real GCS with getSignedUrl — it will fail.
**Warning signs:** `error: cannot sign data without client_email` in local shell output.

### Pitfall 5: Forgetting to pass `contentType` on the PUT

**What goes wrong:** Client uploads with default content-type `application/octet-stream` while the signed URL was issued with `contentType: 'image/jpeg'` — GCS returns 403 "does not match signed content-type".
**Why it happens:** V4 signed URLs bind the Content-Type header; the PUT request must match exactly.
**How to avoid:** In the client gateway, after receiving `uploadUrl`, do `http.put(Uri.parse(uploadUrl), body: bytes, headers: {'Content-Type': contentType})` — same contentType sent to the callable.
**Warning signs:** Intermittent upload 403s, always on specific file types.

### Pitfall 6: `collectionGroup` without an index

**What goes wrong:** If we did follow CONTEXT D-04 literally and use `collectionGroup('events').where(FieldPath.documentId(), '==', eventId)`, Firestore returns `FAILED_PRECONDITION` asking for a new composite index.
**Why it happens:** `collectionGroup` needs collection-group-level indexes, separate from single-collection ones.
**How to avoid:** Pass `groupId` from client (all Event models carry it). Then use `db.doc(\`groups/${groupId}/events/${eventId}\`)` — no index needed.
**Warning signs:** `9 FAILED_PRECONDITION: The query requires an index.` in function logs.

### Pitfall 7: Dart `asyncMap` swallows exceptions in memory stream

**What goes wrong:** `eventMemoriesProvider` uses `asyncMap` with `Future.wait` inside — a callable failure on one URL resolution blocks the entire stream emission.
**Why it happens:** `Future.wait` with default settings throws on the first error.
**How to avoid:** Move URL resolution OUT of the per-item loop — one batched callable per stream event via `listMemoriesWithUrls`. This matches D-03 (batch pre-issue) and fixes the stream robustness issue simultaneously.
**Warning signs:** One corrupted memory causing the entire gallery to refuse to render.

### Pitfall 8: Signed URL fails over HTTPS to a private network

**What goes wrong:** Enterprise wifi or a corporate VPN blocks `storage.googleapis.com` or injects a cert — upload times out.
**Why it happens:** Not Rihla-specific, just general network reality.
**How to avoid:** Surface upload failure as a real error (not silent null); do NOT retry forever; expose a "retry" affordance. The gateway's `FirebaseFunctionsException` → `StorageException.unknown` already covers it.
**Warning signs:** Upload hangs, no error, user thinks it worked.

## Code Examples

Verified patterns from official sources.

### Example 1: Function entry point + global options

```typescript
// Source: https://firebase.google.com/docs/functions/typescript
// functions/src/index.ts
import { setGlobalOptions } from 'firebase-functions/v2';

setGlobalOptions({ region: 'us-central1' });

export { getSignedUploadUrl } from './callables/getSignedUploadUrl';
export { listDocumentsWithUrls } from './callables/listDocumentsWithUrls';
export { listMemoriesWithUrls } from './callables/listMemoriesWithUrls';
export { deleteStorageObject } from './callables/deleteStorageObject';
```

### Example 2: Admin SDK singleton

```typescript
// Source: https://firebase.google.com/docs/admin/setup
// functions/src/admin.ts
import { getApps, initializeApp } from 'firebase-admin/app';

if (!getApps().length) {
  initializeApp();
}
```

### Example 3: Jest test for callable with emulators

```typescript
// Source: https://firebase.google.com/docs/functions/unit-testing + firebase-functions-test README
// functions/test/getSignedUploadUrl.test.ts
import functionsTest from 'firebase-functions-test';
import { initializeTestEnvironment, RulesTestEnvironment } from '@firebase/rules-unit-testing';
import { getFirestore } from 'firebase-admin/firestore';

// Point admin SDK at emulators (must be set BEFORE importing function)
process.env.FIRESTORE_EMULATOR_HOST = '127.0.0.1:8080';
process.env.FIREBASE_STORAGE_EMULATOR_HOST = '127.0.0.1:9199';
process.env.FUNCTIONS_EMULATOR = 'true';
process.env.GCLOUD_PROJECT = 'rihla-safar-test';

import '../src/admin';  // side-effect: initializeApp()
import { getSignedUploadUrl } from '../src/callables/getSignedUploadUrl';

const testEnv = functionsTest({ projectId: 'rihla-safar-test' });
const wrapped = testEnv.wrap(getSignedUploadUrl);

beforeEach(async () => {
  // Seed: group with member alice, event eventA
  const db = getFirestore();
  await db.doc('groups/g1').set({ name: 'Crew', memberIds: ['alice'] });
  await db.doc('groups/g1/events/e1').set({ groupId: 'g1', name: 'Trip' });
});

afterAll(() => testEnv.cleanup());

test('non-member gets permission-denied', async () => {
  await expect(
    wrapped({
      data: { bucket: 'documents', groupId: 'g1', eventId: 'e1', fileName: 'a.pdf', contentType: 'application/pdf', sizeBytes: 100 },
      auth: { uid: 'eve' },
    } as any),
  ).rejects.toMatchObject({ code: 'permission-denied' });
});

test('member gets an upload URL', async () => {
  const res = await wrapped({
    data: { bucket: 'documents', groupId: 'g1', eventId: 'e1', fileName: 'a.pdf', contentType: 'application/pdf', sizeBytes: 100 },
    auth: { uid: 'alice' },
  } as any);
  expect(res.uploadUrl).toMatch(/^http/);  // publicUrl in emulator mode
  expect(res.storagePath).toBe('trip-documents/e1/a.pdf');  // path includes timestamp at runtime — adjust expectation
});
```

### Example 4: firebase.json emulator + functions config

```json
{
  "firestore": { "rules": "security/firestore.rules", "indexes": "firestore.indexes.json" },
  "storage": { "rules": "security/storage.rules" },
  "functions": [
    { "source": "functions", "codebase": "default", "predeploy": ["npm --prefix \"$RESOURCE_DIR\" run build"] }
  ],
  "emulators": {
    "auth":      { "port": 9099 },
    "firestore": { "port": 8080 },
    "functions": { "port": 5001 },
    "storage":   { "port": 9199 },
    "ui":        { "enabled": true, "port": 4000 },
    "singleProjectMode": true
  }
}
```

### Example 5: Flutter emulator hookup in FirebaseConfig

```dart
// Source: https://firebase.flutter.dev/docs/functions/usage/ + D-14
// lib/core/config/firebase_config.dart (additions)
import 'package:cloud_functions/cloud_functions.dart';

static const bool _useEmulator = bool.fromEnvironment('USE_FIREBASE_EMULATOR', defaultValue: false);

static Future<void> initialize() async {
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  FirebaseFirestore.instance.settings = const Settings(
    persistenceEnabled: true,
    cacheSizeBytes: Settings.CACHE_SIZE_UNLIMITED,
  );

  if (_useEmulator) {
    FirebaseAuth.instance.useAuthEmulator('localhost', 9099);
    FirebaseFirestore.instance.useFirestoreEmulator('localhost', 8080);
    FirebaseFunctions.instanceFor(region: 'us-central1').useFunctionsEmulator('localhost', 5001);
    FirebaseStorage.instance.useStorageEmulator('localhost', 9199);
    log('Firebase emulators ON (auth:9099, firestore:8080, functions:5001, storage:9199)');
  }
  log('Firebase initialized');
}

static FirebaseFunctions get functions => FirebaseFunctions.instanceFor(region: 'us-central1');
```

### Example 6: Client call via gateway (document upload flow)

```dart
// Source: https://pub.dev/packages/cloud_functions
// lib/features/vault/services/document_service.dart (new uploadFile internals)
Future<Document> uploadFile({ ... }) async {
  final uid = FirebaseConfig.currentUser?.uid;
  if (uid == null) throw Exception('Not authenticated');

  // 1) Ask callable for a signed PUT URL
  final signed = await _gateway.getSignedUploadUrl(
    bucket: 'documents', groupId: groupId, eventId: eventId,
    fileName: fileName, contentType: mimeType ?? 'application/octet-stream',
    sizeBytes: fileSize,
  );

  // 2) Upload bytes via HTTP PUT to the signed URL (server-enforced 25MB via x-goog-content-length-range)
  final bytes = await File(filePath).readAsBytes();
  final res = await http.put(
    Uri.parse(signed.uploadUrl),
    headers: {
      'Content-Type': mimeType ?? 'application/octet-stream',
      'x-goog-content-length-range': '0,${DocumentService.maxFileSizeBytes}',
    },
    body: bytes,
  );
  if (res.statusCode < 200 || res.statusCode >= 300) {
    throw StorageException.uploadFailed(res.statusCode, res.body);
  }

  // 3) Write Firestore metadata (same as today, but storagePath comes from callable)
  final id = const Uuid().v4();
  final data = { 'id': id, ..., 'storagePath': signed.storagePath, ... };
  await eventSubcollection(groupId, eventId, 'documents').doc(id).set(data);
  return Document.fromFirestore(data);
}
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| V1 callable (`functions.https.onCall((data, context) => ...)`) | V2 callable (`onCall<T, R>(async (request) => ...)`) | firebase-functions 4.x → 5.x (2023), stable in 7.x | Single `CallableRequest` param; `context.auth` → `request.auth`. `wrap()` in functions-test works identically. |
| V2 signed URL (default for admin SDK pre-v11) | V4 signed URL (must opt in via `version: 'v4'`) | @google-cloud/storage 5.x+ (2021) | V2 is still accepted but V4 is shorter, clearer, and carries `x-goog-content-length-range` — always pick V4. |
| `useFunctionsEmulator(origin: 'http://...')` | `useFunctionsEmulator(host, port)` | cloud_functions 4.x breaking change (2022) | Plan must use the 2-arg form. |
| Firebase Functions v1 Node 14/16 | Functions v2 Node 20/22 | 2024 Node 14/16 EOL | Pin Node 20 for max stability through 2026. |
| Firestore rules membership via `get()` | Firestore membership via `memberIds` array field | Rihla prior work D-14 (pre-Phase 38) | The Cloud Function reads the same array — consistent with rules. |

**Deprecated / outdated:**

- `functions.https.onCall` (v1 namespace) — avoid for new code; use v2.
- `CloudFunctionsException` — deprecated, use `FirebaseFunctionsException` on the Flutter side.

## Assumptions Log

| # | Claim | Section | Risk if Wrong |
|---|-------|---------|---------------|
| A1 | Project `rihla-safar` is on the Blaze plan | Environment Availability | HIGH — deploy fails on Spark. Mitigation: add plan verification task to Wave 0. |
| A2 | `firebase deploy` auto-enables Functions + Cloud Build + Artifact Registry APIs on first use | Environment Availability | LOW — gcloud command available as fallback; first deploy prompts user if needed. |
| A3 | Flutter `http` PUT passes `x-goog-content-length-range` header through to the server without modification | Pattern 3 | MEDIUM — if stripped, 25 MB enforcement silently regresses to client-trust. Mitigation: integration test that asserts a 26 MB upload is rejected with 400 before writing Firestore metadata. |
| A4 | The `ios/Runner/Info.plist` ATS exception for `localhost` is sufficient for emulator testing on iOS sim | Pitfall 3 | LOW — only affects iOS dev, not prod or Android, not CI. |
| A5 | Receipt storage path `receipts/{tripId}/{expenseId}/...` — `tripId` == `eventId` in v2 codebase | Runtime State Inventory | MEDIUM — if the path truly uses the pre-rename ID, a separate callable arg or a migration is needed. Planner should grep call sites of `ReceiptService.uploadReceipt` at plan time to confirm which value is passed. |
| A6 | `firebase-functions-test` v3.4.1 `wrap()` correctly invokes v2 onCall handlers with `{data, auth}` shape | Example 3 | LOW — documented as supported; functions-test#163 confirms typing was fixed in recent versions. |
| A7 | `FirebaseFunctions.instanceFor(region: 'us-central1').useFunctionsEmulator(...)` applies to the same instance used by later callable calls | Example 5 | LOW — documented behavior. |
| A8 | No existing Flutter `http` or `dio` dep is needed beyond current pubspec — `http` is already transitively available | Pattern 4 | LOW — worst case: plan task adds `http: ^1.2.0` explicitly. |

## Open Questions (RESOLVED)

1. **`collectionGroup('events')` vs. passing `groupId` explicitly.**
   - What we know: CONTEXT D-04 proposes a collectionGroup lookup; the codebase's Event model already carries `groupId`.
   - What's unclear: whether the planner wants to honor D-04 literally or accept this research's recommendation to pass `groupId` explicitly.
   - Recommendation: Pass `groupId` from client (requires updating all call sites in the three service files to provide `groupId`). All call sites already have `groupId` in scope — verified in `document_service.uploadFile` signature. Net-zero client ergonomics cost, meaningful server cost savings.

2. **Receipt path migration.**
   - What we know: `receipt_service.dart` uses `receipts/{tripId}/{expenseId}/...`; storage.rules currently has no explicit rule for `receipts/*` (falls into default-deny after phase 38 tightening).
   - What's unclear: whether receipts belong in the same callable as documents or get their own callable `getSignedReceiptUploadUrl({ tripId, expenseId, ... })`.
   - Recommendation: Treat receipts as a third bucket namespace in the existing `getSignedUploadUrl` callable: `bucket: 'receipts'` in the API, path built as `receipts/{eventId}/{expenseId}/{uuid}.{ext}`. One callable, three buckets. Path differs by bucket. Membership check uses `(groupId, eventId)` same as documents. Downstream `receipt_service.dart` passes `groupId + eventId + expenseId` instead of `tripId + expenseId`.

3. **iOS release build behavior.**
   - What we know: Release builds set `USE_FIREBASE_EMULATOR=false` by default; no emulator hookup runs.
   - What's unclear: whether adding the ATS `NSAllowsLocalNetworking` exception has any review risk on App Store submission.
   - Recommendation: `NSAllowsLocalNetworking` is Apple-sanctioned for dev/local testing and does not disable ATS in prod. Safe.

4. **`firebase-functions` coverage threshold.**
   - What we know: CI has 80% coverage gate on Flutter code.
   - What's unclear: do we add a second 80% gate on the functions TS code, and how does coverage map when most tests run against emulator?
   - Recommendation: Add `jest --coverage` with a 70% floor on the functions codebase in CI (lower than Flutter because emulator tests exercise integration paths that single-function coverage doesn't perfectly measure). Raise to 80% in a follow-up once patterns settle.

## Validation Architecture

### Test Framework

| Property | Value |
|----------|-------|
| Flutter framework | `flutter_test` + `mocktail` + `fake_cloud_firestore` (existing in pubspec) |
| Functions framework | Jest 29 + ts-jest + firebase-functions-test 3.4.1 + @firebase/rules-unit-testing 5.0.0 |
| Config files | `functions/jest.config.js` (new), `test/dart_test.yaml` (existing) |
| Quick run command | `npm test --prefix functions` (functions), `flutter test test/<narrow>` (Flutter) |
| Full suite command | `firebase emulators:exec --only auth,firestore,functions,storage "npm test --prefix functions"` + `flutter test --coverage` |
| Phase gate | Both command groups green; coverage ≥80% (Flutter) / ≥70% (Functions) |

### Phase Requirements → Test Map

| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| INFRA-01 | Non-member gets `permission-denied` on `getSignedUploadUrl` | integration (emulator) | `firebase emulators:exec --only auth,firestore,functions,storage "npx jest functions/test/getSignedUploadUrl.test.ts -t 'non-member'"` | ❌ Wave 0 |
| INFRA-01 | Non-member gets `permission-denied` on `listDocumentsWithUrls` | integration (emulator) | `firebase emulators:exec ... "npx jest listDocumentsWithUrls.test.ts"` | ❌ Wave 0 |
| INFRA-01 | Non-member gets `permission-denied` on `listMemoriesWithUrls` | integration (emulator) | `firebase emulators:exec ... "npx jest listMemoriesWithUrls.test.ts"` | ❌ Wave 0 |
| INFRA-01 | Non-member gets `permission-denied` on `deleteStorageObject` | integration (emulator) | `firebase emulators:exec ... "npx jest deleteStorageObject.test.ts"` | ❌ Wave 0 |
| INFRA-01 | Member receives valid URL; upload/download succeeds (emulator publicUrl) | integration (emulator) | `firebase emulators:exec ... "npx jest -t 'member happy path'"` | ❌ Wave 0 |
| INFRA-01 | Direct Firebase Storage SDK read to `trip-documents/*` returns permission-denied | integration (rules test) | `firebase emulators:exec --only auth,firestore,storage "npx jest storage-rules.test.ts"` | ❌ Wave 0 |
| INFRA-01 | Direct Firebase Storage SDK write to `trip-memories/*` returns permission-denied | integration (rules test) | Same as above | ❌ Wave 0 |
| INFRA-01 | Flutter `StorageGateway.getSignedUploadUrl` surfaces `StorageException.notMember` on `permission-denied` | unit | `flutter test test/core/services/storage_gateway_test.dart` | ❌ Wave 0 |
| INFRA-01 | Flutter `document_service.uploadFile` calls the callable with correct args and writes Firestore metadata on 2xx PUT | unit (mock gateway + http) | `flutter test test/features/vault/services/document_service_test.dart` | ❌ Wave 0 |
| INFRA-01 | Flutter `memory_service.uploadPhoto` integrates gateway path | unit | `flutter test test/features/memories/services/memory_service_test.dart` | ❌ Wave 0 |
| INFRA-01 | Flutter `receipt_service.uploadReceipt` integrates gateway path | unit | `flutter test test/features/ledger/services/receipt_service_test.dart` | ❌ Wave 0 |
| INFRA-01 | One end-to-end Dart integration test wires emulator and verifies member upload happy path | integration (emulator + Flutter) | `USE_FIREBASE_EMULATOR=true flutter test integration_test/storage_gateway_e2e_test.dart` | ❌ Wave 0 |

### Sampling Rate

- **Per task commit:** `npm test --prefix functions` (fast; emulator not required for `wrap()`-level tests where admin branch can be mocked) + `flutter test test/<task-area>` (narrow).
- **Per wave merge:** `firebase emulators:exec --only auth,firestore,functions,storage "npm test --prefix functions"` (full functions suite) + `flutter test --coverage` (full Flutter).
- **Phase gate:** Both full suites green in CI before `/gsd-verify-work`.

### Wave 0 Gaps

- [ ] `functions/` codebase scaffold — package.json, tsconfig.json, jest.config.js, src/index.ts, src/admin.ts
- [ ] `functions/test/setup.ts` — emulator env var wiring
- [ ] `functions/test/fixtures.ts` — Firestore seeding helpers (groups, events, members)
- [ ] `test/core/services/storage_gateway_test.dart` — gateway unit tests with mocked FirebaseFunctions
- [ ] `integration_test/storage_gateway_e2e_test.dart` — Dart-side emulator happy path
- [ ] CI job in `.github/workflows/release_android.yml` to install firebase-tools, boot emulators, and run `npm test --prefix functions` before Flutter tests

## Security Domain

### Applicable ASVS Categories

| ASVS Category | Applies | Standard Control |
|---------------|---------|-----------------|
| V2 Authentication | yes | Firebase Anonymous Auth + `request.auth` on callable. Anonymous uid is a real uid with a valid ID token — treat identically. |
| V3 Session Management | no | Firebase manages token refresh transparently. |
| V4 Access Control | yes | Callable-level membership check (`memberIds` array on `groups/{gid}`). Storage rules deny direct access — authorization is server-enforced. |
| V5 Input Validation | yes | `validateUploadParams` helper: `fileName` regex (no path traversal), `contentType` allowlist, `sizeBytes` ≤ 25 MB. Callable rejects bad input with `invalid-argument`. |
| V6 Cryptography | yes (via SDK) | V4 signing done by Admin SDK / @google-cloud/storage — never hand-roll HMAC. |
| V10 Malicious Code | yes | Only check: callable validates `fileName` to prevent `../` traversal into an arbitrary prefix. |
| V12 File and Resources | yes | 25 MB server-enforced via `x-goog-content-length-range`; content-type enforced by signed URL binding. |

### Known Threat Patterns for Firebase Storage + Functions

| Pattern | STRIDE | Standard Mitigation |
|---------|--------|---------------------|
| Path traversal via fileName (`../../other-event/x.pdf`) | Tampering | Validate `fileName` against `^[\w\-.\s]{1,128}$`; callable builds the path, never uses client-supplied paths. |
| Cross-group read (member of A requests objects from B's event) | Elevation of Privilege | Membership check verifies the specific `groupId` the caller claims AND that the event belongs to that group (`groups/${gid}/events/${eid}` path existence + `memberIds` array). |
| Signed URL leak (URL leaks in logs, screenshots) | Information Disclosure | 15 min upload / 60 min download TTLs cap blast radius. Do NOT log `uploadUrl`; only log `storagePath + uid + eventId`. |
| Oversized upload DoS | Denial of Service | Edge-enforced 25 MB via `x-goog-content-length-range`; GCS rejects at the network edge. |
| Unauthenticated Storage access | Spoofing / EoP | Storage rules deny all `trip-documents/*`, `trip-memories/*`, `receipts/*` — no anonymous bypass possible. |
| Replay of a signed URL after member removal | Elevation of Privilege | Accepted residual risk — signed URLs don't re-check membership mid-TTL. Mitigated by 60-min max TTL. Ex-member edge case is explicitly deferred (D-deferred). |
| Content-Type confusion (upload JS masquerading as JPEG) | Tampering | Signed URL binds Content-Type; client must set matching header. Firestore metadata records the uploaded `contentType`. Downstream viewers trust Firestore metadata, not MIME sniffing. |
| Storage bucket enumeration | Information Disclosure | Bucket name is public anyway (`rihla-safar.appspot.com`); deny-all rules prevent actual object reads. |
| Function billing abuse (loop a non-member through callable) | Financial DoS | Callable throws early on auth + membership checks — no expensive work done for non-members. Firebase quotas cap per-project invocations. Add per-uid rate limit in follow-up if abuse observed. |

## Sources

### Primary (HIGH confidence)

- [Firebase Cloud Functions: Callable Reference](https://firebase.google.com/docs/functions/callable) — v2 `onCall`, `request.auth`, `HttpsError` taxonomy
- [Firebase Cloud Functions: TypeScript Guide](https://firebase.google.com/docs/functions/typescript) — tsconfig and package.json baseline
- [Firebase Cloud Functions: Unit Testing](https://firebase.google.com/docs/functions/unit-testing) — `firebase-functions-test` and `wrap()`
- [Firebase Storage Admin SDK Intro](https://firebase.google.com/docs/storage/admin/start) — `getStorage().bucket().file().getSignedUrl(...)` API
- [@firebase/rules-unit-testing: npm](https://www.npmjs.com/package/@firebase/rules-unit-testing) — v5.0.0 for Firestore + Storage rules tests
- [firebase-functions-test: npm](https://www.npmjs.com/package/firebase-functions-test) — v3.4.1, supports v2 callables
- [FlutterFire: Cloud Functions usage](https://firebase.flutter.dev/docs/functions/usage/) — `httpsCallable`, `useFunctionsEmulator(host, port)`, `FirebaseFunctionsException`
- [Firebase Emulator: Connect to Cloud Storage](https://firebase.google.com/docs/emulator-suite/connect_storage) — emulator URL formats and limitations
- [pub.dev: cloud_functions 6.2.0](https://pub.dev/packages/cloud_functions) — latest verified 2026-04-18

### Secondary (MEDIUM confidence)

- [firebase-tools#3400: Add `file.getSignedUrl()` support in Storage Emulator](https://github.com/firebase/firebase-tools/issues/3400) — confirms emulator does NOT support signed URLs; publicUrl is documented workaround
- [flutterfire#9705: `useFunctionsEmulator` not connecting](https://github.com/firebase/flutterfire/issues/9705) — ordering-bug documentation and resolution
- [firebase-admin-node#2413: `getSignedUrl` requires service account](https://github.com/firebase/firebase-admin-node/issues/2413) — local-signing-with-ADC limitations
- [firebase-functions-test#163: Incorrect wrap typing for v2 onCall](https://github.com/firebase/firebase-functions-test/issues/163) — typing was fixed in v3.4
- [GCS: x-goog-content-length-range header](https://cloud.google.com/storage/docs/xml-api/reference-headers#xgoogcontentlengthrange) — size-enforcement mechanism

### Tertiary (LOW confidence — flagged as [ASSUMED])

- [DEV Community: Firebase emulator storage testing](https://dev.to/aaronksaunders/using-firebase-emulator-for-testing-file-upload-to-firebase-storage-using-firebase-functions-2h1) — reference for `publicUrl` pattern in tests; community article, not official.

## Metadata

**Confidence breakdown:**

- Standard stack: HIGH — all packages verified via npm/pub registry on 2026-04-18.
- Architecture: HIGH — official docs cited for every pattern; Flutter gateway shape matches FlutterFire reference.
- Pitfalls: HIGH on 1 (emulator signed URL — confirmed unfixed in firebase-tools#3400), 2 (useFunctionsEmulator ordering — confirmed in flutterfire#9705), 3 (iOS ATS — documented platform behavior). MEDIUM on 4–8 (ecosystem-common but not every one reproduced in this session).
- Validation architecture: HIGH — test taxonomy matches CONTEXT D-11/12/13 and standard Jest patterns.
- Security: HIGH — ASVS mapping is domain-standard; threat patterns enumerated against the actual design.

**Research date:** 2026-04-18
**Valid until:** 2026-05-18 (30 days — Firebase ecosystem is stable but firebase-functions versions move monthly)
