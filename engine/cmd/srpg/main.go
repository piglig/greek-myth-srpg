// srpg 是《潘多拉之裔》的统一命令行：战斗规则、模拟、平衡分析、战棋工坊、美术生成都在这一个程序里。
//
// 每组子命令在自己的 cmd_*.go 文件里用 register 注册，互不干扰。
package main

import (
	"fmt"
	"os"
	"sort"
)

type command struct {
	usage string
	run   func(args []string) error
}

var commands = map[string]command{}

func register(name, usage string, run func(args []string) error) {
	commands[name] = command{usage, run}
}

func main() {
	if len(os.Args) < 2 || commands[os.Args[1]].run == nil {
		names := make([]string, 0, len(commands))
		for n := range commands {
			names = append(names, n)
		}
		sort.Strings(names)
		fmt.Fprintln(os.Stderr, "用法: srpg <命令> [参数]")
		for _, n := range names {
			fmt.Fprintf(os.Stderr, "  %-12s %s\n", n, commands[n].usage)
		}
		os.Exit(2)
	}
	if err := commands[os.Args[1]].run(os.Args[2:]); err != nil {
		fmt.Fprintln(os.Stderr, "错误:", err)
		os.Exit(1)
	}
}
