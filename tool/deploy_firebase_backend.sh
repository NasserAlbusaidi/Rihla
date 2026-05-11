#!/usr/bin/env bash
# Deploys the Firebase backend artifacts from this repo, then verifies that
# production matches local rules, indexes, and Functions exports.
set -euo pipefail

PROJECT_ID="${1:-${FIREBASE_PROJECT:-rihla-safar}}"
FIREBASE_TOOLS_VERSION="${FIREBASE_TOOLS_VERSION:-15.8.0}"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

cd "$ROOT_DIR"

echo "Preparing Firebase backend deploy for project: ${PROJECT_ID}"
echo
echo "Prerequisites:"
echo "- Firebase project is on the Blaze plan."
echo "- Firebase Storage has been initialized in the Firebase Console."
echo "- Required APIs for Cloud Functions, Cloud Build, and Artifact Registry can be enabled."
echo

if [ "${RIHLA_CONFIRM_FIREBASE_DEPLOY:-}" != "yes" ]; then
  echo "Refusing to deploy without confirmation."
  echo "Run with RIHLA_CONFIRM_FIREBASE_DEPLOY=yes when the prerequisites above are complete:"
  echo "  RIHLA_CONFIRM_FIREBASE_DEPLOY=yes bash tool/deploy_firebase_backend.sh ${PROJECT_ID}"
  exit 2
fi

npm --prefix functions ci
npm --prefix functions audit --omit=dev --audit-level=low
npm --prefix functions run build

npx --yes "firebase-tools@${FIREBASE_TOOLS_VERSION}" deploy \
  --project "$PROJECT_ID" \
  --only firestore:rules,firestore:indexes,storage:rules,functions

bash tool/check_firebase_prod_state.sh "$PROJECT_ID"
