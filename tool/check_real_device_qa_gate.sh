#!/usr/bin/env bash
# Checks whether this machine can run physical-device release QA and whether
# the matrix in docs/REAL-DEVICE-QA.md is complete. This does not run the app or
# touch Firebase.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP_FILE="$(mktemp)"
FAILURES=0

cleanup() {
  rm -f "$TMP_FILE"
}
trap cleanup EXIT

pass() {
  echo "PASS: $*"
}

fail() {
  echo "FAIL: $*"
  FAILURES=$((FAILURES + 1))
}

require_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    fail "Missing required command: $1"
    return 1
  fi
}

check_matrix_results() {
  awk -F'|' '
    function trim(value) {
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", value);
      return value;
    }

    function is_placeholder(value) {
      return value == "Group ID or screenshot" \
        || value == "Invite code and joined member name" \
        || value == "Group no longer appears on both devices" \
        || value == "Screenshots from both devices" \
        || value == "Keyboard screenshot and saved amount" \
        || value == "Before/after screenshots" \
        || value == "`fcm_tokens/{uid}` exists" \
        || value == "`fcm_tokens/{uid}` removed";
    }

    /^\| RD-[0-9][0-9] \|/ {
      total += 1;
      id = trim($2);
      ios = trim($4);
      android = trim($5);
      evidence = trim($6);

      if (ios !~ /^Pass([[:space:]]|[-:(]|$)/) {
        print "DETAIL: " id " iOS result is not marked Pass in docs/REAL-DEVICE-QA.md";
        failures += 1;
      }
      if (android !~ /^Pass([[:space:]]|[-:(]|$)/) {
        print "DETAIL: " id " Android result is not marked Pass in docs/REAL-DEVICE-QA.md";
        failures += 1;
      }
      if (evidence == "" || is_placeholder(evidence)) {
        print "DETAIL: " id " evidence is missing or still a placeholder in docs/REAL-DEVICE-QA.md";
        failures += 1;
      }
    }

    END {
      if (total != 8) {
        print "DETAIL: Expected 8 real-device QA matrix rows, found " total;
        failures += 1;
      }
      exit failures > 0 ? 1 : 0;
    }
  ' docs/REAL-DEVICE-QA.md
}

cd "$ROOT_DIR"

require_cmd flutter || true
require_cmd jq || true

if [ "$FAILURES" -ne 0 ]; then
  exit 1
fi

if flutter devices --machine >"$TMP_FILE"; then
  ios_devices="$(jq -r '
    .[]
    | select(.targetPlatform == "ios" and .emulator == false)
    | "\(.name) [\(.id)]"
  ' "$TMP_FILE")"
  android_devices="$(jq -r '
    .[]
    | select((.targetPlatform | startswith("android")) and .emulator == false)
    | "\(.name) [\(.id)]"
  ' "$TMP_FILE")"
  non_physical_mobile="$(jq -r '
    .[]
    | select((.targetPlatform == "ios" or (.targetPlatform | startswith("android"))) and .emulator == true)
    | "\(.name) [\(.targetPlatform), simulator/emulator]"
  ' "$TMP_FILE")"

  if [ -n "$ios_devices" ]; then
    pass "Physical iOS device detected: ${ios_devices//$'\n'/, }"
  else
    fail "No physical iOS device detected"
  fi

  if [ -n "$android_devices" ]; then
    pass "Physical Android device detected: ${android_devices//$'\n'/, }"
  else
    fail "No physical Android device detected"
  fi

  if [ -n "$non_physical_mobile" ]; then
    echo "INFO: Mobile simulators/emulators do not satisfy this gate: ${non_physical_mobile//$'\n'/, }"
  fi
else
  fail "Unable to read Flutter device list"
fi

if [ ! -f config.json ]; then
  fail "Missing config.json"
elif jq -e '.USE_FIREBASE_EMULATOR == true' config.json >/dev/null; then
  fail "config.json has USE_FIREBASE_EMULATOR=true; real-device QA must target production Firebase"
else
  pass "config.json exists and does not enable Firebase emulators"
fi

if [ -f android/app/google-services.json ]; then
  pass "Android Firebase config exists"
else
  fail "Missing android/app/google-services.json"
fi

if [ -f ios/Runner/GoogleService-Info.plist ]; then
  pass "iOS Firebase config exists"
else
  fail "Missing ios/Runner/GoogleService-Info.plist"
fi

if check_matrix_results; then
  pass "Real-device QA matrix is complete"
else
  fail "Real-device QA matrix is incomplete"
fi

if [ "$FAILURES" -ne 0 ]; then
  echo "Real-device QA gate FAILED (${FAILURES} issue(s))"
  exit 1
fi

echo "Real-device QA gate PASS"
