#!/usr/bin/env bash
# Verifies GitHub-side release governance before a Play upload. This script is
# read-only: it checks repository variables and branch protection, but does not
# mutate repository settings.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REPO_SLUG="${RIHLA_REPO_SLUG:-NasserAlbusaidi/Rihla}"
PROTECTED_BRANCH="${RIHLA_RELEASE_PROTECTED_BRANCH:-main}"
TARGET_SHA="${RIHLA_RELEASE_TARGET_SHA:-}"
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

variable_value() {
  local name="$1"
  jq -r --arg name "$name" \
    '.[] | select(.name == $name) | .value' \
    "$TMP_DIR/variables.json" \
    | head -n 1
}

require_variable_yes() {
  local name="$1"
  local value
  value="$(variable_value "$name")"

  if [ "$value" = "yes" ]; then
    pass "${name}=yes"
  else
    fail "${name} must be yes before release; current value: ${value:-<unset>}"
  fi
}

check_release_variables() {
  if gh variable list \
    --repo "$REPO_SLUG" \
    --json name,value,updatedAt >"$TMP_DIR/variables.json"; then
    require_variable_yes "RIHLA_BACKEND_RELEASE_READY"
    require_variable_yes "RIHLA_APP_CHECK_READY"
    require_variable_yes "RIHLA_REAL_DEVICE_QA_READY"

    approved_sha="$(variable_value "RIHLA_RELEASE_APPROVED_SHA")"
    if [ -z "$approved_sha" ]; then
      fail "RIHLA_RELEASE_APPROVED_SHA is unset; set it to ${TARGET_SHA} only after all release gates pass for that commit"
    elif [ "$approved_sha" = "$TARGET_SHA" ]; then
      pass "RIHLA_RELEASE_APPROVED_SHA matches target commit ${TARGET_SHA}"
    else
      fail "RIHLA_RELEASE_APPROVED_SHA=${approved_sha} does not match target commit ${TARGET_SHA}"
    fi
  else
    fail "Unable to list GitHub repository variables for ${REPO_SLUG}"
  fi
}

check_branch_protection() {
  local protection_json="$TMP_DIR/branch-protection.json"

  if ! gh api \
    "repos/${REPO_SLUG}/branches/${PROTECTED_BRANCH}/protection" \
    >"$protection_json"; then
    fail "${PROTECTED_BRANCH} branch is not protected"
    return
  fi

  pass "${PROTECTED_BRANCH} branch protection is configured"

  if jq -e '.required_status_checks.strict == true' \
    "$protection_json" >/dev/null; then
    pass "Required status checks enforce up-to-date branches"
  else
    fail "Branch protection must require status checks on up-to-date branches"
  fi

  if jq -e '
    .required_status_checks as $checks
    | ($checks != null)
      and (
        (($checks.contexts // []) | index("readiness") != null)
        or (($checks.contexts // []) | index("Readiness Check / readiness") != null)
        or (($checks.checks // []) | map(.context // "") | index("readiness") != null)
        or (($checks.checks // []) | map(.context // "") | index("Readiness Check / readiness") != null)
      )
  ' "$protection_json" >/dev/null; then
    pass "Branch protection requires Readiness Check / readiness"
  else
    fail "Branch protection must require the Readiness Check / readiness status check"
  fi
}

cd "$ROOT_DIR"

require_cmd gh || true
require_cmd jq || true
require_cmd git || true

if [ "$FAILURES" -ne 0 ]; then
  exit 1
fi

if [ -z "$TARGET_SHA" ]; then
  TARGET_SHA="$(git rev-parse HEAD)"
fi

echo "Checking GitHub release governance for ${REPO_SLUG} at ${TARGET_SHA}"

check_release_variables
check_branch_protection

if [ "$FAILURES" -ne 0 ]; then
  echo "GitHub release governance check FAILED (${FAILURES} issue(s))" >&2
  exit 1
fi

echo "GitHub release governance check PASS"
