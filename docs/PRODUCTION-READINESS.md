# Production Readiness

Last verified: 2026-05-20 (`codex/release-hardening-1-0`, PR #39)

This checklist tracks the remaining launch gates for the Firebase project
`rihla-safar` and the mobile apps. Treat checked items as verified from the
commands listed here, not as permanent guarantees.

Run the consolidated read-only audit:

```bash
RIHLA_SKIP_IOS_QA=yes RIHLA_CONFIRM_APP_CHECK_READY=yes bash tool/check_release_readiness.sh
```

For a full iOS + Android release, omit `RIHLA_SKIP_IOS_QA=yes` and replace the
iOS `Deferred ...` matrix cells with passing physical-device evidence.

Current branch status: local code gates pass for the hardening branch, but the
Firebase production-state audit does not yet pass for this branch because the
new Firestore rules and Functions have not been deployed. v1.2 launches
Android-only on Google Play; iOS is soft-deferred to follow within weeks of
Android Production. The remaining release gates are backend deploy/re-audit,
Android-only physical-device QA (`docs/REAL-DEVICE-QA.md` with
`RIHLA_SKIP_IOS_QA=yes`), and final commit-bound CI release-confirmation repo
variables. GitHub branch-protection governance is configured, but the
consolidated audit will continue to fail until the backend, device QA, and
release-variable gates are recorded as passing.

GitHub also runs `.github/workflows/readiness_check.yml` on `main` pushes and
pull requests. That workflow covers the local non-deploy gates only; it does not
replace the Firebase production-state check or physical-device QA.

Check the current `main` readiness workflow in GitHub Actions before release;
this document intentionally does not pin a run ID because every doc-only push
starts a new run.

## Verified

- [x] Android release bundle builds locally.
  - Command: `flutter build appbundle --release --obfuscate --split-debug-info=./build/app/outputs/symbols --dart-define-from-file=config.json --android-skip-build-dependency-validation`
  - Latest result (2026-05-19): `build/app/outputs/bundle/release/app-release.aab` at 58.5 MB
- [x] Static analysis is clean with infos enabled as non-fatal.
  - Command: `flutter analyze --no-fatal-infos`
- [x] Non-golden Flutter test suite passes with raw coverage over the 80% gate.
  - Command: `flutter test --coverage test/architecture test/core test/features test/helpers test/integration test/shared test/unit test/widget_test.dart`
  - Result: 1287 passed, 3 skipped (verified 2026-05-19 on `codex/release-hardening-1-0`)
  - Coverage: 80.6% raw line coverage
  - Note: CI and `tool/check_release_readiness.sh` both enforce 80% raw line coverage.
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
  - Latest result (2026-05-19): 5 suites passed, 105 tests passed
  - Note: raw `npm --prefix functions test` expects the Firestore emulator to already be running; use `test:emulator` for the normal local/CI backend gate.
  - Note: Homebrew Java 21 may be installed even when `/usr/libexec/java_home -v 21` still resolves to Java 17; prefer the explicit `brew --prefix openjdk@21` path above.
- [x] Firestore production database exists for `rihla-safar`.
  - Database: `(default)`, Native mode, location `nam5`
- [x] Firebase Hosting invite/auth link files are deployed on both default domains.
  - Evidence: production-state audit verifies `/join/<code>` invite fallback,
    Apple App Site Association `/join/*` entries, Digital Asset Links matching
    `com.safar.safar`, and the auth continue page containing
    `rihla://auth-link` on both `rihla-safar.web.app` and
    `rihla-safar.firebaseapp.com`.
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
- [x] Historical Firebase production-state audit passed for v1.2.0+15.
  - Command: `bash tool/check_firebase_prod_state.sh rihla-safar`
  - Historical result (2026-05-15): 12 checks PASS, exit 0. Re-verified 2026-05-16 after v1.2.0+15 functions deploy.
  - Current branch result (2026-05-20, PR #39): FAIL until the branch backend is deployed. Firestore indexes and Hosting passed; Firestore rules differ from production, and the deployed Functions list is missing `deleteAccount`.
- [x] Firebase Functions are deployed in production.
  - Evidence: production-state audit confirms expected functions are deployed (`joinGroupByInviteCode`, `cleanupAnonUidArtifacts`, account-deletion cascade, FCM token cleanup).
  - v1.2.0+15 changes: `joinGroupByInviteCode` now fans the joiner into existing event `participantIds` server-side (Gap 1); new `cleanupAnonUidArtifacts` callable scrubs FCM tokens + joinAttempts for the abandoned anon UID after email-link recovery (Gap 3, fire-and-forget — failures land in Sentry breadcrumbs).
  - v1.0 hardening branch: `cleanupAnonUidArtifacts` now requires a 15-minute one-time `recoveryCleanupIntents/{oldUid}` secret created by the retiring anon UID before sign-out, so recovered users cannot migrate arbitrary visible anon UIDs.
  - Backfill: `tool/backfill_join_event_sync.js` was run against `rihla-safar` on 2026-05-16 to reconcile historical event participant discrepancies.
- [x] Firestore production rules match `security/firestore.rules`.
  - Historical evidence: production-state audit diffed the active v1.2.0+15 ruleset against the repo and reported PASS.
  - Current branch note: production does not yet contain the new `recoveryCleanupIntents/{oldUid}` rules or the latest former-member display-name validation; this checkbox remains historical, not proof that the current branch is deployed.
- [x] Firestore production indexes match `firestore.indexes.json`.
  - Evidence: production-state audit confirms index set matches the repo config; legacy `gear_items` index removed.
- [x] Firebase App Check Console enrolment is verified.
  - Evidence: Android app enrolled with Play Integrity; iOS app enrolled with App Attest (with DeviceCheck fallback). Enforced `joinGroupByInviteCode` callable is live in production.
  - Re-verify path: Firebase Console → App Check → confirm enforcement is ON for Cloud Functions and that both platform apps show "Enforced".

## Blockers

- [ ] Firebase production state is not aligned with this branch yet.
  - Gate command:
    ```bash
    bash tool/check_firebase_prod_state.sh rihla-safar
    ```
  - Latest gate result (2026-05-20, PR #39): Firestore database, indexes, and both
    Hosting domains passed. Firestore rules failed because production lacks
    the current branch's `recoveryCleanupIntents/{oldUid}` rule block and
    latest display-name validation. Functions failed because production is
    missing `deleteAccount`.
  - Required action: deploy Firestore rules/indexes, Functions, and Hosting,
    then rerun the gate before setting `RIHLA_BACKEND_RELEASE_READY=yes`.
- [ ] Real-device QA is not complete (Android-only for v1.2).
  - Runbook: `docs/REAL-DEVICE-QA.md`
  - Gate command (v1.2 Android-only):
    ```bash
    RIHLA_SKIP_IOS_QA=yes bash tool/check_real_device_qa_gate.sh
    ```
  - Latest gate result (2026-05-20, PR #39): no physical Android device detected; matrix iOS cells filled with `Deferred — v1.2 Android-only`; Android cells and evidence still empty for RD-01..RD-09.
  - v1.2.0+15 carry-over: post-launch bugs found on +14 (group-detail back button, event settlement names, `currentUserIdProvider` reactivity, App Check on join callable, join-event-sync, anon-UID cleanup) are all resolved on `main` and documented in `docs/REAL-DEVICE-QA.md` § "Resolved on fix/post-launch-qa-v1.2".
  - Required Android matrix (RD-01..09):
    - Create group, join group by invite code, delete group.
    - Two-device ledger identity (two Android devices in one group; one pays an expense and each device shows the correct payer/ower identity).
    - Android expense entry keyboard exposes decimal input for OMR amounts.
    - Offline and reconnect: create/read flows recover without false permanent offline state.
    - Notification opt-in and opt-out: token is written on enable and removed on disable.
    - Arabic RTL golden path.
  - iOS re-activation: when iOS ships, unset `RIHLA_SKIP_IOS_QA` and replace `Deferred ...` cells with `Pass ...` and concrete iOS evidence.
- [ ] Android release workflow external confirmations are not set.
  - `.github/workflows/release_android.yml` now refuses to upload unless `RIHLA_BACKEND_RELEASE_READY`, `RIHLA_APP_CHECK_READY`, and `RIHLA_REAL_DEVICE_QA_READY` repository variables are all set to `yes`.
  - It also requires `RIHLA_RELEASE_APPROVED_SHA` to match the exact commit being uploaded, so stale `yes` variables from a previous release cannot authorize a newer tag.
  - Leave these unset until the production-state audit, App Check Console enrolment, and physical-device QA matrix pass for the target commit.
- [x] GitHub release governance is configured.
  - Gate command:
    ```bash
    bash tool/check_github_release_governance.sh
    ```
  - Latest gate result (2026-05-20): main branch protection is configured
    with the strict `readiness` status check and admin enforcement. The gate
    still fails intentionally until `RIHLA_BACKEND_RELEASE_READY=yes`,
    `RIHLA_REAL_DEVICE_QA_READY=yes`, and `RIHLA_RELEASE_APPROVED_SHA` match
    the final target commit after #40/#41 pass.

## External Actions

These actions cannot be completed from this repo and remain before release:

1. Connect a physical Android device (or two for RD-04), then run:
   ```bash
   RIHLA_SKIP_IOS_QA=yes bash tool/check_real_device_qa_gate.sh
   ```
   If the gate passes, complete the `docs/REAL-DEVICE-QA.md` matrix
   (RD-01..09) with concrete Android evidence. iOS cells stay marked
   `Deferred — v1.2 Android-only` until iOS ships.
2. After branch testing/review is accepted, deploy the branch backend from a
   clean worktree and verify production state:
   ```bash
   RIHLA_CONFIRM_FIREBASE_DEPLOY=yes RIHLA_CONFIRM_APP_CHECK_READY=yes bash tool/deploy_firebase_backend.sh rihla-safar
   bash tool/check_firebase_prod_state.sh rihla-safar
   ```
   Do not continue until the production-state check exits 0 for the target
   commit.
3. After RD-QA is recorded and the backend re-audit passes for the target
   commit, set the three Android release-workflow repository variables to
   `yes`:
   `RIHLA_BACKEND_RELEASE_READY`, `RIHLA_APP_CHECK_READY`,
   `RIHLA_REAL_DEVICE_QA_READY`.
4. Set `RIHLA_RELEASE_APPROVED_SHA` to the full commit SHA that will be tagged
   or manually dispatched. The release workflow refuses to upload to Play until
   the three readiness variables are `yes` and the approved SHA matches
   `GITHUB_SHA`.
5. Confirm `main` branch protection is still enabled and still requires the
   strict `Readiness Check / readiness` status before merging release branches.
6. Re-run the full audit before promoting the Play Store track:
   ```bash
   RIHLA_SKIP_IOS_QA=yes RIHLA_CONFIRM_APP_CHECK_READY=yes bash tool/check_release_readiness.sh
   ```
   `tool/release.sh` runs this same audit after creating the release commit and
   before creating/pushing the tag. If the audit fails, fix the failed gate
   before tagging that commit.

Historical external actions completed on or before 2026-05-16:

- Upgraded `rihla-safar` to Blaze plan.
- Deployed Firestore rules, indexes, Functions, and Hosting via
  `tool/deploy_firebase_backend.sh`.
- Enrolled Firebase App Check (Play Integrity for Android, App Attest /
  DeviceCheck fallback for iOS).
- Re-ran `bash tool/check_firebase_prod_state.sh rihla-safar` — 12 checks
  PASS for the v1.2.0+15 backend snapshot.
- 2026-05-16: deployed v1.2.0+15 functions (`joinGroupByInviteCode` event
  fan-out + new `cleanupAnonUidArtifacts` callable); ran
  `tool/backfill_join_event_sync.js` against `rihla-safar`; tagged
  `v1.2.0-b15` and triggered Android Release workflow to Play "first" track.

## Follow-ups for v1.2.0+16

- **Orphan anon-UID reconciliation.** Five orphan anon UIDs in production
  have downstream references (`memberIds` / `participantIds` /
  `groups/{gid}/members/{uid}` docs) and cannot be safely auto-pruned by
  the fire-and-forget `cleanupAnonUidArtifacts` callable. Build a
  server-side reconciliation tool (or expand the callable to traverse
  references) before the next batch of recoveries lands. Inspection tool:
  `tool/inspect_orphan_anon_uids.js`.
- **Complete the Android RD-QA matrix.** RD-01..09 cells in
  `docs/REAL-DEVICE-QA.md` are still empty; gate command above will block
  the next release tag until they're filled with concrete evidence.

## Deployment Commands

The initial production deploy is complete. Use these commands for subsequent
backend changes.

Before deploying, run the read-only production-state check to understand
current drift:

```bash
bash tool/check_firebase_prod_state.sh rihla-safar
```

If this branch includes backend changes, rule/function mismatches are expected
before deployment. After deployment, the command should report PASS and exit 0
against the currently deployed backend.

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

### Updating the Play Store listing

Listing assets (icon, feature graphic, screenshots, title, descriptions) are
managed via `fastlane supply` and live under `fastlane/metadata/android/en-US/`.
Listing edits are **decoupled from the AAB release pipeline** — they don't
touch the binary, don't trigger an AAB re-review, and are safe to push while
an Android Release workflow is in flight.

```bash
export PATH="/opt/homebrew/opt/ruby/bin:$PATH"   # Homebrew Ruby 3.x required
bundle install

# Edit fastlane/metadata/android/en-US/<file>, then:
bundle exec fastlane android icon        # icon + feature graphic only
bundle exec fastlane android listing     # icon + screenshots + text (full)
bundle exec fastlane android pull        # re-sync local repo from live Play
```

The service-account key at `secrets/play-key.json` (gitignored) is the same
JSON used by CI as `GOOGLE_PLAY_JSON_KEY`.

Then confirm production state:

```bash
npx --yes firebase-tools@15.8.0 functions:list --project rihla-safar
npx --yes firebase-tools@15.8.0 firestore:indexes --project rihla-safar --database '(default)'
```

For Firestore rules, fetch the active release through the Firebase Rules API and
diff it against `security/firestore.rules`.
