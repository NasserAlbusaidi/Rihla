#!/usr/bin/env bash
# Checks whether this machine can run physical-device release QA and whether
# the matrix in docs/REAL-DEVICE-QA.md is complete. This does not run the app or
# touch Firebase.
#
# Env vars:
#   RIHLA_SKIP_IOS_QA=yes  Soft-defer iOS for the v1.2 Android-only launch.
#                          iOS device absence is downgraded to INFO and matrix
#                          iOS cells must read "Deferred ..." or "Pass ...".
#                          Unset (the default) re-enables the strict iOS+Android
#                          gate for when iOS ships.
#   RIHLA_SINGLE_DEVICE_QA_OK=yes
#                          Explicit override: accept a SINGLE physical Android
#                          device for the RD-04 two-device pass when that QA is
#                          deliberately deferred to pre-promotion testing on the
#                          Play "first" track. Unset (the default) keeps the
#                          strict two-device gate.
#   RIHLA_REAL_DEVICE_QA_DOC
#                          Optional test-only override for the QA matrix file.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP_FILE="$(mktemp)"
FAILURES=0
SKIP_IOS_QA="${RIHLA_SKIP_IOS_QA:-}"
QA_DOC="${RIHLA_REAL_DEVICE_QA_DOC:-docs/REAL-DEVICE-QA.md}"

if [ "$SKIP_IOS_QA" = "yes" ]; then
  echo "INFO: RIHLA_SKIP_IOS_QA=yes — running in Android-only mode (iOS soft-deferred for v1.2)."
fi

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
  awk -F'|' -v skip_ios="${SKIP_IOS_QA:-}" '
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
        || value == "`fcm_tokens/{uid}` removed" \
        || value == "Arabic RTL screenshots and golden-path log";
    }

    function evidence_has_build_trace(value, lower) {
      lower = tolower(value);
      return lower ~ /(commit|sha-256|sha256|apk|aab|app-release)/ \
        || lower ~ /play[[:space:]-]*(track|build|testing|internal|closed|open|production)/ \
        || lower ~ /track[[:space:]-]*(build|version)/ \
        || lower ~ /build[[:space:]-]*(number|version|code)/ \
        || value ~ /[0-9a-fA-F]{12,}/;
    }

    /^\| RD-[0-9][0-9] \|/ {
      total += 1;
      id = trim($2);
      ios = trim($4);
      android = trim($5);
      evidence = trim($6);

      if (skip_ios == "yes") {
        if (ios !~ /^(Pass|Deferred)([[:space:]]|[-:(]|$)/) {
          print "DETAIL: " id " iOS result must be \"Pass ...\" or \"Deferred ...\" in docs/REAL-DEVICE-QA.md (RIHLA_SKIP_IOS_QA=yes)";
          failures += 1;
        }
      } else {
        if (ios !~ /^Pass([[:space:]]|[-:(]|$)/) {
          print "DETAIL: " id " iOS result is not marked Pass in docs/REAL-DEVICE-QA.md";
          failures += 1;
        }
      }
      if (android !~ /^Pass([[:space:]]|[-:(]|$)/) {
        print "DETAIL: " id " Android result is not marked Pass in docs/REAL-DEVICE-QA.md";
        failures += 1;
      }
      if (evidence == "" || is_placeholder(evidence)) {
        print "DETAIL: " id " evidence is missing or still a placeholder in docs/REAL-DEVICE-QA.md";
        failures += 1;
      } else if (!evidence_has_build_trace(evidence)) {
        print "DETAIL: " id " evidence does not include build traceability in docs/REAL-DEVICE-QA.md";
        failures += 1;
      }
    }

    END {
      if (total != 9) {
        print "DETAIL: Expected 9 real-device QA matrix rows, found " total;
        failures += 1;
      }
      exit failures > 0 ? 1 : 0;
    }
  ' "$QA_DOC"
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
  android_device_count="$(jq '
    [
      .[]
      | select((.targetPlatform | startswith("android")) and .emulator == false)
    ]
    | length
  ' "$TMP_FILE")"
  non_physical_mobile="$(jq -r '
    .[]
    | select((.targetPlatform == "ios" or (.targetPlatform | startswith("android"))) and .emulator == true)
    | "\(.name) [\(.targetPlatform), simulator/emulator]"
  ' "$TMP_FILE")"

  if [ -n "$ios_devices" ]; then
    pass "Physical iOS device detected: ${ios_devices//$'\n'/, }"
  elif [ "$SKIP_IOS_QA" = "yes" ]; then
    echo "INFO: No physical iOS device — skipped (RIHLA_SKIP_IOS_QA=yes)"
  else
    fail "No physical iOS device detected"
  fi

  if [ "$SKIP_IOS_QA" = "yes" ]; then
    if [ "$android_device_count" -ge 2 ]; then
      pass "Physical Android devices detected for Android-only two-device QA: ${android_devices//$'\n'/, }"
    elif [ "$android_device_count" -eq 1 ]; then
      if [ "${RIHLA_SINGLE_DEVICE_QA_OK:-}" = "yes" ]; then
        pass "Single Android device accepted (RIHLA_SINGLE_DEVICE_QA_OK=yes): two-device RD-04 QA deferred to pre-promotion testing on the Play 'first' track; detected: ${android_devices//$'\n'/, }"
      else
        fail "At least two physical Android devices required when RIHLA_SKIP_IOS_QA=yes for RD-04; detected: ${android_devices//$'\n'/, }"
      fi
    else
      fail "No physical Android device detected"
    fi
  elif [ -n "$android_devices" ]; then
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
