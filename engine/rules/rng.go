package rules

import (
	"math"
	"math/bits"
)

// RNG 逐位复刻 Godot 的 RandomNumberGenerator（core/math/random_pcg：PCG32）。
// 同一个种子下 Randi / Randf / RandfRange / RandiRange 的输出与 Godot 4 完全一致。
type RNG struct {
	state uint64
	inc   uint64
}

const (
	pcgDefaultInc = 1442695040888963407
	pcgMult       = 6364136223846793005
)

// NewRNG 等价于 `rng = RandomNumberGenerator.new(); rng.seed = seed`。
func NewRNG(seed int64) *RNG {
	r := &RNG{}
	r.Seed(seed)
	return r
}

// Seed 对应 pcg32_srandom_r(state, seed, DEFAULT_INC)。
func (r *RNG) Seed(seed int64) {
	r.state = 0
	r.inc = (pcgDefaultInc << 1) | 1
	r.Randi()
	r.state += uint64(seed)
	r.Randi()
}

// Randi 返回下一个 32 位随机数（pcg32_random_r）。
func (r *RNG) Randi() uint32 {
	old := r.state
	r.state = old*pcgMult + (r.inc | 1)
	xorshifted := uint32(((old >> 18) ^ old) >> 27)
	rot := uint32(old >> 59)
	return bits.RotateLeft32(xorshifted, -int(rot))
}

// Randf 返回 [0, 1] 的单精度随机数（Godot 的 randf 是 float32，再提升为 64 位）。
func (r *RNG) Randf() float64 {
	return float64(r.randf32())
}

func (r *RNG) randf32() float32 {
	proto := r.Randi()
	if proto == 0 {
		return 0
	}
	m := float32(r.Randi() | 0x80000001)
	return float32(math.Ldexp(float64(m), -32-bits.LeadingZeros32(proto)))
}

// RandfRange 对应 randf_range：整个算式在单精度里完成，与引擎一致。
func (r *RNG) RandfRange(from, to float64) float64 {
	f, t := float32(from), float32(to)
	span := float32(t - f)
	prod := float32(r.randf32() * span)
	return float64(float32(prod + f))
}

// RandiRange 对应 randi_range（含两端）。
func (r *RNG) RandiRange(from, to int) int {
	if from == to {
		return from
	}
	lo, hi := int64(from), int64(to)
	if lo > hi {
		lo, hi = hi, lo
	}
	bound := uint32(hi-lo) + 1
	if bound == 0 {
		return int(int64(r.Randi()) + lo)
	}
	threshold := -bound % bound
	for {
		v := r.Randi()
		if v >= threshold {
			return int(int64(v%bound) + lo)
		}
	}
}
