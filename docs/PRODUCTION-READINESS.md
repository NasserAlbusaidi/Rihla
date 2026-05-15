# Production Readiness

Last verified: 2026-05-15

This checklist tracks the remaining launch gates for the Firebase project
`rihla-safar` and the mobile apps. Treat checked items as verified from the
commands listed here, not as permanent guarantees.

Run the consolidated read-only audit:

```bash
RIHLA_CONFIRM_APP_CHECK_READY=yes bash tool/check_release_readiness.sh
```

Backend deployment, App Check Console enrolment, and the Firebase production-
state audit are complete as of 2026-05-15. v1.2 launches Android-only on
Google Play; iOS is soft-deferred to follow within weeks of Android
Production. The remaining release gates are Android-only physical-device QA
(`docs/REAL-DEVICE-QA.md` with `RIHLA_SKIP_IOS_QA=yes`) and the three CI
release-confirmation repo variables. The consolidated audit will continue to
fail until those two gates are recorded as passing.

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
- [x] Firebase project upgraded to Blaze plan.
  - Evidence: Cloud Functions are deployed (see below), which requires `cloudbuild.googleapis.com` and `artifactregistry.googleapis.com` — both gated on Blaze.
- [x] Firebase production-state audit passes.
  - Command: `bash tool/check_firebase_prod_state.sh rihla-safar`
  - Latest result (2026-05-15): 12 checks PASS, exit 0.
- [x] Firebase Functions are deployed in production.
  - Evidence: production-state audit confirms expected functions are deployed (`joinGroupByInviteCode`).
- [x] Firestore production rules match `security/firestore.rules`.
  - Evidence: production-state audit diffs the active ruleset against the repo and reports PASS.
- [x] Firestore production indexes match `firestore.indexes.json`.
  - Evidence: production-state audit confirms index set matches the repo config; legacy `gear_items` index removed.
- [x] Firebase Hosting invite/auth link files are deployed on both default domains.
  - Evidence: production-state audit verifies `/join/<code>` invite fallback, Apple App Site Association `/join/*` entries, Digital Asset Links matching `com.safar.safar`, and the auth continue page containing `rihla://auth-link` on both `rihla-safar.web.app` and `rihla-safar.firebaseapp.com`.
- [x] Firebase App Check Console enrolment is verified.
  - Evidence: Android app enrolled with Play Integrity; iOS app enrolled with App Attest (with DeviceCheck fallback). Enforced `joinGroupByInviteCode` callable is live in production.
  - Re-verify path: Firebase Console → App Check → confirm enforcement is ON for Cloud Functions and that both platform apps show "Enforced".

## Blockers

- [ ] Real-device QA is not complete (Android-only for v1.2).
  - Runbook: `docs/REAL-DEVICE-QA.md`
  - Gate command (v1.2 Android-only):
    ```bash
    RIHLA_SKIP_IOS_QA=yes bash tool/check_real_device_qa_gate.sh
    ```
  - Latest gate result (2026-05-15): no physical Android device detected; matrix iOS cells filled with `Deferred — v1.2 Android-only`; Android cells and evidence still empty.
  - Required Android matrix (RD-01..08):
    - Create group, join group by invite code, delete group.
    - Two-device ledger identity (two Android devices in one group; one pays an expense and each device shows the correct payer/ower identity).
    - Android expense entry keyboard exposes decimal input for OMR amounts.
    - Offline and reconnect: create/read flows recover without false permanent offline state.
    - Notification opt-in and opt-out: token is written on enable and removed on disable.
  - iOS re-activation: when iOS ships, unset `RIHLA_SKIP_IOS_QA` and replace `Deferred ...` cells with `Pass ...` and concrete iOS evidence.
- [ ] Android release workflow external confirmations are not set.
  - `.github/workflows/release_android.yml` now refuses to upload unless `RIHLA_BACKEND_RELEASE_READY`, `RIHLA_APP_CHECK_READY`, and `RIHLA_REAL_DEVICE_QA_READY` repository variables are all set to `yes`.
  - Leave these unset until the production-state audit, App Check Console enrolment, and physical-device QA matrix pass.

## External Actions

These actions cannot be completed from this repo and remain before release:

1. Connect a physical Android device (or two for RD-04), then run:
   ```bash
   RIHLA_SKIP_IOS_QA=yes bash tool/check_real_device_qa_gate.sh
   ```
   If the gate passes, complete the `docs/REAL-DEVICE-QA.md` matrix
   (RD-01..08) with concrete Android evidence. iOS cells stay marked
   `Deferred — v1.2 Android-only` until iOS ships.
2. After RD-QA is recorded and the backend re-audit still passes, set the
   three Android release-workflow repository variables to `yes`:
   `RIHLA_BACKEND_RELEASE_READY`, `RIHLA_APP_CHECK_READY`,
   `RIHLA_REAL_DEVICE_QA_READY`. The release workflow refuses to upload
   to Play until all three are set.
3. Re-run the full audit before promoting the Play Store track:
   ```bash
   RIHLA_CONFIRM_APP_CHECK_READY=yes bash tool/check_release_readiness.sh
   ```

Historical external actions completed on or before 2026-05-15:

- Upgraded `rihla-safar` to Blaze plan.
- Deployed Firestore rules, indexes, Functions, and Hosting via
  `tool/deploy_firebase_backend.sh`.
- Enrolled Firebase App Check (Play Integrity for Android, App Attest /
  DeviceCheck fallback for iOS).
- Re-ran `bash tool/check_firebase_prod_state.sh rihla-safar` — 12 checks
  PASS.

## Deployment Commands

The initial production deploy is complete. Use these commands for subsequent
backend changes.

Before deploying, run the read-only production-state check:

```bash
bash tool/check_firebase_prod_state.sh rihla-safar
```

The command should report 12 PASS lines and exit 0 against the currently
deployed backend. If it fails, the deployed state has drifted from the repo
and needs a redeploy.

Redeploy backend after a rules / indexes / Functions / Hosting change:

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
