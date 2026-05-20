#!/usr/bin/env bash
# Prints the current Android-only physical-device QA handoff without touching
# devices, Firebase, or GitHub state.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APK_PATH="build/app/outputs/flutter-apk/app-release.apk"
AAB_PATH="build/app/outputs/bundle/release/app-release.aab"

cd "$ROOT_DIR"

echo "Rihla Android-only QA handoff"
echo
echo "Branch: $(git rev-parse --abbrev-ref HEAD)"
echo "Commit: $(git rev-parse HEAD)"
echo

if [ -f "$APK_PATH" ] && [ -f "$AAB_PATH" ]; then
  echo "Artifacts:"
  shasum -a 256 "$APK_PATH" "$AAB_PATH"
else
  echo "Artifacts: missing"
  echo "Build them first:"
  echo "  flutter build apk --release --dart-define-from-file=config.json --android-skip-build-dependency-validation"
  echo "  flutter build appbundle --release --obfuscate --split-debug-info=./build/app/outputs/symbols --dart-define-from-file=config.json --android-skip-build-dependency-validation"
fi

echo
echo "Install on two physical Android devices:"
echo "  adb devices"
echo "  adb -s <android-device-id-1> install -r $APK_PATH"
echo "  adb -s <android-device-id-2> install -r $APK_PATH"
echo
echo "After filling docs/REAL-DEVICE-QA.md RD-01 through RD-09:"
echo "  RIHLA_SKIP_IOS_QA=yes bash tool/check_real_device_qa_gate.sh"
