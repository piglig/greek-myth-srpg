// Package splat 用程序直接生成"像素风格"的 3D 高斯泼溅，并把它渲染成像素画。
//
// 每个高斯都是贴在表面上的小圆片（面元），颜色是调色板里的一个编号，明暗是分档的。
// 静态的地形只生成一次；会动的东西（草、树冠、角色、狮子、鸟）每帧重新生成。
package splat

import (
	"math"
	"math/rand/v2"
)

// ---------- 向量 ----------

type V3 [3]float32

func (a V3) Add(b V3) V3      { return V3{a[0] + b[0], a[1] + b[1], a[2] + b[2]} }
func (a V3) Sub(b V3) V3      { return V3{a[0] - b[0], a[1] - b[1], a[2] - b[2]} }
func (a V3) Mul(k float32) V3 { return V3{a[0] * k, a[1] * k, a[2] * k} }
func (a V3) Dot(b V3) float32 { return a[0]*b[0] + a[1]*b[1] + a[2]*b[2] }
func (a V3) Cross(b V3) V3 {
	return V3{a[1]*b[2] - a[2]*b[1], a[2]*b[0] - a[0]*b[2], a[0]*b[1] - a[1]*b[0]}
}
func (a V3) Len() float32 { return float32(math.Sqrt(float64(a.Dot(a)))) }
func (a V3) Unit() V3 {
	l := a.Len()
	if l < 1e-9 {
		return a
	}
	return a.Mul(1 / l)
}

// ---------- 调色板（21 §2，加了几档中间色） ----------

const (
	Bone uint8 = iota
	Plaster
	PlasterD
	PlasterDD
	PlasterDDD
	Stone
	Red
	RedD
	Yellow
	Earth
	EarthD
	Blue
	BlueD
	BlueL
	GreenL
	Green
	GreenD
	Black
	SkinL
	Skin
	SkinD
	nColors
)

var hexes = [nColors]uint32{
	0xF7F3EA, 0xEDE6D6, 0xCFC4AD, 0xB0A48A, 0x857A66, 0x5E5548,
	0xA8432D, 0x6E2A1E, 0xD9A441, 0xB07D2E, 0x855A1F,
	0x2F6FB0, 0x1B3F6E, 0x8DB8D9,
	0x8DB36E, 0x4E8C5A, 0x2E5A3A, 0x1E1A1A,
	0xD98A55, 0xC06A3E, 0x8E4528,
}

// Pal 是调色板的 RGB（0..1）。
var Pal [nColors][3]float32

// Dark、Lighter：每种颜色暗一档、亮一档是哪种颜色。
var Dark = [nColors]uint8{
	Bone: Plaster, Plaster: PlasterD, PlasterD: PlasterDD, PlasterDD: PlasterDDD, PlasterDDD: Stone, Stone: Black,
	Red: RedD, RedD: Black, Yellow: Earth, Earth: EarthD, EarthD: RedD, Blue: BlueD, BlueL: Blue, BlueD: BlueD,
	GreenL: Green, Green: GreenD, GreenD: GreenD, Black: Black, SkinL: Skin, Skin: SkinD, SkinD: RedD,
}
var Lighter [nColors]uint8

func init() {
	for i, h := range hexes {
		Pal[i] = [3]float32{float32(h>>16&255) / 255, float32(h>>8&255) / 255, float32(h&255) / 255}
		Lighter[i] = uint8(i)
	}
	Lighter[PlasterD], Lighter[PlasterDD], Lighter[PlasterDDD], Lighter[Plaster] = Plaster, PlasterD, PlasterDD, Bone
}

// ---------- 全局尺度 ----------

const (
	R    = 24      // 每格的采样数
	D    = 1.0 / R // 面元间距
	LV   = 0.75    // 每层高度（格），只影响画面
	Base = -0.8    // 沙盘底座的底面
	Tau  = 2 * math.Pi
)

var (
	Light = V3{-0.25, 0.75, 0.6}.Unit()
	Up    = V3{0, 1, 0}
)

func sin(x float64) float32 { return float32(math.Sin(x)) }
func cos(x float64) float32 { return float32(math.Cos(x)) }

// ---------- 面元集合 ----------

type Splats struct {
	P, N    []V3
	C       []uint8   // 调色板编号
	S, T, O []float32 // 面内半径、厚度、不透明度
	M       []uint8   // 1 = 角色（用来画外轮廓）
}

const (
	defS  = D * 0.62
	defT  = D * 0.12
	defOp = 0.97
)

func (s *Splats) Add(p, n V3, c uint8)        { s.AddX(p, n, c, defS, defT, 0) }
func (s *Splats) AddM(p, n V3, c, mask uint8) { s.AddX(p, n, c, defS, defT, mask) }
func (s *Splats) AddX(p, n V3, c uint8, sz, th float32, mask uint8) {
	s.P = append(s.P, p)
	s.N = append(s.N, n)
	s.C = append(s.C, c)
	s.S = append(s.S, sz)
	s.T = append(s.T, th)
	s.O = append(s.O, defOp)
	s.M = append(s.M, mask)
}
func (s *Splats) Len() int { return len(s.P) }

// Merge 返回 a 后面接 b 的新集合（不改动 a）。
func Merge(a, b *Splats) *Splats {
	return &Splats{
		P: append(append(make([]V3, 0, len(a.P)+len(b.P)), a.P...), b.P...),
		N: append(append(make([]V3, 0, len(a.N)+len(b.N)), a.N...), b.N...),
		C: append(append(make([]uint8, 0, len(a.C)+len(b.C)), a.C...), b.C...),
		S: append(append(make([]float32, 0, len(a.S)+len(b.S)), a.S...), b.S...),
		T: append(append(make([]float32, 0, len(a.T)+len(b.T)), a.T...), b.T...),
		O: append(append(make([]float32, 0, len(a.O)+len(b.O)), a.O...), b.O...),
		M: append(append(make([]uint8, 0, len(a.M)+len(b.M)), a.M...), b.M...),
	}
}

// ---------- 上色 ----------

// Tone 是一组按受光分档的颜色：3 个是（亮、中、暗），2 个是（中、暗）。
type Tone []uint8

func (t Tone) At(n V3) uint8 {
	d := n.Dot(Light)
	if len(t) == 2 {
		if d > 0.12 {
			return t[0]
		}
		return t[1]
	}
	switch {
	case d > 0.62:
		return t[0]
	case d > 0.12:
		return t[1]
	}
	return t[2]
}

// ColFn 按局部坐标 u（单位球上的点）和世界法线 n 决定颜色。
type ColFn func(u, n V3) uint8

// Axes 是局部坐标轴（侧、上、前）。
type Axes [3]V3

var worldAxes = Axes{{1, 0, 0}, {0, 1, 0}, {0, 0, 1}}

// ---------- 基本形体 ----------

// Ellipsoid 在椭球表面撒面元。fn 为 nil 时按 tone 上色。
func (s *Splats) Ellipsoid(c V3, r V3, tone Tone, mask uint8, ax *Axes, fn ColFn, dens float32) {
	if ax == nil {
		ax = &worldAxes
	}
	if dens == 0 {
		dens = 2.4
	}
	p := 1.6
	area := 4 * math.Pi * math.Pow((math.Pow(float64(r[0]*r[1]), p)+math.Pow(float64(r[0]*r[2]), p)+math.Pow(float64(r[1]*r[2]), p))/3, 1/p)
	n := max(24, int(area/(D*D)*float64(dens)))
	golden := math.Pi * (1 + math.Sqrt(5))
	for i := 0; i < n; i++ {
		phi := math.Acos(1 - 2*(float64(i)+0.5)/float64(n))
		th := golden * (float64(i) + 0.5)
		u := V3{cos(th) * sin(phi), cos(phi), sin(th) * sin(phi)}
		nl := V3{u[0] / r[0], u[1] / r[1], u[2] / r[2]}.Unit()
		pos := c.Add(ax[0].Mul(u[0] * r[0])).Add(ax[1].Mul(u[1] * r[1])).Add(ax[2].Mul(u[2] * r[2]))
		nw := ax[0].Mul(nl[0]).Add(ax[1].Mul(nl[1])).Add(ax[2].Mul(nl[2]))
		var col uint8
		if fn != nil {
			col = fn(u, nw)
		} else {
			col = tone.At(nw)
		}
		s.AddM(pos, nw, col, mask)
	}
}

// Limb 是两点之间的圆柱，可以一头粗一头细（rb < 0 表示和 ra 一样）。
func (s *Splats) Limb(a, b V3, ra float32, tone Tone, rb float32, mask uint8) {
	if rb < 0 {
		rb = ra
	}
	ax := b.Sub(a)
	L := ax.Len() + 1e-6
	ax = ax.Mul(1 / L)
	e1 := ax.Cross(V3{0.31, 0.22, 0.9}).Unit()
	e2 := ax.Cross(e1)
	nl := max(2, int(L/D*1.5))
	na := max(7, int(Tau*float64(max(ra, rb))/D*1.7))
	for ia := 0; ia < na; ia++ {
		an := Tau * float64(ia) / float64(na)
		nr := e1.Mul(cos(an)).Add(e2.Mul(sin(an)))
		col := tone.At(nr)
		for il := 0; il < nl; il++ {
			t := float32(il) / float32(nl-1)
			s.AddM(a.Add(ax.Mul(t*L)).Add(nr.Mul(ra+(rb-ra)*t)), nr, col, mask)
		}
	}
	cap := func(end V3, rr, sg float32) { // 封口
		k := max(1, int(rr/D))
		n := ax.Mul(sg)
		col := tone.At(n)
		for x := -k; x <= k; x++ {
			for y := -k; y <= k; y++ {
				if x*x+y*y <= k*k+1 {
					s.AddM(end.Add(e1.Mul(float32(x)*D*0.8)).Add(e2.Mul(float32(y)*D*0.8)), n, col, mask)
				}
			}
		}
	}
	cap(a, ra, -1)
	cap(b, rb, 1)
}

// Disc 是朝向 nrm 的椭圆片；fn 的 u、v 在 -1..1。
func (s *Splats) Disc(c, nrm, tang V3, ru, rv float32, fn func(u, v float32) uint8, mask uint8) {
	nrm = nrm.Unit()
	tang = tang.Unit()
	bt := nrm.Cross(tang)
	k := int(max(ru, rv)/D*1.4) + 1
	for iv := -k; iv <= k; iv++ {
		for iu := -k; iu <= k; iu++ {
			u, v := float32(iu)/float32(k), float32(iv)/float32(k)
			if u*u+v*v <= 1 {
				s.AddM(c.Add(tang.Mul(u*ru)).Add(bt.Mul(v*rv)), nrm, fn(u, v), mask)
			}
		}
	}
}

// Node 是管子上的一个节点：位置和椭圆截面的两个半径。
type Node struct {
	P      V3
	RX, RZ float32
}

func catmull(p0, p1, p2, p3, t float32) float32 {
	return 0.5 * (2*p1 + (p2-p0)*t + (2*p0-5*p1+4*p2-p3)*t*t + (3*p1-p0-3*p2+p3)*t*t*t)
}

// Tube 沿一串节点扫出一根光滑的管子，截面是椭圆，粗细可以逐段变化。
// side 是截面 X 方向的参考向量；fn 的 u = (cosθ, 沿管子的 0..1, sinθ)，其中 sinθ>0 是 side×切线 的一侧。
// caps 的两位分别表示起点、终点要不要封口。
func (s *Splats) Tube(nodes []Node, side V3, tone Tone, mask uint8, fn ColFn, caps int) {
	n := len(nodes)
	at := func(i int) Node { return nodes[min(max(i, 0), n-1)] }
	type ring struct {
		p, e1, e2, tan V3
		rx, rz, t      float32
	}
	var rings []ring
	total := float32(0)
	for i := 0; i+1 < n; i++ {
		total += nodes[i+1].P.Sub(nodes[i].P).Len()
	}
	acc := float32(0)
	for i := 0; i+1 < n; i++ {
		p0, p1, p2, p3 := at(i-1), at(i), at(i+1), at(i+2)
		seg := p2.P.Sub(p1.P).Len()
		steps := max(2, int(seg/D*1.5))
		for k := 0; k < steps || (i == n-2 && k == steps); k++ {
			u := float32(k) / float32(steps)
			var r ring
			for c := 0; c < 3; c++ {
				r.p[c] = catmull(p0.P[c], p1.P[c], p2.P[c], p3.P[c], u)
				r.tan[c] = catmull(p0.P[c], p1.P[c], p2.P[c], p3.P[c], u+0.02) - catmull(p0.P[c], p1.P[c], p2.P[c], p3.P[c], u-0.02)
			}
			r.rx = max(catmull(p0.RX, p1.RX, p2.RX, p3.RX, u), 0.004)
			r.rz = max(catmull(p0.RZ, p1.RZ, p2.RZ, p3.RZ, u), 0.004)
			r.tan = r.tan.Unit()
			r.e1 = side.Sub(r.tan.Mul(side.Dot(r.tan))).Unit()
			r.e2 = r.e1.Cross(r.tan)
			r.t = (acc + seg*u) / (total + 1e-6)
			rings = append(rings, r)
		}
		acc += seg
	}
	for ri, r := range rings {
		na := max(8, int(Tau*float64(max(r.rx, r.rz))/D*1.6))
		for ia := 0; ia < na; ia++ {
			th := Tau * (float64(ia) + 0.5*float64(ri%2)) / float64(na)
			c, sn := cos(th), sin(th)
			nr := r.e1.Mul(c / r.rx).Add(r.e2.Mul(sn / r.rz)).Unit()
			var col uint8
			if fn != nil {
				col = fn(V3{c, r.t, sn}, nr)
			} else {
				col = tone.At(nr)
			}
			s.AddM(r.p.Add(r.e1.Mul(c*r.rx)).Add(r.e2.Mul(sn*r.rz)), nr, col, mask)
		}
	}
	cap := func(r ring, sg float32, t float32) {
		nr := r.tan.Mul(sg)
		k := int(max(r.rx, r.rz)/D*1.3) + 1
		for iy := -k; iy <= k; iy++ {
			for ix := -k; ix <= k; ix++ {
				x, y := float32(ix)/float32(k), float32(iy)/float32(k)
				if x*x+y*y > 1 {
					continue
				}
				var col uint8
				if fn != nil {
					col = Dark[fn(V3{x, t, y}, nr)]
				} else {
					col = tone.At(nr)
				}
				s.AddM(r.p.Add(r.e1.Mul(x*r.rx*0.92)).Add(r.e2.Mul(y*r.rz*0.92)), nr, col, mask)
			}
		}
	}
	if caps&1 != 0 {
		cap(rings[0], -1, 0)
	}
	if caps&2 != 0 {
		cap(rings[len(rings)-1], 1, 1)
	}
}

// Line 是两点之间等粗的细管（弓弦、箭杆这类）。
func (s *Splats) Line(a, b V3, r float32, tone Tone, mask uint8) {
	s.Tube([]Node{{a, r, r}, {b, r, r}}, pickSide(b.Sub(a)), tone, mask, nil, 3)
}

func pickSide(dir V3) V3 {
	if abs32(dir.Unit()[1]) > 0.9 {
		return V3{1, 0, 0}
	}
	return V3{0, 1, 0}
}

func lerp(a, b V3, t float32) V3 { return a.Add(b.Sub(a).Mul(t)) }

// ---------- 噪声 ----------

// vnoise 返回 n×n 的平滑噪声（按行存放），值域 0..1。
func vnoise(n, cells int, seed uint64) []float32 {
	rng := rand.New(rand.NewPCG(seed, seed*7919+1))
	w := cells + 2
	r := make([]float32, w*w)
	for i := range r {
		r[i] = rng.Float32()
	}
	idx := make([]int, n)
	f := make([]float32, n)
	for k := 0; k < n; k++ {
		t := float32(k) * float32(cells) / float32(n)
		idx[k] = int(t)
		x := t - float32(idx[k])
		f[k] = x * x * (3 - 2*x)
	}
	out := make([]float32, n*n)
	for j := 0; j < n; j++ {
		for i := 0; i < n; i++ {
			a, b := r[idx[j]*w+idx[i]], r[idx[j]*w+idx[i]+1]
			c, d := r[(idx[j]+1)*w+idx[i]], r[(idx[j]+1)*w+idx[i]+1]
			out[j*n+i] = (a*(1-f[i])+b*f[i])*(1-f[j]) + (c*(1-f[i])+d*f[i])*f[j]
		}
	}
	return out
}

// wob 是沿一条线的平滑起伏。
func wob(a, k float64) float64 {
	return 0.5*math.Sin(a*2.1*k+1.3) + 0.3*math.Sin(a*5.3*k+0.4) + 0.2*math.Sin(a*11.7*k+2.2)
}

func frac(x float64) float64 { return x - math.Floor(x) }
func abs32(x float32) float32 {
	if x < 0 {
		return -x
	}
	return x
}
