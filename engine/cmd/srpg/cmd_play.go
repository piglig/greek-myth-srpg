package main

// play：给 Godot 原型用的规则服务。游戏启动时自己拉起它，退出（连接断开）时它跟着结束。

import (
	"flag"
	"fmt"
	"os"
	"time"

	"srpg/play"
)

func init() {
	register("play", "给 Godot 原型提供规则服务：本机 TCP，一问一答（-port -port-file -data-dir -tables -set）", cmdPlay)
}

func cmdPlay(args []string) error {
	fs := flag.NewFlagSet("play", flag.ContinueOnError)
	port := fs.Int("port", 0, "监听 127.0.0.1 上的这个端口（0 = 由系统挑一个）")
	portFile := fs.String("port-file", "", "就绪后把实际端口写进这个文件（游戏用它得知端口）")
	wait := fs.Int("wait", 30, "等客户端连上来的秒数，超时就退出（0 = 一直等）")
	var df dataFlags
	df.register(fs)
	if err := fs.Parse(args); err != nil {
		return err
	}
	data, err := df.load()
	if err != nil {
		return err
	}
	return play.NewServer(data).ListenAndServe(*port, time.Duration(*wait)*time.Second, func(p int) {
		fmt.Fprintf(os.Stdout, "LISTEN %d\n", p)
		if *portFile != "" {
			// 先写临时文件再改名，对方不会读到写了一半的内容
			tmp := *portFile + ".tmp"
			if os.WriteFile(tmp, []byte(fmt.Sprint(p)), 0o644) == nil {
				os.Rename(tmp, *portFile)
			}
		}
	})
}
