package balance

import "math"

// 回归：和 statsmodels 的 Logit(...).fit().get_margeff() 与 OLS(...).fit().conf_int() 同样的算法。
// 设计矩阵 X 的第 0 列是常数项。

// invert 用列主元高斯消元求逆；矩阵奇异时返回 false。
func invert(a [][]float64) ([][]float64, bool) {
	n := len(a)
	m := make([][]float64, n)
	for i := range m {
		m[i] = make([]float64, 2*n)
		copy(m[i], a[i])
		m[i][n+i] = 1
	}
	for c := 0; c < n; c++ {
		p := c
		for r := c + 1; r < n; r++ {
			if math.Abs(m[r][c]) > math.Abs(m[p][c]) {
				p = r
			}
		}
		if !(math.Abs(m[p][c]) > 0) || math.IsInf(m[p][c], 0) { // 只在真正奇异时放弃（和 numpy 一样）
			return nil, false
		}
		m[c], m[p] = m[p], m[c]
		piv := m[c][c]
		for j := range m[c] {
			m[c][j] /= piv
		}
		for r := 0; r < n; r++ {
			if r != c && m[r][c] != 0 {
				f := m[r][c]
				for j := range m[r] {
					m[r][j] -= f * m[c][j]
				}
			}
		}
	}
	out := make([][]float64, n)
	for i := range out {
		out[i] = m[i][n:]
	}
	return out, true
}

func matVec(a [][]float64, v []float64) []float64 {
	out := make([]float64, len(a))
	for i, row := range a {
		for j, x := range row {
			out[i] += x * v[j]
		}
	}
	return out
}

// hasConstantColumn：除常数项外还有恒定的列时，statsmodels 的 add_constant 不会加常数项，这里直接不估计。
func degenerate(X [][]float64) bool {
	if len(X) == 0 {
		return true
	}
	for j := 1; j < len(X[0]); j++ {
		same := true
		for i := range X {
			if math.IsNaN(X[i][j]) {
				return true
			}
			same = same && X[i][j] == X[0][j]
		}
		if same {
			return true
		}
	}
	return false
}

// logitMargins 拟合 Logit（牛顿法，起点 0，最多 35 步，容差 1e-8），返回每个参数的
// 平均边际效应（dy/dx，对全体样本取平均）和用 delta 方法得到的 95% 区间。
func logitMargins(X [][]float64, y []float64) (eff, lo, hi []float64, ok bool) {
	if degenerate(X) {
		return nil, nil, nil, false
	}
	n, k := len(X), len(X[0])
	fn := float64(n)
	beta := make([]float64, k)
	prob := func(b []float64) []float64 {
		p := make([]float64, n)
		for i, row := range X {
			z := 0.0
			for j, x := range row {
				z += x * b[j]
			}
			p[i] = 1 / (1 + math.Exp(-z))
		}
		return p
	}
	xwx := func(p []float64) [][]float64 {
		h := make([][]float64, k)
		for a := range h {
			h[a] = make([]float64, k)
		}
		for i, row := range X {
			w := p[i] * (1 - p[i])
			for a := 0; a < k; a++ {
				for b := 0; b < k; b++ {
					h[a][b] += w * row[a] * row[b]
				}
			}
		}
		return h
	}
	moved := true
	for iter := 0; iter < 35 && moved; iter++ {
		p := prob(beta)
		h := xwx(p)
		for a := range h {
			for b := range h[a] {
				h[a][b] /= fn
			}
			h[a][a] += 1e-10 // statsmodels 的 ridge_factor
		}
		g := make([]float64, k) // -score / n
		for i, row := range X {
			for a := 0; a < k; a++ {
				g[a] -= (y[i] - p[i]) * row[a] / fn
			}
		}
		inv, good := invert(h)
		if !good {
			return nil, nil, nil, false
		}
		step := matVec(inv, g)
		moved = false
		for a := range beta {
			beta[a] -= step[a]
			moved = moved || math.Abs(step[a]) > 1e-8
			if math.IsNaN(beta[a]) || math.IsInf(beta[a], 0) {
				return nil, nil, nil, false
			}
		}
	}
	p := prob(beta)
	cov, good := invert(xwx(p))
	if !good {
		return nil, nil, nil, false
	}
	meanF := 0.0
	dfx := make([]float64, k) // mean_i f'(x_i·β) x_ik
	for i, row := range X {
		f := p[i] * (1 - p[i])
		meanF += f / fn
		for a := 0; a < k; a++ {
			dfx[a] += f * (1 - 2*p[i]) * row[a] / fn
		}
	}
	z := NormPPF(0.975)
	eff, lo, hi = make([]float64, k), make([]float64, k), make([]float64, k)
	for j := 0; j < k; j++ {
		jac := make([]float64, k)
		for a := 0; a < k; a++ {
			jac[a] = beta[j] * dfx[a]
		}
		jac[j] += meanF
		v := 0.0
		cj := matVec(cov, jac)
		for a := 0; a < k; a++ {
			v += jac[a] * cj[a]
		}
		se := math.Sqrt(v)
		eff[j] = meanF * beta[j]
		lo[j], hi[j] = eff[j]-z*se, eff[j]+z*se
	}
	return eff, lo, hi, true
}

// olsFit 是最小二乘，返回系数和基于 t 分布的 95% 区间。
func olsFit(X [][]float64, y []float64) (beta, lo, hi []float64, ok bool) {
	if degenerate(X) {
		return nil, nil, nil, false
	}
	n, k := len(X), len(X[0])
	xtx := make([][]float64, k)
	xty := make([]float64, k)
	for a := range xtx {
		xtx[a] = make([]float64, k)
	}
	for i, row := range X {
		for a := 0; a < k; a++ {
			xty[a] += row[a] * y[i]
			for b := 0; b < k; b++ {
				xtx[a][b] += row[a] * row[b]
			}
		}
	}
	inv, good := invert(xtx)
	if !good || n <= k {
		return nil, nil, nil, false
	}
	beta = matVec(inv, xty)
	ssr := 0.0
	for i, row := range X {
		e := y[i]
		for a := 0; a < k; a++ {
			e -= row[a] * beta[a]
		}
		ssr += e * e
	}
	df := float64(n - k)
	t := StudentTPPF(0.975, df)
	lo, hi = make([]float64, k), make([]float64, k)
	for a := 0; a < k; a++ {
		se := math.Sqrt(ssr / df * inv[a][a])
		lo[a], hi[a] = beta[a]-t*se, beta[a]+t*se
	}
	return beta, lo, hi, true
}

// StudentTPPF 是 t 分布的分位数（scipy.stats.t.ppf），p ≥ 0.5。
func StudentTPPF(p, df float64) float64 {
	if p < 0.5 {
		return -StudentTPPF(1-p, df)
	}
	cdf := func(t float64) float64 { return 1 - 0.5*regIncBeta(df/2, 0.5, df/(df+t*t)) }
	lo, hi := 0.0, 1.0
	for cdf(hi) < p {
		hi *= 2
	}
	for i := 0; i < 200 && hi-lo > 1e-15*hi; i++ {
		mid := (lo + hi) / 2
		if cdf(mid) < p {
			lo = mid
		} else {
			hi = mid
		}
	}
	return (lo + hi) / 2
}

// regIncBeta 是正则化不完全 Beta 函数 I_x(a, b)（连分式）。
func regIncBeta(a, b, x float64) float64 {
	if x <= 0 {
		return 0
	}
	if x >= 1 {
		return 1
	}
	la, _ := math.Lgamma(a + b)
	lb, _ := math.Lgamma(a)
	lc, _ := math.Lgamma(b)
	front := math.Exp(la - lb - lc + a*math.Log(x) + b*math.Log(1-x))
	if x < (a+1)/(a+b+2) {
		return front * betaCF(a, b, x) / a
	}
	return 1 - front*betaCF(b, a, 1-x)/b
}

func betaCF(a, b, x float64) float64 {
	const tiny = 1e-300
	qab, qap, qam := a+b, a+1, a-1
	c, d := 1.0, 1-qab*x/qap
	if math.Abs(d) < tiny {
		d = tiny
	}
	d = 1 / d
	h := d
	for m := 1; m <= 500; m++ {
		fm := float64(m)
		aa := fm * (b - fm) * x / ((qam + 2*fm) * (a + 2*fm))
		d = 1 + aa*d
		if math.Abs(d) < tiny {
			d = tiny
		}
		c = 1 + aa/c
		if math.Abs(c) < tiny {
			c = tiny
		}
		d = 1 / d
		h *= d * c
		aa = -(a + fm) * (qab + fm) * x / ((a + 2*fm) * (qap + 2*fm))
		d = 1 + aa*d
		if math.Abs(d) < tiny {
			d = tiny
		}
		c = 1 + aa/c
		if math.Abs(c) < tiny {
			c = tiny
		}
		d = 1 / d
		del := d * c
		h *= del
		if math.Abs(del-1) < 1e-16 {
			break
		}
	}
	return h
}
