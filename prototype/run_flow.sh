#!/usr/bin/env bash
# Walks the whole game from a new save to the second chapter and checks the save after
# every step (tests/flow/campaign_flow.gd). Uses a save file of its own.
# Set GODOT to override the engine path. Pass --window to watch it instead of running headless.
set -u
cd "$(dirname "$0")"
GODOT="${GODOT:-/d/golang/cloudbound-isles/.tools/godot/Godot_v4.7.2-stable_win64_console.exe}"
mode="--headless"
[ "${1:-}" = "--window" ] && mode="--resolution 1280x720"
"$GODOT" $mode --path . -- --flow 2>&1 | grep -E "^\[flow\]|SCRIPT ERROR|ERROR:|   at: " | grep -v -E "leaked|in use at exit|_free_rids|Unreferenced"
exit ${PIPESTATUS[0]}
