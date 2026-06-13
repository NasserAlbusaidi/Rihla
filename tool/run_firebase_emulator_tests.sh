#!/usr/bin/env bash
# Runs Firebase Auth/Firestore emulator tests on isolated ports so local
# services using the default emulator ports do not break release gates.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FIREBASE_TOOLS_VERSION="${FIREBASE_TOOLS_VERSION:-15.8.0}"
PROJECT_ID="${RIHLA_FIREBASE_EMULATOR_PROJECT:-rihla-safar-test}"
AUTH_PORT="${RIHLA_AUTH_EMULATOR_PORT:-19099}"
FIRESTORE_PORT="${RIHLA_FIRESTORE_EMULATOR_PORT:-18080}"
TEST_COMMAND="${RIHLA_FIREBASE_EMULATOR_TEST_COMMAND:-npx --yes node@22 node_modules/jest/bin/jest.js --runInBand}"
# emulators:exec takes one command STRING, so positional args (e.g.
# `npm run test:emulator -- balanceAggregator.test.ts`) must be appended
# shell-quoted; before this they were silently dropped and the full suite ran.
for arg in "$@"; do
  TEST_COMMAND+=" $(printf '%q' "$arg")"
done
TEMP_FILES=()

cleanup() {
  local file
  for file in "${TEMP_FILES[@]-}"; do
    if [ -z "$file" ]; then
      continue
    fi
    rm -f "$file"
  done
}
trap cleanup EXIT

config="$(mktemp "$ROOT_DIR/.firebase-release-emulators.XXXXXX")"
TEMP_FILES+=("$config")

cat >"$config" <<JSON
{
  "firestore": {
    "rules": "security/firestore.rules",
    "indexes": "firestore.indexes.json"
  },
  "emulators": {
    "auth": { "port": ${AUTH_PORT} },
    "firestore": { "port": ${FIRESTORE_PORT} },
    "ui": { "enabled": false },
    "singleProjectMode": true
  }
}
JSON

(
  cd "$ROOT_DIR/functions"
  npx --yes "firebase-tools@${FIREBASE_TOOLS_VERSION}" emulators:exec \
    --config "$config" \
    --project "$PROJECT_ID" \
    --only auth,firestore \
    "$TEST_COMMAND"
)
