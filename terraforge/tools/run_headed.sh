#!/usr/bin/env bash
# Run a Godot command for TerraForge on a virtual display.
#   tools/run_headed.sh [--size WxH] -- <godot args...>
set -uo pipefail
SIZE="1920x1080"
if [ "${1:-}" = "--size" ]; then SIZE="$2"; shift 2; fi
[ "${1:-}" = "--" ] && shift
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DISP=":$(( (RANDOM % 80) + 40 ))"
Xvfb "$DISP" -screen 0 "${SIZE}x24" >/dev/null 2>&1 &
XPID=$!
sleep 2
DISPLAY="$DISP" godot --path "$ROOT" --rendering-driver opengl3 \
  --resolution "$SIZE" "$@"
CODE=$?
kill $XPID 2>/dev/null; wait $XPID 2>/dev/null
exit $CODE
