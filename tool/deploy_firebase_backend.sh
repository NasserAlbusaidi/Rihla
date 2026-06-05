#!/usr/bin/env bash
# Deploys the Firebase backend and Hosting artifacts from this repo, then
# verifies that production matches local rules, indexes, Functions exports, and
# hosted link files.
set -euo pipefail

PROJECT_ID="${1:-${FIREBASE_PROJECT:-rihla-safar}}"
FIREBASE_TOOLS_VERSION="${FIREBASE_TOOLS_VERSION:-15.8.0}"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

cd "$ROOT_DIR"

npm22() {
  local npm_cli
  npm_cli="$(command -v npm || true)"
  if [ -z "$npm_cli" ]; then
    echo "npm not found"
    return 1
  fi

  npx --yes node@22 "$npm_cli" "$@"
}

require_clean_worktree() {
  if [ "${RIHLA_ALLOW_DIRTY_FIREBASE_DEPLOY:-}" = "yes" ]; then
    echo "WARNING: RIHLA_ALLOW_DIRTY_FIREBASE_DEPLOY=yes — deploying from a dirty worktree."
    return 0
  fi

  if ! git diff --quiet \
    || ! git diff --cached --quiet \
    || [ -n "$(git ls-files --others --exclude-standard)" ]; then
    echo "Refusing to deploy Firebase backend from a dirty working tree."
    echo "Commit, stash, or remove local changes first so production can be tied to an exact commit."
    echo "Emergency override: RIHLA_ALLOW_DIRTY_FIREBASE_DEPLOY=yes"
    exit 2
  fi
}

require_approved_sha() {
  local current_sha
  current_sha="$(git rev-parse HEAD)"

  if [ -z "${RIHLA_FIREBASE_DEPLOY_APPROVED_SHA:-}" ]; then
    echo "Refusing to deploy without commit-bound approval."
    echo "Set RIHLA_FIREBASE_DEPLOY_APPROVED_SHA to the exact commit being deployed:"
    echo "  RIHLA_FIREBASE_DEPLOY_APPROVED_SHA=\"$current_sha\""
    exit 2
  fi

  if [ "$RIHLA_FIREBASE_DEPLOY_APPROVED_SHA" != "$current_sha" ]; then
    echo "Refusing to deploy: RIHLA_FIREBASE_DEPLOY_APPROVED_SHA=${RIHLA_FIREBASE_DEPLOY_APPROVED_SHA} does not match current commit ${current_sha}."
    exit 2
  fi
}

echo "Preparing Firebase backend deploy for project: ${PROJECT_ID}"
echo
echo "Prerequisites:"
echo "- Firebase project is on the Blaze plan."
echo "- Required APIs for Cloud Functions, Cloud Build, and Artifact Registry can be enabled."
echo "- Firebase App Check is enrolled for the Android and iOS apps before deploying enforced callables."
echo "- Repo Firebase config is the source of truth; --force removes stale remote indexes/functions not present here."
echo

if [ "${RIHLA_CONFIRM_FIREBASE_DEPLOY:-}" != "yes" ] || [ "${RIHLA_CONFIRM_APP_CHECK_READY:-}" != "yes" ]; then
  echo "Refusing to deploy without confirmation."
  echo "Run with both confirmations when the prerequisites above are complete:"
  echo "  RIHLA_CONFIRM_FIREBASE_DEPLOY=yes RIHLA_CONFIRM_APP_CHECK_READY=yes RIHLA_FIREBASE_DEPLOY_APPROVED_SHA=\"$(git rev-parse HEAD)\" bash tool/deploy_firebase_backend.sh ${PROJECT_ID}"
  exit 2
fi

require_clean_worktree
require_approved_sha

npm22 --prefix functions ci
npm22 --prefix functions audit --omit=dev --audit-level=low
npm22 --prefix functions run build
require_clean_worktree
require_approved_sha

npx --yes "firebase-tools@${FIREBASE_TOOLS_VERSION}" deploy \
  --force \
  --project "$PROJECT_ID" \
  --only firestore:rules,firestore:indexes,functions,hosting

bash tool/check_firebase_prod_state.sh "$PROJECT_ID"
