# Production Readiness

Last verified: 2026-05-11

This checklist tracks the remaining launch gates for the Firebase project
`rihla-safar` and the mobile apps. Treat checked items as verified from the
commands listed here, not as permanent guarantees.

Run the consolidated read-only audit:

```bash
bash tool/check_release_readiness.sh
```

It should fail until Firebase Storage, Firebase Functions deployment, and
physical-device QA are complete.

GitHub also runs `.github/workflows/readiness_check.yml` on `main` pushes and
pull requests. That workflow covers the local non-deploy gates only; it does not
replace the Firebase production-state check or physical-device QA.

Check the current `main` readiness workflow in GitHub Actions before release;
this document intentionally does not pin a run ID because every doc-only push
starts a new run.

## Verified

- [x] Android release bundle builds locally.
  - Command: `flutter build appbundle --release --obfuscate --split-debug-info=./build/app/outputs/symbols --dart-define-from-file=config.json --android-skip-build-dependency-validation`
  - Output: `build/app/outputs/bundle/release/app-release.aab` at 52.7 MB
- [x] Static analysis is clean with infos enabled as non-fatal.
  - Command: `flutter analyze --no-fatal-infos`
- [x] Non-golden Flutter test suite passes with raw coverage over 80%.
  - Command: `flutter test --coverage test/architecture test/core test/features test/helpers test/integration test/shared test/unit test/widget_test.dart`
  - Result: 829 passed, 3 skipped
  - Coverage: 80.9% raw line coverage from `coverage/lcov.info`
- [x] Local macOS golden tests pass.
  - Command: `flutter test test/goldens/ --tags golden`
  - Result: 8 passed
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
  - Evidence: `bash tool/check_firebase_prod_state.sh rihla-safar` reports these missing deployed Functions: `getSignedUploadUrl`, `deleteStorageObject`, `joinGroupByInviteCode`, `listDocumentsWithUrls`, `listMemoriesWithUrls`.
  - Local exports expected in production: `getSignedUploadUrl`, `deleteStorageObject`, `joinGroupByInviteCode`, `listDocumentsWithUrls`, `listMemoriesWithUrls`.
  - Deploy blocker: `npx --yes firebase-tools@15.8.0 deploy --project rihla-safar --only functions --dry-run` requires the project to upgrade to Blaze before `cloudbuild.googleapis.com` and `artifactregistry.googleapis.com` can be enabled.
  - Currently enabled related APIs: `cloudfunctions.googleapis.com`, `firebase.googleapis.com`, `firebaserules.googleapis.com`, `firebasestorage.googleapis.com`, `firestore.googleapis.com`.
- [ ] Firebase Storage is not initialized in production.
  - Evidence: `npx --yes firebase-tools@15.8.0 deploy --project rihla-safar --only storage:rules --dry-run` reports that Firebase Storage has not been set up.
  - Required action: open Firebase Console for `rihla-safar`, go to Storage, click **Get Started**, then deploy `security/storage.rules`.
- [ ] Storage production rules are not deployed.
  - Evidence: `bash tool/check_firebase_prod_state.sh rihla-safar` reports `No active Storage rules release found`.
  - Blocked by Firebase Storage initialization.
- [ ] Real-device QA is not complete.
  - Runbook: `docs/REAL-DEVICE-QA.md`
  - Gate command: `bash tool/check_real_device_qa_gate.sh`
  - Latest gate result: no physical iOS device and no physical Android device detected; only iPhone 17 Pro and iPhone 17 Pro Max simulators were visible.
  - Required matrix:
    - iOS: create group, join group, delete group.
    - Android: create group, join group, delete group.
    - Two devices in one group: one user pays an expense and each device shows the correct payer/ower identity.
    - iOS and Android expense entry keyboards expose decimal input for OMR amounts.
    - Offline and reconnect: create/read flows recover without false permanent offline state.
    - Notification opt-in and opt-out: token is written on enable and removed on disable.

## External Actions

These actions cannot be completed safely from this repo without an explicit
Firebase Console or billing decision:

1. Upgrade `rihla-safar` to Blaze:
   - Console: `https://console.firebase.google.com/project/rihla-safar/usage/details`
   - Needed so Cloud Build and Artifact Registry APIs can be enabled for
     Cloud Functions deployment.
2. Initialize Firebase Storage:
   - Console: `https://console.firebase.google.com/project/rihla-safar/storage`
   - Click **Get Started** and finish the bucket setup.
3. Deploy backend artifacts from this repo:
   ```bash
   RIHLA_CONFIRM_FIREBASE_DEPLOY=yes bash tool/deploy_firebase_backend.sh rihla-safar
   ```
4. Re-run the full audit:
   ```bash
   bash tool/check_release_readiness.sh
   ```
5. Connect physical iOS and Android devices, then run:
   ```bash
   bash tool/check_real_device_qa_gate.sh
   ```
   If the gate passes, complete `docs/REAL-DEVICE-QA.md`.

## Deployment Commands

Before deploying, run the read-only production-state check:

```bash
bash tool/check_firebase_prod_state.sh rihla-safar
```

The command should fail until Storage rules and all expected Functions are live.

Run this after the Firebase project setup blockers are cleared:

```bash
RIHLA_CONFIRM_FIREBASE_DEPLOY=yes bash tool/deploy_firebase_backend.sh rihla-safar
```

The script installs Functions dependencies from the lockfile, audits production
dependencies at low severity, builds Functions, deploys Firestore rules/indexes,
Storage rules, and Functions, then runs `tool/check_firebase_prod_state.sh`.

Equivalent manual deploy command:

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
