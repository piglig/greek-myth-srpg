package main

import (
	"flag"
	"fmt"
	"time"

	"srpg/splat"
)

func init() {
	register("palette", "导出调色板文件（.hex、.gpl、说明表、色卡图）到 art/palette", func(args []string) error {
		fs := flag.NewFlagSet("palette", flag.ContinueOnError)
		out := fs.String("out", "../art/palette", "输出目录")
		if err := fs.Parse(args); err != nil {
			return err
		}
		files, err := splat.WritePalette(*out)
		for _, f := range files {
			fmt.Println(" ", f)
		}
		return err
	})
	register("splat", "从关卡数据生成像素风格的高斯泼溅沙盘和预览图", func(args []string) error {
		fs := flag.NewFlagSet("splat", flag.ContinueOnError)
		battle := fs.String("battle", "../prototype/data/tables/battles/1-5.json", "关卡文件")
		out := fs.String("out", "../art/splatgen/out", "输出目录")
		frames := fs.Int("frames", 16, "循环动画的帧数")
		if err := fs.Parse(args); err != nil {
			return err
		}
		b, err := splat.LoadBattle(*battle)
		if err != nil {
			return err
		}
		t0 := time.Now()
		res, err := splat.Export(b, *out, *frames)
		if err != nil {
			return err
		}
		fmt.Printf("静态高斯 %d 个，每帧共 %d 个，%d 帧，用时 %.2f 秒\n", res.StaticCount, res.FrameCount, *frames, time.Since(t0).Seconds())
		for _, f := range res.Files {
			fmt.Println(" ", f)
		}
		return nil
	})
}
