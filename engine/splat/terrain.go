package splat

import (
	"math"
	"math/rand/v2"
)

// Battle 是关卡文件里和地形有关的部分。
type Battle struct {
	ID      string   `json:"id"`
	Heights []string `json:"heights"`
	Terrain []string `json:"terrain"`
	Cave    *struct {
		Entrances []struct {
			Anchor [2]int `json:"anchor"`
		} `json:"entrances"`
		Boulders []struct {
			Pos [2]int `json:"pos"`
		} `json:"boulders"`
	} `json:"cave"`
}

type Tree struct{ X, Z, H float32 }
type Bush struct{ X, Z, R float32 }

type tuft struct {
	x, y, z, h, ph, lean float32
	c1, c2               uint8
}
type flower struct {
	x, y, z, ph float32
	c           uint8
}

// Terrain 保存从关卡数据推出来的细网格，以及植物的位置。
type Terrain struct {
	B       *Battle
	NX, NZ  int
	N       int       // 细网格的边长
	H0      []float32 // 每格的层数，NZ×NX
	Hf      []float32 // 细网格上的层数，N×N（崖线被扰动过）
	G       []uint8   // 细网格上的地面颜色
	shadow  []bool
	grass   []bool
	meadow  []bool
	rng     *rand.Rand
	Cypress []Tree
	Olive   []Tree
	Bushes  []Bush
	tufts   []tuft
	flowers []flower
}

func NewTerrain(b *Battle) *Terrain {
	t := &Terrain{B: b, NZ: len(b.Heights), NX: len(b.Heights[0])}
	t.N = t.NX * R
	t.H0 = make([]float32, t.NX*t.NZ)
	for j, row := range b.Heights {
		for i, ch := range row {
			t.H0[j*t.NX+i] = float32(ch - '0')
		}
	}
	N := t.N
	wx, wz := vnoise(N, 9, 1), vnoise(N, 9, 2)
	t.Hf = make([]float32, N*N)
	for j := 0; j < N; j++ {
		for i := 0; i < N; i++ {
			x := (float32(i)+0.5)*D + (wx[j*N+i]-0.5)*0.2
			z := (float32(j)+0.5)*D + (wz[j*N+i]-0.5)*0.2
			t.Hf[j*N+i] = t.H0[clampi(int(z), 0, t.NZ-1)*t.NX+clampi(int(x), 0, t.NX-1)]
		}
	}
	t.shadow = make([]bool, N*N)
	t.rng = rand.New(rand.NewPCG(11, 13))
	for j := 0; j < t.NZ; j++ {
		for i := 0; i < t.NX; i++ {
			if b.Terrain[j][i] == 'f' {
				for _, q := range [][3]float32{{0.3, 0.35, 0.27}, {0.7, 0.6, 0.23}, {0.35, 0.8, 0.18}} {
					t.Bushes = append(t.Bushes, Bush{float32(i) + q[0], float32(j) + q[1], q[2]})
				}
			}
		}
	}
	return t
}

func clampi(v, lo, hi int) int { return min(max(v, lo), hi) }

// Y 是整格的地面高度；Yf 是细网格上的地面高度。
func (t *Terrain) Y(x, z float32) float32 {
	return t.H0[clampi(int(z), 0, t.NZ-1)*t.NX+clampi(int(x), 0, t.NX-1)] * LV
}
func (t *Terrain) Yf(x, z float32) float32 {
	return t.Hf[clampi(int(z*R), 0, t.N-1)*t.N+clampi(int(x*R), 0, t.N-1)] * LV
}

// Cast 登记一块落在地面上的影子（物体在 (x,z)，半径 r，高 h）。要在 Build 之前调用。
func (t *Terrain) Cast(x, z, r, h float32) {
	cx, cz := x-Light[0]*h, z-Light[2]*h
	N := t.N
	for j := clampi(int((cz-r)*R)-1, 0, N-1); j <= clampi(int((cz+r)*R)+1, 0, N-1); j++ {
		for i := clampi(int((cx-r*1.3)*R)-1, 0, N-1); i <= clampi(int((cx+r*1.3)*R)+1, 0, N-1); i++ {
			dx, dz := ((float32(i)+0.5)*D-cx)/(r*1.25), ((float32(j)+0.5)*D-cz)/(r*0.8)
			if dx*dx+dz*dz < 1 {
				t.shadow[j*N+i] = true
			}
		}
	}
}

// Build 生成地面和侧壁。path 是踩出来的小路经过的点。
func (t *Terrain) Build(s *Splats, path [][2]float32) {
	N, Hf := t.N, t.Hf
	G := make([]uint8, N*N)
	n3, n4, n5, n6, n8, n9 := vnoise(N, 7, 3), vnoise(N, 10, 4), vnoise(N, 31, 5), vnoise(N, 12, 6), vnoise(N, 37, 8), vnoise(N, 40, 9)
	t.grass, t.meadow = make([]bool, N*N), make([]bool, N*N)
	for k := range G {
		G[k] = Plaster
		if n3[k] > 0.7 {
			G[k] = PlasterD
		}
		g := n4[k] + n5[k]*0.3
		if Hf[k] == 0 {
			if g > 0.62 {
				G[k] = Yellow
			}
			if g > 0.8 {
				G[k] = Earth
			}
			t.grass[k] = g > 0.58
		}
		if Hf[k] == 2 {
			if n6[k]+n8[k]*0.25 > 0.82 {
				G[k] = GreenL
			}
			t.meadow[k] = n6[k] > 0.62
		}
	}
	// 小路
	for j := 0; j < N; j++ {
		for i := 0; i < N; i++ {
			x, z := (float32(i)+0.5)*D, (float32(j)+0.5)*D
			d := float32(9)
			for q := 0; q+1 < len(path); q++ {
				a, b := path[q], path[q+1]
				abx, abz := b[0]-a[0], b[1]-a[1]
				tt := ((x-a[0])*abx + (z-a[1])*abz) / (abx*abx + abz*abz)
				tt = min(max(tt, 0), 1)
				d = min(d, float32(math.Hypot(float64(x-a[0]-tt*abx), float64(z-a[1]-tt*abz))))
			}
			k := j*N + i
			pw := 0.3 + (n9[k]-0.5)*0.3
			if d < pw {
				G[k] = PlasterD
			}
			if d < pw*0.55 {
				G[k] = PlasterDD
			}
			if d <= pw+0.1 {
				t.grass[k], t.meadow[k] = false, false
			}
		}
	}
	// 地形自己投下的影子：朝光源方向一步步看过去，有没有更高的东西挡着
	h := math.Hypot(float64(Light[0]), float64(Light[2]))
	slope := float64(Light[1]) / h
	steps := int(3*LV/slope/D) + 2
	sh := make([]bool, N*N)
	for k := 1; k < steps; k++ {
		di, dj := int(math.RoundToEven(float64(k)*float64(Light[0])/h)), int(math.RoundToEven(float64(k)*float64(Light[2])/h))
		need := float32(float64(k) * D * slope)
		for j := 0; j < N; j++ {
			sj := clampi(j+dj, 0, N-1)
			for i := 0; i < N; i++ {
				if (Hf[sj*N+clampi(i+di, 0, N-1)]-Hf[j*N+i])*LV > need {
					sh[j*N+i] = true
				}
			}
		}
	}
	for j := 0; j < N; j++ {
		for i := 0; i < N; i++ {
			k := j*N + i
			ao := false // 墙根一圈暗一档
			if j >= 3 && j < N-3 && i >= 3 && i < N-3 {
				for q := 1; q <= 3 && !ao; q++ {
					ao = Hf[k-q] > Hf[k] || Hf[k+q] > Hf[k] || Hf[k-q*N] > Hf[k] || Hf[k+q*N] > Hf[k]
				}
			}
			if sh[k] || t.shadow[k] || ao {
				G[k] = Dark[G[k]]
			}
			x := (float32(i)+0.5)*D + (t.rng.Float32()-0.5)*D*0.5
			z := (float32(j)+0.5)*D + (t.rng.Float32()-0.5)*D*0.5
			s.Add(V3{x, Hf[k] * LV, z}, Up, G[k])
		}
	}
	t.G = G
	t.walls(s, 0)
	t.walls(s, 1)
}

// walls 生成相邻细格之间的竖直面。axis 0：法线沿 X；axis 1：法线沿 Z。
func (t *Terrain) walls(s *Splats, axis int) {
	N := t.N
	outside := float32(Base / LV)
	hf := func(j, i int) float32 {
		if i < 0 || j < 0 || i >= N || j >= N {
			return outside
		}
		return t.Hf[j*N+i]
	}
	for jj := 0; jj <= N; jj++ {
		for ii := 0; ii <= N; ii++ {
			var a, b float32
			if axis == 0 {
				if jj >= N {
					continue
				}
				a, b = hf(jj, ii-1), hf(jj, ii)
			} else {
				if ii >= N {
					continue
				}
				a, b = hf(jj-1, ii), hf(jj, ii)
			}
			if a == b {
				continue
			}
			lo, hi := min(a, b)*LV, max(a, b)*LV
			sign := float32(-1)
			if a > b {
				sign = 1
			}
			var x, z, along float32
			var nr V3
			var edge bool
			if axis == 0 {
				x, z = float32(ii)*D, (float32(jj)+0.5)*D
				nr, along, edge = V3{sign, 0, 0}, z, ii == 0 || ii == N
			} else {
				x, z = (float32(ii)+0.5)*D, float32(jj)*D
				nr, along, edge = V3{0, 0, sign}, x, jj == 0 || jj == N
			}
			lit := nr.Dot(Light) > 0.1
			height := hi - lo
			al := float64(along)
			cnt := max(1, int(math.RoundToEven(float64(height)/D)))
			for st := 0; st < cnt; st++ {
				y := lo + (float32(st)+0.5)*D
				below := hi - y
				c := PlasterDD
				if lit {
					c = PlasterD
				}
				if y < 0 {
					c = Dark[c]
				}
				// 岩层线和错缝的裂纹
				yy := float64(y) + 0.035*wob(al, 1)
				band := math.Floor(yy / 0.2)
				strata := yy/0.2-band < D/0.2*0.95
				crack := frac(al/0.52+band*0.37+0.07*wob(band*3.1+al*0.2, 1)) < D/0.52*0.9
				if strata || (crack && math.Sin(band*12.9+math.Floor(al/0.52)*7.7) > -0.3) {
					c = Dark[c]
				}
				if below < D*1.05 { // 顶沿的一条亮边
					c = Lighter[c]
				}
				if y-lo < D*1.6 && lo >= 0 { // 墙根
					c = Dark[c]
				}
				// 壁画饰带
				if height >= 2*LV-1e-3 && y > 0.02 {
					if below > 0.13 && below < 0.22 {
						c = Red
					}
					if abs32(below-0.255) < D*0.55 {
						c = Bone
					}
				}
				if height >= 3*LV-1e-3 && y > 0.02 {
					wave := 0.44 + 0.055*sin(al*Tau*1.5)
					if abs32(below-wave) < 0.03 {
						c = Blue
					}
					if abs32(below-0.57) < D*0.55 {
						c = RedD
					}
					fr := float32(frac(al*1.5) - 0.5)
					dy := (below - 0.68) / 0.045
					if (fr/0.09)*(fr/0.09)+dy*dy < 1 {
						c = Red
					}
				}
				// 底座上的两条线和一排锯齿
				if edge && y < 0 {
					if abs32(y+0.2) < D*0.6 || abs32(y+0.52) < D*0.6 {
						c = RedD
					}
					tri := float32(math.Abs(frac(al*2)-0.5) * 2)
					if abs32(y-(-0.44+0.17*tri)) < D*0.75 {
						c = Red
					}
				}
				// 洞口
				if axis == 0 && t.B.Cave != nil {
					for _, e := range t.B.Cave.Entrances {
						ex, ez := e.Anchor[0], e.Anchor[1]
						wxp := float32(ex)
						if ex < t.NX/2 {
							wxp = float32(ex + 1)
						}
						if abs32(x-wxp) < 1.3 && abs32(lo-t.H0[ez*t.NX+ex]*LV) < 1e-3 {
							dz, dy := (z-float32(ez)-0.5)/0.4, (y-lo)/0.62
							rr := dz*dz + dy*dy
							if rr < 1 {
								c = Black
							}
							if rr < 0.45 && y-lo < 0.2 {
								c = Stone
							}
						}
					}
				}
				s.Add(V3{x, y, z}, nr, c)
			}
		}
	}
}

var rockTone = Tone{PlasterD, PlasterDD, PlasterDDD}

// Scenery 生成不会动的摆设：洞口的石框、骨头、巨石、碎石、树干。它会登记影子，所以要在 Build 之前调用。
func (t *Terrain) Scenery(s *Splats) {
	rng := t.rng
	uni := func(a, b float32) float32 { return a + (b-a)*rng.Float32() }
	if c := t.B.Cave; c != nil {
		for _, e := range c.Entrances {
			ex, ez := float32(e.Anchor[0]), float32(e.Anchor[1])
			west := e.Anchor[0] < t.NX/2
			wx, out := ex, float32(1)
			if west {
				wx, out = ex+1, -1
			}
			y0 := t.Y(ex, ez)
			for k := 0; k < 9; k++ { // 洞口的石框
				a := math.Pi * float64(k) / 8
				r := uni(0.13, 0.19)
				s.Ellipsoid(V3{wx + out*0.06, y0 + 0.66*sin(a) + 0.02, ez + 0.5 + 0.5*cos(a)}, V3{r * 0.9, r, r}, Tone{Plaster, PlasterD, PlasterDD}, 0, nil, nil, 0)
			}
			for k := 0; k < 5; k++ { // 洞口散落的骨头
				bx, bz := ex+0.5+out*uni(-0.2, 0.9), ez+0.5+uni(-0.9, 0.9)
				an := float64(uni(0, math.Pi))
				s.Limb(V3{bx, y0 + 0.04, bz}, V3{bx + 0.22*cos(an), y0 + 0.04, bz + 0.22*sin(an)}, 0.03, Tone{Bone, PlasterD}, -1, 0)
			}
			sx, sz := ex+0.5+out*0.5, ez+1.25 // 一个头骨
			s.Ellipsoid(V3{sx, y0 + 0.09, sz}, V3{0.1, 0.09, 0.1}, Tone{Bone, Plaster, PlasterD}, 0, nil, nil, 0)
			s.AddX(V3{sx - 0.04, y0 + 0.1, sz + 0.09}, V3{0, 0.3, 1}, Black, D*0.5, defT, 0)
			s.AddX(V3{sx + 0.05, y0 + 0.1, sz + 0.08}, V3{0, 0.3, 1}, Black, D*0.5, defT, 0)
		}
		for _, bd := range c.Boulders {
			i, j := float32(bd.Pos[0]), float32(bd.Pos[1])
			y0 := t.Y(i, j)
			s.Ellipsoid(V3{i + 0.5, y0 + 0.36, j + 0.5}, V3{0.42, 0.42, 0.4}, rockTone, 0, nil, nil, 0)
			s.Ellipsoid(V3{i + 0.66, y0 + 0.62, j + 0.4}, V3{0.22, 0.2, 0.22}, rockTone, 0, nil, nil, 0)
			s.Ellipsoid(V3{i + 0.3, y0 + 0.2, j + 0.68}, V3{0.2, 0.18, 0.18}, rockTone, 0, nil, nil, 0)
			t.Cast(i+0.5, j+0.5, 0.5, 0.7)
		}
	}
	for k := 0; k < 46; k++ { // 各处的碎石
		x, z, r := uni(0.2, float32(t.NX)-0.2), uni(0.2, float32(t.NZ)-0.2), uni(0.05, 0.13)
		if t.Yf(x, z) != t.Yf(x+0.3, z) || t.Yf(x, z) != t.Yf(x, z+0.3) {
			continue
		}
		s.Ellipsoid(V3{x, t.Yf(x, z) + r*0.5, z}, V3{r, r * 0.7, r * 0.9}, rockTone, 0, nil, nil, 0)
	}
	for x := float32(4.2); x < 9.9; x += 0.55 { // 断崖脚下的落石
		r := uni(0.1, 0.24)
		z := 7.0 + uni(0.1, 0.35) + r
		s.Ellipsoid(V3{x + uni(-0.15, 0.15), t.Yf(x, z) + r*0.55, z}, V3{r, r * 0.75, r}, rockTone, 0, nil, nil, 0)
	}
	trunk := Tone{Earth, EarthD, RedD}
	for _, c := range t.Cypress {
		y0 := t.Yf(c.X, c.Z)
		s.Limb(V3{c.X, y0, c.Z}, V3{c.X, y0 + 0.4, c.Z}, 0.06, Tone{EarthD, RedD}, -1, 0)
		t.Cast(c.X, c.Z, 0.3, c.H)
	}
	for _, o := range t.Olive {
		x, z, y0 := o.X, o.Z, t.Yf(o.X, o.Z)
		fork := V3{x + 0.08, y0 + 0.45, z - 0.04}
		s.Limb(V3{x, y0, z}, fork, 0.1, trunk, 0.07, 0)
		s.Limb(fork, V3{x - 0.12, y0 + 0.8, z + 0.1}, 0.065, trunk, 0.04, 0)
		s.Limb(fork, V3{x + 0.28, y0 + 0.78, z - 0.1}, 0.06, trunk, 0.04, 0)
		t.Cast(x, z, 0.55, 0.9)
	}
	for _, b := range t.Bushes {
		t.Cast(b.X, b.Z, b.R*1.1, b.R)
	}
}

// ScatterPlants 决定草丛和花的位置。要在 Build 之后调用。
func (t *Terrain) ScatterPlants() {
	rng := rand.New(rand.NewPCG(5, 6))
	N := t.N
	pick := func(mask []bool, n int, fn func(x, y, z float32)) {
		var cells []int
		for k, m := range mask {
			if m {
				cells = append(cells, k)
			}
		}
		rng.Shuffle(len(cells), func(a, b int) { cells[a], cells[b] = cells[b], cells[a] })
		for _, k := range cells[:min(n, len(cells))] {
			fn((float32(k%N)+rng.Float32())*D, t.Hf[k]*LV, (float32(k/N)+rng.Float32())*D)
		}
	}
	mk := func(x, y, z float32, c1, c2 uint8) {
		t.tufts = append(t.tufts, tuft{x: x, y: y, z: z, c1: c1, c2: c2, h: 0.1 + 0.14*rng.Float32(),
			ph: x*1.3 + z*0.7 + 0.8*rng.Float32(), lean: -0.03 + 0.06*rng.Float32()}) // 风是一阵一阵吹过去的
	}
	pick(t.grass, 2600, func(x, y, z float32) {
		switch c := rng.Float32(); {
		case c < 0.5:
			mk(x, y, z, Earth, Yellow)
		case c < 0.85:
			mk(x, y, z, Yellow, Plaster)
		default:
			mk(x, y, z, Green, GreenL)
		}
	})
	pick(t.meadow, 1500, func(x, y, z float32) {
		if rng.Float32() < 0.6 {
			mk(x, y, z, Green, GreenL)
		} else {
			mk(x, y, z, GreenD, Green)
		}
	})
	fl := func(x, y, z float32) {
		c := Bone
		if rng.Float32() < 0.7 {
			c = Red
		}
		t.flowers = append(t.flowers, flower{x, y, z, x*1.3 + z*0.7, c})
	}
	pick(t.meadow, 70, fl)
	pick(t.grass, 40, fl)
}
