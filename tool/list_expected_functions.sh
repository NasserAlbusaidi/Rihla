#!/usr/bin/env bash
# Prints, one per line, the Cloud Function names that functions/src/index.ts
# re-exports — the set that MUST be deployed. Single source of truth shared by
# tool/check_firebase_prod_state.sh and locked by
# test/unit/release_workflow_gate_test.dart.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
INDEX_FILE="${1:-$ROOT_DIR/functions/src/index.ts}"

# Capture every identifier inside an `export { ... }` re-export block. Handles
# BOTH single-line `export { foo } from '...'` and multi-line
#   export {
#     foo,
#     bar,
#   } from '...';
# The previous single-line `sed` silently dropped multi-line blocks (#53
# notifiers, #198 monitors), undercounting the deploy set. Do NOT revert to a
# one-line regex — locked by test/unit/release_workflow_gate_test.dart.
awk '
  /^export[[:space:]]*\{/ { capturing = 1 }
  capturing {
    line = $0
    sub(/^export[[:space:]]*\{/, "", line)
    closed = 0
    if (index(line, "}") > 0) { sub(/\}.*/, "", line); closed = 1 }
    n = split(line, parts, /[[:space:],]+/)
    for (i = 1; i <= n; i++) {
      if (parts[i] ~ /^[A-Za-z_$][A-Za-z0-9_$]*$/) print parts[i]
    }
    if (closed) capturing = 0
  }
' "$INDEX_FILE" | sort -u
