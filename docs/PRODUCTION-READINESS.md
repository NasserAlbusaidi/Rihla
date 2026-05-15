# Production Readiness

Last verified: 2026-05-15

This checklist tracks the remaining launch gates for the Firebase project
`rihla-safar` and the mobile apps. Treat checked items as verified from the
commands listed here, not as permanent guarantees.

Run the consolidated read-only audit:

```bash
RIHLA_CONFIRM_APP_CHECK_READY=yes bash tool/check_release_readiness.sh
```

It should fail until Firebase backend/Hosting deployment, App Check setup, and
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
  - Output: `build/app/outputs/bundle/release/app-release.aab` at 54.2 MB
- [x] Static analysis is clean with infos enabled as non-fatal.
  - Command: `flutter analyze --no-fatal-infos`
- [x] Non-golden Flutter test suite passes with raw coverage over the temporary 70% gate.
  - Command: `flutter test --coverage test/architecture test/core test/features test/helpers test/integration test/shared test/unit test/widget_test.dart`
  - Result: 1028 passed, 3 skipped
  - Coverage: 74.0% raw line coverage from `coverage/lcov.info` (9866 of 13333 lines)
  - Note: CI and `tool/check_release_readiness.sh` currently enforce 70%; ratchet back to 80% after the auth/profile/settings test backlog is closed.
- [x] Navigation smoke tests cover the shippable route tree and invite links.
  - Command: `flutter test test/unit/app_router_test.dart test/helpers/navigation_test.dart test/unit/deep_link_service_test.dart test/unit/auth_link_hosting_files_test.dart test/features/activity/activity_feed_screen_test.dart test/features/groups/qr_invite_sheet_test.dart test/features/groups/group_detail_navigation_test.dart test/features/events/event_command_center_test.dart test/features/ledger/ledger_screen_overflow_test.dart`
  - Result: 61 passed
  - Coverage: splash redirects to `/home`, `/join/:code` stays addressable on fresh installs, onboarding is not in the production route tree, invite links use Firebase Hosting, normalize legacy lowercase codes before sharing, and accept browser-normalized trailing slashes, account-recovery browser fallback links use the `rihla://auth-link` app scheme, both Firebase default Hosting domains are checked by the production-state verifier, production code avoids imperative `Navigator.push`, `state.extra`, and named GoRouter calls, GroupDetail create-event/settle-up/settings/activity entry points route to expected destinations, event hub module cards, expense hero, and settings button route to ledger/activity/settings, Ledger settings/search/add/settle-up/edit entry points route to expected destinations, and direct-entry nested back navigation covers group settings, group settle-up, group activity, create-event, typed create-event, event hub, event activity, ledger, activity, settings, add, edit, and settle-up.
- [x] Account-recovery success routes are restoration-safe.
  - Command: `flutter test test/features/auth/link_email_screen_test.dart test/features/auth/recover_screen_test.dart`
  - Result: 12 passed
  - Coverage: link-email and restore flows carry the normalized email in the route query instead of GoRouter `extra`; direct `/profile/link-email` and `/recover` entry back buttons route to `/profile` and `/home`; `rg -n "state\\.extra|extra: email" lib test` has no matches.
- [x] Direct route close/back controls are guarded.
  - Command: `flutter test test/features/groups/create_join_group_test.dart --plain-name "direct create close routes home when there is no stack to pop"`, `flutter test test/features/groups/create_join_group_test.dart --plain-name "direct invite close routes home when there is no stack to pop"`, `flutter test test/features/profile/profile_screen_test.dart --plain-name "direct profile back button routes home when showBack is true"`, and `flutter test test/features/group_detail_screen_test.dart --plain-name "direct entry back button routes home when no stack exists"`
  - Result: 4 focused tests passed
  - Coverage: `/create-group`, `/join/:code`, `/profile`, and `/group/:gid` no longer pop or no-op on the last GoRouter page when opened as direct entry routes. Full-suite route-backed tests also cover direct-entry back controls for group settings, group activity, event hub, event activity, event settings, and ledger.
- [x] Recovery completion drains pending writes before replacing the anonymous UID.
  - Command: `flutter test test/unit/auth_email_link_bootstrap_test.dart test/unit/auth_recovery_service_test.dart`
  - Result: 26 passed
  - Coverage: recovery deep links dispatch by persisted operation kind from warm link streams, cold-start initial URLs, and hosted-page custom-scheme fallbacks; `completeRecovery()` waits for pending Firestore writes with a timeout, signs out the transient anonymous UID, then signs in with the email link.
- [x] Local macOS golden tests pass.
  - Command: `flutter test test/goldens/ --tags golden`
  - Result: 8 passed
- [x] Firebase emulator/rules tests pass under Java 21.
  - Command: `npm --prefix functions run test:emulator`
  - Result: 3 suites passed, 80 tests passed
  - Note: raw `npm --prefix functions test` expects the Firestore emulator to already be running; use `test:emulator` for the normal local/CI backend gate.
  - Note: Homebrew Java 21 may be installed even when `/usr/libexec/java_home -v 21` still resolves to Java 17; prefer the explicit `brew --prefix openjdk@21` path above.
- [x] Firestore production database exists for `rihla-safar`.
  - Database: `(default)`, Native mode, location `nam5`
- [x] Some Firebase Hosting public files are already live.
  - `https://rihla-safar.web.app/.well-known/assetlinks.json` contains the Android package `com.safar.safar`.
  - The hosted auth continue pages are reachable, but the deployed copies are stale and still tracked as a release blocker below.
- [x] Production Functions dependency audit has no known vulnerabilities at low-or-higher severity.
  - Command: `npm --prefix functions audit --omit=dev --audit-level=low`
- [x] App Check client and callable enforcement are wired in the repo.
  - Evidence: `lib/core/config/firebase_config.dart` activates debug providers outside release builds and Play Integrity/App Attest with DeviceCheck fallback for release builds.
  - Evidence: `functions/src/callables/joinGroupByInviteCode.ts` sets `enforceAppCheck: true`.
  - Evidence: `tool/check_release_readiness.sh` fails if callable App Check enforcement is removed.
  - Evidence: `tool/check_release_readiness.sh` also requires `RIHLA_CONFIRM_APP_CHECK_READY=yes` so Console enrolment stays an explicit release assertion.
- [x] Join callable display-name validation matches the Firestore rules contract.
  - Evidence: `functions/src/callables/joinGroupByInviteCode.ts` rejects over-32-character names and control characters before Admin SDK writes.
  - Evidence: `functions/test/callables/joinGroupByInviteCode.test.ts` covers missing-name fallback, over-length rejection, and control-character rejection.
- [x] Join callable repairs and rejects malformed membership edge cases.
  - Evidence: `joinGroupByInviteCode` creates a missing `groups/{groupId}/members/{uid}` doc when `memberIds` already contains the caller.
  - Evidence: `joinGroupByInviteCode` rejects malformed `memberIds` before writing a member document.
- [x] Join screen preserves server rate-limit feedback.
  - Evidence: `test/features/groups/create_join_group_test.dart` covers `resource-exhausted` failures showing `Too many attempts. Try again later.` instead of the generic connection error.
- [x] Profile display-name edits use the same Firestore-compatible validation.
  - Evidence: `lib/features/settings/widgets/edit_name_bottom_sheet.dart` uses `validateDisplayName()` and `normalizeDisplayName()`.
  - Evidence: `test/features/profile/profile_screen_test.dart` rejects a 33-character profile name and leaves the persisted setting unchanged.
- [x] Device-name persistence cannot carry invalid names into later backend writes.
  - Evidence: `SettingsNotifier.setDeviceName()` rejects invalid non-empty names, normalizes valid names before saving, and avoids propagating empty names to Firestore.
  - Evidence: `SettingsService.loadSettings()` drops invalid legacy persisted names instead of surfacing them to create/join flows.

## Blockers

- [ ] Firebase production-state audit fails.
  - Command: `bash tool/check_firebase_prod_state.sh rihla-safar`
  - Latest result (2026-05-15): 9 issues.
- [ ] Firebase Functions are not deployed in production.
  - Evidence: `bash tool/check_firebase_prod_state.sh rihla-safar` reports the missing deployed Function: `joinGroupByInviteCode`.
  - Local exports expected in production: `joinGroupByInviteCode`.
  - Deploy blocker: `npx --yes firebase-tools@15.8.0 deploy --project rihla-safar --only functions --dry-run` requires the project to upgrade to Blaze before `cloudbuild.googleapis.com` and `artifactregistry.googleapis.com` can be enabled.
  - Currently enabled related APIs: `cloudfunctions.googleapis.com`, `firebase.googleapis.com`, `firebaserules.googleapis.com`, `firestore.googleapis.com`.
- [ ] Group join callable deployed and clients route through it.
  - Local code now routes joins through `joinGroupByInviteCode`; production still needs the callable and Firestore rules deployed together.
- [ ] Firestore production rules are stale and weaker than `security/firestore.rules`.
  - The deployed rules still allow direct invite-code reads and older join/update patterns that the local callable-based rules remove.
- [ ] Firestore production indexes do not match `firestore.indexes.json`.
  - The remote database still has an extra `gear_items` collection-group index from removed module work; the confirmed deploy command uses `--force` so production converges to the repo index config instead of preserving stale removed-module indexes.
- [ ] Firebase Hosting invite/auth link files deployed.
  - Local code now generates `https://rihla-safar.web.app/join/<code>` invite links and depends on Hosting rewrites plus App/Asset Link files being live on both Firebase default domains.
  - Latest production-state check: `/join/ABC123` returns 404, the live Apple App Site Association file does not contain `/join/*`, and the live auth continue page does not contain `rihla://auth-link` on both `rihla-safar.web.app` and `rihla-safar.firebaseapp.com`.
- [ ] Firebase App Check Console enrolment is not verified.
  - Local code is ready, but production release still requires the Android app to be enrolled with Play Integrity and the iOS app to be enrolled with App Attest/DeviceCheck in Firebase Console before deploying the enforced callable.
  - Current mitigation: callers must be Firebase-authenticated and failed invite lookups are rate-limited through server-only `joinAttempts/{uid}` documents.
- [ ] Real-device QA is not complete.
  - Runbook: `docs/REAL-DEVICE-QA.md`
  - Gate command: `bash tool/check_real_device_qa_gate.sh`
  - Latest gate result (2026-05-15): no physical iOS device and no physical Android device detected; only an iPhone 17 Pro Max simulator was visible; RD-01 through RD-08 are still missing recorded iOS/Android pass results and concrete evidence.
  - Required matrix:
    - iOS: create group, join group, delete group.
    - Android: create group, join group, delete group.
    - Two devices in one group: one user pays an expense and each device shows the correct payer/ower identity.
    - iOS and Android expense entry keyboards expose decimal input for OMR amounts.
    - Offline and reconnect: create/read flows recover without false permanent offline state.
    - Notification opt-in and opt-out: token is written on enable and removed on disable.
- [ ] Android release workflow external confirmations are not set.
  - `.github/workflows/release_android.yml` now refuses to upload unless `RIHLA_BACKEND_RELEASE_READY`, `RIHLA_APP_CHECK_READY`, and `RIHLA_REAL_DEVICE_QA_READY` repository variables are all set to `yes`.
  - Leave these unset until the production-state audit, App Check Console enrolment, and physical-device QA matrix pass.

## External Actions

These actions cannot be completed safely from this repo without an explicit
Firebase Console or billing decision:

1. Upgrade `rihla-safar` to Blaze:
   - Console: `https://console.firebase.google.com/project/rihla-safar/usage/details`
   - Needed so Cloud Build and Artifact Registry APIs can be enabled for
     Cloud Functions deployment.
2. Deploy backend and Hosting artifacts from this repo:
   ```bash
   RIHLA_CONFIRM_FIREBASE_DEPLOY=yes RIHLA_CONFIRM_APP_CHECK_READY=yes bash tool/deploy_firebase_backend.sh rihla-safar
   ```
3. Enroll Firebase App Check for the Android and iOS apps in Firebase Console
   before deploying the enforced `joinGroupByInviteCode` callable.
4. Re-run the full audit:
   ```bash
   RIHLA_CONFIRM_APP_CHECK_READY=yes bash tool/check_release_readiness.sh
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

The command should fail until the join callable is live.

Run this after the Firebase project setup blockers are cleared:

```bash
RIHLA_CONFIRM_FIREBASE_DEPLOY=yes RIHLA_CONFIRM_APP_CHECK_READY=yes bash tool/deploy_firebase_backend.sh rihla-safar
```

The script installs Functions dependencies from the lockfile, audits production
dependencies at low severity, builds Functions, deploys Firestore rules/indexes,
Functions, and Hosting, then runs `tool/check_firebase_prod_state.sh`.

Equivalent manual deploy command:

```bash
npx --yes firebase-tools@15.8.0 deploy \
  --force \
  --project rihla-safar \
  --only firestore:rules,firestore:indexes,functions,hosting
```

Then confirm production state:

```bash
npx --yes firebase-tools@15.8.0 functions:list --project rihla-safar
npx --yes firebase-tools@15.8.0 firestore:indexes --project rihla-safar --database '(default)'
```

For Firestore rules, fetch the active release through the Firebase Rules API and
diff it against `security/firestore.rules`.
