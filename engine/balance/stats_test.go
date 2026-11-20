package balance

import (
	"math"
	"testing"
)

func approx(t *testing.T, name string, got, want, tol float64) {
	t.Helper()
	if math.Abs(got-want) > tol || math.IsNaN(got) != math.IsNaN(want) {
		t.Errorf("%s = %.12g，期望 %.12g（容差 %g）", name, got, want, tol)
	}
}

// 参考值来自 np.random.default_rng(0).integers(0, 7, 12) 等。
func TestPCG64MatchesNumpy(t *testing.T) {
	r := NewPCG64(0)
	want := []uint32{5, 4, 3, 1, 2, 0, 0, 0, 1, 5, 4, 6}
	for i, w := range want {
		if g := r.Below(7); g != w {
			t.Fatalf("integers(0,7)[%d] = %d，期望 %d", i, g, w)
		}
	}
	r = NewPCG64(1<<40 + 5)
	for i, w := range []uint32{14, 4, 449, 372, 915} {
		if g := r.Below(1000); g != w {
			t.Fatalf("大种子 integers(0,1000)[%d] = %d，期望 %d", i, g, w)
		}
	}
}

func TestWilsonMatchesReferenceValues(t *testing.T) {
	// 参考：263 中 81 次成功，95% Wilson 区间 ≈ (0.2553, 0.3662)
	e := Proportion(81, 263, 0)
	approx(t, "lo", e.Lo, 0.2553, 5e-4)
	approx(t, "hi", e.Hi, 0.3662, 5e-4)
	// scipy 的精确值
	approx(t, "lo", e.Lo, 0.2552885198782742, 1e-12)
	approx(t, "hi", e.Hi, 0.36620957698280004, 1e-12)
}

func TestWilsonStaysInsideUnitInterval(t *testing.T) {
	approx(t, "lo", Proportion(0, 10, 0).Lo, 0, 1e-12)
	approx(t, "hi", Proportion(10, 10, 0).Hi, 1, 1e-12)
}

func TestRunsForFivePercentMargin(t *testing.T) {
	if n := RunsForMargin(0.05, 0.5, 0.95); n != 385 {
		t.Fatalf("RunsForMargin = %d，期望 385", n)
	}
}

// 参考值来自 Python 版 stats.median / stats.mean（scipy.stats.bootstrap，种子 0）。
func TestBootstrapMatchesScipy(t *testing.T) {
	v := []float64{1, 2, 3, 4, 5, 6, 7, 8, 9, 10.5, 3, 3, 8}
	m := Median(v, 0)
	approx(t, "median", m.Value, 5, 1e-12)
	approx(t, "median.lo", m.Lo, 3, 1e-12)
	approx(t, "median.hi", m.Hi, 8, 1e-12)
	a := Mean(v, 0)
	approx(t, "mean", a.Value, 5.346153846153846, 1e-12)
	approx(t, "mean.lo", a.Lo, 3.769230769230769, 1e-12)
	approx(t, "mean.hi", a.Hi, 6.884615384615385, 1e-12)
	w := make([]float64, 200)
	for i := range w {
		w[i] = 0.1 * float64(i) * float64(i)
	}
	b := Mean(w, 0.9875)
	approx(t, "mean200", b.Value, 1323.35, 1e-9)
	approx(t, "mean200.lo", b.Lo, 1127.6295812500002, 1e-9)
	approx(t, "mean200.hi", b.Hi, 1526.287465625, 1e-9)
}

func TestEstimateFmt(t *testing.T) {
	if s := (Estimate{0.845, 0.7, 0.925, 50}).Fmt(true); s != "84%（70%–92%）" {
		t.Errorf("Fmt = %q", s)
	}
	if s := (Estimate{8, 7.25, 9, 50}).Fmt(false); s != "8.0（7.2–9.0）" {
		t.Errorf("Fmt = %q", s)
	}
	if s := (Estimate{N: 0}).Fmt(true); s != "—" {
		t.Errorf("Fmt = %q", s)
	}
	if FmtG(6) != "6" || FmtG(0.35) != "0.35" || FmtG(1e7) != "1e+07" {
		t.Errorf("FmtG: %s %s %s", FmtG(6), FmtG(0.35), FmtG(1e7))
	}
}

// 参考值：scipy.stats.norm.ppf，要求逐位相同。
func TestNormPPFMatchesScipyExactly(t *testing.T) {
	for p, want := range map[float64]float64{0.975: 1.959963984540054, 0.99375: 2.497705474412374, 0.9875: 2.241402727604947,
		0.996875: 2.7343687865331767, 0.995: 2.5758293035489004, 0.95: 1.6448536269514722, 0.75: 0.6744897501960817,
		0.6: 0.2533471031357997, 0.5: 0, 0.3: -0.5244005127080409, 0.1: -1.2815515655446004,
		0.9916666666666667: 2.3939797998185104, 0.9999999: 5.199337582290661} {
		if got := NormPPF(p); got != want {
			t.Errorf("NormPPF(%v) = %v，期望 %v", p, got, want)
		}
	}
	approx(t, "NormPPF(0.01)", NormPPF(0.01), -2.3263478740408408, 1e-14) // 下尾差在 math.Log 的最后一位，分析里用不到
}
