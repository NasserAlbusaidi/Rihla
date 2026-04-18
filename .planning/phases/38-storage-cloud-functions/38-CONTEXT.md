# Phase 38: Storage Cloud Functions - Context

**Gathered:** 2026-04-18
**Status:** Ready for planning

<domain>
## Phase Boundary

Enforce group-membership on Firebase Storage access for the `trip-documents/*` and `trip-memories/*` buckets, replacing the current "any authenticated user" rule. Scope:

- Introduce a Cloud Functions codebase (`functions/` does not exist yet).
- Implement callable Cloud Functions that issue short-lived signed URLs for upload, download, and delete, after verifying the caller is a member of the event's group.
- Tighten `security/storage.rules` to deny all direct client access to `trip-documents/*` and `trip-memories/*`; default-deny elsewhere.
- Migrate `document_service.dart`, `memory_service.dart`, and `receipt_service.dart` from direct Firebase Storage SDK calls (`putFile`/`getDownloadURL`/`delete`) to callables.
- Add a minimal integration test suite (emulator-based) proving a non-member cannot read/write any trip bucket path, and a member can.
- Wire the Flutter app to optionally use the Firebase emulator suite during local development.

**Out of scope (deferred):**
- Storage path migration to include `groupId` (not needed; the function does the lookup).
- Orphan/unused object cleanup (housekeeping, separate quick task if ever).
- Custom claims or Remote Config feature flags.
- Renaming `trip-documents` / `trip-memories` to v2 terminology.

</domain>

<decisions>
## Implementation Decisions

### Enforcement Mechanism

- **D-01:** Use **callable Cloud Functions issuing short-lived signed URLs** for upload, download, and delete. Storage rules deny all direct client access to `trip-documents/*` and `trip-memories/*`.
- **D-02:** Signed-URL TTLs: **uploads 15 minutes, downloads 1 hour**. Tight enough to limit leak blast radius, loose enough to handle mobile upload retries and offline viewing of a screen's images.
- **D-03:** **Batch pre-issue on list.** When the client requests a list (documents for an event, memories for an event), the callable returns `{doc, signedUrl}` tuples in one round trip. No per-image callable on render.
- **D-04:** Membership check is **event → group → member**: function looks up `events/{eventId}` (via `collectionGroup('events')` or `groups/{gid}/events/{eid}` index), reads its `groupId`, then verifies `groups/{gid}/members/{uid}` exists. Accepts one extra Firestore read per call in exchange for zero client coupling.
- **D-05:** **Deletes go through a callable** (`deleteStorageObject`) that verifies membership, then uses the admin SDK to delete. Storage rules deny direct client deletes. Consistent with upload/download gate.

### Callable API shape (guidance — planner finalizes)

- `getSignedUploadUrl({ bucket: 'documents'|'memories', eventId, fileName, contentType, sizeBytes })` → `{ uploadUrl, storagePath, expiresAt }`. Enforces 25 MB server-side.
- `listDocumentsWithUrls({ groupId, eventId })` → `[{ docId, ...fields, signedUrl, expiresAt }]`.
- `listMemoriesWithUrls({ groupId, eventId })` → `[{ memoryId, ...fields, signedUrl, expiresAt }]`.
- `deleteStorageObject({ storagePath })` → `{ deleted: true }` (path parsed to recover eventId for membership check).

Every callable rejects with `permission-denied` when membership check fails and `unauthenticated` when `context.auth` is null.

### Storage Path Scheme

- **D-06:** **Keep existing paths.** No migration. Paths remain:
  - `trip-documents/{eventId}/{timestamp}-{fileName}`
  - `trip-memories/{eventId}/{timestamp}.{ext}`
- **D-07:** **Keep existing prefix names** (`trip-documents`, `trip-memories`). Renaming to v2 terminology is cosmetic only and would force an avoidable migration.

### Rollout & Migration

- **D-08:** **Hard cutover in one release.** Client update, functions deploy, and rules tightening ship together. No dual-path / fallback code. Fits the pre-launch posture.
- **D-09:** **Accept old-client breakage.** Pre-38 app versions will fail uploads and downloads after rules deploy. Call this out in release notes; force-update is not required but recommended.
- **D-10:** **No object backfill.** Existing Storage objects continue to work — the callable looks up event → group regardless of when the object was uploaded. Orphan cleanup is deferred.

### Test Strategy

- **D-11:** Integration tests run against the **Firebase Emulator Suite** (auth + firestore + storage + functions). CI executes them via `firebase emulators:exec "npm test"`. Proves the whole gate end-to-end with no prod risk.
- **D-12:** Tests are written in **TypeScript** alongside the functions (`functions/test/`) using Jest + `@firebase/rules-unit-testing` + `firebase-functions-test`. A single thin Dart-side integration test wires the Flutter client to the emulators and verifies one happy path.
- **D-13:** **Coverage floor for INFRA-01 success criterion #3** — three tests minimum:
  1. Non-member callable returns `permission-denied` for upload + download + delete.
  2. Member callable returns a valid signed URL; upload/download via that URL succeeds.
  3. Direct Firebase Storage SDK access to both buckets (without a signed URL) returns 403.
  Edge cases (expired URL, cross-event access, ex-member) are nice-to-have, not blocking.

### Local Dev

- **D-14:** Add a **config-gated emulator hookup**. Introduce `USE_FIREBASE_EMULATOR` (bool, default false) to `config.json`. When true, `main.dart` bootstrap calls:
  - `FirebaseAuth.instance.useAuthEmulator('localhost', 9099)`
  - `FirebaseFirestore.instance.useFirestoreEmulator('localhost', 8080)`
  - `FirebaseFunctions.instance.useFunctionsEmulator('localhost', 5001)`
  - `FirebaseStorage.instance.useStorageEmulator('localhost', 9199)`
  Off for prod/CI test builds. The matching ports must exist in `firebase.json` (only auth+firestore are configured today — functions and storage emulators need to be added).

### Claude's Discretion

- Cloud Functions runtime/region: pick current LTS Node (Functions v2 / Node 20) and `us-central1` unless a `preferences.functions_region` exists.
- Admin SDK signing approach: use `Storage.bucket().file().getSignedUrl({ action, expires })` on the default bucket.
- Exact callable names and argument schemas: finalize in PLAN.md; shapes above are guidance.
- Error surfacing on the Flutter side when a callable fails (toast vs error widget): choose the pattern already in use for Firestore errors.
- Logging: use `functions.logger.info/error` with `{eventId, groupId, uid}` structured fields. Alerting is out of scope.

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Phase scope & requirements
- `.planning/ROADMAP.md` — Phase 38 entry
- `.planning/milestones/v2.4-ROADMAP.md` §"Phase 38: Storage Cloud Functions" — goal, dependencies, success criteria
- `.planning/milestones/v2.4-REQUIREMENTS.md` §"Infrastructure (Phase 38)" — INFRA-01 acceptance text
- `.planning/review/README.md` — issue #1b context (open storage vulnerability)

### Prior related work
- `.planning/quick/260414-smu-fix-all-5-critical-firestore-storage-sec/260414-smu-PLAN.md` — the quick-task that added 25 MB limits and explicitly deferred membership enforcement to Phase 38
- `.planning/quick/260414-smu-fix-all-5-critical-firestore-storage-sec/260414-smu-SUMMARY.md` — outcome of that task

### Current rules & config
- `security/storage.rules` — current state: auth + 25 MB, to be tightened to deny-all for trip buckets
- `security/firestore.rules` — not modified this phase, but used by the callable (membership reads)
- `firebase.json` — emulator ports; only auth + firestore configured today
- `.firebaserc` — project is `rihla-safar`

### Client code to migrate
- `lib/features/vault/services/document_service.dart` — `putFile`, `getDownloadURL`, `ref.delete`
- `lib/features/memories/services/memory_service.dart` — `putFile`, `getDownloadURL`, `ref.delete`
- `lib/features/ledger/services/receipt_service.dart` — storage writes
- `lib/features/memories/providers/memory_provider.dart` — URL resolution caller
- `lib/features/vault/models/document_model.dart` — document data shape

### Firestore structure used by the function
- `groups/{groupId}/members/{uid}` — authoritative membership
- `groups/{groupId}/events/{eventId}` — event record (carries `groupId` implicitly via path)

### Project-level
- `CLAUDE.md` — Firebase-only stack, anonymous auth constraint, offline-first expectation, 80%+ test coverage, Decimal for money (not relevant here but documented policy)
- `.planning/PROJECT.md` — vision + non-negotiables

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- **`FirebaseConfig`** (used across services) — already wraps Firebase singletons; add `FirebaseFunctions.instance` getter here.
- **Emulator hookup pattern** — none exists in the app yet; auth/firestore emulators are declared in `firebase.json` but nothing wires Flutter to them.
- **Signed-URL handling on client** — none; today the client holds direct Storage refs and downloads bytes straight from `getDownloadURL()`. Memories provider caches these URLs per session (see `memory_provider.dart`).

### Established Patterns
- **Service layer owns Firebase calls** — every feature has a `*_service.dart` that is the sole Firebase touchpoint. The migration should replace the `_storage.ref()...` block inside each service and leave callers untouched.
- **Streaming providers with cache-on-success + fallback-to-cache** — both `document_service` and `memory_service` already use Firestore streams. Signed URLs slot in on the reader side; the Firestore stream itself stays unchanged.
- **No existing Cloud Functions** — `functions/` directory must be bootstrapped. Use Firebase Functions v2 (Node 20), TypeScript.

### Integration Points
- **`main.dart` bootstrap** — already has an ordered init (Firebase → Supabase-removed → Auth → SharedPrefs → runApp). Add the conditional `use*Emulator` block between Firebase init and Auth session.
- **`pubspec.yaml`** — add `cloud_functions: ^5.x` (not currently installed). Confirm version compatibility with Flutter 3.27+.
- **`firebase.json`** — extend emulators block with `functions` (5001) and `storage` (9199); add `functions: { source: "functions", runtime: "nodejs20" }`.
- **CI (`.github/workflows/release_android.yml`)** — add a functions test job that runs `firebase emulators:exec "npm test --prefix functions"` before the Flutter test job.
- **Deploy** — `firebase deploy --only functions,storage,firestore:rules` (storage rules ship with functions). `.firebaserc` default project `rihla-safar` already set.

</code_context>

<specifics>
## Specific Ideas

- The callable API should match the shape downstream providers already expect as closely as possible — the goal is to swap a block inside each service, not rewire providers or screens.
- Batch pre-issue is important for the memories gallery specifically — it renders dozens of `Image.network` widgets, and per-item callables would nuke the UX.
- Pre-launch posture means we can accept a hard cutover — no user base to grandfather.

</specifics>

<deferred>
## Deferred Ideas

- **Storage path migration to `{groupId}/{eventId}/…`** — would make the scheme self-describing; not needed because the function does the lookup. Revisit only if we ever move back to rules-based checks.
- **Orphan object cleanup** — one-shot admin script to delete Storage objects whose eventId no longer exists. Housekeeping, its own quick task.
- **Remote Config / feature-flag gated rollout** — overkill for pre-launch. Revisit when there are real users to protect.
- **Path-prefix rename** (`trip-*` → `event-*`) — cosmetic; defer indefinitely.
- **Expanded test edge cases** (expired URL, cross-event access, ex-member eviction) — not required by INFRA-01 success criterion; leave for a follow-up hardening phase if warranted.
- **Observability/alerting** on the callables (Cloud Monitoring, error budgets) — beyond this phase's scope.

</deferred>

---

*Phase: 38-storage-cloud-functions*
*Context gathered: 2026-04-18*
