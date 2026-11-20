#!/usr/bin/env bash
# 生成带额外参数（--data-dir / --set / --picks）的 Godot 基准行。
# 注意：原 GDScript 引擎已从 prototype/ 移除，存档在同目录的 gdscript_engine.zip。
# 要重新生成基准，先把存档解压回工程（覆盖 prototype/ 下的同名文件）。
# 用法: gen_variant.sh <输出名> <battle> <bot> <seeds> [传给 simulate.gd 的额外参数...]
set -u
HERE="$(cd "$(dirname "$0")" && pwd -W 2>/dev/null || pwd)"
GODOT="${GODOT:-/d/golang/cloudbound-isles/.tools/godot/Godot_v4.7.2-stable_win64_console.exe}"
name="$1"; battle="$2"; bot="$3"; seeds="$4"; shift 4
"$GODOT" --headless --path "$HERE/../../../prototype" --script res://tools/simulate.gd -- \
	--battle="$battle" --bot="$bot" --runs="$seeds" --seed=0 --out="$HERE/$name.jsonl" "$@" >"$HERE/$name.log" 2>&1
wc -l "$HERE/$name.jsonl"
