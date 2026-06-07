#!/usr/bin/env bash
# Reports the backend changes merged to origin/main but NOT yet deployed to prod.
#
# Source of truth for "what is deployed" is the moving git tag `backend-deployed`,
# which tool/deploy_firebase_backend.sh advances to the deployed commit on a
# successful deploy. This script diffs that tag against origin/main over the exact
# surface the deploy ships (rules + indexes + functions). It exists to kill the
# ghost-debt where merged-but-undeployed Functions/rules changes are tracked only
# in scattered memory notes.
#
# Exit codes:
#   0 = nothing pending (prod matches main on the backend surface)
#   1 = pending backend changes (printed)
#   2 = setup error (tag missing, etc.)
#
# Bash 3.2 compatible (macOS default) — no mapfile.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

DEPLOY_TAG="${RIHLA_DEPLOY_TAG:-backend-deployed}"

# The deploy ships firestore:rules,firestore:indexes,functions,hosting. Hosting is
# static legal pages (low ghost-debt risk); the surface that silently breaks money
# /security when it lags prod is rules + functions + indexes, so those define "pending".
BACKEND_PATHS="functions/ security/firestore.rules firestore.indexes.json"

# A force-MOVED tag is not advanced by a plain fetch — force-fetch it explicitly.
git fetch --quiet origin main 2>/dev/null || echo "warn: could not fetch origin/main; using local ref" >&2
git fetch --quiet --force origin "refs/tags/${DEPLOY_TAG}:refs/tags/${DEPLOY_TAG}" 2>/dev/null || true

base_ref=""
if git rev-parse --verify --quiet "refs/tags/${DEPLOY_TAG}" >/dev/null; then
  base_ref="$(git rev-parse "refs/tags/${DEPLOY_TAG}")"
fi
target_ref="$(git rev-parse origin/main 2>/dev/null || git rev-parse main)"

echo "Backend deploy status"
echo "  deployed tag : ${DEPLOY_TAG} -> ${base_ref:-<unset>}"
echo "  main         : ${target_ref}"
echo "  surface      : ${BACKEND_PATHS}"
echo

if [ -z "$base_ref" ]; then
  echo "No '${DEPLOY_TAG}' tag found — cannot compute a delta."
  echo "Seed it at the last-deployed commit, then push:"
  echo "  git tag -f ${DEPLOY_TAG} <last-deployed-sha> && git push --force origin ${DEPLOY_TAG}"
  exit 2
fi

# shellcheck disable=SC2086  # BACKEND_PATHS is an intentional word-split path list
pending="$(git log --oneline "${base_ref}..${target_ref}" -- $BACKEND_PATHS)"

if [ -z "$pending" ]; then
  echo "✅ Prod is up to date — no backend changes pending deploy."
  exit 0
fi

count="$(printf '%s\n' "$pending" | grep -c .)"
echo "⚠️  ${count} backend change(s) merged but NOT deployed:"
printf '%s\n' "$pending" | sed 's/^/   /'
echo
echo "Files in the pending delta:"
# shellcheck disable=SC2086
git diff --stat "${base_ref}..${target_ref}" -- $BACKEND_PATHS | sed 's/^/   /'
echo
echo "Deploy via the ceremony (.claude/skills/deploy-ceremony), or directly from clean main:"
echo "  RIHLA_CONFIRM_FIREBASE_DEPLOY=yes RIHLA_CONFIRM_APP_CHECK_READY=yes \\"
echo "    RIHLA_FIREBASE_DEPLOY_APPROVED_SHA=\"\$(git rev-parse HEAD)\" \\"
echo "    bash tool/deploy_firebase_backend.sh rihla-safar"
exit 1
