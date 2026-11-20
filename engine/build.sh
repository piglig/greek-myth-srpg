#!/usr/bin/env bash
# 构建规则引擎和工具：engine/bin/srpg(.exe)。Godot 原型启动时会拉起它（srpg play）。
set -eu
cd "$(dirname "$0")"
exe=srpg
case "$(go env GOOS)" in windows) exe=srpg.exe ;; esac
go build -o "bin/$exe" ./cmd/srpg
echo "built bin/$exe"
