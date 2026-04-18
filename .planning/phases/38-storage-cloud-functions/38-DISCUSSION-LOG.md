# Phase 38: Storage Cloud Functions - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-04-18
**Phase:** 38-storage-cloud-functions
**Areas discussed:** Enforcement mechanism, Storage path scheme, Rollout & migration, Test strategy

---

## Enforcement mechanism

### Q1: How should Storage access be gated?

| Option | Description | Selected |
|--------|-------------|----------|
| Signed-URL callable | Callable Cloud Function verifies membership, issues short-lived signed URL. Storage rules deny direct access. | ✓ |
| Custom claims on token | Firestore trigger updates `groupIds[]` custom claims; Storage rules read them. Stale until token refresh, 1000-byte limit. | |
| Metadata match (path+md) | Object custom metadata carries groupId; rules match metadata. Weaker, still needs a gate function. | |

**User's choice:** Signed-URL callable
**Notes:** Picked because it sidesteps stale-claim problems for anonymous auth, gives the tightest gate, and avoids the 1000-byte claim-size ceiling.

### Q2: Signed URL TTLs

| Option | Description | Selected |
|--------|-------------|----------|
| Upload 15m / Download 1h | Matches mobile upload time + offline viewing window. | ✓ |
| Upload 10m / Download 10m | Stronger against link leakage; worse offline UX. | |
| Upload 1h / Download 24h | Best UX; stolen URL usable for a day. | |

**User's choice:** Upload 15m / Download 1h

### Q3: Download path

| Option | Description | Selected |
|--------|-------------|----------|
| Batch pre-issue on list | Callable returns `{doc, signedUrl}` pairs on list. Cuts latency. | ✓ |
| Per-item callable | Each image triggers its own callable. Simpler, N+1 problem. | |

**User's choice:** Batch pre-issue on list

### Q4: Membership source

| Option | Description | Selected |
|--------|-------------|----------|
| Event→group→members | Function looks up event by eventId, reads its groupId, checks membership. 2 Firestore reads. | ✓ |
| Require groupId in payload | Client passes `{eventId, groupId}`; function cross-checks. Saves little, adds coupling. | |

**User's choice:** Event→group→members

### Q5: Deletion gate

| Option | Description | Selected |
|--------|-------------|----------|
| Callable delete | `deleteStorageObject({path})` callable verifies membership then admin-SDK deletes. | ✓ |
| Firestore trigger cleanup | onDelete trigger deletes Storage object server-side. Couples the two; orphan risk on trigger failure. | |
| Client deletes + rules allow | Leave direct client delete in place. Leaves same vuln for deletes. | |

**User's choice:** Callable delete

---

## Storage path scheme

### Q1: Should the path scheme change to include groupId?

| Option | Description | Selected |
|--------|-------------|----------|
| Keep eventId-only | Paths remain `trip-{documents,memories}/{eventId}/...`. No migration. | ✓ |
| Migrate to groupId/eventId | Self-describing path, enables future rules-based checks. Requires dual-read or backfill. | |
| New paths for new, old paths frozen | Two schemes live permanently. Avoids backfill but adds complexity. | |

**User's choice:** Keep eventId-only

### Q2: Path prefix — keep or rename?

| Option | Description | Selected |
|--------|-------------|----------|
| Keep current prefixes | `trip-documents`, `trip-memories`. No rename. | ✓ |
| Rename to event-documents/event-memories | v2 terminology alignment; cosmetic only. | |

**User's choice:** Keep current prefixes

---

## Rollout & migration

### Q1: How to roll out the locked-down rules + callable functions?

| Option | Description | Selected |
|--------|-------------|----------|
| Hard cutover in one release | Client, functions, and rules ship together. Old clients break. | ✓ |
| Phased with client fallback | Client tries callable first, falls back to direct SDK. Safer for old app versions. | |
| Feature-flag gated | Remote Config toggle. Dark-launch capable; overkill for solo project. | |

**User's choice:** Hard cutover in one release

### Q2: Old client compatibility

| Option | Description | Selected |
|--------|-------------|----------|
| Accept breakage | Old clients lose upload/download after rules tighten. Release-notes mention. | ✓ |
| Keep a grace period | Rules retain `auth != null` read for 30 days alongside signed-URL path; log direct reads; cut over later. | |

**User's choice:** Accept breakage

### Q3: Existing objects in Storage

| Option | Description | Selected |
|--------|-------------|----------|
| Accessible via the same callable | Function looks up event→group regardless of when uploaded. Zero backfill. | ✓ |
| Audit + prune orphans | One-shot admin script. Housekeeping, separate quick task. | |

**User's choice:** Accessible via the same callable

---

## Test strategy

### Q1: Where do integration tests run?

| Option | Description | Selected |
|--------|-------------|----------|
| Firebase Emulator Suite | auth+firestore+storage+functions emulators. CI via `firebase emulators:exec`. Fast, deterministic, free. | ✓ |
| Staging Firebase project | Real infra. Slow, costs, state bleed between runs. | |
| Functions unit tests only | `firebase-functions-test` offline SDK with mocks. Misses proof that rules are deny-all. | |

**User's choice:** Firebase Emulator Suite

### Q2: Test language

| Option | Description | Selected |
|--------|-------------|----------|
| TypeScript (with functions) | Tests live in `functions/test/` using Jest + `@firebase/rules-unit-testing` + `firebase-functions-test`. | ✓ |
| Dart-only | Add to `test/integration/` via `cloud_functions` + emulator connection. Thinner tooling in Dart. | |

**User's choice:** TypeScript (with functions)

### Q3: Minimum test coverage

| Option | Description | Selected |
|--------|-------------|----------|
| Core negative + positive pair | Non-member rejected, member gets URL, direct SDK access returns 403. Three tests. | ✓ |
| Plus edge cases | Above + expired URL, cross-event access, ex-member eviction. ~8 tests. | |

**User's choice:** Core negative + positive pair

### Q4: Local dev emulator hookup

| Option | Description | Selected |
|--------|-------------|----------|
| Config-gated emulator hookup | `USE_FIREBASE_EMULATOR` flag in config.json; main.dart wires emulators when true. Off by default. | ✓ |
| Always production | No emulator hookup in the app. Dev tests functions via Node only. | |

**User's choice:** Config-gated emulator hookup

---

## Claude's Discretion

- Cloud Functions runtime/region (Functions v2, Node 20, `us-central1` default).
- Admin SDK signing approach (Storage bucket default + getSignedUrl).
- Exact callable names and argument schemas (shape guidance in CONTEXT.md; planner finalizes).
- Flutter error-surfacing pattern for callable failures (match Firestore-error pattern already in use).
- Logging: `functions.logger.info/error` with structured `{eventId, groupId, uid}` fields. No alerting.

## Deferred Ideas

- Storage path migration to `{groupId}/{eventId}/…` scheme.
- Orphan object cleanup script.
- Remote Config / feature-flag gated rollout.
- Path prefix rename (`trip-*` → `event-*`).
- Expanded test edge cases (expired URL, cross-event, ex-member).
- Observability/alerting on callables.
