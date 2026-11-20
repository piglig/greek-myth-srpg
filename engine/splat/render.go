package splat

import (
	"bufio"
	"encoding/binary"
	"fmt"
	"image"
	"image/color"
	"math"
	"os"
	"runtime"
	"sort"
	"sync"
)

// View 是一次渲染的镜头设置。镜头是正交的 2:1 等距视角。
type View struct {
	W, H   int // 输出的像素尺寸
	SS     int // 超采样倍数
	Turn   int // 绕沙盘中心转几个 90 度
	Center V3  // 画面中心对着的世界坐标
	Pivot  [2]float32
	TilePx float32 // 一格在屏幕上的宽度
}

func DefaultView() View {
	return View{W: 640, H: 360, SS: 2, Center: V3{7, 0.55, 7}, Pivot: [2]float32{7, 7}, TilePx: 40}
}

type proj struct {
	u, v, depth float32
	ia, ib, ic  float32 // 屏幕上协方差的逆
	rad         int32
	idx         int32
}

// Render 把面元渲染成调色板图像：先以 SS 倍分辨率做由近到远的 alpha 合成，
// 每个像素取权重最大的那种调色板颜色，最后勾线。
func Render(g *Splats, vw View) *image.Paletted {
	ss := vw.SS
	Ws, Hs := vw.W*ss, vw.H*ss
	ca, sa := cos(float64(vw.Turn)*math.Pi/2), sin(float64(vw.Turn)*math.Pi/2)
	rot := func(p V3, cx, cz float32) V3 {
		x, z := p[0]-cx, p[2]-cz
		return V3{x*ca - z*sa + cx, p[1], x*sa + z*ca + cz}
	}
	k := vw.TilePx / 2 * float32(ss)
	kv := vw.TilePx / 2 * float32(math.Sqrt(1.5)) * float32(ss)
	J := [2]V3{{k, 0, -k}, {k / 2, -kv, k / 2}}
	jj00, jj01, jj11 := J[0].Dot(J[0]), J[0].Dot(J[1]), J[1].Dot(J[1])

	n := g.Len()
	ps := make([]proj, n)
	nys := make([]float32, n)
	parallel(n, func(lo, hi int) {
		for i := lo; i < hi; i++ {
			p := rot(g.P[i], vw.Pivot[0], vw.Pivot[1])
			nr := rot(g.N[i], 0, 0)
			nys[i] = nr[1]
			d := p.Sub(vw.Center)
			jn0, jn1 := J[0].Dot(nr), J[1].Dot(nr)
			s2, t2 := g.S[i]*g.S[i], g.T[i]*g.T[i]
			c00 := s2*(jj00-jn0*jn0) + t2*jn0*jn0 + 0.3
			c01 := s2*(jj01-jn0*jn1) + t2*jn0*jn1
			c11 := s2*(jj11-jn1*jn1) + t2*jn1*jn1 + 0.3
			det := c00*c11 - c01*c01
			ps[i] = proj{
				u: J[0].Dot(d) + float32(Ws)/2, v: J[1].Dot(d) + float32(Hs)/2,
				depth: (p[0]+p[2])*0.6124 + p[1]*0.5,
				ia:    c11 / det, ib: -c01 / det, ic: c00 / det,
				rad: int32(min(8, math.Ceil(3*math.Sqrt(float64(max(c00, c11)))))), idx: int32(i),
			}
		}
	})
	sort.Slice(ps, func(a, b int) bool { return ps[a].depth > ps[b].depth }) // 近的先画

	Tr := make([]float32, Ws*Hs)
	for i := range Tr {
		Tr[i] = 1
	}
	// 每个采样按调色板编号累计权重，最后取权重最大的那种颜色。不做 RGB 混合，所以不会混出调色板以外的色相
	V := make([]uint16, Ws*Hs*int(nColors))
	Dp, Mk, NY := make([]float32, Ws*Hs), make([]float32, Ws*Hs), make([]float32, Ws*Hs)
	// 按水平条带并行：每个条带只写自己的像素，条带内保持由近到远的顺序
	bands := runtime.NumCPU()
	bandH := (Hs + bands - 1) / bands
	var wg sync.WaitGroup
	for b := 0; b < bands; b++ {
		y0, y1 := b*bandH, min(Hs, (b+1)*bandH)
		wg.Add(1)
		go func() {
			defer wg.Done()
			for pi := range ps {
				p := &ps[pi]
				cy := int(math.RoundToEven(float64(p.v)))
				r := int(p.rad)
				if cy+r < y0 || cy-r >= y1 {
					continue
				}
				cx := int(math.RoundToEven(float64(p.u)))
				i := p.idx
				op, ci, mk, ny := g.O[i], int(g.C[i]), float32(g.M[i]), nys[i]
				for py := max(y0, cy-r); py <= min(y1-1, cy+r); py++ {
					dy := float32(py) - p.v
					for px := max(0, cx-r); px <= min(Ws-1, cx+r); px++ {
						q := py*Ws + px
						tr := Tr[q]
						if tr < 0.003 {
							continue
						}
						dx := float32(px) - p.u
						e := p.ia*dx*dx + 2*p.ib*dx*dy + p.ic*dy*dy
						if e > 10 {
							continue
						}
						al := op * float32(math.Exp(float64(-0.5*e)))
						if al < 1.0/255 {
							continue
						}
						w := tr * al
						V[q*int(nColors)+ci] += uint16(w * 65000)
						Dp[q] += w * p.depth
						Mk[q] += w * mk
						NY[q] += w * ny
						Tr[q] = tr * (1 - al)
					}
				}
			}
		}()
	}
	wg.Wait()

	// 像素化
	W, H := vw.W, vw.H
	out := make([]uint8, W*H)
	solid, mask, top := make([]bool, W*H), make([]bool, W*H), make([]bool, W*H)
	depth := make([]float32, W*H)
	parallel(H, func(lo, hi int) {
		var votes [nColors]uint32
		for y := lo; y < hi; y++ {
			for x := 0; x < W; x++ {
				votes = [nColors]uint32{}
				var cov, d, m, ny float32
				for sy := 0; sy < ss; sy++ {
					for sx := 0; sx < ss; sx++ {
						q := (y*ss+sy)*Ws + x*ss + sx
						a := max(1-Tr[q], 1e-4)
						for c, v := range V[q*int(nColors) : (q+1)*int(nColors)] {
							votes[c] += uint32(v)
						}
						cov += 1 - Tr[q]
						d += Dp[q] / a
						m += Mk[q] / a
						ny += NY[q] / a
					}
				}
				best := 0
				for c := 1; c < int(nColors); c++ {
					if votes[c] > votes[best] {
						best = c
					}
				}
				nn := float32(ss * ss)
				p := y*W + x
				out[p] = uint8(best)
				solid[p] = cov/nn > 0.5
				depth[p] = -1e3
				if solid[p] {
					depth[p] = d / nn
				}
				mask[p] = m/nn > 0.5 && solid[p]
				top[p] = ny/nn > 0.5
			}
		}
	})
	// 背景：深蓝底上一排排波纹
	for y := 0; y < H; y++ {
		for x := 0; x < W; x++ {
			if p := y*W + x; !solid[p] {
				out[p] = BlueD
				if y%14 == 6 && (x+(y/14)*11)%30 < 7 {
					out[p] = Blue
				}
			}
		}
	}
	// 勾线：明显比邻居更靠近镜头的边缘涂黑；角色内部的层次用暗一档的颜色；角色外面再加一圈黑边
	res := make([]uint8, W*H)
	copy(res, out)
	for y := 0; y < H; y++ {
		for x := 0; x < W; x++ {
			p := y*W + x
			var edge, inner, ring bool
			for _, o := range [4][2]int{{0, 1}, {0, -1}, {1, 0}, {-1, 0}} {
				nx, ny := x+o[0], y+o[1]
				if nx < 0 || ny < 0 || nx >= W || ny >= H {
					continue
				}
				q := ny*W + nx
				dd := depth[p] - depth[q]
				edge = edge || dd > 0.42
				inner = inner || (dd > 0.13 && mask[q])
				ring = ring || mask[q]
			}
			switch {
			case ring && !mask[p]:
				res[p] = Black
			case inner && mask[p]:
				res[p] = Dark[out[p]]
			case edge && solid[p] && !mask[p]:
				res[p] = Black
			case y+1 < H && top[p] && !top[p+W] && solid[p] && solid[p+W] && !mask[p] && !mask[p+W]:
				res[p] = PlasterDDD // 顶面和侧壁相接的折线
			}
		}
	}
	img := image.NewPaletted(image.Rect(0, 0, W, H), Palette())
	copy(img.Pix, res)
	return img
}

// Palette 返回 image/color 形式的调色板。
func Palette() color.Palette {
	p := make(color.Palette, nColors)
	for i, h := range hexes {
		p[i] = color.RGBA{uint8(h >> 16), uint8(h >> 8), uint8(h), 255}
	}
	return p
}

// Upscale 把图像按整数倍放大（最近邻）。
func Upscale(src *image.Paletted, k int) *image.Paletted {
	b := src.Bounds()
	dst := image.NewPaletted(image.Rect(0, 0, b.Dx()*k, b.Dy()*k), src.Palette)
	for y := 0; y < b.Dy()*k; y++ {
		row := src.Pix[(y/k)*src.Stride:]
		for x := 0; x < b.Dx()*k; x++ {
			dst.Pix[y*dst.Stride+x] = row[x/k]
		}
	}
	return dst
}

func parallel(n int, fn func(lo, hi int)) {
	w := runtime.NumCPU()
	chunk := (n + w - 1) / w
	var wg sync.WaitGroup
	for lo := 0; lo < n; lo += max(chunk, 1) {
		wg.Add(1)
		go func(lo, hi int) { defer wg.Done(); fn(lo, hi) }(lo, min(n, lo+chunk))
	}
	wg.Wait()
}

// WritePLY 导出标准 3DGS 格式的 .ply（球谐只有 0 阶）。
func WritePLY(path string, g *Splats) error {
	f, err := os.Create(path)
	if err != nil {
		return err
	}
	defer f.Close()
	w := bufio.NewWriterSize(f, 1<<20)
	fmt.Fprintf(w, "ply\nformat binary_little_endian 1.0\nelement vertex %d\n", g.Len())
	for _, name := range []string{"x", "y", "z", "nx", "ny", "nz", "f_dc_0", "f_dc_1", "f_dc_2", "opacity", "scale_0", "scale_1", "scale_2", "rot_0", "rot_1", "rot_2", "rot_3"} {
		fmt.Fprintf(w, "property float %s\n", name)
	}
	fmt.Fprint(w, "end_header\n")
	ln := func(x float32) float32 { return float32(math.Log(float64(x))) }
	buf := make([]byte, 17*4)
	for i := range g.P {
		n := g.N[i]
		// 把局部 Z 轴转到法线方向的四元数（w, x, y, z）
		q := [4]float32{1 + n[2], -n[1], n[0], 0}
		l := float32(math.Sqrt(float64(q[0]*q[0] + q[1]*q[1] + q[2]*q[2])))
		if l < 1e-6 {
			q, l = [4]float32{0, 1, 0, 0}, 1
		}
		op := min(max(g.O[i], 1e-4), 1-1e-4)
		c := Pal[g.C[i]]
		vals := [17]float32{g.P[i][0], g.P[i][1], g.P[i][2], n[0], n[1], n[2],
			(c[0] - 0.5) / 0.28209479, (c[1] - 0.5) / 0.28209479, (c[2] - 0.5) / 0.28209479,
			ln(op / (1 - op)), ln(g.S[i]), ln(g.S[i]), ln(g.T[i]), q[0] / l, q[1] / l, q[2] / l, q[3] / l}
		for k, v := range vals {
			binary.LittleEndian.PutUint32(buf[k*4:], math.Float32bits(v))
		}
		w.Write(buf)
	}
	return w.Flush()
}
