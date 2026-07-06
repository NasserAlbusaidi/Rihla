#!/usr/bin/env bash
# Runs the release-readiness gates that can be checked from this machine.
# This script is read-only with respect to Firebase production: it lists and
# compares deployed state, but it does not deploy or enable APIs.
#
# Env vars:
#   RIHLA_CONFIRM_APP_CHECK_READY=yes  Confirms Firebase App Check Console
#                                      enrollment before release.
#   RIHLA_SKIP_IOS_QA=yes             Runs the real-device QA gate in
#                                      Android-only mode for the current
#                                      Google Play launch. Unset this when
#                                      iOS ships.
set -uo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
JAVA21_HOME="${JAVA21_HOME:-}"
FAILURES=0

pass() {
  echo "PASS: $*"
}

fail() {
  echo "FAIL: $*"
  FAILURES=$((FAILURES + 1))
}

run_step() {
  local name="$1"
  shift

  echo
  echo "==> ${name}"
  if "$@"; then
    pass "$name"
  else
    fail "$name"
  fi
}

require_cmd() {
  command -v "$1" >/dev/null 2>&1
}

npm22() {
  local npm_cli
  npm_cli="$(command -v npm || true)"
  if [ -z "$npm_cli" ]; then
    echo "npm not found"
    return 1
  fi

  npx --yes node@22 "$npm_cli" "$@"
}

node22_available() {
  npx --yes node@22 -e 'const major = Number(process.versions.node.split(".")[0]); console.log(process.version); process.exit(major === 22 ? 0 : 1);'
}

setup_java21() {
  if [ -z "$JAVA21_HOME" ]; then
    if require_cmd brew; then
      JAVA21_HOME="$(brew --prefix openjdk@21 2>/dev/null)/libexec/openjdk.jdk/Contents/Home"
    else
      return 1
    fi
  fi

  if [ ! -x "$JAVA21_HOME/bin/java" ]; then
    echo "Java 21 not found at JAVA21_HOME=${JAVA21_HOME}"
    return 1
  fi

  export JAVA_HOME="$JAVA21_HOME"
  export PATH="$JAVA_HOME/bin:$PATH"
  java -version 2>&1 | grep -q 'version "21'
}

check_raw_coverage() {
  local coverage
  local summary
  summary="$(lcov --summary coverage/lcov.info 2>&1)"
  echo "$summary"
  coverage="$(printf '%s\n' "$summary" \
    | awk '/lines/ && /%/ { for (i = 1; i <= NF; i++) if ($i ~ /^[0-9.]+%$/) { gsub("%", "", $i); print $i; exit } }')"

  if [ -z "$coverage" ]; then
    echo "Unable to read line coverage from coverage/lcov.info"
    return 1
  fi

  echo "Raw coverage: ${coverage}%"
  awk -v coverage="$coverage" 'BEGIN { exit (coverage >= 80.0) ? 0 : 1 }'
}

# Diff/new-code coverage floor: lines changed relative to origin/main must clear
# a higher bar (90%) than the repo-wide 80% aggregate above, so an under-tested
# new module can't merge on the healthy baseline. Mirrors the CI step in
# .github/workflows/readiness_check.yml. diff-cover ignores diff lines with no
# coverage data, so an assets-only / docs-only tree passes vacuously.
check_diff_coverage() {
  if ! require_cmd diff-cover; then
    echo "WARNING: diff-cover is not installed locally; skipping the diff coverage floor."
    echo "         CI enforces it (readiness_check.yml, --fail-under=90). Install with: pipx install diff-cover"
    return 0
  fi

  if ! git rev-parse --verify --quiet origin/main >/dev/null 2>&1; then
    echo "WARNING: origin/main is not available locally; skipping the diff coverage floor."
    echo "         Run 'git fetch origin main' so diff-cover can compute the merge-base."
    return 0
  fi

  diff-cover coverage/lcov.info --compare-branch=origin/main --fail-under=90
}

check_app_check_enforced() {
  if grep -R "TODO: enforce App Check" functions/src lib >/dev/null 2>&1; then
    echo "App Check public-launch TODO is still present."
    return 1
  fi

  if ! grep -R "enforceAppCheck\\|request\\.app" functions/src >/dev/null 2>&1; then
    echo "No callable App Check enforcement marker found in functions/src."
    return 1
  fi
}

check_app_check_enrollment_confirmed() {
  if [ "${RIHLA_CONFIRM_APP_CHECK_READY:-}" != "yes" ]; then
    echo "Firebase App Check Console enrollment is not confirmed."
    echo "Run with RIHLA_CONFIRM_APP_CHECK_READY=yes only after Android and iOS App Check enrollment is complete."
    return 1
  fi
}

cd "$ROOT_DIR"

if [ "${RIHLA_SKIP_IOS_QA:-}" = "yes" ]; then
  echo "INFO: RIHLA_SKIP_IOS_QA=yes - real-device QA will run in Android-only mode."
fi

run_step "Java 21 available" setup_java21
run_step "Node 22 available for Functions commands" node22_available
run_step "Functions dependencies install from lockfile" npm22 --prefix functions ci
run_step "Functions dependency audit at low severity" npm22 --prefix functions audit --omit=dev --audit-level=low
run_step "Functions TypeScript build" npm22 --prefix functions run build
run_step "App Check enforcement configured" check_app_check_enforced
run_step "App Check Console enrollment confirmed" check_app_check_enrollment_confirmed
run_step "Firebase emulator rules/functions tests" bash tool/run_firebase_emulator_tests.sh
run_step "Flutter analyzer" flutter analyze --no-fatal-infos
run_step "Theme purity check" bash tool/check_theme_purity.sh
run_step "Navigation smoke tests" \
  flutter test \
    test/unit/app_router_test.dart \
    test/helpers/navigation_test.dart \
    test/unit/deep_link_service_test.dart \
    test/unit/auth_link_hosting_files_test.dart \
    test/features/activity/activity_feed_screen_test.dart \
    test/features/groups/qr_invite_sheet_test.dart \
    test/features/groups/group_detail_navigation_test.dart \
    test/features/events/event_command_center_test.dart \
    test/features/ledger/ledger_screen_overflow_test.dart
run_step "Flutter tests with coverage" \
  flutter test --coverage \
    test/architecture \
    test/core \
    test/features \
    test/helpers \
    test/integration \
    test/shared \
    test/unit \
    test/widget_test.dart
run_step "Raw coverage threshold" check_raw_coverage
run_step "Diff coverage floor" check_diff_coverage
run_step "Android release app bundle" \
  flutter build appbundle \
    --release \
    --obfuscate \
    --split-debug-info=./build/app/outputs/symbols \
    --dart-define-from-file=config.json \
    --android-skip-build-dependency-validation
run_step "Firebase production state" bash tool/check_firebase_prod_state.sh rihla-safar
run_step "Real-device QA gate" bash tool/check_real_device_qa_gate.sh
run_step "GitHub release governance" bash tool/check_github_release_governance.sh

echo
if [ "$FAILURES" -ne 0 ]; then
  echo "Release readiness FAILED (${FAILURES} issue(s))"
  exit 1
fi

echo "Release readiness PASS"
