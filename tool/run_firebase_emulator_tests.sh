#!/usr/bin/env bash
# Runs Firebase Auth/Firestore emulator tests on per-invocation FREE ports so
# every run gets a private emulator instance. Fixed default ports let two
# concurrent runs (parallel sessions/worktrees) either hard-fail on a port
# conflict or share one Firestore namespace and cross-contaminate — the #1157
# nondeterministic claimShadow failures. Hub/logging ports are pinned too:
# their firebase-tools defaults (4400/4500) would still collide across
# concurrent invocations.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FIREBASE_TOOLS_VERSION="${FIREBASE_TOOLS_VERSION:-15.8.0}"
PROJECT_ID="${RIHLA_FIREBASE_EMULATOR_PROJECT:-rihla-safar-test}"
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

# Picks a free TCP port in [20000, 39999], skipping ports already chosen this
# invocation (passed as args). Sets REPLY. Deliberately NOT invoked via
# command substitution: a $(...) subshell would replay the parent's RANDOM
# state, handing every pick the same candidate sequence.
pick_free_port() {
  local candidate taken
  for _ in $(seq 1 50); do
    candidate=$(( (RANDOM % 20000) + 20000 ))
    for taken in "$@"; do
      if [ "${candidate}" = "${taken}" ]; then
        continue 2
      fi
    done
    if ! lsof -nP -iTCP:"${candidate}" -sTCP:LISTEN >/dev/null 2>&1; then
      REPLY="${candidate}"
      return 0
    fi
  done
  echo "run_firebase_emulator_tests: no free port found after 50 attempts" >&2
  return 1
}

if [ -n "${RIHLA_AUTH_EMULATOR_PORT:-}" ]; then
  AUTH_PORT="${RIHLA_AUTH_EMULATOR_PORT}"
else
  pick_free_port
  AUTH_PORT="${REPLY}"
fi
if [ -n "${RIHLA_FIRESTORE_EMULATOR_PORT:-}" ]; then
  FIRESTORE_PORT="${RIHLA_FIRESTORE_EMULATOR_PORT}"
else
  pick_free_port "${AUTH_PORT}"
  FIRESTORE_PORT="${REPLY}"
fi
pick_free_port "${AUTH_PORT}" "${FIRESTORE_PORT}"
HUB_PORT="${REPLY}"
pick_free_port "${AUTH_PORT}" "${FIRESTORE_PORT}" "${HUB_PORT}"
LOGGING_PORT="${REPLY}"

echo "run_firebase_emulator_tests: auth=${AUTH_PORT} firestore=${FIRESTORE_PORT} hub=${HUB_PORT} logging=${LOGGING_PORT} project=${PROJECT_ID}" >&2

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
    "hub": { "port": ${HUB_PORT} },
    "logging": { "port": ${LOGGING_PORT} },
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
