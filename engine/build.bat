@echo off
rem 构建规则引擎和工具：enginein\srpg.exe。Godot 原型启动时会拉起它（srpg play）。
cd /d "%~dp0"
go build -o bin\srpg.exe .\cmd\srpg || exit /b 1
echo built bin\srpg.exe
