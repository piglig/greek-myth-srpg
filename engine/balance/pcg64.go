package balance

import "math/bits"

// PCG64 复刻 numpy.random.default_rng(seed)：SeedSequence 播种 + PCG64（XSL-RR 128/64），
// 以及 Generator.integers 的 32 位 Lemire 有界取整。自助法区间因此和 scipy 完全一致。
type PCG64 struct {
	hi, lo       uint64 // 128 位状态
	incHi, incLo uint64
	has32        bool
	buf32        uint32
}

const (
	pcgMulHi = 0x2360ED051FC65DA4
	pcgMulLo = 0x4385DF649FCCF645
)

// NewPCG64 等价于 np.random.default_rng(seed)。
func NewPCG64(seed uint64) *PCG64 {
	s := seedSequence(seed, 4)
	p := &PCG64{}
	// pcg_setseq_128_srandom_r：state = 0; inc = (initseq << 1) | 1; step; state += initstate; step
	p.incHi = s[2]<<1 | s[3]>>63
	p.incLo = s[3]<<1 | 1
	p.step()
	var c uint64
	p.lo, c = bits.Add64(p.lo, s[1], 0)
	p.hi, _ = bits.Add64(p.hi, s[0], c)
	p.step()
	return p
}

func (p *PCG64) step() {
	hi, lo := bits.Mul64(p.lo, pcgMulLo)
	hi += p.hi*pcgMulLo + p.lo*pcgMulHi
	var c uint64
	p.lo, c = bits.Add64(lo, p.incLo, 0)
	p.hi, _ = bits.Add64(hi, p.incHi, c)
}

// Uint64 是下一个 64 位输出。
func (p *PCG64) Uint64() uint64 {
	p.step()
	return bits.RotateLeft64(p.hi^p.lo, -int(p.hi>>58))
}

// Uint32 按 numpy 的方式把一个 64 位输出拆成两个 32 位（先低后高）。
func (p *PCG64) Uint32() uint32 {
	if p.has32 {
		p.has32 = false
		return p.buf32
	}
	v := p.Uint64()
	p.has32 = true
	p.buf32 = uint32(v >> 32)
	return uint32(v)
}

// Below 返回 [0, n) 内的均匀整数，等价于 rng.integers(0, n)（n < 2^32）。
func (p *PCG64) Below(n uint32) uint32 {
	if n <= 1 {
		return 0
	}
	m := uint64(p.Uint32()) * uint64(n)
	left := uint32(m)
	if left < n {
		threshold := uint32((0xFFFFFFFF - uint64(n-1)) % uint64(n))
		for left < threshold {
			m = uint64(p.Uint32()) * uint64(n)
			left = uint32(m)
		}
	}
	return uint32(m >> 32)
}

// seedSequence 等价于 np.random.SeedSequence(seed).generate_state(n, np.uint64)。
func seedSequence(seed uint64, n int) []uint64 {
	const (
		initA, multA = 0x43b0d7e5, 0x931e8875
		initB, multB = 0x8b51f9dd, 0x58f38ded
		mixL, mixR   = 0xca01f9dd, 0x4973f715
		shift        = 16
	)
	entropy := []uint32{uint32(seed)}
	if seed>>32 != 0 {
		entropy = append(entropy, uint32(seed>>32))
	}
	hc := uint32(initA)
	hashmix := func(v uint32) uint32 {
		v ^= hc
		hc *= multA
		v *= hc
		return v ^ v>>shift
	}
	mix := func(x, y uint32) uint32 {
		r := mixL*x - mixR*y
		return r ^ r>>shift
	}
	var pool [4]uint32
	for i := range pool {
		if i < len(entropy) {
			pool[i] = hashmix(entropy[i])
		} else {
			pool[i] = hashmix(0)
		}
	}
	for src := range pool {
		for dst := range pool {
			if src != dst {
				pool[dst] = mix(pool[dst], hashmix(pool[src]))
			}
		}
	}
	hb := uint32(initB)
	words := make([]uint32, 2*n)
	for i := range words {
		v := pool[i%4] ^ hb
		hb *= multB
		v *= hb
		words[i] = v ^ v>>shift
	}
	out := make([]uint64, n)
	for i := range out {
		out[i] = uint64(words[2*i]) | uint64(words[2*i+1])<<32
	}
	return out
}
