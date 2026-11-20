#!/usr/bin/env bash
# Runs the gdUnit4 rule tests headless. JUnit/HTML reports go to reports/.
# Set GODOT to override the engine path.
set -u
cd "$(dirname "$0")"
GODOT="${GODOT:-/d/golang/cloudbound-isles/.tools/godot/Godot_v4.7.2-stable_win64_console.exe}"
"$GODOT" --headless --path . --import >/dev/null 2>&1
"$GODOT" --headless --path . -s -d --remote-debug tcp://127.0.0.1:0 \
	res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests -rd reports -rc 3 "$@"
code=$?
"$GODOT" --headless --path . --quiet -s res://addons/gdUnit4/bin/GdUnitCopyLog.gd -rd reports >/dev/null 2>&1
exit $code
