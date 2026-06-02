# Android Public Release Hardening Log - 2026-06-01

Branch: `release/android-public-hardening-2026-06-01`
Base: `origin/main` at `51f358e` (`Merge pull request #209 from NasserAlbusaidi/codex/coverage-test-gaps`)

Purpose: track the release-hardening work for the public Android launch. Every touched path must be categorized as added, modified, or removed with a short justification and verification note.

## Working Rules

- Treat the current checkout and command output as authoritative.
- Record every touched path in the change ledger before the work is handed off.
- Use failing tests first for behavior changes and bug fixes.
- Keep production-affecting checks read-only unless deploy approval is explicit.

## Change Ledger

### Added

| Path | Category | Justification | Verification |
| --- | --- | --- | --- |
| `docs/ANDROID-PUBLIC-RELEASE-HARDENING-2026-06-01.md` | Release documentation | Required standing log for all public Android release hardening changes, grouped by added, modified, and removed. | Created on the release hardening branch before product code changes. |
| `test/unit/active_journeys_provider_test.dart` | Performance test coverage | Added a provider regression test proving inactive groups do not trigger expensive group-balance aggregation, plus a guard that active journeys still receive user balance totals. | Red: failed before provider change because `groupBalancesProvider` was watched for an inactive group. Green: `flutter test test/unit/active_journeys_provider_test.dart`. |

### Modified

| Path | Category | Justification | Verification |
| --- | --- | --- | --- |
| `AGENTS.md` | Agent/release guidance | Updated the current version from stale `1.2.0+16` to `1.3.0+18` so future agents do not use closed-test release context for the public Android release line. | Cross-checked against `pubspec.yaml` and `CHANGELOG.md`. |
| `docs/PRODUCTION-READINESS.md` | Release documentation | Replaced older PR #39 status with the 2026-06-01 audit result and exact remaining blockers: Firebase production drift, incomplete Android RD-QA, and stale release-approved SHA. | Backed by `RIHLA_SKIP_IOS_QA=yes RIHLA_CONFIRM_APP_CHECK_READY=yes bash tool/check_release_readiness.sh`. |
| `lib/features/home/providers/active_journeys_provider.dart` | Performance | Filters deleted/inactive events before watching `groupBalancesProvider`, avoiding unnecessary cross-event balance aggregation for groups that cannot contribute active journey cards. | `flutter test test/unit/active_journeys_provider_test.dart`. |

### Removed

None yet.

## Findings Queue

| ID | Status | Finding | Evidence | Next action |
| --- | --- | --- | --- | --- |
| RH-001 | External blocker | Firebase production state is not aligned with this branch. | `tool/check_release_readiness.sh` failed `Firebase production state`: Firestore indexes differ, Firestore rules differ, and deployed Functions are missing `deleteGroup`. | Requires approved Firebase backend deploy, then rerun `bash tool/check_firebase_prod_state.sh rihla-safar`. |
| RH-002 | External blocker | Android real-device QA is incomplete for RD-01..RD-09 and no physical Android device was detected. | `tool/check_release_readiness.sh` failed `Real-device QA gate`: no physical Android device, matrix entries missing/pass placeholders in `docs/REAL-DEVICE-QA.md`. | Complete the Android physical-device matrix against the target build and rerun `RIHLA_SKIP_IOS_QA=yes bash tool/check_real_device_qa_gate.sh`. |
| RH-003 | External blocker | GitHub release approval SHA is stale for the current target commit. | `tool/check_release_readiness.sh` failed `GitHub release governance`: `RIHLA_RELEASE_APPROVED_SHA=f03a89a15b03f9c873bdfa08158a31357c869061` does not match `51f358e727a58ec260b0783c54535becd568b3cb`. | After final release gates pass, set `RIHLA_RELEASE_APPROVED_SHA` to the exact approved release commit. |
| RH-004 | Investigating | Release build emits a Cupertino icon font tree-shaker warning, but no app reference is proven yet. | AAB build warned about `packages/cupertino_icons/CupertinoIcons`; `rg -n "CupertinoIcons\|cupertino_icons\|IconData\(" lib test pubspec.yaml pubspec.lock` found no matches. | Keep under observation; do not change dependencies without a reproducible app-side reference. |
| RH-005 | Fixed | `activeJourneysProvider` aggregated group balances for groups whose events were all inactive or deleted. | Failing test: `flutter test test/unit/active_journeys_provider_test.dart` failed with `inactive groups should not aggregate balances` before the provider filter moved ahead of the balance watch. | Fixed by filtering active events first; focused test now passes. |

## Verification Runs

| Time | Command | Result | Notes |
| --- | --- | --- | --- |
| 2026-06-01 | `git switch -c release/android-public-hardening-2026-06-01 origin/main` | Pass | Branch created from current `origin/main` after `git fetch origin main`. |
| 2026-06-01 21:08 +04 | `RIHLA_SKIP_IOS_QA=yes RIHLA_CONFIRM_APP_CHECK_READY=yes bash tool/check_release_readiness.sh` | Fail | Local/backend code gates passed through AAB build: Java 21, Node 20, Functions install/audit/build, App Check marker checks, emulator tests, analyzer, theme purity, navigation smoke tests, full Flutter coverage at 88.3%, and Android release AAB at 56.5 MB. Failed on RH-001, RH-002, and RH-003. |
| 2026-06-01 | `rg -n "CupertinoIcons\|cupertino_icons\|IconData\(" lib test pubspec.yaml pubspec.lock` | Pass | No source or manifest references found for the release-build Cupertino icon warning. |
| 2026-06-01 | `flutter test test/unit/active_journeys_provider_test.dart` | Fail | Intentional RED: proved inactive groups still watched `groupBalancesProvider` before the performance fix. |
| 2026-06-01 | `flutter test test/unit/active_journeys_provider_test.dart` | Pass | GREEN after filtering inactive/deleted events before group-balance aggregation. |
