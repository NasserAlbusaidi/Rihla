#!/usr/bin/env bash
# Checks whether this machine is ready to run the physical-device release QA
# matrix in docs/REAL-DEVICE-QA.md. This does not run the app or touch Firebase.
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

if [ "$FAILURES" -ne 0 ]; then
  echo "Real-device QA gate FAILED (${FAILURES} issue(s))"
  exit 1
fi

echo "Real-device QA gate PASS"
