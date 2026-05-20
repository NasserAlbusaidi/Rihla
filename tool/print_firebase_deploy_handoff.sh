#!/usr/bin/env bash
# Prints the current Firebase backend deploy handoff without deploying,
# enabling APIs, or mutating Firebase/GitHub state.
set -euo pipefail

PROJECT_ID="${1:-${FIREBASE_PROJECT:-rihla-safar}}"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

cd "$ROOT_DIR"

current_sha="$(git rev-parse HEAD)"

echo "Rihla Firebase backend deploy handoff"
echo
echo "Branch: $(git rev-parse --abbrev-ref HEAD)"
echo "Commit: ${current_sha}"
echo "Project: ${PROJECT_ID}"
echo

echo "Worktree:"
if [ -n "$(git status --short)" ]; then
  echo "  dirty - tool/deploy_firebase_backend.sh will refuse unless RIHLA_ALLOW_DIRTY_FIREBASE_DEPLOY=yes is set"
  git status --short | sed 's/^/  /'
else
  echo "  clean"
fi
echo

echo "Read-only production drift check:"
echo "  bash tool/check_firebase_prod_state.sh ${PROJECT_ID}"
echo

echo "Deploy this exact commit only after branch review/testing is accepted:"
echo "  RIHLA_CONFIRM_FIREBASE_DEPLOY=yes RIHLA_CONFIRM_APP_CHECK_READY=yes RIHLA_FIREBASE_DEPLOY_APPROVED_SHA=\"${current_sha}\" bash tool/deploy_firebase_backend.sh ${PROJECT_ID}"
echo

echo "Post-deploy verification:"
echo "  bash tool/check_firebase_prod_state.sh ${PROJECT_ID}"
echo
echo "After the production-state check exits 0 for this commit:"
echo "  Set RIHLA_BACKEND_RELEASE_READY=yes for the Android release workflow."
