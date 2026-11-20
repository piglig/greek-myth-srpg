package splat

import (
	"math"
	"math/rand/v2"
)

// Lion 生成涅墨亚狮子：压低头、前肩高耸的潜行姿势。
func (tr *Terrain) Lion(s *Splats, x, z float32, face [2]float32, t float64, sc float32) {
	f := V3{face[0], 0, face[1]}.Unit()
	sd := V3{f[2], 0, -f[0]}
	o := V3{x, tr.Yf(x, z), z}
	at := func(fw, up, side float32) V3 {
		return o.Add(f.Mul(fw * sc)).Add(Up.Mul(up * sc)).Add(sd.Mul(side * sc))
	}
	nd := func(p V3, rx, rz float32) Node { return Node{p, rx * sc, rz * sc} }
	r3 := func(x, y, z float32) V3 { return V3{x * sc, y * sc, z * sc} }
	const M = 1
	br := sin(Tau*t) * 0.014
	fur := Tone{Yellow, Earth, EarthD}
	pale := Tone{Bone, Plaster, PlasterD}

	// ---- 躯干：深胸、收腹、结实的后臀。皮毛上有一道游走的亮光（刀枪不入） ----
	glint := frac(t)
	s.Tube([]Node{nd(at(-0.72, 0.7, 0), 0.14, 0.16), nd(at(-0.58, 0.74+br*0.5, 0), 0.215, 0.235), nd(at(-0.28, 0.73+br, 0), 0.175, 0.19),
		nd(at(0.05, 0.75+br, 0), 0.225, 0.27), nd(at(0.36, 0.8+br, 0), 0.25, 0.31), nd(at(0.6, 0.84+br, 0), 0.19, 0.24), nd(at(0.86, 0.84, 0), 0.15, 0.18)},
		sd.Mul(-1), fur, M, func(u, n V3) uint8 {
			if u[2] < -0.55 { // 腹部颜色浅
				return Tone{Plaster, PlasterD, PlasterDD}.At(n)
			}
			if d := abs32(u[1] - float32(glint)); u[2] > 0.72 && (d < 0.035 || d > 0.965) {
				return Bone
			}
			if u[2] > 0.93 {
				return Yellow
			}
			return fur.At(n)
		}, 1)

	// ---- 腿 ----
	paw := func(p V3) {
		s.Ellipsoid(p, r3(0.085, 0.06, 0.12), fur, M, &Axes{sd, Up, f}, nil, 0)
		for _, q := range []float32{-0.05, 0, 0.05} { // 脚趾和爪
			s.Ellipsoid(p.Add(f.Mul(0.1*sc)).Add(sd.Mul(q*sc)).Sub(Up.Mul(0.015*sc)), r3(0.03, 0.035, 0.04), fur, M, nil, nil, 0)
			s.AddX(p.Add(f.Mul(0.145*sc)).Add(sd.Mul(q*sc)).Sub(Up.Mul(0.035*sc)), f, Bone, D*0.55, defT, M)
		}
	}
	for i, sg := range []float32{-1, 1} {
		st := float32(i)*0.24 - 0.1 // 前腿一前一后
		sh, el, wr, pw := at(0.4, 0.66+br, 0.17*sg), at(0.34+st*0.3, 0.42, 0.19*sg), at(0.4+st, 0.14, 0.19*sg), at(0.42+st, 0.05, 0.19*sg)
		s.Tube([]Node{nd(sh, 0.12, 0.15), nd(lerp(sh, el, 0.6), 0.1, 0.12), nd(el, 0.08, 0.085), nd(wr, 0.062, 0.062), nd(pw.Add(Up.Mul(0.03*sc)), 0.065, 0.065)}, sd, fur, M, nil, 0)
		paw(pw)
		hs := float32(i)*-0.2 + 0.08 // 后腿：髋、膝、跗关节，折成 Z 形
		hip, kn, hk, hp := at(-0.56, 0.66+br*0.5, 0.15*sg), at(-0.4+hs*0.4, 0.4, 0.18*sg), at(-0.66+hs, 0.22, 0.18*sg), at(-0.58+hs, 0.05, 0.18*sg)
		s.Tube([]Node{nd(hip, 0.13, 0.19), nd(lerp(hip, kn, 0.55).Add(f.Mul(0.03*sc)), 0.115, 0.16), nd(kn, 0.085, 0.1), nd(hk, 0.05, 0.055), nd(hp.Add(Up.Mul(0.04*sc)), 0.058, 0.06)}, sd, fur, M, nil, 0)
		paw(hp)
	}

	// ---- 尾巴：先垂下再翘起，尾尖一撮深色的毛，来回甩 ----
	var tail []Node
	for k := 0; k <= 8; k++ {
		q := float32(k) / 8
		sw := sin(Tau*t*2-float64(k)*0.55) * 0.11 * q
		tail = append(tail, nd(at(-0.74-0.62*q, 0.72-0.5*q+0.62*q*q, sw), 0.045-0.02*q, 0.045-0.02*q))
	}
	s.Tube(tail, sd, fur, M, nil, 0)
	tp := tail[8].P
	td := tp.Sub(tail[7].P).Unit()
	s.Tube([]Node{{tp, 0.03 * sc, 0.03 * sc}, {tp.Add(td.Mul(0.07 * sc)), 0.07 * sc, 0.07 * sc}, {tp.Add(td.Mul(0.2 * sc)), 0.01 * sc, 0.01 * sc}}, sd, Tone{EarthD, RedD, Black}, M, nil, 0)

	// ---- 头：压低，左右慢慢扫视 ----
	yaw := float64(sin(Tau*t)) * 0.16
	hf := f.Mul(cos(yaw)).Add(sd.Mul(sin(yaw))).Add(Up.Mul(0.04)).Unit()
	hs := V3{hf[2], 0, -hf[0]}.Unit()
	hu := hs.Cross(hf).Mul(-1)
	if hu[1] < 0 {
		hu = hu.Mul(-1)
	}
	hax := &Axes{hs, hu, hf}
	hc := at(1.02, 0.8+br*0.6, 0).Add(sd.Mul(sin(yaw) * 0.1 * sc))
	hp := func(side, up, fw float32) V3 {
		return hc.Add(hs.Mul(side * sc)).Add(hu.Mul(up * sc)).Add(hf.Mul(fw * sc))
	}
	s.Ellipsoid(hc, r3(0.2, 0.19, 0.22), nil, M, hax, func(u, n V3) uint8 {
		ax0 := abs32(u[0])
		if u[2] > 0.3 {
			slant := 0.36 - (ax0-0.3)*0.5 // 眉骨向鼻梁压下去，眼神才凶
			if ax0 > 0.18 && ax0 < 0.8 && abs32(u[1]-slant) < 0.075 {
				return RedD
			}
			ex := abs32(ax0 - 0.48)
			if ex < 0.17 && u[1] < slant-0.06 && u[1] > slant-0.26 {
				if ex < 0.07 {
					return Black
				}
				return Bone
			}
		}
		if ax0 < 0.1 && u[2] > 0.2 && u[1] > -0.1 { // 鼻梁
			return Yellow
		}
		return fur.At(n)
	}, 5)
	s.Ellipsoid(hp(0, -0.05, 0.21), r3(0.125, 0.095, 0.14), pale, M, hax, nil, 3)             // 上颌
	s.Ellipsoid(hp(0, 0.0, 0.345), r3(0.06, 0.045, 0.03), Tone{Black, Black}, M, hax, nil, 0) // 鼻头
	jaw := 0.035 + 0.02*sin(Tau*t*2)                                                          // 下颌一张一合
	s.Ellipsoid(hp(0, -0.15-jaw, 0.15), r3(0.09, 0.05, 0.12), Tone{Plaster, PlasterD, PlasterDD}, M, hax, nil, 0)
	s.Ellipsoid(hp(0, -0.1-jaw*0.5, 0.17), r3(0.075, 0.03, 0.1), Tone{RedD, RedD, Black}, M, hax, nil, 0) // 口腔
	for _, sg := range []float32{-1, 1} {
		s.Ellipsoid(hp(0.06*sg, -0.1, 0.275), r3(0.016, 0.04, 0.016), Tone{Bone, Bone}, M, hax, nil, 0)      // 上犬齿
		s.Ellipsoid(hp(0.045*sg, -0.12-jaw, 0.25), r3(0.014, 0.03, 0.014), Tone{Bone, Bone}, M, hax, nil, 0) // 下犬齿
		ear := sin(Tau*t*3+float64(sg)) * 0.01
		s.Ellipsoid(hp(0.16*sg, 0.17+ear, -0.02), r3(0.06, 0.065, 0.035), Tone{Earth, EarthD, RedD}, M, hax, nil, 0)
		s.Ellipsoid(hp(0.16*sg, 0.17+ear, 0.01), r3(0.03, 0.035, 0.02), Tone{RedD, Black}, M, hax, nil, 0)
	}

	// ---- 鬃毛：一绺一绺向后披的火焰形，前浅后深 ----
	rr := rand.New(rand.NewPCG(3, 4))
	tuft := func(p, dir V3, r, long float32, tone Tone, k int) {
		dir = dir.Add(sd.Mul(sin(Tau*t+float64(k)*0.9) * 0.1)).Unit()
		e1 := dir.Cross(V3{0.3, 0.9, 0.2}).Unit()
		e2 := dir.Cross(e1)
		s.Ellipsoid(p.Add(dir.Mul(r*long*0.6*sc)), r3(r, r*long, r*0.8), tone, M, &Axes{e1, dir, e2}, nil, 2.2)
	}
	layers := []struct {
		fw, rad, r, long float32
		n                int
		tone             Tone
	}{
		{-0.16, 0.2, 0.06, 1.7, 13, Tone{Yellow, Earth, EarthD}},
		{-0.27, 0.25, 0.075, 2.0, 15, Tone{Yellow, Earth, EarthD}},
		{-0.4, 0.29, 0.09, 2.2, 15, Tone{Earth, EarthD, RedD}},
		{-0.55, 0.3, 0.095, 2.3, 14, Tone{Earth, EarthD, RedD}},
		{-0.7, 0.26, 0.09, 2.2, 11, Tone{EarthD, RedD, RedD}},
	}
	k := 0
	for li, L := range layers {
		for i := 0; i < L.n; i++ {
			an := Tau*(float64(i)+0.5*float64(li%2))/float64(L.n) + float64(rr.Float32())*0.2
			out := hu.Mul(cos(an)).Add(hs.Mul(sin(an)))
			if li <= 1 && cos(an) > 0.35 { // 额头上方不长，否则从上往下看会盖住脸
				continue
			}
			if li == 0 && cos(an) < -0.75 { // 脸的正下方留给下巴
				continue
			}
			p := hc.Add(hf.Mul(L.fw * sc)).Add(out.Mul(L.rad * (0.9 + 0.2*rr.Float32()) * sc))
			if li >= 3 { // 后两层跟着脖子，不跟着头转
				p = at(1.02+L.fw, 0.82+br, 0).Add(Up.Mul(cos(an) * L.rad * sc)).Add(sd.Mul(sin(an) * L.rad * sc))
				out = Up.Mul(cos(an)).Add(sd.Mul(sin(an)))
			}
			tuft(p, out.Mul(0.3).Sub(f.Mul(0.95)).Sub(Up.Mul(0.1)), L.r, L.long, L.tone, k)
			k++
		}
	}
	for i := 0; i < 9; i++ { // 胸前垂下来的一片
		q := float32(i%3) - 1
		tuft(at(0.62-0.07*float32(i/3), 0.62-0.08*float32(i/3), q*0.11), Up.Mul(-1).Add(f.Mul(0.25)).Add(sd.Mul(q*0.2)), 0.08, 2.3, Tone{EarthD, RedD, Black}, k)
		k++
	}
	for i := 0; i < 6; i++ { // 沿脊背到肩胛的一道
		tuft(at(0.5-0.11*float32(i), 1.02-0.012*float32(i)+br, 0), Up.Mul(0.5).Sub(f), 0.07-0.005*float32(i), 2.0, Tone{Earth, EarthD, RedD}, k)
		k++
	}
	_ = math.Pi
}
