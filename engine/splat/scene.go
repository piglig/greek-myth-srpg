package splat

import (
	"encoding/json"
	"fmt"
	"image"
	"image/gif"
	"image/png"
	"os"
	"path/filepath"
	"sync"
)

// Scene 是一张沙盘加上面的角色。静态部分只生成一次。
type Scene struct {
	T      *Terrain
	Static *Splats
	Cast   []Actor
	Lion   *Actor
}

// LoadBattle 读关卡文件。
func LoadBattle(path string) (*Battle, error) {
	raw, err := os.ReadFile(path)
	if err != nil {
		return nil, err
	}
	b := &Battle{}
	if err := json.Unmarshal(raw, b); err != nil {
		return nil, fmt.Errorf("%s: %w", path, err)
	}
	return b, nil
}

// NewScene 按关卡数据搭好沙盘。树、小路和角色的摆放目前写在这里，以后挪进关卡数据。
func NewScene(b *Battle) *Scene {
	t := NewTerrain(b)
	t.Cypress = []Tree{{0.6, 0.7, 2.3}, {1.3, 1.6, 1.9}, {12.9, 0.8, 2.4}, {13.3, 2.2, 1.8}, {0.6, 12.9, 2.1}}
	t.Olive = []Tree{{X: 11.7, Z: 1.5}, {X: 12.6, Z: 9.2}, {X: 1.2, Z: 9.4}}
	sc := &Scene{T: t, Static: &Splats{}}
	sc.Cast = []Actor{
		{X: 6.3, Z: 10.3, Kind: "hero", Face: [2]float32{1, 0.6}, Scale: 1},
		{X: 4.2, Z: 11.6, Kind: "heracles", Face: [2]float32{1, 0.5}, Phase: 1.5, Scale: 1.22},
		{X: 9.2, Z: 11.1, Kind: "atalanta", Face: [2]float32{0.7, 1}, Phase: 3, Scale: 0.96},
	}
	sc.Lion = &Actor{X: 6.6, Z: 4.9, Face: [2]float32{-0.15, 1}, Scale: 1.3}
	for _, a := range sc.Cast {
		t.Cast(a.X, a.Z, 0.3, 0.5)
	}
	t.Cast(6.5, 3.5, 0.75, 0.6)
	t.Scenery(sc.Static)
	t.Build(sc.Static, [][2]float32{{6.5, 13.9}, {6.3, 11}, {4, 9.2}, {2.2, 8.2}, {1.6, 6.6}, {2.2, 4.6}, {3.3, 3.5}})
	t.ScatterPlants()
	return sc
}

// Frame 生成循环时间 t（0..1）那一刻的全部面元。
func (sc *Scene) Frame(t float64, cast []Actor, withLion bool) *Splats {
	d := &Splats{}
	sc.T.Vegetation(d, t)
	Birds(d, t)
	for _, a := range cast {
		sc.T.Figure(d, a, t)
	}
	if withLion && sc.Lion != nil {
		sc.T.Lion(d, sc.Lion.X, sc.Lion.Z, sc.Lion.Face, t, sc.Lion.Scale)
	}
	return Merge(sc.Static, d)
}

// Result 汇报一次导出做了什么。
type Result struct {
	StaticCount, FrameCount int
	Files                   []string
}

// Export 生成 .ply、循环动画和几张单帧图。
func Export(b *Battle, outDir string, frames int) (*Result, error) {
	if err := os.MkdirAll(outDir, 0o755); err != nil {
		return nil, err
	}
	sc := NewScene(b)
	res := &Result{StaticCount: sc.Static.Len()}
	p := func(name string) string {
		f := filepath.Join(outDir, b.ID+name)
		res.Files = append(res.Files, f)
		return f
	}
	if err := WritePLY(p(".ply"), sc.Static); err != nil {
		return nil, err
	}
	vw := DefaultView()
	imgs := make([]*image.Paletted, frames)
	var wg sync.WaitGroup
	sem := make(chan struct{}, 4) // 每帧内部已经并行，这里只限制同时占用的内存
	for i := range imgs {
		wg.Add(1)
		go func() {
			defer wg.Done()
			sem <- struct{}{}
			g := sc.Frame(float64(i)/float64(frames), sc.Cast, true)
			if i == 0 {
				res.FrameCount = g.Len()
			}
			imgs[i] = Render(g, vw)
			<-sem
		}()
	}
	wg.Wait()
	if err := savePNG(p("_x3.png"), Upscale(imgs[0], 3)); err != nil {
		return nil, err
	}
	anim := &gif.GIF{}
	for _, im := range imgs {
		anim.Image = append(anim.Image, Upscale(im, 2))
		anim.Delay = append(anim.Delay, 11)
	}
	f, err := os.Create(p(".gif"))
	if err != nil {
		return nil, err
	}
	if err := gif.EncodeAll(f, anim); err != nil {
		f.Close()
		return nil, err
	}
	f.Close()
	back := vw
	back.Turn = 1
	if err := savePNG(p("_back_x3.png"), Upscale(Render(sc.Frame(0, sc.Cast, true), back), 3)); err != nil {
		return nil, err
	}
	// 神性四阶的近景对照
	var row []Actor
	for k, dv := range []int{0, 1, 3, 4} {
		row = append(row, Actor{X: 4.4 + float32(k)*1.3, Z: 10.6 + float32(k)*0.25, Kind: "hero", Divine: dv, Face: [2]float32{0.35, 1}, Scale: 1})
	}
	near := vw
	near.Center, near.TilePx = V3{6.3, 0.5, 10.8}, 96
	if err := savePNG(p("_divine_x3.png"), Upscale(Render(sc.Frame(0, row, false), near), 3)); err != nil {
		return nil, err
	}
	// 造型检查用的转面图：每个角色四个朝向
	flat := &Battle{ID: "studio"}
	for i := 0; i < 16; i++ {
		flat.Heights = append(flat.Heights, "1111111111111111")
		flat.Terrain = append(flat.Terrain, "................")
	}
	turns := [][2]float32{{1, 1}, {1, -1}, {-1, -1}, {-1, 1}}
	sheet := func(name string, tilePx float32, place func(tr *Terrain) func(d *Splats, t float64)) error {
		ft := NewTerrain(flat)
		draw := place(ft)
		st := &Splats{}
		ft.Build(st, nil)
		v := View{W: 640, H: 360, SS: 2, Center: V3{8, 1.65, 8}, Pivot: [2]float32{8, 8}, TilePx: tilePx}
		shots := make([]*image.Paletted, frames)
		for i := range shots {
			d := &Splats{}
			draw(d, float64(i)/float64(frames))
			shots[i] = Render(Merge(st, d), v)
		}
		if err := savePNG(p(name+"_x3.png"), Upscale(shots[0], 3)); err != nil {
			return err
		}
		return saveGIF(p(name+".gif"), shots, 2)
	}
	err = sheet("_cast", 64, func(tr *Terrain) func(*Splats, float64) {
		var as []Actor
		for r, kind := range []string{"hero", "atalanta", "heracles"} {
			sc := []float32{1, 0.96, 1.2}[r]
			for c, fc := range turns {
				dx, dy := (float32(c)-1.5)*1.9, (float32(r)-1)*3.5
				a := Actor{X: 8 + dx + dy, Z: 8 - dx + dy, Kind: kind, Face: fc, Scale: sc, Phase: float64(c)}
				tr.Cast(a.X, a.Z, 0.3, 0.5)
				as = append(as, a)
			}
		}
		return func(d *Splats, t float64) {
			for _, a := range as {
				tr.Figure(d, a, t)
			}
		}
	})
	if err != nil {
		return nil, err
	}
	err = sheet("_lion", 72, func(tr *Terrain) func(*Splats, float64) {
		type pl struct {
			x, z float32
			f    [2]float32
		}
		var ps []pl
		for i, fc := range turns {
			dx, dy := (float32(i%2)-0.5)*3.4, (float32(i/2)-0.5)*3.8
			ps = append(ps, pl{8 + dx + dy, 8 - dx + dy, fc})
			tr.Cast(8+dx+dy, 8-dx+dy, 0.8, 0.6)
		}
		return func(d *Splats, t float64) {
			for _, q := range ps {
				tr.Lion(d, q.x, q.z, q.f, t, 1.3)
			}
		}
	})
	if err != nil {
		return nil, err
	}
	return res, nil
}

func saveGIF(path string, imgs []*image.Paletted, scale int) error {
	anim := &gif.GIF{}
	for _, im := range imgs {
		anim.Image = append(anim.Image, Upscale(im, scale))
		anim.Delay = append(anim.Delay, 11)
	}
	f, err := os.Create(path)
	if err != nil {
		return err
	}
	defer f.Close()
	return gif.EncodeAll(f, anim)
}

func savePNG(path string, img image.Image) error {
	f, err := os.Create(path)
	if err != nil {
		return err
	}
	defer f.Close()
	return png.Encode(f, img)
}
