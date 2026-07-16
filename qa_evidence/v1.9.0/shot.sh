#!/usr/bin/env bash
# Screenshot helper: ./shot.sh <A|B> <label>   -> qa_evidence/v1.9.0/screens/<label>.png
set -euo pipefail
A=4C171FDAS001U0
B=RF8N213CZWK
dev=$1; label=$2
case "$dev" in A) id=$A;; B) id=$B;; *) id=$dev;; esac
out="$(dirname "$0")/screens/${label}.png"
adb -s "$id" exec-out screencap -p > "$out"
echo "saved $out ($(du -h "$out" | cut -f1))"
