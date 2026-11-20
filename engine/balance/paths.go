package balance

import (
	"fmt"
	"os"
	"path/filepath"
)

// Paths 是项目里各目录的位置（对应 Python 版的 paths.py）。
type Paths struct {
	Project   string // 仓库根目录
	Balance   string // balance/
	Prototype string // prototype/（Godot 原型，只在截图预览和默认规则哈希里用到）
	Tables    string // 基线数据表
	Schemas   string
	Specs     string
	Targets   string
	Out       string // balance/out
	Workspace string // balance/workspace
	WebDist   string // balance/web/dist
}

// NewPaths 以仓库根目录推出默认布局。
func NewPaths(project string) Paths {
	b := filepath.Join(project, "balance")
	return Paths{
		Project: project, Balance: b, Prototype: filepath.Join(project, "prototype"),
		Tables:  filepath.Join(project, "prototype", "data", "tables"),
		Schemas: filepath.Join(b, "schemas"), Specs: filepath.Join(b, "specs"), Targets: filepath.Join(b, "targets"),
		Out: filepath.Join(b, "out"), Workspace: filepath.Join(b, "workspace"), WebDist: filepath.Join(b, "web", "dist"),
	}
}

// FindProject 找仓库根目录：$SRPG_PROJECT，否则从当前目录和可执行文件所在目录向上找含 balance/schemas 的目录。
func FindProject() (string, error) {
	if p := os.Getenv("SRPG_PROJECT"); p != "" {
		return filepath.Abs(p)
	}
	var starts []string
	if wd, err := os.Getwd(); err == nil {
		starts = append(starts, wd)
	}
	if exe, err := os.Executable(); err == nil {
		starts = append(starts, filepath.Dir(exe))
	}
	for _, dir := range starts {
		for {
			if st, err := os.Stat(filepath.Join(dir, "balance", "schemas")); err == nil && st.IsDir() {
				return dir, nil
			}
			parent := filepath.Dir(dir)
			if parent == dir {
				break
			}
			dir = parent
		}
	}
	return "", fmt.Errorf("找不到项目根目录（含 balance/schemas）；请在仓库内运行，或设置 SRPG_PROJECT")
}

// SimDir 是某关卡的模拟结果目录；variant 为空表示基线。
func (p Paths) SimDir(battle, variant string) string {
	base := filepath.Join(p.Out, "sim", battle)
	if variant != "" {
		return filepath.Join(base, "variants", variant)
	}
	return base
}

// RunDir 是某个机器人的结果目录（里面是 runs.jsonl 和 meta.json）。
func (p Paths) RunDir(battle, bot, variant string) string {
	return filepath.Join(p.SimDir(battle, variant), bot)
}

// TargetsPath 是关卡的设计目标文件。
func (p Paths) TargetsPath(battle string) string {
	return filepath.Join(p.Targets, battle+".yaml")
}
