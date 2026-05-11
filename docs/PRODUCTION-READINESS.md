# Production Readiness

Last verified: 2026-05-11

This checklist tracks the remaining launch gates for the Firebase project
`rihla-safar` and the mobile apps. Treat checked items as verified from the
commands listed here, not as permanent guarantees.

## Verified

- [x] Android release bundle builds locally.
  - Command: `flutter build appbundle --release --obfuscate --split-debug-info=./build/app/outputs/symbols --dart-define-from-file=config.json --android-skip-build-dependency-validation`
  - Output: `build/app/outputs/bundle/release/app-release.aab` at 52.7 MB
- [x] Static analysis is clean with infos enabled as non-fatal.
  - Command: `flutter analyze --no-fatal-infos`
- [x] Full Flutter test suite passes with raw coverage over 80%.
  - Command: `flutter test --coverage`
  - Result: 837 passed, 3 skipped
  - Coverage: 80.9% raw line coverage from `coverage/lcov.info`
- [x] Firebase emulator/rules tests pass under Java 21.
  - Command: `JAVA_HOME="$(brew --prefix openjdk@21)/libexec/openjdk.jdk/Contents/Home" npx --yes firebase-tools@15.8.0 emulators:exec --project rihla-safar-test --only auth,firestore,storage "npm --prefix functions test"`
- [x] Firestore production database exists for `rihla-safar`.
  - Database: `(default)`, Native mode, location `nam5`
- [x] Firestore production rules match `security/firestore.rules`, ignoring trailing blank lines.
- [x] Firestore production indexes match `firestore.indexes.json`, ignoring Firebase-added implicit `__name__` and density fields.
- [x] Production Functions dependency audit has no known vulnerabilities at low-or-higher severity.
  - Command: `npm --prefix functions audit --omit=dev --audit-level=low`

## Blockers

- [ ] Firebase Functions are not deployed in production.
  - Evidence: `npx --yes firebase-tools@15.8.0 functions:list --project rihla-safar` reports no functions.
  - Local exports expected in production: `getSignedUploadUrl`, `deleteStorageObject`, `joinGroupByInviteCode`, `listDocumentsWithUrls`, `listMemoriesWithUrls`.
  - Deploy blocker: `firebase deploy --project rihla-safar --only functions --dry-run` requires the project to upgrade to Blaze before Cloud Build and Artifact Registry APIs can be enabled.
- [ ] Firebase Storage is not initialized in production.
  - Evidence: `firebase deploy --project rihla-safar --only storage:rules --dry-run` reports that Firebase Storage has not been set up.
  - Required action: open Firebase Console for `rihla-safar`, go to Storage, click **Get Started**, then deploy `security/storage.rules`.
- [ ] Storage production rules are not deployed.
  - Blocked by Firebase Storage initialization.
- [ ] Real-device QA is not complete.
  - Runbook: `docs/REAL-DEVICE-QA.md`
  - Gate command: `bash tool/check_real_device_qa_gate.sh`
  - Required matrix:
    - iOS: create group, join group, delete group.
    - Android: create group, join group, delete group.
    - Two devices in one group: one user pays an expense and each device shows the correct payer/ower identity.
    - iOS and Android expense entry keyboards expose decimal input for OMR amounts.
    - Offline and reconnect: create/read flows recover without false permanent offline state.
    - Notification opt-in and opt-out: token is written on enable and removed on disable.

## Deployment Commands

Before deploying, run the read-only production-state check:

```bash
bash tool/check_firebase_prod_state.sh rihla-safar
```

The command should fail until Storage rules and all expected Functions are live.

Run these after the Firebase project setup blockers are cleared:

```bash
npx --yes firebase-tools@15.8.0 deploy \
  --project rihla-safar \
  --only firestore:rules,firestore:indexes,storage:rules,functions
```

Then confirm production state:

```bash
npx --yes firebase-tools@15.8.0 functions:list --project rihla-safar
npx --yes firebase-tools@15.8.0 firestore:indexes --project rihla-safar --database '(default)'
```

For Firestore rules, fetch the active release through the Firebase Rules API and
diff it against `security/firestore.rules`.
