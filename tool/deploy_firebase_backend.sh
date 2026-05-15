#!/usr/bin/env bash
# Deploys the Firebase backend and Hosting artifacts from this repo, then
# verifies that production matches local rules, indexes, Functions exports, and
# hosted link files.
set -euo pipefail

PROJECT_ID="${1:-${FIREBASE_PROJECT:-rihla-safar}}"
FIREBASE_TOOLS_VERSION="${FIREBASE_TOOLS_VERSION:-15.8.0}"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

cd "$ROOT_DIR"

npm20() {
  local npm_cli
  npm_cli="$(command -v npm || true)"
  if [ -z "$npm_cli" ]; then
    echo "npm not found"
    return 1
  fi

  npx --yes node@20 "$npm_cli" "$@"
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
  echo "  RIHLA_CONFIRM_FIREBASE_DEPLOY=yes RIHLA_CONFIRM_APP_CHECK_READY=yes bash tool/deploy_firebase_backend.sh ${PROJECT_ID}"
  exit 2
fi

npm20 --prefix functions ci
npm20 --prefix functions audit --omit=dev --audit-level=low
npm20 --prefix functions run build

npx --yes "firebase-tools@${FIREBASE_TOOLS_VERSION}" deploy \
  --force \
  --project "$PROJECT_ID" \
  --only firestore:rules,firestore:indexes,functions,hosting

bash tool/check_firebase_prod_state.sh "$PROJECT_ID"
