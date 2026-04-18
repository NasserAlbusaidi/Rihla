---
phase: 38
plan: 01
subsystem: infrastructure / firebase-functions
tags:
  - infrastructure
  - firebase-functions
  - emulators
  - flutter-deps
dependency-graph:
  requires: []
  provides:
    - functions-codebase
    - cloud_functions-flutter-dep
    - emulator-config-functions+storage
    - USE_FIREBASE_EMULATOR-flag
  affects:
    - phase-38-wave-1
    - phase-38-wave-2
    - phase-38-wave-3
tech-stack:
  added:
    - firebase-functions@^7.2.5 (npm)
    - firebase-admin@^13.8.0 (npm)
    - firebase-functions-test@^3.4.1 (npm devDep)
    - "@firebase/rules-unit-testing@^5.0.0 (npm devDep)"
    - jest@^29.7.0 + ts-jest@^29.1.2 (npm devDep)
    - typescript@^5.3.3 (npm devDep)
    - cloud_functions: ^6.2.0 (Flutter)
  patterns:
    - Cloud Functions v2 setGlobalOptions with us-central1 region
    - firebase-admin singleton via getApps().length guard
    - Emulator env vars set in test/setup.ts before any import
    - Firebase emulator suite (auth/firestore/functions/storage + UI) with singleProjectMode
key-files:
  created:
    - functions/package.json
    - functions/tsconfig.json
    - functions/jest.config.js
    - functions/.eslintrc.js
    - functions/.gitignore
    - functions/src/index.ts
    - functions/src/admin.ts
    - functions/test/setup.ts
    - functions/test/fixtures.ts
    - functions/test/helpers/emulator-setup.ts
    - functions/package-lock.json
    - config.json.example
  modified:
    - firebase.json
    - pubspec.yaml
    - pubspec.lock
    - .gitignore
decisions:
  - Pinned firebase-functions to 7.2.5 and firebase-admin to 13.8.0 per RESEARCH §Standard Stack
  - Set Jest coverage floor at 70% globally (RESEARCH Open Question 4) — to be revisited per-callable in Wave 1+
  - Used singleProjectMode in firebase.json so all four emulators share rihla-safar project namespace
  - cloud_functions placed alphabetically in firebase cluster to match existing convention (cloud_firestore → cloud_functions → firebase_auth)
  - USE_FIREBASE_EMULATOR defaulted to false in config.json.example — the real config.json is intentionally NOT modified; user updates manually
metrics:
  duration: ~10 min
  tasks-completed: 2 of 3 (Task 3 = checkpoint, advisory)
  completed-date: 2026-04-18
---

# Phase 38 Plan 01: Storage + Cloud Functions Foundation Summary

Scaffold a buildable functions/ TypeScript project (firebase-functions@7.2.5 + firebase-admin@13.8.0 + Jest), wire firebase.json for the four-emulator suite (auth/firestore/functions/storage), add cloud_functions: ^6.2.0 to pubspec, and introduce the USE_FIREBASE_EMULATOR compile-time flag — unblocking every Wave 1+ callable.

## What Was Built

### Task 1 — Cloud Functions codebase scaffold (commit `ca0f36e`)

Created the entire `functions/` workspace from scratch:

- **`functions/package.json`** — Node 20 engine, pinned versions (`firebase-functions@^7.2.5`, `firebase-admin@^13.8.0`, `jest@^29.7.0`, `ts-jest@^29.1.2`, `typescript@^5.3.3`, `firebase-functions-test@^3.4.1`, `@firebase/rules-unit-testing@^5.0.0`); scripts: `build`, `serve`, `deploy`, `test`, `test:coverage`.
- **`functions/tsconfig.json`** — CommonJS, ES2020, strict mode, source maps, `outDir: lib`.
- **`functions/jest.config.js`** — `ts-jest` preset, Node test environment, 70% coverage threshold across branches/functions/lines/statements, 30s timeout.
- **`functions/.eslintrc.js`** — minimal single-quote rule (matches Firebase Functions sample).
- **`functions/.gitignore`** — excludes `lib/`, `node_modules/`, `coverage/`, `.env`.
- **`functions/src/index.ts`** — entry point: `setGlobalOptions({ region: 'us-central1' })` + import side-effect for `./admin`. Wave 1+ callable exports stubbed in comments.
- **`functions/src/admin.ts`** — guarded singleton: `if (!getApps().length) initializeApp()`.
- **`functions/test/setup.ts`** — sets `FIRESTORE_EMULATOR_HOST=127.0.0.1:8080`, `FIREBASE_STORAGE_EMULATOR_HOST=127.0.0.1:9199`, `FUNCTIONS_EMULATOR=true`, `GCLOUD_PROJECT=rihla-safar-test`, `FIREBASE_AUTH_EMULATOR_HOST=127.0.0.1:9099` BEFORE any import (per RESEARCH Code Example 3).
- **`functions/test/fixtures.ts`** — `seedGroupWithEvent()` and `clearFirestore()` helpers for Wave 1+ integration tests.
- **`functions/test/helpers/emulator-setup.ts`** — thin re-export façade.
- **Root `.gitignore`** — appended `functions/lib/`, `functions/node_modules/`, `functions/coverage/`.

#### Install + build output (truncated)

```
$ npm install --prefix functions
added 556 packages, and audited 557 packages in 3m

$ npm run build --prefix functions
> tsc
(exit 0)

$ ls functions/lib/
admin.js  admin.js.map  index.js  index.js.map

$ npm test --prefix functions -- --passWithNoTests
No tests found, exiting with code 0
```

### Task 2 — firebase.json + pubspec + config flag (commit `1ed213a`)

- **`firebase.json`** — added top-level `functions` array with `source: "functions"`, `codebase: "default"`, `predeploy: ["npm --prefix \"$RESOURCE_DIR\" run build"]`. Added `functions: { port: 5001 }`, `storage: { port: 9199 }` to emulator block, plus `singleProjectMode: true`.
- **`pubspec.yaml`** — inserted `cloud_functions: ^6.2.0` alphabetically inside the Firebase cluster (between `cloud_firestore` and `firebase_auth`). `flutter pub get` resolved version `6.2.0` cleanly.
- **`config.json.example`** — newly created; includes `USE_FIREBASE_EMULATOR: false` plus the existing Supabase keys for backward compatibility (the real `config.json` was intentionally not touched).

### Task 3 — Blaze + GCP API checkpoint (advisory)

Per the executor prompt, this checkpoint is **advisory for plan 38-01** (the actual hard gate lives in plan 38-04 before deploy). All scaffold tasks are complete and the deployment-blocking verification can be done before Wave 3.

**Awaiting user confirmation before plan 38-04 deploy:**

1. Open https://console.firebase.google.com/project/rihla-safar/usage/details and confirm plan = **Blaze - Pay as you go** (upgrade from Spark if needed).
2. Open https://console.cloud.google.com/apis/library/cloudfunctions.googleapis.com?project=rihla-safar — confirm Cloud Functions API ENABLED.
3. Open https://console.cloud.google.com/apis/library/cloudbuild.googleapis.com?project=rihla-safar — confirm Cloud Build API ENABLED.
4. Open https://console.cloud.google.com/apis/library/artifactregistry.googleapis.com?project=rihla-safar — confirm Artifact Registry API ENABLED.

Reply "blaze confirmed" before plan 38-04 runs `firebase deploy --only functions`.

## Verification Results

| Check | Command | Result |
|---|---|---|
| Functions build | `npm run build --prefix functions` | exit 0; `lib/index.js` + `lib/admin.js` produced |
| Functions tests | `npm test --prefix functions -- --passWithNoTests` | exit 0; "No tests found" |
| Flutter deps resolve | `flutter pub get` | exit 0; cloud_functions 6.2.0 in pubspec.lock |
| firebase.json shape | `grep "functions"` and `port": 5001/9199` | confirmed present |
| pubspec contains dep | `grep "cloud_functions: \^6.2.0"` | confirmed present |
| config.json.example flag | `grep "USE_FIREBASE_EMULATOR"` | confirmed `false` |
| Blaze plan check (Task 3) | Manual console review | **awaiting user confirmation** (advisory for plan 01) |

## Acceptance Criteria

- [x] `functions/package.json` contains `firebase-functions@^7.2.5` AND `firebase-admin@^13.8.0`
- [x] `functions/package.json` contains `firebase-functions-test@^3.4.1` AND `@firebase/rules-unit-testing@^5.0.0`
- [x] `functions/tsconfig.json` contains `"strict": true` and `"outDir": "lib"`
- [x] `functions/jest.config.js` contains `ts-jest` and `testMatch` and 70% coverage floor
- [x] `functions/src/index.ts` contains `setGlobalOptions({ region: 'us-central1' })`
- [x] `functions/src/admin.ts` contains `if (!getApps().length)` and `initializeApp()`
- [x] `functions/lib/` exists after build with compiled `index.js`, `admin.js`
- [x] `npm test --prefix functions -- --passWithNoTests` exits 0
- [x] Root `.gitignore` excludes `functions/lib/`, `functions/node_modules/`, `functions/coverage/`
- [x] `firebase.json` contains `functions` source block (`"source": "functions"`, `"codebase": "default"`)
- [x] `firebase.json` emulators include `functions: 5001` AND `storage: 9199`
- [x] `firebase.json` contains `"singleProjectMode": true`
- [x] `pubspec.yaml` contains `cloud_functions: ^6.2.0`
- [x] `config.json.example` contains `"USE_FIREBASE_EMULATOR": false`
- [x] `flutter pub get` exits 0; resolves cloud_functions 6.2.0
- [ ] Blaze plan confirmed via Task 3 checkpoint — **advisory; awaits user reply before plan 38-04 deploy**

## Deviations from Plan

### Auto-fixed Issues

None. Plan 38-01 executed exactly as written, with one procedural note: the Blaze plan checkpoint (Task 3) is left as an awaiting item rather than blocking, per the executor prompt's `<checkpoint_handling>` instruction stating that the deploy gate properly belongs to plan 38-04.

### Notes / Out-of-Scope Observations

- `flutter analyze` reports 1033 issues with 9+ errors — but every error originates from leftover untracked files (`lib/core/config/supabase_config.dart`, `lib/core/services/cache_service.dart`, etc.) that are pre-existing and unrelated to this plan. They were present in the worktree before plan execution and are not within plan 38-01's scope. Logged here for awareness; no fix attempted (deviation Rule scope boundary).
- Node 25.2.1 is installed locally; functions/package.json declares `"engines": { "node": "20" }`. `npm install` printed an `EBADENGINE` warning but completed successfully. Cloud Build will use Node 20 at deploy time, so this is not a runtime concern.

## Authentication Gates

None encountered during execution. The Blaze + GCP API checkpoint (Task 3) is a manual verification gate that lives outside plan 38-01's automated scope per the prompt.

## Commits

| Task | Hash | Message |
|---|---|---|
| 1 | `ca0f36e` | feat(38-01): bootstrap Cloud Functions TypeScript codebase |
| 2 | `1ed213a` | feat(38-01): wire functions+storage emulators, add cloud_functions, USE_FIREBASE_EMULATOR flag |

## Next Wave

**Wave 1** (plan 38-02) — Membership + signing helpers + first callable (`getSignedUploadUrl`). Now unblocked: callables can import from `firebase-functions/v2/https`, helpers can use the seeded admin singleton, tests can rely on the emulator harness in `test/setup.ts`.

## Self-Check: PASSED

Files verified:
- FOUND: functions/package.json
- FOUND: functions/tsconfig.json
- FOUND: functions/jest.config.js
- FOUND: functions/.eslintrc.js
- FOUND: functions/.gitignore
- FOUND: functions/src/index.ts
- FOUND: functions/src/admin.ts
- FOUND: functions/test/setup.ts
- FOUND: functions/test/fixtures.ts
- FOUND: functions/test/helpers/emulator-setup.ts
- FOUND: functions/lib/index.js
- FOUND: functions/lib/admin.js
- FOUND: config.json.example

Commits verified:
- FOUND: ca0f36e
- FOUND: 1ed213a
