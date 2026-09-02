#!/usr/bin/env bash
# Run the TerraForge domain test suite headlessly.
#   tools/run_tests.sh [-v]
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
GODOT="${GODOT:-godot}"
"$GODOT" --headless --path "$ROOT" --import >/dev/null 2>&1 || true
exec "$GODOT" --headless --path "$ROOT" --script res://tests/run_tests.gd -- "$@"
