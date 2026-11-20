package splat

import (
	"math"
	"math/rand/v2"
)

var leanN = V3{-0.3, 0.45, 0.85} // 草叶和花瓣朝向镜头的法线

// Vegetation 生成会动的植物：树冠、灌木、草丛、花。t 是 0..1 的循环时间。
func (tr *Terrain) Vegetation(s *Splats, t float64) {
	for k, c := range tr.Cypress {
		y0 := tr.Yf(c.X, c.Z)
		sw := sin(Tau*t+float64(k)) * 0.03
		for q := 0; q < 7; q++ {
			f := float32(q) / 6
			r := 0.27*float32(math.Pow(float64(1-f), 0.8)) + 0.05
			s.Ellipsoid(V3{c.X + sw*f*2, y0 + 0.4 + f*(c.H-0.5), c.Z}, V3{r, 0.2, r}, Tone{Green, GreenD, GreenD}, 0, nil, nil, 0)
		}
	}
	crown := [][4]float32{{-0.15, 0.95, 0.1, 0.3}, {0.3, 0.92, -0.12, 0.28}, {0.05, 1.15, 0, 0.3}, {-0.3, 0.8, -0.15, 0.2}, {0.38, 0.75, 0.15, 0.18}, {0.1, 0.85, 0.3, 0.2}}
	leaf := Tone{GreenL, Green, GreenD}
	for k, o := range tr.Olive {
		y0 := tr.Yf(o.X, o.Z)
		sw := sin(Tau*t+float64(k)*1.7) * 0.025
		for q, c := range crown {
			s.Ellipsoid(V3{o.X + c[0] + sw*float32(1+q%2), y0 + c[1] + sw*0.4*float32(q%3-1), o.Z + c[2]}, V3{c[3], c[3] * 0.72, c[3]}, leaf, 0, nil, nil, 2)
		}
	}
	for k, b := range tr.Bushes {
		y0 := tr.Yf(b.X, b.Z)
		sw := sin(Tau*t+float64(k)*2.3) * 0.012
		c := V3{b.X + sw, y0 + b.R*0.75, b.Z}
		s.Ellipsoid(c, V3{b.R, b.R * 0.85, b.R}, leaf, 0, nil, nil, 2)
		if k%2 == 0 { // 红色的浆果
			rr := rand.New(rand.NewPCG(uint64(k), 99))
			for q := 0; q < 5; q++ {
				u := V3{float32(rr.NormFloat64()), float32(math.Abs(rr.NormFloat64())), float32(rr.NormFloat64())}.Unit()
				s.AddX(c.Add(V3{u[0] * b.R, u[1] * b.R * 0.85, u[2] * b.R}.Mul(1.02)), u, Red, D*0.75, defT, 0)
			}
		}
	}
	// 草丛：每根草是 4 个叠起来的面元，上端随风摆
	const seg = 4
	for _, g := range tr.tufts {
		w := sin(Tau*t + float64(g.ph))
		for q := 0; q < seg; q++ {
			f := (float32(q) + 0.5) / seg
			sway := w*0.07*float32(math.Pow(float64(f), 1.5)) + g.lean*f
			c := g.c1
			if f > 0.7 {
				c = g.c2
			}
			s.AddX(V3{g.x + sway, g.y + g.h*f, g.z - sway*0.5}, leanN, c, D*0.5, D*0.5, 0)
		}
	}
	for _, f := range tr.flowers {
		hx := f.x + sin(Tau*t+float64(f.ph))*0.03
		hy := f.y + 0.26
		for k := 0; k < 3; k++ {
			s.AddX(V3{f.x + (hx-f.x)*float32(k)/3, f.y + 0.08*(float32(k)+0.5), f.z}, leanN, Green, D*0.45, D*0.45, 0)
		}
		for _, d := range [][2]float32{{-0.045, 0.02}, {0.045, 0.02}, {0, 0.06}} {
			s.AddX(V3{hx + d[0], hy + d[1], f.z}, leanN, f.c, D*0.62, D*0.5, 0)
		}
		s.AddX(V3{hx, hy, f.z + 0.02}, leanN, Yellow, D*0.4, D*0.4, 0)
	}
}

// Birds 生成天上飞过的三只鸟。
func Birds(s *Splats, t float64) {
	n := V3{0.5, 0.5, 0.5}
	for k, b := range [][2]float32{{9.5, 4.4}, {10.6, 4.1}, {10.1, 4.8}} {
		x := float32(frac(t+float64(k)*0.07))*20 - 3
		z := b[0] + sin(Tau*t+float64(k))*0.2
		fl := sin(Tau*t*3 + float64(k)*2)
		c := V3{x, b[1] + fl*0.03, z}
		for _, sg := range []float32{-1, 1} {
			for q := 0; q < 7; q++ {
				w := 0.03 + 0.23*float32(q)/6
				s.AddX(c.Add(V3{-0.3 * w, w*fl*0.9 + 0.02, sg * w}), n, Black, D*0.5, D*0.5, 0)
			}
		}
		for _, dx := range []float32{0.03, 0, -0.04} {
			s.AddX(c.Add(V3{dx, 0, 0}), n, Black, D*0.6, D*0.6, 0)
		}
	}
}
