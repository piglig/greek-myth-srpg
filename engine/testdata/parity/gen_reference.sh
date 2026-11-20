#!/usr/bin/env bash
# 用 Godot 原版引擎生成对拍基准行（每个进程跑一段种子，最后按种子顺序拼接）。
# 注意：原 GDScript 引擎已从 prototype/ 移除，存档在同目录的 gdscript_engine.zip。
# 要重新生成基准，先把存档解压回工程（覆盖 prototype/ 下的同名文件）。
# 用法: gen_reference.sh <battle> <bot> <seeds> [每进程种子数=10]
set -u
HERE="$(cd "$(dirname "$0")" && pwd -W 2>/dev/null || pwd)"
GODOT="${GODOT:-/d/golang/cloudbound-isles/.tools/godot/Godot_v4.7.2-stable_win64_console.exe}"
PROTO="$HERE/../../../prototype"
battle="$1"; bot="$2"; seeds="$3"; chunk="${4:-10}"
mkdir -p "$HERE/parts"
pids=()
for ((s = 0; s < seeds; s += chunk)); do
	n=$chunk; ((s + n > seeds)) && n=$((seeds - s))
	part=$(printf "%s/parts/%s_%s_%04d.jsonl" "$HERE" "$battle" "$bot" "$s")
	"$GODOT" --headless --path "$PROTO" --script res://tools/simulate.gd -- \
		--battle="$battle" --bot="$bot" --runs="$n" --seed="$s" --out="$part" >"$part.log" 2>&1 &
	pids+=($!)
done
wait "${pids[@]}"
cat "$HERE"/parts/"${battle}_${bot}"_*.jsonl >"$HERE/godot_${battle}_${bot}.jsonl"
wc -l "$HERE/godot_${battle}_${bot}.jsonl"
