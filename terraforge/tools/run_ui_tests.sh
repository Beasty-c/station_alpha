#!/usr/bin/env bash
# Run the TerraForge UI harness against a real window and save screenshots.
# Needs a display; on a headless machine this wraps itself in Xvfb.
#   tools/run_ui_tests.sh [WxH] [output-dir]
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SIZE="${1:-1600x900}"
OUT="${2:-$ROOT/../build/screenshots}"
GODOT="${GODOT:-godot}"
mkdir -p "$OUT"

run() {
  "$GODOT" --path "$ROOT" --rendering-driver opengl3 --resolution "$SIZE" \
    --script res://tests/ui_smoke.gd -- --out="$OUT"
}

if [ -n "${DISPLAY:-}" ]; then
  run
else
  command -v Xvfb >/dev/null || { echo "No DISPLAY and no Xvfb; run this on a desktop."; exit 1; }
  DISP=":$(( (RANDOM % 80) + 40 ))"
  Xvfb "$DISP" -screen 0 "${SIZE}x24" >/dev/null 2>&1 &
  XPID=$!
  sleep 2
  DISPLAY="$DISP" run
  CODE=$?
  kill $XPID 2>/dev/null; wait $XPID 2>/dev/null
  exit $CODE
fi
