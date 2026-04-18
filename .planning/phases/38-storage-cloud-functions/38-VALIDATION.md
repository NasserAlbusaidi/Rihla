---
phase: 38
slug: storage-cloud-functions
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-04-18
---

# Phase 38 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.
> See `38-RESEARCH.md` §"Validation Architecture" for the full source of truth.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework (Functions)** | Jest 29 + ts-jest + firebase-functions-test 3.4.1 + @firebase/rules-unit-testing 5.0.0 |
| **Framework (Flutter)** | flutter_test + mocktail + fake_cloud_firestore (existing) |
| **Config files** | `functions/jest.config.js` (new, Wave 0), `test/dart_test.yaml` (existing) |
| **Quick run command** | `npm test --prefix functions` OR `flutter test test/<narrow>` |
| **Full suite command** | `firebase emulators:exec --only auth,firestore,functions,storage "npm test --prefix functions"` then `flutter test --coverage` |
| **Estimated runtime** | ~45s functions, ~60s flutter |

---

## Sampling Rate

- **After every task commit:** Run the narrowest applicable quick command (single `npx jest <file>` or `flutter test <file>`)
- **After every plan wave:** Run the full suite for the side that changed (functions or flutter)
- **Before `/gsd-verify-work`:** Full suite must be green on both sides
- **Max feedback latency:** ~60 seconds per wave

---

## Per-Task Verification Map

> Populated by the planner in Wave 0 and refined as tasks are created.
> Canonical REQ→Test matrix lives in `38-RESEARCH.md` §"Phase Requirements → Test Map".

| Task ID | Plan | Wave | Requirement | Threat Ref | Secure Behavior | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|------------|-----------------|-----------|-------------------|-------------|--------|
| 38-01-01 | 01 | 0 | INFRA-01 | T-38-01 | Functions codebase scaffolded with Jest + emulator config | unit | `npm test --prefix functions -- --listTests` | ❌ Wave 0 | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

- [ ] `functions/package.json` — Node 20, firebase-functions@7.2.5, firebase-admin@13.8.0, typescript@5, jest@29, ts-jest, firebase-functions-test@3.4.1, @firebase/rules-unit-testing@5.0.0
- [ ] `functions/tsconfig.json` — target ES2020, module commonjs, strict true
- [ ] `functions/jest.config.js` — ts-jest preset, `testMatch: ['<rootDir>/test/**/*.test.ts']`, coverage 70%+ threshold
- [ ] `functions/src/index.ts` — `setGlobalOptions({ region: 'us-central1' })` stub
- [ ] `functions/test/helpers/emulator-setup.ts` — shared fixture: admin init against emulator hosts
- [ ] `firebase.json` — add `emulators.functions` (5001) and `emulators.storage` (9199); add `functions: { source: 'functions', runtime: 'nodejs20' }`
- [ ] `pubspec.yaml` — add `cloud_functions: ^6.2.0`
- [ ] Stub test files for every INFRA-01 entry in the REQ→Test table (14 entries) so Wave 1+ tasks can fill them in TDD style

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| Production deploy succeeds (`firebase deploy --only functions,storage,firestore:rules`) | INFRA-01 | Requires Blaze plan + real project credentials; cannot run in CI without exposing the service-account key | Run from local dev machine after wave completion; verify `gcloud functions list --regions=us-central1` shows 4 callables |
| Old client (pre-38 app version) fails uploads post-cutover | D-09 | Requires side-by-side install of old + new APK | Install v2.3 APK after v2.4 deploy; attempt document upload; confirm surfaced error matches "app out of date" copy |

---

## Validation Sign-Off

- [ ] All tasks have `<automated>` verify or Wave 0 dependencies
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers all MISSING references (functions/ scaffold, jest config, emulator config, cloud_functions package)
- [ ] No watch-mode flags (`--watch`, `--watchAll`)
- [ ] Feedback latency < 60s for any task
- [ ] `nyquist_compliant: true` set in frontmatter after planner populates the per-task table

**Approval:** pending
