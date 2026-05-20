# Release Hardening Audit

Last updated: 2026-05-20 (`codex/release-hardening-1-0`, PR #39)

This audit maps the release-hardening request to concrete branch artifacts. It is
not a release approval. The branch remains not release complete while release
blockers #40 and #41 are open.

Use the wake-up handoff to print the current commit, Android artifact hashes,
Firebase deploy command, release audit command, and blocker links:

```bash
bash tool/print_release_wakeup_handoff.sh rihla-safar
```

## Verdict

- Code hardening for the branch scope is implemented and covered by local tests
  plus PR readiness CI.
- Wake-up testing is ready for a human tester.
- Final 1.0 release approval is blocked by physical Android QA and Firebase
  production deployment/verification.

## Prompt-To-Artifact Map

| Requirement | Evidence | Status |
| --- | --- | --- |
| Group release-hardening work in a new branch for later wake-up testing. | `codex/release-hardening-1-0`, PR #39, `tool/print_release_wakeup_handoff.sh` | Complete. |
| Fix frontend button labels that were visually cut off. | `lib/core/theme/app_theme.dart`; `test/core/theme/app_theme_button_test.dart` covers minimum button heights, label descender clearance, and local override regressions. | Complete and CI-covered. |
| Harden backend and service release gates. | `tool/check_release_readiness.sh`, `tool/check_firebase_prod_state.sh`, `tool/deploy_firebase_backend.sh`, `tool/print_firebase_deploy_handoff.sh`, `functions/test/`, `security/firestore.rules` | Code path is complete; production deploy remains blocked by #41. |
| Keep release workflow guarded until external checks pass. | `.github/workflows/release_android.yml`, `tool/check_github_release_governance.sh`, `tool/release.sh`, `docs/PRODUCTION-READINESS.md` | Complete; release variables must stay unset until #40 and #41 pass for the target commit. |
| Prepare branch for wake-up testing. | `tool/print_android_qa_handoff.sh`, `tool/print_firebase_deploy_handoff.sh`, `tool/print_release_wakeup_handoff.sh`, `docs/REAL-DEVICE-QA.md` | Ready for the next tester. |
| Ensure the app is fully ready for the 1.0 release. | GitHub blockers #40 and #41; `RIHLA_SKIP_IOS_QA=yes RIHLA_CONFIRM_APP_CHECK_READY=yes bash tool/check_release_readiness.sh` | Not complete. External gates still block release approval. |

## Open Release Blockers

- #40: Complete the physical Android QA matrix RD-01 through RD-09 in
  `docs/REAL-DEVICE-QA.md`, with concrete build traceability in every evidence
  cell.
- #41: Deploy the branch Firebase backend only after explicit approval, then
  rerun `bash tool/check_firebase_prod_state.sh rihla-safar` until it exits 0.
- Android release workflow variables must remain unset until #40 and #41 pass
  for the exact target commit.

## Verification Surface

The branch evidence is intentionally split between automated gates and external
release checks:

- Frontend label clipping: `flutter test test/core/theme/app_theme_button_test.dart`
- Release workflow regression guards: `flutter test test/unit/release_workflow_gate_test.dart`
- Consolidated local audit: `RIHLA_SKIP_IOS_QA=yes RIHLA_CONFIRM_APP_CHECK_READY=yes bash tool/check_release_readiness.sh`
- Physical Android QA gate: `RIHLA_SKIP_IOS_QA=yes bash tool/check_real_device_qa_gate.sh`
- Firebase production-state gate: `bash tool/check_firebase_prod_state.sh rihla-safar`
