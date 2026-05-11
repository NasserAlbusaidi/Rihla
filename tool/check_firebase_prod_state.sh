#!/usr/bin/env bash
# Verifies that the live Firebase project matches the backend artifacts in this
# repo. This is intentionally read-only: it lists resources and reads active
# rulesets, but it does not deploy or enable APIs.
set -euo pipefail

PROJECT_ID="${1:-${FIREBASE_PROJECT:-rihla-safar}}"
FIREBASE_TOOLS_VERSION="${FIREBASE_TOOLS_VERSION:-15.8.0}"
DATABASE_ID="${FIRESTORE_DATABASE_ID:-(default)}"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP_DIR="$(mktemp -d)"
FAILURES=0

cleanup() {
  rm -rf "$TMP_DIR"
}
trap cleanup EXIT

pass() {
  echo "PASS: $*"
}

fail() {
  echo "FAIL: $*" >&2
  FAILURES=$((FAILURES + 1))
}

require_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    fail "Missing required command: $1"
    return 1
  fi
}

firebase_cli() {
  npx --yes "firebase-tools@${FIREBASE_TOOLS_VERSION}" "$@"
}

normalize_indexes() {
  jq '
    .indexes |= sort_by(.collectionGroup)
    | (.indexes[]?.fields) |= map(select(.fieldPath != "__name__"))
    | del(.indexes[]?.density)
  '
}

diff_rules_ignoring_blank_lines() {
  local local_file="$1"
  local remote_file="$2"

  if diff -B -u "$local_file" "$remote_file" >"$TMP_DIR/rules.diff"; then
    return 0
  fi

  cat "$TMP_DIR/rules.diff" >&2
  return 1
}

fetch_ruleset_file() {
  local token="$1"
  local ruleset_name="$2"
  local preferred_file="$3"
  local output_file="$4"
  local ruleset_json="$TMP_DIR/ruleset.json"

  curl -fsS \
    -H "Authorization: Bearer ${token}" \
    -H "x-goog-user-project: ${PROJECT_ID}" \
    "https://firebaserules.googleapis.com/v1/${ruleset_name}" \
    >"$ruleset_json"

  if ! jq -er --arg name "$preferred_file" \
    '.source.files[] | select(.name == $name) | .content' \
    "$ruleset_json" >"$output_file"; then
    jq -er '.source.files[0].content' "$ruleset_json" >"$output_file"
  fi
}

cd "$ROOT_DIR"

require_cmd jq || true
require_cmd curl || true
require_cmd npx || true
require_cmd gcloud || true

if [ "$FAILURES" -ne 0 ]; then
  exit 1
fi

echo "Checking Firebase production state for project: ${PROJECT_ID}"

db_json="$TMP_DIR/firestore-db.json"
if firebase_cli firestore:databases:get "$DATABASE_ID" \
  --project "$PROJECT_ID" \
  --json >"$db_json"; then
  if jq -e '.status == "success" and .result.type == "FIRESTORE_NATIVE"' \
    "$db_json" >/dev/null; then
    pass "Firestore database ${DATABASE_ID} exists and is native mode"
  else
    fail "Firestore database ${DATABASE_ID} did not report native mode"
  fi
else
  fail "Unable to read Firestore database ${DATABASE_ID}"
fi

remote_indexes="$TMP_DIR/firestore-indexes.remote.json"
local_indexes="$TMP_DIR/firestore-indexes.local.json"
indexes_json="$TMP_DIR/firestore-indexes.raw.json"
if firebase_cli firestore:indexes \
  --project "$PROJECT_ID" \
  --database "$DATABASE_ID" \
  --json >"$indexes_json"; then
  jq '.result' "$indexes_json" | normalize_indexes >"$remote_indexes"
  normalize_indexes < firestore.indexes.json >"$local_indexes"
  if diff -u "$local_indexes" "$remote_indexes" >"$TMP_DIR/indexes.diff"; then
    pass "Firestore indexes match firestore.indexes.json"
  else
    cat "$TMP_DIR/indexes.diff" >&2
    fail "Firestore indexes do not match firestore.indexes.json"
  fi
else
  fail "Unable to list Firestore indexes"
fi

token="$(gcloud auth print-access-token 2>/dev/null || true)"
if [ -z "$token" ]; then
  fail "Unable to get a gcloud access token for Firebase Rules API"
else
  releases_json="$TMP_DIR/rules-releases.json"
  if curl -fsS \
    -H "Authorization: Bearer ${token}" \
    -H "x-goog-user-project: ${PROJECT_ID}" \
    "https://firebaserules.googleapis.com/v1/projects/${PROJECT_ID}/releases" \
    >"$releases_json"; then
    firestore_ruleset="$(jq -r '
      .releases[]?
      | select(.name | endswith("/releases/cloud.firestore"))
      | .rulesetName
    ' "$releases_json" | head -n 1)"

    if [ -z "$firestore_ruleset" ]; then
      fail "No active Firestore rules release found"
    else
      remote_firestore_rules="$TMP_DIR/firestore.rules.remote"
      if fetch_ruleset_file \
        "$token" \
        "$firestore_ruleset" \
        "security/firestore.rules" \
        "$remote_firestore_rules" \
        && diff_rules_ignoring_blank_lines \
          "security/firestore.rules" \
          "$remote_firestore_rules"; then
        pass "Firestore rules match security/firestore.rules"
      else
        fail "Firestore rules do not match security/firestore.rules"
      fi
    fi

    storage_ruleset="$(jq -r '
      .releases[]?
      | select(.name | test("firebase\\.storage|storage"))
      | .rulesetName
    ' "$releases_json" | head -n 1)"

    if [ -z "$storage_ruleset" ]; then
      fail "No active Storage rules release found"
    else
      remote_storage_rules="$TMP_DIR/storage.rules.remote"
      if fetch_ruleset_file \
        "$token" \
        "$storage_ruleset" \
        "security/storage.rules" \
        "$remote_storage_rules" \
        && diff_rules_ignoring_blank_lines \
          "security/storage.rules" \
          "$remote_storage_rules"; then
        pass "Storage rules match security/storage.rules"
      else
        fail "Storage rules do not match security/storage.rules"
      fi
    fi
  else
    fail "Unable to list Firebase Rules releases"
  fi
fi

functions_json="$TMP_DIR/functions.json"
if firebase_cli functions:list --project "$PROJECT_ID" --json >"$functions_json"; then
  expected_functions="$TMP_DIR/expected-functions.txt"
  sed -n 's/^export { \([^ }]*\) }.*/\1/p' functions/src/index.ts \
    >"$expected_functions"
  deployed_functions="$TMP_DIR/deployed-functions.txt"
  jq -r '.result[]? | .id // .name // empty' "$functions_json" \
    | awk -F/ '{ print $NF }' \
    | sed 's/(.*//' \
    | sort -u >"$deployed_functions"

  functions_missing=0
  while IFS= read -r function_name; do
    [ -z "$function_name" ] && continue
    if ! grep -Fxq "$function_name" "$deployed_functions"; then
      fail "Missing deployed Function: ${function_name}"
      functions_missing=$((functions_missing + 1))
    fi
  done <"$expected_functions"

  if [ "$functions_missing" -eq 0 ] \
    && [ -s "$expected_functions" ]; then
    pass "All expected Functions are deployed"
  fi
else
  fail "Unable to list deployed Functions"
fi

if [ "$FAILURES" -ne 0 ]; then
  echo "Firebase production state check FAILED (${FAILURES} issue(s))" >&2
  exit 1
fi

echo "Firebase production state check PASS"
