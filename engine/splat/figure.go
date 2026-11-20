package splat

import (
	"math"
	"math/rand/v2"
)

// Actor 描述场上的一个人物。
type Actor struct {
	X, Z   float32
	Kind   string // hero、atalanta、heracles
	Divine int    // 神性阶 0..4（只对 hero 有意义）
	Face   [2]float32
	Phase  float64
	Scale  float32
}

type kit struct {
	skin      Tone
	hair      Tone
	wide      float32 // 肩宽和四肢粗细的倍数
	bare      bool    // 赤膊
	top, kilt Tone
	stripe    uint8 // 短裙上的织纹
	hem, band uint8
	weapon    string
	locks     float32 // 脑后长发垂到多高（0 = 短发）
	beard     bool
	boots     bool
	baldric   bool
}

var kits = map[string]kit{
	"hero": {skin: Tone{SkinL, Skin, SkinD}, hair: Tone{Black, Black}, wide: 1, bare: true,
		kilt: Tone{Yellow, Earth, EarthD}, stripe: Earth, hem: Red, band: Yellow, weapon: "spear", locks: 1.2, boots: true},
	"atalanta": {skin: Tone{Bone, Plaster, PlasterD}, hair: Tone{Black, Black}, wide: 0.84,
		top: Tone{Red, Red, RedD}, kilt: Tone{Red, Red, RedD}, stripe: RedD, hem: Yellow, band: Red, weapon: "bow", locks: 0.95, boots: true},
	"heracles": {skin: Tone{Skin, SkinD, RedD}, hair: Tone{Black, Black}, wide: 1.22, bare: true,
		kilt: Tone{Bone, Plaster, PlasterD}, stripe: PlasterD, hem: Red, band: Red, weapon: "club", beard: true, baldric: true},
}

// Figure 生成一个人物。身体各段都挂在关节位置上，关节随时间变化就是动作。
func (tr *Terrain) Figure(s *Splats, a Actor, t float64) {
	K := kits[a.Kind]
	sc := a.Scale
	if sc == 0 {
		sc = 1
	}
	W := K.wide
	f := V3{a.Face[0], 0, a.Face[1]}.Unit()
	sd := V3{f[2], 0, -f[0]}
	o := V3{a.X, tr.Yf(a.X, a.Z), a.Z}
	at := func(fw, up, side float32) V3 {
		return o.Add(f.Mul(fw * sc)).Add(Up.Mul(up * sc)).Add(sd.Mul(side * sc))
	}
	nd := func(p V3, rx, rz float32) Node { return Node{p, rx * sc, rz * sc} }
	r3 := func(x, y, z float32) V3 { return V3{x * sc, y * sc, z * sc} }
	ax := &Axes{sd, Up, f}
	const M = 1

	// 动作：呼吸、重心左右换、头慢慢转、眨眼
	br, sway := sin(Tau*t+a.Phase), sin(Tau*t+a.Phase+1.2)
	bob, shift, lean := br*0.012, sway*0.022, sway*0.012
	blink := frac(t+a.Phase*0.37) > 0.93

	skin, hair, kilt, stripe, hem := K.skin, K.hair, K.kilt, K.stripe, K.hem
	gold := Tone{Yellow, Yellow, Earth}
	shaft, tip, eye, rim := Tone{Earth, Earth, EarthD}, Tone{SkinL, Red, RedD}, Black, Yellow
	if a.Divine >= 1 {
		eye = Blue
	}
	if a.Divine >= 2 {
		gold = Tone{BlueL, Blue, BlueD}
		rim = Blue
	}
	if a.Divine >= 3 {
		kilt, stripe, hem = Tone{Blue, Blue, BlueD}, BlueD, BlueL
		shaft, tip = Tone{Blue, Blue, BlueD}, Tone{Bone, BlueL, Blue}
	}
	if a.Divine >= 4 {
		hair, skin = Tone{BlueD, BlueD}, Tone{BlueL, Blue, BlueD}
	}

	// ---- 腿：大腿、膝、小腿肚、脚踝；靴子到小腿中间 ----
	for _, sg := range []float32{-1, 1} {
		step := 0.05 * sg // 两脚一前一后
		hip, knee, ank := at(0, 0.92+bob*0.5, 0.1*sg*W+shift), at(0.03+step, 0.5, 0.11*sg*W+shift*0.4), at(step, 0.09, 0.12*sg*W)
		s.Tube([]Node{nd(hip, 0.1*W, 0.105*W), nd(lerp(hip, knee, 0.5).Add(f.Mul(0.02*sc)), 0.1*W, 0.105*W), nd(knee, 0.068*W, 0.07*W),
			nd(lerp(knee, ank, 0.4).Sub(f.Mul(0.025*sc)), 0.078*W, 0.085*W), nd(ank, 0.048, 0.05)}, sd, skin, M, func(u, n V3) uint8 {
			if K.boots {
				if u[1] > 0.74 {
					return Tone{Bone, Plaster, PlasterD}.At(n)
				}
				if u[1] > 0.7 {
					return hem
				}
			} else if u[1] > 0.86 && u[1] < 0.92 {
				return gold.At(n)
			}
			return skin.At(n)
		}, 0)
		foot := skin
		if K.boots {
			foot = Tone{Bone, Plaster, PlasterD}
		}
		s.Ellipsoid(at(step+0.07, 0.045, 0.12*sg*W), r3(0.06, 0.05, 0.135), foot, M, ax, nil, 0)
	}

	// ---- 短裙：腰带、斜织纹、白边、下摆，前面垂一条饰带 ----
	belt := Tone{Yellow, Yellow, Earth}
	if hem != Red && a.Divine < 3 {
		belt = Tone{Red, Red, RedD}
	}
	if a.Divine >= 2 {
		belt = gold
	}
	s.Tube([]Node{nd(at(0, 1.04+bob, shift), 0.135*W, 0.115), nd(at(0, 0.94+bob, shift), 0.185*W, 0.15),
		nd(at(0.01, 0.76+bob*0.5, shift*0.7), 0.215*W, 0.18), nd(at(0.02, 0.62, shift*0.5), 0.225*W, 0.19)}, sd, kilt, M, func(u, n V3) uint8 {
		switch t := u[1]; {
		case t < 0.15:
			return belt.At(n)
		case t > 0.88:
			return hem
		case t > 0.8:
			return Bone
		case math.Sin(math.Atan2(float64(u[2]), float64(u[0]))*5+float64(t)*13) > 0.6:
			return stripe
		}
		return kilt.At(n)
	}, 2)
	fl := sway * 0.02
	s.Tube([]Node{nd(at(0.14, 1.0+bob, shift), 0.055, 0.03), nd(at(0.18, 0.78, shift+fl), 0.045, 0.025), nd(at(0.2, 0.5, shift+fl*2), 0.012, 0.012)},
		sd, Tone{hem, hem, Dark[hem]}, M, func(u, n V3) uint8 {
			return Tone{hem, hem, Dark[hem]}.At(n)
		}, 0)

	// ---- 躯干：细腰、宽肩 ----
	body := skin
	if !K.bare {
		body = K.top
	}
	tor := func(up, k float32) V3 { return at(lean*k, up+bob, shift*(1-k*1.6)) }
	s.Tube([]Node{nd(tor(0.98, 0), 0.13*W, 0.105), nd(tor(1.08, 0.3), 0.125*W, 0.1), nd(tor(1.22, 0.6), 0.19*W, 0.125*W),
		nd(tor(1.34, 0.85), 0.235*W, 0.145*W), nd(tor(1.43, 1), 0.22*W, 0.115*W), nd(tor(1.49, 1), 0.085, 0.075)}, sd, body, M, func(u, n V3) uint8 {
		t, front := u[1], u[2] > 0.25
		if K.baldric && math.Abs(float64(u[0])-float64(t-0.55)*2.6) < 0.2 && t > 0.2 && t < 0.92 {
			return Tone{Red, Red, RedD}.At(n)
		}
		if K.bare {
			if t > 0.84 && t < 0.9 { // 项圈
				return gold.At(n)
			}
			if front && ((math.Abs(float64(t)-0.63) < 0.018 && abs32(u[0]) > 0.12) || (abs32(u[0]) < 0.05 && t > 0.3 && t < 0.62)) {
				return skin[len(skin)-1] // 胸线和腹中线
			}
		} else if t > 0.86 && front && abs32(u[0]) < 0.3 {
			return skin.At(n) // 领口
		} else if t < 0.1 || (t > 0.8 && t < 0.84) {
			return K.hem
		}
		return body.At(n)
	}, 0)
	for _, sg := range []float32{-1, 1} {
		s.Ellipsoid(tor(1.42, 1).Add(sd.Mul(0.235*sg*W*sc)), r3(0.085*W, 0.08*W, 0.085*W), body, M, ax, nil, 0)
	}
	s.Tube([]Node{nd(tor(1.47, 1), 0.062*W, 0.062*W), nd(tor(1.57, 1.1), 0.055*W, 0.058*W)}, sd, skin, M, nil, 0)

	// ---- 头 ----
	yaw := float64(sway)*0.16 + 0.1
	hf := f.Mul(cos(yaw)).Add(sd.Mul(sin(yaw)))
	hs := V3{hf[2], 0, -hf[0]}
	hax := &Axes{hs, Up, hf}
	// 头按 1.4 倍做：照真实比例，脸在游戏镜头里只有六七个像素宽，看不清五官
	hk := sc * 1.4
	hc := tor(1.8, 1.2).Add(Up.Mul(bob * 0.4 * sc))
	hp := func(side, up, fw float32) V3 {
		return hc.Add(hs.Mul(side * hk)).Add(Up.Mul(up * hk)).Add(hf.Mul(fw * hk))
	}
	h3 := func(x, y, z float32) V3 { return V3{x * hk, y * hk, z * hk} }
	s.Ellipsoid(hc, h3(0.165, 0.2, 0.185), nil, M, hax, func(u, n V3) uint8 {
		if u[1] > 0.66-0.1*u[2] || u[2] < -0.3 {
			return hair.At(n)
		}
		ex, ey := abs32(abs32(u[0])-0.5), u[1]+0.02
		if u[2] > 0.3 {
			if !blink && (ex/0.28)*(ex/0.28)+(ey/0.19)*(ey/0.19) < 1 { // 杏仁眼
				if ex < 0.13 {
					return eye
				}
				return Bone
			}
			if ex < 0.32 && ((ey > 0.17 && ey < 0.24) || (blink && abs32(ey) < 0.04)) { // 上眼线
				return Black
			}
			if ex < 0.33 && ey > 0.32 && ey < 0.4 { // 眉
				return hair[len(hair)-1]
			}
		}
		if K.beard && u[1] < -0.28 && u[2] > -0.25 {
			return hair.At(n)
		}
		if u[2] > 0.72 && abs32(u[1]+0.5) < 0.05 && abs32(u[0]) < 0.3 { // 嘴
			return RedD
		}
		return skin.At(n)
	}, 5)
	s.Ellipsoid(hp(0, -0.03, 0.185), h3(0.035, 0.06, 0.05), skin, M, hax, nil, 0) // 鼻子
	for _, sg := range []float32{-1, 1} {
		s.Ellipsoid(hp(0.165*sg, -0.02, -0.01), h3(0.028, 0.055, 0.04), Tone{skin[1], skin[len(skin)-1]}, M, hax, nil, 0) // 耳朵
	}
	// 头发：头顶一粒粒的卷发，额前一圈发带，脑后和耳前垂下几绺
	rr := rand.New(rand.NewPCG(uint64(len(a.Kind)), 21))
	nCurl := 110
	for i := 0; i < nCurl; i++ {
		phi := math.Acos(1 - 2*(float64(i)+0.5)/float64(nCurl))
		th := math.Pi * (1 + math.Sqrt(5)) * (float64(i) + 0.5)
		u := V3{cos(th) * sin(phi), cos(phi), sin(th) * sin(phi)}
		chin := K.beard && u[1] < -0.3 && u[2] > -0.1 && u[2] < 0.75
		if !(u[1] > 0.7-0.1*u[2] || u[2] < -0.35) && !chin {
			continue
		}
		r := 0.034 + 0.016*rr.Float32()
		s.Ellipsoid(hp(u[0]*0.175, u[1]*0.21, u[2]*0.195), h3(r, r, r), hair, M, nil, nil, 0)
	}
	var ring []Node
	for k := 0; k <= 16; k++ {
		an := Tau * float64(k) / 16
		ring = append(ring, nd(hp(cos(an)*0.168, 0.14-0.02*sin(an), sin(an)*0.187), 0.012, 0.015))
	}
	bandT := Tone{K.band, K.band, Dark[K.band]}
	if a.Divine >= 2 {
		bandT = gold
	}
	s.Tube(ring, Up, bandT, M, nil, 0)
	if K.locks > 0 {
		for i, q := range []float32{-0.11, -0.04, 0.04, 0.11} {
			w := sin(Tau*t+a.Phase+float64(i)) * 0.02
			s.Tube([]Node{nd(hp(q, 0.06, -0.14), 0.05, 0.05), nd(hp(q*1.2+w, -0.16, -0.2), 0.045, 0.045),
				nd(tor(K.locks+0.18, 1).Add(sd.Mul((q*1.4+w*2)*sc)).Sub(f.Mul(0.16*sc)), 0.04, 0.04),
				nd(tor(K.locks, 1).Add(sd.Mul((q*1.5+w*3)*sc)).Sub(f.Mul(0.13*sc)), 0.018, 0.018)}, hs, hair, M, nil, 0)
		}
		for _, sg := range []float32{-1, 1} { // 耳前的一绺
			s.Tube([]Node{nd(hp(0.15*sg, 0.08, 0.06), 0.026, 0.026), nd(hp(0.175*sg, -0.14, 0.07), 0.024, 0.024),
				nd(tor(1.36, 1).Add(sd.Mul(0.17*sg*W*sc)).Add(f.Mul(0.12*sc)), 0.012, 0.012)}, hs, hair, M, nil, 0)
		}
	}

	// ---- 手臂 ----
	arm := func(sh, el, hd V3) {
		out := el.Sub(lerp(sh, hd, 0.5)).Unit().Mul(0.01 * sc)
		s.Tube([]Node{nd(sh, 0.075*W, 0.075*W), nd(lerp(sh, el, 0.45).Add(out), 0.078*W, 0.08*W), nd(el, 0.055*W, 0.055*W),
			nd(lerp(el, hd, 0.35), 0.06*W, 0.058*W), nd(hd, 0.04*W, 0.04*W)}, f, skin, M, func(u, n V3) uint8 {
			if (u[1] > 0.2 && u[1] < 0.26) || (u[1] > 0.88 && u[1] < 0.94) { // 臂环和手镯
				return gold.At(n)
			}
			return skin.At(n)
		}, 0)
		s.Ellipsoid(hd, r3(0.052*W, 0.052*W, 0.052*W), skin, M, nil, nil, 0)
	}
	shR, shL := tor(1.42, 1).Sub(sd.Mul(0.245*W*sc)), tor(1.42, 1).Add(sd.Mul(0.245*W*sc))
	switch K.weapon {
	case "spear":
		hd := at(0.27, 1.18+bob*2, -0.31*W)
		arm(shR, at(0.05, 1.15+bob, -0.36*W), hd)
		foot := at(0.3, 0.02, -0.34*W).Add(sd.Mul(sway * 0.02 * sc))
		dir := hd.Sub(foot).Unit()
		top := foot.Add(dir.Mul(2.3 * sc))
		s.Tube([]Node{nd(foot, 0.012, 0.012), nd(foot.Add(dir.Mul(0.1*sc)), 0.024, 0.024), nd(top, 0.022, 0.022)}, sd, shaft, M, nil, 1)
		s.Tube([]Node{nd(top.Sub(dir.Mul(0.04*sc)), 0.034, 0.034), nd(top.Add(dir.Mul(0.03*sc)), 0.034, 0.034)}, sd, gold, M, nil, 0)
		s.Tube([]Node{nd(top, 0.02, 0.02), nd(top.Add(dir.Mul(0.1*sc)), 0.012, 0.07), nd(top.Add(dir.Mul(0.22*sc)), 0.01, 0.05),
			nd(top.Add(dir.Mul(0.36*sc)), 0.004, 0.004)}, sd, tip, M, nil, 0) // 叶形矛头
	case "club":
		hd := at(0.2, 0.95+bob, -0.37*W)
		arm(shR, at(-0.02, 1.13+bob, -0.4*W), hd)
		dir := Up.Mul(0.86).Sub(f.Mul(0.3)).Sub(sd.Mul(0.25)).Unit()
		wood := Tone{Earth, EarthD, RedD}
		s.Tube([]Node{nd(hd.Sub(dir.Mul(0.14*sc)), 0.04, 0.04), nd(hd, 0.034, 0.034), nd(hd.Add(dir.Mul(0.45*sc)), 0.065, 0.065),
			nd(hd.Add(dir.Mul(0.85*sc)), 0.125, 0.125), nd(hd.Add(dir.Mul(1.02*sc)), 0.09, 0.09)}, sd, wood, M, nil, 3)
		for k := 0; k < 9; k++ { // 木瘤
			an := float64(k) * 2.4
			e1 := dir.Cross(Up).Unit()
			e2 := dir.Cross(e1)
			c := hd.Add(dir.Mul((0.55 + 0.045*float32(k)) * sc)).Add(e1.Mul(cos(an) * 0.1 * sc)).Add(e2.Mul(sin(an) * 0.1 * sc))
			s.Ellipsoid(c, r3(0.04, 0.04, 0.04), wood, M, nil, nil, 0)
		}
	case "bow":
		arm(shR, at(-0.04, 1.13+bob, -0.3*W), at(0.1, 0.9+bob, -0.27*W))
	}
	switch K.weapon {
	case "spear": // 八字形的牛皮盾
		hd := at(0.18, 1.12+bob, 0.38*W)
		arm(shL, at(0, 1.14+bob, 0.36*W), hd)
		nrm := sd.Mul(0.82).Add(f.Mul(0.57)).Unit()
		tang := nrm.Cross(Up).Unit()
		sax := &Axes{tang, Up, nrm}
		hide := func(r float32) ColFn {
			return func(u, n V3) uint8 {
				if u[2] < -0.2 {
					return EarthD
				}
				if u[0]*u[0]+u[1]*u[1] > 0.74 {
					return rim
				}
				x, y := float64(u[0]*r)*9, float64(u[1]*r)*9
				if math.Sin(x*1.9+1)*math.Sin(y*1.6+x*0.7) > 0.28 {
					if math.Sin(x*3+y) > 0.3 {
						return Black
					}
					return EarthD
				}
				if n.Dot(Light) > 0.1 {
					return Bone
				}
				return Plaster
			}
		}
		c := hd.Add(sd.Mul(0.1 * sc)).Sub(Up.Mul(0.16 * sc))
		s.Ellipsoid(c.Add(Up.Mul(0.25*sc)), r3(0.23, 0.24, 0.06), nil, M, sax, hide(0.23), 3.2)
		s.Ellipsoid(c.Sub(Up.Mul(0.2*sc)), r3(0.29, 0.3, 0.07), nil, M, sax, hide(0.29), 3.2)
		s.Ellipsoid(c.Add(Up.Mul(0.04*sc)).Add(nrm.Mul(0.06*sc)), r3(0.06, 0.06, 0.04), gold, M, sax, nil, 0)
	case "bow":
		hd := at(0.38, 1.24+bob, 0.26*W)
		arm(shL, at(0.16, 1.16+bob, 0.33*W), hd)
		var limb []Node
		for k := 0; k <= 10; k++ {
			q := float32(k)/5 - 1 // -1..1
			aq := abs32(q)
			fwd := -0.3*q*q + 0.16*aq*aq*aq*aq // 反曲弓：弓梢朝前翘
			limb = append(limb, nd(hd.Add(Up.Mul(q*0.66*sc)).Add(f.Mul(fwd*sc)), 0.026-0.014*aq, 0.03-0.016*aq))
		}
		s.Tube(limb, sd, Tone{Earth, Earth, EarthD}, M, func(u, n V3) uint8 {
			if abs32(u[1]-0.5) < 0.07 || u[1] < 0.04 || u[1] > 0.96 {
				return gold.At(n)
			}
			return Tone{Earth, Earth, EarthD}.At(n)
		}, 3)
		s.Line(limb[0].P, limb[10].P, 0.008*sc, Tone{Bone, Bone}, M)
		qa, qb := tor(1.0, 0.5).Sub(f.Mul(0.17*sc)).Sub(sd.Mul(0.1*sc)), tor(1.55, 1).Sub(f.Mul(0.2*sc)).Add(sd.Mul(0.13*sc))
		s.Tube([]Node{nd(qa, 0.05, 0.05), nd(lerp(qa, qb, 0.5), 0.065, 0.065), nd(qb, 0.07, 0.07)}, sd, Tone{RedD, RedD, Black}, M, func(u, n V3) uint8 {
			if u[1] > 0.88 || abs32(u[1]-0.45) < 0.04 {
				return gold.At(n)
			}
			return Tone{Earth, EarthD, RedD}.At(n)
		}, 3) // 箭袋
		qd := qb.Sub(qa).Unit()
		for k, q := range []float32{-0.03, 0.01, 0.04} {
			e := qb.Add(qd.Mul((0.12 + 0.03*float32(k)) * sc)).Add(sd.Mul(q * sc))
			s.Line(qb.Add(sd.Mul(q*sc)), e, 0.008*sc, Tone{Earth, EarthD}, M)
			s.Ellipsoid(e, r3(0.022, 0.045, 0.022), Tone{Bone, Plaster}, M, nil, nil, 0)
		}
	default:
		arm(shL, at(-0.06, 1.12+bob, 0.42*W), at(0.07, 0.98+bob, 0.25*W)) // 叉腰
	}
}
