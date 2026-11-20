package splat

import (
	"fmt"
	"image"
	"os"
	"path/filepath"
	"strings"
)

// 调色板每种颜色的中文名和用途，和上面的常量顺序一致。
var colorInfo = [nColors][3]string{
	{"bone", "骨白", "最亮的高光、眼白、牙、文字"},
	{"plaster", "灰泥白", "地面亮部、界面底色、女性肤色的中间档"},
	{"plaster_d", "灰泥暗", "地面暗部、受光的墙面"},
	{"plaster_dd", "灰泥深", "背光的墙面、地面的影子"},
	{"plaster_ddd", "灰泥褐", "墙根、折线、岩石暗部"},
	{"stone", "石色", "最深的石头、洞口内侧"},
	{"red", "赭红", "凡人的衣饰、饰带、青铜、敌方标识"},
	{"red_d", "深赭红", "赭红的暗部、口腔、深色鬃毛"},
	{"yellow", "赭黄", "金、秋草、狮子皮毛亮部"},
	{"earth", "土黄", "赭黄的暗部、木头、皮革"},
	{"earth_d", "深土黄", "土黄的暗部、牛皮斑"},
	{"blue", "埃及蓝", "神：神力、圣物、高神性主角；我方标识"},
	{"blue_d", "深蓝", "埃及蓝的暗部、背景"},
	{"blue_l", "浅蓝", "埃及蓝的亮部、水面、银器"},
	{"green_l", "浅绿", "植物亮部"},
	{"green", "孔雀石绿", "植物、毒"},
	{"green_d", "深绿", "植物暗部"},
	{"black", "矿物黑", "勾线、头发、瞳孔"},
	{"skin_l", "肤赭亮", "男性肤色亮部"},
	{"skin", "肤赭", "男性肤色"},
	{"skin_d", "肤赭暗", "男性肤色暗部"},
}

// WritePalette 把调色板导出成几种通用格式：.hex（每行一个色值）、.gpl（GIMP / Aseprite）、.md（带用途的表）、色卡图。
func WritePalette(dir string) ([]string, error) {
	if err := os.MkdirAll(dir, 0o755); err != nil {
		return nil, err
	}
	var hex, gpl, md strings.Builder
	gpl.WriteString("GIMP Palette\nName: Pandora 21\nColumns: 7\n#\n")
	md.WriteString("| 编号 | 名称 | 色值 | 用途 |\n|---|---|---|---|\n")
	for i, h := range hexes {
		fmt.Fprintf(&hex, "%06x\n", h)
		fmt.Fprintf(&gpl, "%3d %3d %3d\t%s\n", h>>16&255, h>>8&255, h&255, colorInfo[i][0])
		fmt.Fprintf(&md, "| %d | %s `%s` | `#%06X` | %s |\n", i, colorInfo[i][1], colorInfo[i][0], h, colorInfo[i][2])
	}
	const cell, cols = 48, 7
	rows := (int(nColors) + cols - 1) / cols
	img := image.NewPaletted(image.Rect(0, 0, cols*cell, rows*cell), Palette())
	for y := 0; y < rows*cell; y++ {
		for x := 0; x < cols*cell; x++ {
			i := (y/cell)*cols + x/cell
			if i >= int(nColors) {
				i = int(Black)
			}
			img.Pix[y*img.Stride+x] = uint8(i)
		}
	}
	files := map[string]string{"pandora-21.hex": hex.String(), "pandora-21.gpl": gpl.String(), "pandora-21.md": md.String()}
	var out []string
	for name, body := range files {
		p := filepath.Join(dir, name)
		if err := os.WriteFile(p, []byte(body), 0o644); err != nil {
			return nil, err
		}
		out = append(out, p)
	}
	p := filepath.Join(dir, "pandora-21.png")
	out = append(out, p)
	return out, savePNG(p, img)
}
