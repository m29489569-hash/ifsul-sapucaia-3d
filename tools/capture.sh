#!/usr/bin/env bash
set -euo pipefail
ITER="${1:-iter-00}"
GODOT_BIN="${GODOT_BIN:-/d/Downloads/Godot_v4.7-stable_win64.exe/Godot_v4.7-stable_win64_console.exe}"
if ! command -v "$GODOT_BIN" >/dev/null 2>&1 && [ ! -f "$GODOT_BIN" ]; then
  GODOT_BIN="godot"
fi
"$GODOT_BIN" --path . --fixed-fps 60 --resolution 1280x720 -s tools/capture.gd -- --iter "$ITER"
