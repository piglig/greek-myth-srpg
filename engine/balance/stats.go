// Package balance 是平衡分析：统计、设计目标判定、自适应模拟、参数扫描、报告。
//
// 数值方法和原 Python 版（scipy / numpy / statsmodels）逐位对齐：Wilson 区间、
// 固定种子的百分位自助法（同一个 PCG64 随机流）、Bonferroni 多次查看、Logit 平均边际效应、OLS。
package balance

import (
	"fmt"
	"math"
	"sort"
	"strconv"
)

// DefaultLevel 是默认置信水平。
const DefaultLevel = 0.95

// Estimate 是点估计加置信区间。
type Estimate struct {
	Value, Lo, Hi float64
	N             int
}

// Fmt 输出 "84%（71%–92%）" 或 "8.0（7.0–9.0）"。
func (e Estimate) Fmt(pct bool) string {
	if e.N == 0 {
		return "—"
	}
	if pct {
		return fmt.Sprintf("%s（%s–%s）", Pct0(e.Value), Pct0(e.Lo), Pct0(e.Hi))
	}
	return fmt.Sprintf("%.1f（%.1f–%.1f）", e.Value, e.Lo, e.Hi)
}

// Pct0 等价于 Python 的 f"{x:.0%}"。
func Pct0(x float64) string {
	if math.IsNaN(x) {
		return "nan%"
	}
	return strconv.FormatFloat(x*100, 'f', 0, 64) + "%"
}

// FmtG 等价于 Python 的 f"{x:g}"。
func FmtG(x float64) string { return strconv.FormatFloat(x, 'g', 6, 64) }

// NormPPF 是标准正态分布的分位数函数（scipy.stats.norm.ppf）。
func NormPPF(p float64) float64 { return ndtri(p) }

func levelOr(level float64) float64 {
	if level == 0 {
		return DefaultLevel
	}
	return level
}

// Proportion 是比例的 Wilson 区间；level 传 0 表示 95%。
func Proportion(successes, n int, level float64) Estimate {
	if n == 0 {
		return Estimate{math.NaN(), 0, 1, 0}
	}
	z := NormPPF(0.5 + levelOr(level)/2)
	fn := float64(n)
	p := float64(successes) / fn
	denom := 1 + z*z/fn
	centre := (p + z*z/(2*fn)) / denom
	half := z * math.Sqrt(p*(1-p)/fn+z*z/(4*fn*fn)) / denom
	return Estimate{p, math.Max(0, centre-half), math.Min(1, centre+half), n}
}

// Median 是中位数加百分位自助法区间（固定种子 0，2000 次重采样，与 scipy.stats.bootstrap 相同）。
func Median(values []float64, level float64) Estimate {
	return bootstrap(values, levelOr(level), 0, medianOf)
}

// Mean 是均值加百分位自助法区间。
func Mean(values []float64, level float64) Estimate {
	return bootstrap(values, levelOr(level), 0, meanOf)
}

const nResamples = 2000

func bootstrap(values []float64, level float64, seed uint64, stat func([]float64) float64) Estimate {
	n := len(values)
	if n == 0 {
		return Estimate{math.NaN(), math.NaN(), math.NaN(), 0}
	}
	same := true
	for _, v := range values {
		same = same && v == values[0]
	}
	if n == 1 || same {
		return Estimate{values[0], values[0], values[0], n}
	}
	rng := NewPCG64(seed)
	theta := make([]float64, nResamples)
	buf := make([]float64, n)
	for k := range theta {
		for i := range buf {
			buf[i] = values[rng.Below(uint32(n))]
		}
		theta[k] = stat(buf)
	}
	sort.Float64s(theta)
	alpha := (1 - level) / 2
	return Estimate{stat(append([]float64(nil), values...)), percentileSorted(theta, alpha*100),
		percentileSorted(theta, (1-alpha)*100), n}
}

// medianOf 会就地排序。
func medianOf(v []float64) float64 {
	sort.Float64s(v)
	n := len(v)
	if n%2 == 1 {
		return v[n/2]
	}
	return (v[n/2-1] + v[n/2]) / 2
}

// meanOf 用 numpy 的成对求和，保证末位一致。
func meanOf(v []float64) float64 { return pairwiseSum(v) / float64(len(v)) }

func pairwiseSum(a []float64) float64 {
	n := len(a)
	if n < 8 {
		s := 0.0
		for _, x := range a {
			s += x
		}
		return s
	}
	if n <= 128 {
		var r [8]float64
		copy(r[:], a[:8])
		i := 8
		for ; i+8 <= n; i += 8 {
			for j := 0; j < 8; j++ {
				r[j] += a[i+j]
			}
		}
		s := ((r[0] + r[1]) + (r[2] + r[3])) + ((r[4] + r[5]) + (r[6] + r[7]))
		for ; i < n; i++ {
			s += a[i]
		}
		return s
	}
	half := n / 2
	half -= half % 8
	return pairwiseSum(a[:half]) + pairwiseSum(a[half:])
}

// percentileSorted 等价于 np.percentile（线性插值）。
func percentileSorted(sorted []float64, q float64) float64 {
	vi := q / 100 * float64(len(sorted)-1)
	lo := math.Floor(vi)
	t := vi - lo
	i := int(lo)
	if i >= len(sorted)-1 {
		return sorted[len(sorted)-1]
	}
	a, b := sorted[i], sorted[i+1]
	if t >= 0.5 {
		return b - (b-a)*(1-t)
	}
	return a + (b-a)*t
}

// RunsForMargin 是让比例的区间约为 ±margin 所需的局数（最坏情况 p = 0.5）。
func RunsForMargin(margin, p, level float64) int {
	z := NormPPF(0.5 + levelOr(level)/2)
	return int(math.Ceil(z * z * p * (1 - p) / (margin * margin)))
}

// roundTo 等价于 Python 的 round(x, digits)。
func roundTo(x float64, digits int) float64 {
	if math.IsNaN(x) || math.IsInf(x, 0) {
		return x
	}
	f, _ := strconv.ParseFloat(strconv.FormatFloat(x, 'f', digits, 64), 64)
	return f
}

// RoundTo 导出给工坊分析用。
func RoundTo(x float64, digits int) float64 { return roundTo(x, digits) }
