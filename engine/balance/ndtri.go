package balance

import "math"

// ndtri 是 Cephes 的标准正态分位数（scipy.stats.norm.ppf 用的就是它），系数和运算顺序照搬，
// 这样 Wilson 区间和 Python 版连最后一位都一样。
var (
	ndtriP0 = []float64{-5.99633501014107895267e1, 9.80010754185999661536e1, -5.66762857469070293439e1,
		1.39312609387279679503e1, -1.23916583867381258016e0}
	ndtriQ0 = []float64{1.95448858338141759834e0, 4.67627912898881538453e0, 8.63602421390890590575e1,
		-2.25462687854119370527e2, 2.00260212380060660359e2, -8.20372256168333339912e1,
		1.59056225126211695515e1, -1.18331621121330003142e0}
	ndtriP1 = []float64{4.05544892305962419923e0, 3.15251094599893866154e1, 5.71628192246421288162e1,
		4.40805073893200834700e1, 1.46849561928858024014e1, 2.18663306850790267539e0,
		-1.40256079171354495875e-1, -3.50424626827848203418e-2, -8.57456785154685413611e-4}
	ndtriQ1 = []float64{1.57799883256466749731e1, 4.53907635128879210584e1, 4.13172038254672030440e1,
		1.50425385692907503408e1, 2.50464946208309415979e0, -1.42182922854787788574e-1,
		-3.80806407691578277194e-2, -9.33259480895457427372e-4}
)

func polevl(x float64, c []float64) float64 {
	r := c[0]
	for _, v := range c[1:] {
		r = r*x + v
	}
	return r
}

// p1evl：首项系数为 1 的多项式。
func p1evl(x float64, c []float64) float64 {
	r := x + c[0]
	for _, v := range c[1:] {
		r = r*x + v
	}
	return r
}

func ndtri(y0 float64) float64 {
	const s2pi = 2.50662827463100050242e0
	const expm2 = 0.13533528323661269189 // exp(-2)
	if y0 <= 0 {
		return math.Inf(-1)
	}
	if y0 >= 1 {
		return math.Inf(1)
	}
	negate := true
	y := y0
	if y > 1-expm2 {
		y = 1 - y
		negate = false
	}
	if y > expm2 {
		y -= 0.5
		y2 := y * y
		x := y + y*(y2*polevl(y2, ndtriP0)/p1evl(y2, ndtriQ0))
		return x * s2pi
	}
	x := math.Sqrt(-2 * math.Log(y))
	if x >= 8 { // 尾部极端值（p < e^-32）：平衡分析用不到，退回 erfinv
		return math.Sqrt2 * math.Erfinv(2*y0-1)
	}
	x0 := x - math.Log(x)/x
	z := 1 / x
	x = x0 - z*polevl(z, ndtriP1)/p1evl(z, ndtriQ1)
	if negate {
		return -x
	}
	return x
}
