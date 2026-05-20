#!/usr/bin/env bash
# Prints the current release wake-up handoff without touching devices,
# Firebase, or GitHub state.
set -euo pipefail

PROJECT_ID="${1:-${FIREBASE_PROJECT:-rihla-safar}}"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

cd "$ROOT_DIR"

echo "Rihla release wake-up handoff"
echo
echo "Branch: $(git rev-parse --abbrev-ref HEAD)"
echo "Commit: $(git rev-parse HEAD)"
echo "PR: https://github.com/NasserAlbusaidi/Rihla/pull/39"
echo "Release hardening audit: docs/RELEASE-HARDENING-AUDIT.md"
echo
echo "Open release blockers:"
echo "- #40 Physical Android QA: https://github.com/NasserAlbusaidi/Rihla/issues/40"
echo "- #41 Firebase backend deploy: https://github.com/NasserAlbusaidi/Rihla/issues/41"
echo
echo "Android QA handoff"
echo "------------------"
bash tool/print_android_qa_handoff.sh
echo
echo "Firebase backend handoff"
echo "------------------------"
bash tool/print_firebase_deploy_handoff.sh "$PROJECT_ID"
echo
echo "Final Android-only release audit after #40 and #41 pass:"
echo "  RIHLA_SKIP_IOS_QA=yes RIHLA_CONFIRM_APP_CHECK_READY=yes bash tool/check_release_readiness.sh"
echo
echo "Release variables stay blocked until both external gates pass for this exact commit:"
echo "  RIHLA_BACKEND_RELEASE_READY=yes"
echo "  RIHLA_REAL_DEVICE_QA_READY=yes"
echo "  RIHLA_RELEASE_APPROVED_SHA=$(git rev-parse HEAD)"
