#!/usr/bin/env bash
# Runs the release-readiness gates that can be checked from this machine.
# This script is read-only with respect to Firebase production: it lists and
# compares deployed state, but it does not deploy or enable APIs.
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
  coverage="$(lcov --summary coverage/lcov.info 2>&1 \
    | awk '/lines\.\.\.\.\.\.\.:/ { gsub("%", "", $2); print $2; exit }')"

  if [ -z "$coverage" ]; then
    echo "Unable to read line coverage from coverage/lcov.info"
    return 1
  fi

  echo "Raw coverage: ${coverage}%"
  awk -v coverage="$coverage" 'BEGIN { exit (coverage >= 80.0) ? 0 : 1 }'
}

cd "$ROOT_DIR"

run_step "Java 21 available" setup_java21
run_step "Functions dependencies install from lockfile" npm --prefix functions ci
run_step "Functions dependency audit at low severity" npm --prefix functions audit --omit=dev --audit-level=low
run_step "Functions TypeScript build" npm --prefix functions run build
run_step "Firebase emulator rules/functions tests" \
  npx --yes firebase-tools@15.8.0 emulators:exec \
    --project rihla-safar-test \
    --only auth,firestore,storage \
    "cd functions && npx --yes node@20 node_modules/jest/bin/jest.js --runInBand"
run_step "Flutter analyzer" flutter analyze --no-fatal-infos
run_step "Theme purity check" bash tool/check_theme_purity.sh
run_step "Flutter tests with coverage" flutter test --coverage --exclude-tags golden
run_step "Raw coverage threshold" check_raw_coverage
run_step "Android release app bundle" \
  flutter build appbundle \
    --release \
    --obfuscate \
    --split-debug-info=./build/app/outputs/symbols \
    --dart-define-from-file=config.json \
    --android-skip-build-dependency-validation
run_step "Firebase production state" bash tool/check_firebase_prod_state.sh rihla-safar
run_step "Real-device QA gate" bash tool/check_real_device_qa_gate.sh

echo
if [ "$FAILURES" -ne 0 ]; then
  echo "Release readiness FAILED (${FAILURES} issue(s))"
  exit 1
fi

echo "Release readiness PASS"
