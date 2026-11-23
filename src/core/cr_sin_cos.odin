package core

// Correctly rounded binary64 sin and cos (#162), ported from CORE-MATH (https://core-math.gitlabpages.inria.fr/),
// https://gitlab.inria.fr/core-math/core-math at commit 333d11d04d73ef165cf217e773b3b3d6372aa66f,
// src/binary64/sin/sin.c and src/binary64/cos/cos.c. The oracle's sin/cos behave as correctly rounded over the
// whole DB (#140, #161), so `core` uses these on every target instead of the host libm.
//
// Port notes:
// - Round to nearest only. The upstream code has no rounding-mode branches; errno (CORE_MATH_SUPPORT_ERRNO) and
//   feraiseexcept(FE_INVALID) are dropped: `core` never reads either.
// - Same operation order as the C source, `intrinsics.fused_mul_add` where it calls `__builtin_fma` (it lowers to
//   `llvm.fma.f64`, an exact fma, never `llvm.fmuladd`), and no other contraction (ADR 0003 d4).
// - `roundeven_finite` is the portable fallback of sin.c:66-92 (Odin has no scalar roundeven intrinsic).
// - cos.c copies sin.c's tables and helpers (cos.c:27-34 lists them); here both functions share one copy.
// - Hex-float constants are written as `0h` bit patterns (Odin has no hex-float literals); the tables were converted
//   mechanically and the comment above each one cites its source lines.
//
// CORE-MATH licence (MIT):
//
// Copyright (c) 2026 Paul Zimmermann and Alexei Sibidanov
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in all
// copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
// SOFTWARE.
//
// (cos.c carries the same notice with "Copyright (c) 2026 Paul Zimmermann".)

import "base:intrinsics"
import "core:math"

// cr_sin: sin(x) correctly rounded to nearest. sin.c:955-991 (`cr_sin`).
cr_sin :: proc "contextless" (x: f64) -> f64 {
	t := transmute(u64)x
	e := (t >> 52) & 0x7ff
	if e < 0x3ff - 26 { 	// |x| < 2^-26: |sin(x) - x| < 1/2 ulp
		au := t << 1
		if au == 0 {
			return x // ±0
		}
		return intrinsics.fused_mul_add(x, NEG_TWO_M54, x)
	}
	if e < 0x3ff + 31 {
		return sin_moderate(x, uint(t >> 63)) // |x| < 2^31
	}
	if e == 0x7ff {
		return transmute(f64)u64(0x7ff8000000000000) // NaN, +Inf, -Inf: a quiet NaN
	}
	return sin_large(x) // |x| >= 2^31
}

// cr_cos: cos(x) correctly rounded to nearest. cos.c:943-971 (`cr_cos`).
cr_cos :: proc "contextless" (x: f64) -> f64 {
	z := abs(x)
	t := transmute(u64)z
	e := t >> 52
	if e < 0x3ff - 27 { 	// |x| < 2^-27: cos(x) rounds to 1
		return intrinsics.fused_mul_add(x, -x, 1.0)
	}
	if e < 0x3ff + 31 {
		return cos_moderate(z) // |x| < 2^31
	}
	if e == 0x7ff { 	// NaN, +Inf, -Inf: propagate a quiet NaN, Inf -> qNaN, sNaN -> qNaN
		u := transmute(u64)x | (u64(1) << 51)
		return transmute(f64)u
	}
	return cos_large(z) // |x| >= 2^31
}

@(private = "file")
NEG_TWO_M54 :: 0hBC90000000000000 // -0x1p-54
// sin.c:563-564: |2^14 (PIH + PIL) + pi| < 2^-108.041.
@(private = "file")
PIH :: 0hBF2921FB54442D18 // -0x1.921fb54442d18p-13
@(private = "file")
PIL :: 0hBBC1A62633145C07 // -0x1.1a62633145c07p-67
@(private = "file")
INVPI :: 0h40B45F306DC9C883 // 0x1.45f306dc9c883p+12, |INVPI/2^14 - 1/pi| < 2^-55.496
@(private = "file", rodata)
SGN := [2]f64{1.0, -1.0}

// roundeven_finite: round to nearest integer, ties to even. sin.c:78-90 (the portable branch).
@(private = "file")
roundeven_finite :: proc "contextless" (x: f64) -> f64 {
	ix := math.round(x) // nearest, ties away from 0
	if abs(ix - x) == 0.5 {
		// if ix is odd, return ix-1 if x>0 and ix+1 if x<0
		u := transmute(u64)ix
		v := transmute(u64)(ix - math.copy_sign(1.0, x))
		// v is 0 when x = 0.5; u cannot be 0 since ix is rounded away from 0
		if v == 0 || intrinsics.count_trailing_zeros(v) > intrinsics.count_trailing_zeros(u) {
			ix = transmute(f64)v
		}
	}
	return ix
}

// u128_tod: round (-1)^s r/2^128 to f64, r non-zero and not subnormal. sin.c:100-122.
@(private = "file")
u128_tod :: proc "contextless" (r: u128, s: uint) -> f64 {
	@(static, rodata)
	sgn := [2]f64{0h3CA0000000000000, 0hBCA0000000000000} // ±0x1p-53
	@(static, rodata)
	low := [2]f64{0h3FD8000000000000, 0h3FE8000000000000} // 0x1.8p-2, 0x1.8p-1
	// r/2^128 >= ~2^-60.888 (closest binary64 to a multiple of pi/2), so r >> 64 != 0 and sh <= 60
	sh := intrinsics.count_leading_zeros(u64(r >> 64))
	h := u64(r >> (75 - sh)) // upper 53 non-zero bits
	rbit := uint(r >> (74 - sh)) & 1 // round bit
	v := transmute(u64)sgn[s]
	v -= sh << 52 // scale by 2^-sh
	vf := transmute(f64)v
	a := f64(h) * vf
	b := low[rbit] * vf
	return a + b
}

// mh_uu: floor(a b / 2^128), dropping the low-by-low product. sin.c:179-186 (`mhUU`).
@(private = "file")
mh_uu :: #force_inline proc "contextless" (a, b: u128) -> u128 {
	ah, al := u64(a >> 64), u64(a)
	bh, bl := u64(b >> 64), u64(b)
	ahbh := u128(ah) * u128(bh)
	ahbl := u128(ah) * u128(bl)
	albh := u128(al) * u128(bh)
	return ahbh + ((ahbl >> 64) + (albh >> 64))
}

// eval_ps: Sr/2^128 ~ sin(2 pi r) for 0 <= r < 2^-14, u = 8r, u2 ~ u^2, u4 ~ u^4, u2h = floor(u2/2^64), fixed
// point, Estrin's scheme. sin.c:191-211 (`evalPS`).
@(private = "file")
eval_ps :: proc "contextless" (u, u2, u2h, u4: u128) -> u128 {
	sh := PS[2] - PS[3] * u2h
	sh = mh_uu(sh, u4)
	s := mh_uu(PS[1], u2)
	s = PS[0] - s
	s = s + sh
	return mh_uu(s, u)
}

// eval_pc: Cr/2^128 ~ cos(2 pi r), same arguments as eval_ps. sin.c:214-223 (`evalPC`).
@(private = "file")
eval_pc :: proc "contextless" (u2, u2h, u4: u128) -> u128 {
	sh := PC[3] - u2h * PC[4]
	sh = PC[2] - mh_uu(sh, u2)
	s := mh_uu(PC[1], u2)
	s = PC[0] - s
	return s + mh_uu(sh, u4)
}

// reduce_large: for x >= 2^31, returns j (15 bits) and r with x/(2pi) mod 1 = j/2^15 + r + s, 0 <= r < 2^-15,
// 0 <= s < 2^-67.988 (Payne-Hanek). sin.c:229-262 = cos.c:876-909.
@(private = "file")
reduce_large :: proc "contextless" (x: f64) -> (j: u64, r: f64) {
	t := transmute(u64)x
	e := int((t >> 52) & 0x7ff) // 1054 <= e <= 2046
	m := (u64(1) << 52) | (t & 0xfffffffffffff) // x = m 2^(e-1075)
	i := (e - 1011) / 64 // ceil((e-1074)/64), 0 <= i <= 16
	f := uint((e - 1011) & 0x3f)
	// m T[i] has 64-f fractional bits: shift by f to get 64
	v0, v1: u64
	if f == 0 {
		v0 = T_INV_2PI[i]
		v1 = T_INV_2PI[i + 1]
	} else {
		v0 = (T_INV_2PI[i] << f) | (T_INV_2PI[i + 1] >> (64 - f))
		v1 = (T_INV_2PI[i + 1] << f) | (T_INV_2PI[i + 2] >> (64 - f))
	}
	u := u128(v1) | (u128(v0) << 64)
	u = u128(m) * u
	// round r to nearest, 2^112 + 129 2^52
	MAGIC :: (u128(1) << 112) + (u128(129) << 52)
	u += MAGIC
	h := u64((u << 15) >> 75) // the 53 bits of u after the first 15 (an integer, converted exactly)
	r = f64(h) * 0h3BB0000000000000 - 0h3EF0000000000000 // h 2^-68 - 2^-16
	return u64(u >> 113), r
}

// reduce_large_acc: for |x| >= 2^-27, returns k (13 bits), r and neg with x/(2pi) mod 1 = k/2^13 + (-1)^neg r/2^128
// + eps, |r/2^128| <= 2^-14, 0 <= eps < 2^-127.999. sin.c:572-612 (cos.c:681-721 is the same for x > 0; sin.c masks
// the sign bit, so this takes either).
@(private = "file")
reduce_large_acc :: proc "contextless" (x: f64) -> (k: u64, r: u128, neg: bool) {
	t := transmute(u64)x
	e := int((t >> 52) & 0x7ff)
	m := (u64(1) << 52) | (t & 0xfffffffffffff) // x = m 2^(e-1075)
	i := -1 + (e - 947) / 64 // ceil((e-1074)/64), -1 <= i <= 16
	f := uint((e - 1011) & 0x3f)
	v0 := i >= 0 ? T_INV_2PI[i] : 0
	v1 := T_INV_2PI[i + 1]
	v2 := T_INV_2PI[i + 2]
	if f != 0 {
		v0 = (v0 << f) | (v1 >> (64 - f))
		v1 = (v1 << f) | (v2 >> (64 - f))
		v2 = (v2 << f) | (T_INV_2PI[i + 3] >> (64 - f))
	}
	// m v0: weights 2^-1..2^-64; m v1: 2^-12..2^-128; m v2: 2^-76..2^-192; the rest < 2^-139
	u := u128(v1) | (u128(v0) << 64)
	u = u128(m) * u
	v := u128(m) * u128(v2)
	u += v >> 64 // m v2 from 2^-76 to 2^-128
	k = u64(u >> (128 - 13))
	MASK :: (u128(0x7ffffffffffff) << 64) | 0xffffffffffffffff
	u &= MASK // drop the leading 13 bits
	// round k to nearest so that |r/2^128| < 2^-14
	neg = (u >> 114) != 0
	if neg { 	// k + 1, r - 1/2^13
		k = (k + 1) & ((u64(1) << 13) - 1)
		u = MASK + 1 - u
	}
	return k, u, neg
}

// fast_two_sum: s + e = x + y exactly, |x| >= |y|. sin.c:264-268 (`fasttwosum`).
@(private = "file")
fast_two_sum :: #force_inline proc "contextless" (x, y: f64) -> (s, e: f64) {
	s = x + y
	z := s - x
	e = y - z
	return
}

// fast_sum: double-double sum. sin.c:270-274 (`fastsum`).
@(private = "file")
fast_sum :: #force_inline proc "contextless" (xh, xl, yh, yl: f64) -> (sh, e: f64) {
	sl: f64
	sh, sl = fast_two_sum(xh, yh)
	e = (xl + yl) + sl
	return
}

// mul_dd: double-double product. sin.c:276-288 (`muldd`, the `#if 1` branch).
@(private = "file")
mul_dd :: #force_inline proc "contextless" (xh, xl, ch, cl: f64) -> (h, l: f64) {
	h = xh * ch
	l = (xh * cl + xl * ch) + intrinsics.fused_mul_add(xh, ch, -h)
	return
}

// Accurate path shared by sin and cos: reduce x, then |sin(z)|, cos(z) for z = pi k/2^12 mod pi from S1U/S2U/C2U,
// and sin(2 pi r), cos(2 pi r) from PS/PC. sin.c:803-842 = cos.c:768-804.
@(private = "file")
Accurate :: struct {
	k:        u64,
	neg:      bool,
	i1:       uint,
	s1u, c1u: u128, // |sin(z)|, |cos(z)|
	sr, cr:   u128, // |sin(2 pi r)|, cos(2 pi r)
}

@(private = "file")
accurate_terms :: proc "contextless" (x: f64) -> (a: Accurate) {
	r: u128
	a.k, r, a.neg = reduce_large_acc(x)
	r = r << 3 // 8 r
	u2 := mh_uu(r, r)
	u4 := mh_uu(u2, u2)
	u2h := u2 >> 64
	// k = 2^12 s + 2^6 i1 + i2, t1 = pi i1/2^6, t2 = pi i2/2^12
	a.i1 = uint((a.k >> 6) & 0x3f)
	i2 := uint(a.k & 0x3f)
	i1 := a.i1
	s1 := i1 <= 32 ? S1U[i1] : S1U[64 - i1] // sin(pi - x) = sin(x)
	c1 := i1 <= 32 ? S1U[32 - i1] : S1U[i1 - 32] // |C1u[i1]| = |S1u[(i1+32) mod 64]|
	s1u := mh_uu(s1, C2U[i2])
	t := mh_uu(c1, S2U[i2])
	a.s1u = i1 < 32 ? s1u + t : s1u - t // sin(z) >= 0 for 0 <= z < pi
	c1u := mh_uu(c1, C2U[i2])
	t = mh_uu(s1, S2U[i2])
	a.c1u = i1 < 32 ? c1u - t : c1u + t
	a.sr = eval_ps(r, u2, u2h, u4)
	a.cr = eval_pc(u2, u2h, u4)
	return
}

// sin_large_accurate: accurate path for |x| >= 2^-16. sin.c:801-857.
@(private = "file")
sin_large_accurate :: proc "contextless" (x: f64) -> f64 {
	a := accurate_terms(x)
	sbit := uint(x > 0 ? 0 : 1)
	sbit ~= uint(a.k >> 12)
	// sin(x) ~ sin(z) C + cos(z) S
	s1u := mh_uu(a.s1u, a.cr)
	c1u := mh_uu(a.c1u, a.sr)
	// s1u >= 0; c1u has the sign of cos(z) (> 0 for i1 < 32) times the sign of r
	if (a.i1 < 32) ~ a.neg {
		s1u += c1u
	} else if s1u < c1u {
		s1u = c1u - s1u
		sbit ~= 1
	} else {
		s1u -= c1u
	}
	return u128_tod(s1u, sbit)
}

// cos_exceptions: inputs where cos(x) has 72-88 identical bits after the round bit. cos.c:750-762. Upstream returns
// `hi + tiny` for the directed roundings; to nearest that sum is `hi`.
@(private = "file")
cos_exceptions :: proc "contextless" (x, ret: f64) -> f64 {
	switch abs(x) {
	case 0h3E88000000000009:
		return 0h3FEFFFFFFFFFFF70 // 0x1.8000000000009p-23 -> 0x1.fffffffffff7p-1
	case 0h3E98000000000024:
		return 0h3FEFFFFFFFFFFDC0 // 0x1.8000000000024p-22 -> 0x1.ffffffffffdcp-1
	case 0h3EA8000000000090:
		return 0h3FEFFFFFFFFFF700 // 0x1.800000000009p-21 -> 0x1.ffffffffff7p-1
	case 0h3EB20000000000F3:
		return 0h3FEFFFFFFFFFEBC0 // 0x1.20000000000f3p-20 -> 0x1.fffffffffebcp-1
	}
	return ret
}

// cos_large_accurate: accurate path for x >= 2^-27. cos.c:766-825.
@(private = "file")
cos_large_accurate :: proc "contextless" (x: f64) -> f64 {
	a := accurate_terms(x)
	sbit := uint((a.k >> 12) & 1)
	// cos(x) ~ cos(z) C - sin(z) S
	c1u := mh_uu(a.c1u, a.cr)
	s1u := mh_uu(a.s1u, a.sr)
	// c1u has the sign of cos(z) (<= 0 for i1 >= 32); s1u has the sign of r
	if (a.i1 >= 32) ~ a.neg {
		c1u += s1u
	} else if c1u <= s1u {
		c1u = s1u - c1u
		sbit ~= 1
	} else {
		c1u -= s1u
	}
	// cos(z) <= 0 for i1 >= 32: flip the sign
	ret := u128_tod(c1u, sbit ~ (a.i1 >= 32 ? 1 : 0))
	d := u64(c1u) + 5
	if d <= 3 {
		return cos_exceptions(x, ret)
	}
	return ret
}

// sin_small_accurate: accurate path for |x| < 2^-16, x + (c3h + c3l) x^3 + c5 x^5 with relative error < 2^-112.743.
// sin.c:861-877.
@(private = "file")
sin_small_accurate :: proc "contextless" (x: f64) -> f64 {
	C3H :: 0hBFC5555555555555 // -0x1.5555555555555p-3
	C3L :: 0hBC655554B00DE7E8 // -0x1.55554b00de7e8p-57
	C5 :: 0h3F81111111108480 // 0x1.111111110848p-7
	x2h := x * x
	x2l := intrinsics.fused_mul_add(x, x, -x2h)
	h, l, t: f64
	h = C5 * x2h
	h += C3L
	h, l = fast_two_sum(C3H, h)
	h, l = mul_dd(h, l, x2h, x2l)
	h, l = mul_dd(h, l, x, 0)
	h, t = fast_two_sum(x, h)
	l += t
	return h + l
}

// sin_table: sin(t1 + t2) as Sh + Sl and cos(t1 + t2) as Ch, t1 = i1 pi/2^7, t2 = i2 pi/2^14. sin.c:900-905 =
// sin.c:933-938.
@(private = "file")
sin_table :: #force_inline proc "contextless" (i1, i2: i64) -> (sh, sl, ch: f64) {
	s1h, s1l := mul_dd(U1[i1][0], U1[i1][1], U2[i2][2], U2[i2][3])
	s2h, s2l := mul_dd(U2[i2][0], U2[i2][1], U1[i1][2], U1[i1][3])
	sh, sl = fast_sum(s1h, s1l, s2h, s2l)
	ch = U1[i1][2] * U2[i2][2] - U1[i1][0] * U2[i2][0]
	return
}

// cos_table: cos(t1 + t2) as Ch + Cl and sin(t1 + t2) as Sh. cos.c:846-855 = cos.c:924-929.
@(private = "file")
cos_table :: #force_inline proc "contextless" (i1, i2: i64) -> (ch, cl, sh: f64) {
	c1h, c1l := mul_dd(U1[i1][2], U1[i1][3], U2[i2][2], U2[i2][3]) // cos(t1) cos(t2)
	c2h, c2l := mul_dd(U2[i2][0], U2[i2][1], U1[i1][0], U1[i1][1]) // sin(t1) sin(t2)
	ch, cl = fast_sum(c1h, c1l, -c2h, -c2l)
	sh = U1[i1][0] * U2[i2][2] + U1[i1][2] * U2[i2][0]
	return
}

// sin_moderate: fast path for 2^-26 <= |x| < 2^31; sbit is the sign bit of x. sin.c:883-919 (`cr_sin_moderate`).
@(private = "file")
sin_moderate :: proc "contextless" (x: f64, sign: uint) -> f64 {
	sbit := sign
	ax := abs(x)
	k := roundeven_finite(INVPI * ax)
	rh := intrinsics.fused_mul_add(k, PIH, ax) // exact
	rl := k * PIL
	r := rh + rl // |r| < 2^-13.339
	r2 := r * r
	j := i64(k)
	sbit ~= uint((j >> 14) & 1) // odd multiple of pi?
	i1, i2 := (j >> 7) & 0x7f, j & 0x7f
	big_sh, big_sl, big_ch := sin_table(i1, i2)
	// sin(r) ~ r - c r^3 (error < 2^-76.494), cos(r) - 1 ~ -r^2/2 + c' r^4 (error < 2^-92.723)
	sh := r * (1.0 - 0h3FC55555553068F0 * r2) // 0x1.55555553068fp-3
	ch := r2 * (-0.5 + 0h3FA55555553BFD30 * r2) // 0x1.55555553bfd3p-5
	fh := big_sh
	fl := big_sl + big_sh * ch + big_ch * sh
	fh = SGN[sbit] * fh
	fl = SGN[sbit] * fl
	EPS :: 0h3BFDE00000000000 // 0x1.dep-64
	lb := fh + (fl - EPS)
	ub := fh + (fl + EPS)
	if ub == lb {
		return lb
	}
	if abs(x) < 0h3EF0000000000000 { 	// 2^-16
		return sin_small_accurate(x)
	}
	return sin_large_accurate(x)
}

// sin_large: fast path for |x| >= 2^31. sin.c:923-952 (`cr_sin_large`).
@(private = "file")
sin_large :: proc "contextless" (x: f64) -> f64 {
	ax := abs(x)
	j, r := reduce_large(ax) // x/(2pi) ~ k + j/2^15 + r, 0 <= r < 2^-15
	sbit := uint(x > 0 ? 0 : 1)
	r2 := r * r
	sbit ~= uint(j >> 14) // odd multiple of pi?
	i1, i2 := i64((j >> 7) & 0x7f), i64(j & 0x7f)
	big_sh, big_sl, big_ch := sin_table(i1, i2)
	sh := r * (0h401921FB54442D18 - 0h4044ABBCDB6B26D1 * r2) // 0x1.921fb54442d18p2, 0x1.4abbcdb6b26d1p5
	ch := r2 * (-0h4033BD3CC9BE45DE + 0h40503C1EEE483083 * r2) // 0x1.3bd3cc9be45dep4, 0x1.03c1eee483083p6
	fh := big_sh
	fl := big_sl + big_sh * ch + big_ch * sh
	fh = SGN[sbit] * fh
	fl = SGN[sbit] * fl
	EPS :: 0h3C00100000000000 // 0x1.01p-63
	lb := fh + (fl - EPS)
	ub := fh + (fl + EPS)
	if lb == ub {
		return lb
	}
	return sin_large_accurate(x)
}

// cos_moderate: fast path for 2^-27 <= x < 2^31, x >= 0. cos.c:831-870 (`cr_cos_moderate`).
@(private = "file")
cos_moderate :: proc "contextless" (x: f64) -> f64 {
	k := roundeven_finite(INVPI * x)
	rh := intrinsics.fused_mul_add(k, PIH, x) // exact
	rl := k * PIL
	r := rh + rl // |r| < 2^-13.339
	r2 := r * r
	j := i64(k)
	sbit := uint((j >> 14) & 1) // odd multiple of pi?
	i1, i2 := (j >> 7) & 0x7f, j & 0x7f
	big_ch, big_cl, big_sh := cos_table(i1, i2)
	sh := r * (1.0 - 0h3FC55555553068F0 * r2) // 0x1.55555553068fp-3
	ch := r2 * (-0.5 + 0h3FA55555553BFD30 * r2) // 0x1.55555553bfd3p-5
	fh := big_ch
	fl := big_cl + big_ch * ch - big_sh * sh
	fh = SGN[sbit] * fh
	fl = SGN[sbit] * fl
	EPS :: 0h3BFDE00000000000 // 0x1.dep-64
	lb := fh + (fl - EPS)
	ub := fh + (fl + EPS)
	if ub == lb {
		return lb
	}
	return cos_large_accurate(x)
}

// cos_large: fast path for x >= 2^31. cos.c:913-940 (`cr_cos_large`).
@(private = "file")
cos_large :: proc "contextless" (x: f64) -> f64 {
	j, r := reduce_large(x) // x/(2pi) ~ k + j/2^15 + r, 0 <= r < 2^-15
	r2 := r * r
	sbit := uint(j >> 14) // odd multiple of pi?
	i1, i2 := i64((j >> 7) & 0x7f), i64(j & 0x7f)
	big_ch, big_cl, big_sh := cos_table(i1, i2)
	sh := r * (0h401921FB54442D18 - 0h4044ABBCDB6B26D1 * r2)
	ch := r2 * (-0h4033BD3CC9BE45DE + 0h40503C1EEE483083 * r2)
	fh := big_ch
	fl := big_cl + big_ch * ch - big_sh * sh
	fh = SGN[sbit] * fh
	fl = SGN[sbit] * fl
	EPS :: 0h3C00100000000000 // 0x1.01p-63
	lb := fh + (fl - EPS)
	ub := fh + (fl + EPS)
	if lb == ub {
		return lb
	}
	return cos_large_accurate(x)
}

// Tables shared by sin and cos (cos.c copies them from sin.c).

// sin.c:127-149 (`_T`): 1/(2pi) rounded down to 1280 bits, 1/(2pi) ~ sum T_INV_2PI[i] / 2^(64 i).
@(private = "file", rodata)
T_INV_2PI := [20]u64 {
	0,
	0x28be60db9391054a,
	0x7f09d5f47d4d3770,
	0x36d8a5664f10e410,
	0x7f9458eaf7aef158,
	0x6dc91b8e909374b8,
	0x1924bba82746487,
	0x3f877ac72c4a69cf,
	0xba208d7d4baed121,
	0x3a671c09ad17df90,
	0x4e64758e60d4ce7d,
	0x272117e2ef7e4a0e,
	0xc7fe25fff7816603,
	0xfbcbc462d6829b47,
	0xdb4d9fb3c9f2c26d,
	0xd3d18fd9a797fa8b,
	0x5d49eeb1faf97c5e,
	0xcf41ce7de294a4ba,
	0x9afed7ec47e35742,
	0x1580cc11bf1edaea,
}

// sin.c:158-164 (`PS`), `U128(lo, hi)` written as one 128-bit literal `hi_lo`.
@(private = "file", rodata)
PS := [4]u128 {
	0xc90fdaa22168c234_c4c6628b80dbed80,
	0x14abbce625be52be_abb8e5506ca45b03,
	0x00a335e33bad570e_044c54995bb97635,
	0x0000000000000000_000265a5999d06c4,
}

// sin.c:171-177 (`PC`), `U128(lo, hi)` written as one 128-bit literal `hi_lo`.
@(private = "file", rodata)
PC := [5]u128 {
	0xffffffffffffffff_ffffffffffffffff,
	0x4ef4f326f9177969_2b71366cbcf0b096,
	0x040f07c206d6b0ec_d4c9076e3db78fed,
	0x00155d3c7e3cbef9_eec6962368fb7c41,
	0x0000000000000000_00003c3e845b5510,
}

// sin.c:618-652 (`S1u`), `U128(lo, hi)` written as one 128-bit literal `hi_lo`.
@(private = "file", rodata)
S1U := [33]u128 {
	0x0000000000000000_0000000000000000,
	0x0c8fb2f886ec09f3_76a17954b2b7c517,
	0x1917a6bc29b42be1_d8e72d912977ee71,
	0x259020dd1cc27444_c002a2684781f080,
	0x31f17078d34c156c_9732300393f33614,
	0x3e33f2f642be355e_90887712e9dc9663,
	0x4a5018bb567c16a2_d725d3b9ed35fbaa,
	0x563e69d6ac7f73f8_408fca9cc277fc1f,
	0x61f78a9abaa58b46_98916152cf7eee1c,
	0x6d744027857300ad_9b165cba0c171818,
	0x78ad74e01bd8ec78_362474f1a105878f,
	0x839c3cc917ff6cb4_bfd79717f2880abf,
	0x8e39d9cd73464364_bba4cfecbff54867,
	0x987fbfe70b81a708_19cec845ac87a5c6,
	0xa267992848eeb0c0_3b5167ee359a234e,
	0xabeb49a46764fd15_1becda8089c1a94c,
	0xb504f333f9de6484_597d89b3754abe9f,
	0xbdaef913557d76f0_ac85320f528d6d5d,
	0xc5e40358a8ba05a7_43da25d99267326b,
	0xcd9f023f9c3a059e_23af31db7179a4aa,
	0xd4db3148750d1819_f630e8b6dac83e69,
	0xdb941a28cb71ec87_2c19b63253da43fc,
	0xe1c5978c05ed8691_f4e8a8372f8c5810,
	0xe76bd7a1e63b9786_125129529d48a92f,
	0xec835e79946a3145_7e610231ac1d6181,
	0xf1090827b43725fd_67127db35b287316,
	0xf4fa0ab6316ed2ec_163c5c7f03b718c5,
	0xf853f7dc9186b952_c7adc6b4988891bb,
	0xfb14be7fbae58156_2172a361fd2a722f,
	0xfd3aabf84528b50b_eae6bd951c1dabbe,
	0xfec46d1e89292cf0_41390efdc726e9ef,
	0xffb10f1bcb6bef1d_421e8edaaf59453e,
	0xffffffffffffffff_ffffffffffffffff,
}

// sin.c:657-722 (`S2u`), `U128(lo, hi)` written as one 128-bit literal `hi_lo`.
@(private = "file", rodata)
S2U := [64]u128 {
	0x0000000000000000_0000000000000000,
	0x003243f655d966c0_c3b0abf2b35a62f8,
	0x006487eabb991cb6_11ad1d7b5620834a,
	0x0096cbdb41258434_c4a32c4560d01e70,
	0x00c90fc5f66525d2_57480f7956b64707,
	0x00fb53a8eb3ec385_328421cf8014d698,
	0x012d97822f996bc4_f96857b5aa8f6208,
	0x015fdb4fd35c8caa_d230a30592f25049,
	0x01921f0fe6700711_ab967fe6b7a9b037,
	0x01c462c078bc41b6_7db6e69ab68f0d10,
	0x01f6a65f9a2a3c58_85cede1f0314607b,
	0x0228e9eb5aa3a2d9_7c11ebc1b33cafb5,
	0x025b2d61ca12e05d_c2dd9c015a46e767,
	0x028d70c0f863326c_8e8d6151676ae94d,
	0x02bfb406f580bc10_053205a54588f0ab,
	0x02f1f731d15898f5_556febf4862da970,
	0x03243a3f9bd8f08c_c3c75f41b6ce7aa8,
	0x03567d2e64f10929_ad8a2d0c1a9e3a8c,
	0x0388bffc3c915b22_80c1c97a65cf2291,
	0x03bb02a732aba3f0_a8493bf9c07f7765,
	0x03ed452d5732f950_6b5e1380c7e6bddb,
	0x041f878cba1bdc60_bfeba221fb9d05be,
	0x0451c9c36b5c4cc3_0ed3c01c030008bb,
	0x04840bcf7aebdbba_e97857207bc589da,
	0x04b64daef8c3bf4d_afc8f71b8eb233ee,
	0x04e88f5ff4dee562_2617b65f5a2a8f5a,
	0x051ad0e07f3a06df_f9f89fb65be2a455,
	0x054d122ea7d3bacf_356ef187634a531d,
	0x057f53487eac8977_9fab71e43d71e2b7,
	0x05b1942c13c6ff80_0a9f1c1238fd05d5,
	0x05e3d4d77727c10d_8ca56cd8d54b97f0,
	0x06161548b8d59ce2_a58993a76b3f4ffe,
	0x0648557de8d99f7e_4e29cf6e5fed0679,
	0x067a9575173f263a_f1fc3edb7a0f1757,
	0x06acd52c5413f26d_51b86c83422cbab4,
	0x06df14a1af683c83_4e68e062eb177e2d,
	0x071153d3394ec722_9c28010f1c93a252,
	0x074392bf01dcf247_5bcb8fd41cb1096f,
	0x0775d163192ace62_9ac20c033d7f5cc3,
	0x07a80fbd8f532f78_b8654aa824578975,
	0x07da4dcc7473c03f_b00590e675e4e556,
	0x080c8b8dd8ad153d_46f0804dae5f13ba,
	0x083ec8ffcc22bfe5_1db725856ff8c284,
	0x087106205efb61b6_a3f67ad05a5be69e,
	0x08a342eda160bf5a_ede5b1068d174bea,
	0x08d57f65a37fd3c2_6aed92d34c17df54,
	0x0907bb867588e342_7c8c5732d89e910b,
	0x0939f74e27af8eb2_ecc93966728e412d,
	0x096c32baca2ae68b_437b2dd49d5fca3c,
	0x099e6dca6d357dff_f9a60c93317892c4,
	0x09d0a87b210d7e1f_8a318ba775fd7b04,
	0x0a02e2caf5f4b8ef_5f3d645e787b94f2,
	0x0a351cb7fc30bc88_9b56007d16d4ad5a,
	0x0a675640440ae634_bdcd0d6bb4b9cd3e,
	0x0a998f61ddd0758a_217954ed6093c44c,
	0x0acbc81ad9d29f88_55213c653bfb79b7,
	0x0afe00694866a1b4_4cd34d2751c2e1da,
	0x0b30384b39e5d534_6b7029d39efd7682,
	0x0b626fbebeadc1ec_63a95642f565102f,
	0x0b94a6c1e7203198_efb8391d83d6da18,
	0x0bc6dd52c3a342eb_5f10bfca3d646401,
	0x0bf9136f64a17ca4_f9530f050886d756,
	0x0c2b4915da89e0b2_35bfac0f965612e2,
	0x0c5d7e4435cfff45_c6718c1dfd2aa612,
}

// sin.c:732-797 (`C2u`), `U128(lo, hi)` written as one 128-bit literal `hi_lo`.
@(private = "file", rodata)
C2U := [64]u128 {
	0xffffffffffffffff_ffffffffffffffff,
	0xfffffb10b0d19f76_491a703231e0a12e,
	0xffffec42c3773235_ec9e2e75cb525f2c,
	0xffffd3963882d553_6276b75b91de105e,
	0xffffb10b10e80e95_3031437d7eccb9df,
	0xffff84a14dfbcc6a_858425d8b397dee6,
	0xffff4e58f17465de_177338053fd93920,
	0xffff0e31fd699a85_3a11d60588d8b96e,
	0xfffec42c7454926b_38e310779edfec68,
	0xfffe7048590fddf8_edd8e1034213f22b,
	0xfffe1285aed775d8_96f351efc65556cf,
	0xfffdaae47948bad5_ea80aedd6a19710f,
	0xfffd3964bc6275ba_69fff9ae0dedb047,
	0xfffcbe067c84d725_f3a703b987eca44a,
	0xfffc38c9be717763_928db07a0e70ba36,
	0xfffba9ae874b563a_8d800bed6653dcba,
	0xfffb10b4dc96dabb_b47903f7a19f8ee2,
	0xfffa6ddcc439d30a_ecc7b9244a48eb19,
	0xfff9c126447b7424_fbe18032d0016082,
	0xfff90a91640459a1_90e2d2eaf6da4d1e,
	0xfff84a1e29de8571_8cc193c5d508e13f,
	0xfff77fcc9d755f99_89332d07a713477e,
	0xfff6ab9cc695b5e8_9e4938f661aa140c,
	0xfff5cd8ead6dbbab_66c785e86dfbb75f,
	0xfff4e5a25a8d095b_43366df666fd54ff,
	0xfff3f3d7d6e49c49_dbb49f29fa872a83,
	0xfff2f82f2bc6d648_e08b96133ecce0bd,
	0xfff1f2a862e77d4e_098a31bcda3def20,
	0xfff0e343865bbb13_5428ed0647c9e5d1,
	0xffefca00a09a1cb3_807b6e7a4a723dae,
	0xffeea6dfbc7a9242_ccf344c647917821,
	0xffed79e0e5366e63_f0f7cb05bde024f1,
	0xffec4304266865d9_5657552366961732,
	0xffeb02498c0c8f12_9195e99fbca2f10a,
	0xffe9b7b1228061b6_191df31aaa6f7f45,
	0xffe8633af682b627_3b57790bf77b6b2d,
	0xffe704e71533c508_53aa9423bb0adc21,
	0xffe59cb58c1526b9_3e71f7d99688082a,
	0xffe42aa66909d2d2_0be28fbec7cfb8a6,
	0xffe2aeb9ba561f99_f1ed54343fe7be24,
	0xffe128ef8e9fc17a_7d209f32d42d864e,
	0xffdf9947f4edca6f_008e6ee05573d420,
	0xffddffc2fca8a970_44bd28b8d85b530a,
	0xffdc5c60b59a29dc_75a8951fc304b914,
	0xffdaaf212fed72db_4fd8f038449ec436,
	0xffd8f8047c2f06be_8c9611f0b1d8f023,
	0xffd7370aab4cc25e_8d3cd437dc7fa9d2,
	0xffd56c33ce95dc73_45bd035edb0a65f5,
	0xffd3977ff7bae4e9_664649b4d541b9c5,
	0xffd1b8ef38cdc433_c42aac754bedcfde,
	0xffcfd081a441ba99_01fd552bf146b4a6,
	0xffcdde374ceb5f7d_76f487bb853a6989,
	0xffcbe2104600a0a9_5595ca3f421ae09c,
	0xffc9dc0ca318c18b_11b369083a7a62e5,
	0xffc7cc2c782c5a76_05c2a6019679e41f,
	0xffc5b26fd99557dd_579207cfe424dcb7,
	0xffc38ed6dc0ef98b_1c676208aa3be545,
	0xffc1616194b5d1d3_bc8d54e81d94f831,
	0xffbf2a101907c4c5_965827f33d906c7c,
	0xffbce8e27ee40754_e0aa07fcb29eef39,
	0xffba9dd8dc8b1e83_ccfed60a91097c48,
	0xffb848f3489ede86_e907d9a298ab1feb,
	0xffb5ea31da2269e5_bfdfce09aea7ac02,
	0xffb38194a87a3097_badfe70a1ef51116,
}

// sin.c:297-426 (`U1`), hex floats written as `0h` bit patterns.
@(private = "file", rodata)
U1 := [128][4]f64 {
	{0h0000000000000000, 0h0000000000000000, 0h3FF0000000000000, 0h0000000000000000},
	{0h3F992155F7A3667E, 0hBBFB1D63091A0130, 0h3FEFFD886084CD0D, 0hBC81354D4556E4CB},
	{0h3FA91F65F10DD814, 0hBC2912BD0D569A90, 0h3FEFF621E3796D7E, 0hBC6C57BC2E24AA15},
	{0h3FB2D52092CE19F6, 0hBC49A088A8BF6B2C, 0h3FEFE9CDAD01883A, 0h3C6521ECD0C67E35},
	{0h3FB917A6BC29B42C, 0hBC3E2718D26ED688, 0h3FEFD88DA3D12526, 0hBC887DF6378811C7},
	{0h3FBF564E56A9730E, 0h3C4A2704729AE56D, 0h3FEFC26470E19FD3, 0h3C81EC8668ECACEE},
	{0h3FC2C8106E8E613A, 0h3C513000A89A11E0, 0h3FEFA7557F08A517, 0hBC87A0A8CA13571F},
	{0h3FC5E214448B3FC6, 0h3C6531FF779DDAC6, 0h3FEF8764FA714BA9, 0h3C7AB256778FFCB6},
	{0h3FC8F8B83C69A60B, 0hBC626D19B9FF8D82, 0h3FEF6297CFF75CB0, 0h3C7562172A361FD3},
	{0h3FCC0B826A7E4F63, 0hBC1AF1439E521935, 0h3FEF38F3AC64E589, 0hBC7D7BAFB51F72E6},
	{0h3FCF19F97B215F1B, 0hBC642DEEF11DA2C4, 0h3FEF0A7EFB9230D7, 0h3C752C7ADC6B4989},
	{0h3FD111D262B1F677, 0h3C7824C20AB7AA9A, 0h3FEED740E7684963, 0h3C7E82C791F59CC2},
	{0h3FD294062ED59F06, 0hBC75D28DA2C4612D, 0h3FEE9F4156C62DDA, 0h3C8760B1E2E3F81E},
	{0h3FD4135C94176601, 0h3C70C97C4AFA2518, 0h3FEE6288EC48E112, 0hBC616B56F2847754},
	{0h3FD58F9A75AB1FDD, 0hBC1EFDC0D58CF620, 0h3FEE212104F686E5, 0hBC8014C76C126527},
	{0h3FD7088530FA459F, 0hBC744B19E0864C5D, 0h3FEDDB13B6CCC23C, 0h3C883C37C6107DB3},
	{0h3FD87DE2A6AEA963, 0hBC672CEDD3D5A610, 0h3FED906BCF328D46, 0h3C7457E610231AC2},
	{0h3FD9EF7943A8ED8A, 0h3C66DA81290BDBAB, 0h3FED4134D14DC93A, 0hBC84EF5295D25AF2},
	{0h3FDB5D1009E15CC0, 0h3C65B362CB974183, 0h3FECED7AF43CC773, 0hBC5E7B6BB5AB58AE},
	{0h3FDCC66E9931C45E, 0h3C56850E59C37F8F, 0h3FEC954B213411F5, 0hBC52FB761E946603},
	{0h3FDE2B5D3806F63B, 0h3C5E0D891D3C6841, 0h3FEC38B2F180BDB1, 0hBC76E0B1757C8D07},
	{0h3FDF8BA4DBF89ABA, 0hBC32EC1FC1B776B8, 0h3FEBD7C0AC6F952A, 0hBC8825A732AC700A},
	{0h3FE073879922FFEE, 0hBC8A5A014347406C, 0h3FEB728345196E3E, 0hBC8BC69F324E6D61},
	{0h3FE11EB3541B4B23, 0hBC8EF23B69ABE4F1, 0h3FEB090A58150200, 0hBC8926DA300FFCCE},
	{0h3FE1C73B39AE68C8, 0h3C8B25DD267F6600, 0h3FEA9B66290EA1A3, 0h3C39F630E8B6DAC8},
	{0h3FE26D054CDD12DF, 0hBC85DA743EF3770C, 0h3FEA29A7A0462782, 0hBC7128BB015DF175},
	{0h3FE30FF7FCE17035, 0hBC6EFCC626F74A6F, 0h3FE9B3E047F38741, 0hBC830EE286712474},
	{0h3FE3AFFA292050B9, 0h3C7E3E25E3954964, 0h3FE93A22499263FB, 0h3C83D419A920DF0B},
	{0h3FE44CF325091DD6, 0h3C68076A2CFDC6B3, 0h3FE8BC806B151741, 0hBC82C5E12ED1336D},
	{0h3FE4E6CABBE3E5E9, 0h3C63C293EDCEB327, 0h3FE83B0E0BFF976E, 0hBC76F420F8EA3475},
	{0h3FE57D69348CECA0, 0hBC875720992BFBB2, 0h3FE7B5DF226AAFAF, 0hBC70F537ACDF0AD7},
	{0h3FE610B7551D2CDF, 0hBC7251B352FF2A37, 0h3FE72D0837EFFF96, 0h3C80D4EF0F1D915C},
	{0h3FE6A09E667F3BCD, 0hBC8BDD3413B26456, 0h3FE6A09E667F3BCD, 0hBC8BDD3413B26456},
	{0h3FE72D0837EFFF96, 0h3C80D4EF0F1D915C, 0h3FE610B7551D2CDF, 0hBC7251B352FF2A37},
	{0h3FE7B5DF226AAFAF, 0hBC70F537ACDF0AD7, 0h3FE57D69348CECA0, 0hBC875720992BFBB2},
	{0h3FE83B0E0BFF976E, 0hBC76F420F8EA3475, 0h3FE4E6CABBE3E5E9, 0h3C63C293EDCEB327},
	{0h3FE8BC806B151741, 0hBC82C5E12ED1336D, 0h3FE44CF325091DD6, 0h3C68076A2CFDC6B3},
	{0h3FE93A22499263FB, 0h3C83D419A920DF0B, 0h3FE3AFFA292050B9, 0h3C7E3E25E3954964},
	{0h3FE9B3E047F38741, 0hBC830EE286712474, 0h3FE30FF7FCE17035, 0hBC6EFCC626F74A6F},
	{0h3FEA29A7A0462782, 0hBC7128BB015DF175, 0h3FE26D054CDD12DF, 0hBC85DA743EF3770C},
	{0h3FEA9B66290EA1A3, 0h3C39F630E8B6DAC8, 0h3FE1C73B39AE68C8, 0h3C8B25DD267F6600},
	{0h3FEB090A58150200, 0hBC8926DA300FFCCE, 0h3FE11EB3541B4B23, 0hBC8EF23B69ABE4F1},
	{0h3FEB728345196E3E, 0hBC8BC69F324E6D61, 0h3FE073879922FFEE, 0hBC8A5A014347406C},
	{0h3FEBD7C0AC6F952A, 0hBC8825A732AC700A, 0h3FDF8BA4DBF89ABA, 0hBC32EC1FC1B776B8},
	{0h3FEC38B2F180BDB1, 0hBC76E0B1757C8D07, 0h3FDE2B5D3806F63B, 0h3C5E0D891D3C6841},
	{0h3FEC954B213411F5, 0hBC52FB761E946603, 0h3FDCC66E9931C45E, 0h3C56850E59C37F8F},
	{0h3FECED7AF43CC773, 0hBC5E7B6BB5AB58AE, 0h3FDB5D1009E15CC0, 0h3C65B362CB974183},
	{0h3FED4134D14DC93A, 0hBC84EF5295D25AF2, 0h3FD9EF7943A8ED8A, 0h3C66DA81290BDBAB},
	{0h3FED906BCF328D46, 0h3C7457E610231AC2, 0h3FD87DE2A6AEA963, 0hBC672CEDD3D5A610},
	{0h3FEDDB13B6CCC23C, 0h3C883C37C6107DB3, 0h3FD7088530FA459F, 0hBC744B19E0864C5D},
	{0h3FEE212104F686E5, 0hBC8014C76C126527, 0h3FD58F9A75AB1FDD, 0hBC1EFDC0D58CF620},
	{0h3FEE6288EC48E112, 0hBC616B56F2847754, 0h3FD4135C94176601, 0h3C70C97C4AFA2518},
	{0h3FEE9F4156C62DDA, 0h3C8760B1E2E3F81E, 0h3FD294062ED59F06, 0hBC75D28DA2C4612D},
	{0h3FEED740E7684963, 0h3C7E82C791F59CC2, 0h3FD111D262B1F677, 0h3C7824C20AB7AA9A},
	{0h3FEF0A7EFB9230D7, 0h3C752C7ADC6B4989, 0h3FCF19F97B215F1B, 0hBC642DEEF11DA2C4},
	{0h3FEF38F3AC64E589, 0hBC7D7BAFB51F72E6, 0h3FCC0B826A7E4F63, 0hBC1AF1439E521935},
	{0h3FEF6297CFF75CB0, 0h3C7562172A361FD3, 0h3FC8F8B83C69A60B, 0hBC626D19B9FF8D82},
	{0h3FEF8764FA714BA9, 0h3C7AB256778FFCB6, 0h3FC5E214448B3FC6, 0h3C6531FF779DDAC6},
	{0h3FEFA7557F08A517, 0hBC87A0A8CA13571F, 0h3FC2C8106E8E613A, 0h3C513000A89A11E0},
	{0h3FEFC26470E19FD3, 0h3C81EC8668ECACEE, 0h3FBF564E56A9730E, 0h3C4A2704729AE56D},
	{0h3FEFD88DA3D12526, 0hBC887DF6378811C7, 0h3FB917A6BC29B42C, 0hBC3E2718D26ED688},
	{0h3FEFE9CDAD01883A, 0h3C6521ECD0C67E35, 0h3FB2D52092CE19F6, 0hBC49A088A8BF6B2C},
	{0h3FEFF621E3796D7E, 0hBC6C57BC2E24AA15, 0h3FA91F65F10DD814, 0hBC2912BD0D569A90},
	{0h3FEFFD886084CD0D, 0hBC81354D4556E4CB, 0h3F992155F7A3667E, 0hBBFB1D63091A0130},
	{0h3FF0000000000000, 0h0000000000000000, 0h0000000000000000, 0h0000000000000000},
	{0h3FEFFD886084CD0D, 0hBC81354D4556E4CB, 0hBF992155F7A3667E, 0h3BFB1D63091A0130},
	{0h3FEFF621E3796D7E, 0hBC6C57BC2E24AA15, 0hBFA91F65F10DD814, 0h3C2912BD0D569A90},
	{0h3FEFE9CDAD01883A, 0h3C6521ECD0C67E35, 0hBFB2D52092CE19F6, 0h3C49A088A8BF6B2C},
	{0h3FEFD88DA3D12526, 0hBC887DF6378811C7, 0hBFB917A6BC29B42C, 0h3C3E2718D26ED688},
	{0h3FEFC26470E19FD3, 0h3C81EC8668ECACEE, 0hBFBF564E56A9730E, 0hBC4A2704729AE56D},
	{0h3FEFA7557F08A517, 0hBC87A0A8CA13571F, 0hBFC2C8106E8E613A, 0hBC513000A89A11E0},
	{0h3FEF8764FA714BA9, 0h3C7AB256778FFCB6, 0hBFC5E214448B3FC6, 0hBC6531FF779DDAC6},
	{0h3FEF6297CFF75CB0, 0h3C7562172A361FD3, 0hBFC8F8B83C69A60B, 0h3C626D19B9FF8D82},
	{0h3FEF38F3AC64E589, 0hBC7D7BAFB51F72E6, 0hBFCC0B826A7E4F63, 0h3C1AF1439E521935},
	{0h3FEF0A7EFB9230D7, 0h3C752C7ADC6B4989, 0hBFCF19F97B215F1B, 0h3C642DEEF11DA2C4},
	{0h3FEED740E7684963, 0h3C7E82C791F59CC2, 0hBFD111D262B1F677, 0hBC7824C20AB7AA9A},
	{0h3FEE9F4156C62DDA, 0h3C8760B1E2E3F81E, 0hBFD294062ED59F06, 0h3C75D28DA2C4612D},
	{0h3FEE6288EC48E112, 0hBC616B56F2847754, 0hBFD4135C94176601, 0hBC70C97C4AFA2518},
	{0h3FEE212104F686E5, 0hBC8014C76C126527, 0hBFD58F9A75AB1FDD, 0h3C1EFDC0D58CF620},
	{0h3FEDDB13B6CCC23C, 0h3C883C37C6107DB3, 0hBFD7088530FA459F, 0h3C744B19E0864C5D},
	{0h3FED906BCF328D46, 0h3C7457E610231AC2, 0hBFD87DE2A6AEA963, 0h3C672CEDD3D5A610},
	{0h3FED4134D14DC93A, 0hBC84EF5295D25AF2, 0hBFD9EF7943A8ED8A, 0hBC66DA81290BDBAB},
	{0h3FECED7AF43CC773, 0hBC5E7B6BB5AB58AE, 0hBFDB5D1009E15CC0, 0hBC65B362CB974183},
	{0h3FEC954B213411F5, 0hBC52FB761E946603, 0hBFDCC66E9931C45E, 0hBC56850E59C37F8F},
	{0h3FEC38B2F180BDB1, 0hBC76E0B1757C8D07, 0hBFDE2B5D3806F63B, 0hBC5E0D891D3C6841},
	{0h3FEBD7C0AC6F952A, 0hBC8825A732AC700A, 0hBFDF8BA4DBF89ABA, 0h3C32EC1FC1B776B8},
	{0h3FEB728345196E3E, 0hBC8BC69F324E6D61, 0hBFE073879922FFEE, 0h3C8A5A014347406C},
	{0h3FEB090A58150200, 0hBC8926DA300FFCCE, 0hBFE11EB3541B4B23, 0h3C8EF23B69ABE4F1},
	{0h3FEA9B66290EA1A3, 0h3C39F630E8B6DAC8, 0hBFE1C73B39AE68C8, 0hBC8B25DD267F6600},
	{0h3FEA29A7A0462782, 0hBC7128BB015DF175, 0hBFE26D054CDD12DF, 0h3C85DA743EF3770C},
	{0h3FE9B3E047F38741, 0hBC830EE286712474, 0hBFE30FF7FCE17035, 0h3C6EFCC626F74A6F},
	{0h3FE93A22499263FB, 0h3C83D419A920DF0B, 0hBFE3AFFA292050B9, 0hBC7E3E25E3954964},
	{0h3FE8BC806B151741, 0hBC82C5E12ED1336D, 0hBFE44CF325091DD6, 0hBC68076A2CFDC6B3},
	{0h3FE83B0E0BFF976E, 0hBC76F420F8EA3475, 0hBFE4E6CABBE3E5E9, 0hBC63C293EDCEB327},
	{0h3FE7B5DF226AAFAF, 0hBC70F537ACDF0AD7, 0hBFE57D69348CECA0, 0h3C875720992BFBB2},
	{0h3FE72D0837EFFF96, 0h3C80D4EF0F1D915C, 0hBFE610B7551D2CDF, 0h3C7251B352FF2A37},
	{0h3FE6A09E667F3BCD, 0hBC8BDD3413B26456, 0hBFE6A09E667F3BCD, 0h3C8BDD3413B26456},
	{0h3FE610B7551D2CDF, 0hBC7251B352FF2A37, 0hBFE72D0837EFFF96, 0hBC80D4EF0F1D915C},
	{0h3FE57D69348CECA0, 0hBC875720992BFBB2, 0hBFE7B5DF226AAFAF, 0h3C70F537ACDF0AD7},
	{0h3FE4E6CABBE3E5E9, 0h3C63C293EDCEB327, 0hBFE83B0E0BFF976E, 0h3C76F420F8EA3475},
	{0h3FE44CF325091DD6, 0h3C68076A2CFDC6B3, 0hBFE8BC806B151741, 0h3C82C5E12ED1336D},
	{0h3FE3AFFA292050B9, 0h3C7E3E25E3954964, 0hBFE93A22499263FB, 0hBC83D419A920DF0B},
	{0h3FE30FF7FCE17035, 0hBC6EFCC626F74A6F, 0hBFE9B3E047F38741, 0h3C830EE286712474},
	{0h3FE26D054CDD12DF, 0hBC85DA743EF3770C, 0hBFEA29A7A0462782, 0h3C7128BB015DF175},
	{0h3FE1C73B39AE68C8, 0h3C8B25DD267F6600, 0hBFEA9B66290EA1A3, 0hBC39F630E8B6DAC8},
	{0h3FE11EB3541B4B23, 0hBC8EF23B69ABE4F1, 0hBFEB090A58150200, 0h3C8926DA300FFCCE},
	{0h3FE073879922FFEE, 0hBC8A5A014347406C, 0hBFEB728345196E3E, 0h3C8BC69F324E6D61},
	{0h3FDF8BA4DBF89ABA, 0hBC32EC1FC1B776B8, 0hBFEBD7C0AC6F952A, 0h3C8825A732AC700A},
	{0h3FDE2B5D3806F63B, 0h3C5E0D891D3C6841, 0hBFEC38B2F180BDB1, 0h3C76E0B1757C8D07},
	{0h3FDCC66E9931C45E, 0h3C56850E59C37F8F, 0hBFEC954B213411F5, 0h3C52FB761E946603},
	{0h3FDB5D1009E15CC0, 0h3C65B362CB974183, 0hBFECED7AF43CC773, 0h3C5E7B6BB5AB58AE},
	{0h3FD9EF7943A8ED8A, 0h3C66DA81290BDBAB, 0hBFED4134D14DC93A, 0h3C84EF5295D25AF2},
	{0h3FD87DE2A6AEA963, 0hBC672CEDD3D5A610, 0hBFED906BCF328D46, 0hBC7457E610231AC2},
	{0h3FD7088530FA459F, 0hBC744B19E0864C5D, 0hBFEDDB13B6CCC23C, 0hBC883C37C6107DB3},
	{0h3FD58F9A75AB1FDD, 0hBC1EFDC0D58CF620, 0hBFEE212104F686E5, 0h3C8014C76C126527},
	{0h3FD4135C94176601, 0h3C70C97C4AFA2518, 0hBFEE6288EC48E112, 0h3C616B56F2847754},
	{0h3FD294062ED59F06, 0hBC75D28DA2C4612D, 0hBFEE9F4156C62DDA, 0hBC8760B1E2E3F81E},
	{0h3FD111D262B1F677, 0h3C7824C20AB7AA9A, 0hBFEED740E7684963, 0hBC7E82C791F59CC2},
	{0h3FCF19F97B215F1B, 0hBC642DEEF11DA2C4, 0hBFEF0A7EFB9230D7, 0hBC752C7ADC6B4989},
	{0h3FCC0B826A7E4F63, 0hBC1AF1439E521935, 0hBFEF38F3AC64E589, 0h3C7D7BAFB51F72E6},
	{0h3FC8F8B83C69A60B, 0hBC626D19B9FF8D82, 0hBFEF6297CFF75CB0, 0hBC7562172A361FD3},
	{0h3FC5E214448B3FC6, 0h3C6531FF779DDAC6, 0hBFEF8764FA714BA9, 0hBC7AB256778FFCB6},
	{0h3FC2C8106E8E613A, 0h3C513000A89A11E0, 0hBFEFA7557F08A517, 0h3C87A0A8CA13571F},
	{0h3FBF564E56A9730E, 0h3C4A2704729AE56D, 0hBFEFC26470E19FD3, 0hBC81EC8668ECACEE},
	{0h3FB917A6BC29B42C, 0hBC3E2718D26ED688, 0hBFEFD88DA3D12526, 0h3C887DF6378811C7},
	{0h3FB2D52092CE19F6, 0hBC49A088A8BF6B2C, 0hBFEFE9CDAD01883A, 0hBC6521ECD0C67E35},
	{0h3FA91F65F10DD814, 0hBC2912BD0D569A90, 0hBFEFF621E3796D7E, 0h3C6C57BC2E24AA15},
	{0h3F992155F7A3667E, 0hBBFB1D63091A0130, 0hBFEFFD886084CD0D, 0h3C81354D4556E4CB},
}

// sin.c:432-561 (`U2`), hex floats written as `0h` bit patterns.
@(private = "file", rodata)
U2 := [128][4]f64 {
	{0h0000000000000000, 0h0000000000000000, 0h3FF0000000000000, 0h0000000000000000},
	{0h3F2921FB51AEB57C, 0hBBCA6E1D4916C435, 0h3FEFFFFFF621619C, 0hBC87507DBBBD8FE6},
	{0h3F3921FB49EE4EA6, 0h3BDE894D744A453E, 0h3FEFFFFFD8858675, 0hBC879F0E54748EAB},
	{0h3F42D97C6DC23A75, 0hBBD1C27727253849, 0h3FEFFFFFA72C6E9D, 0h3C7FFA0E2A0E5C29},
	{0h3F4921FB2AECB360, 0h3BE876157E566B4C, 0h3FEFFFFF62161A34, 0hBC6136DCB1F9B9C4},
	{0h3F4F6A79D8965EBA, 0hBBEA2A951670A396, 0h3FEFFFFF09428963, 0h3C82F505FBA9C0B0},
	{0h3F52D97C396F8497, 0hBBD45CB4CC3D0FB1, 0h3FEFFFFE9CB1BC62, 0h3C70FE9FA3478EC9},
	{0h3F55FDBB7AF33FBB, 0h3BEC0C37A5D5101D, 0h3FEFFFFE1C63B373, 0h3C8A50F155E87E56},
	{0h3F5921FAAEE6472E, 0hBBFEE52E284A9DF8, 0h3FEFFFFD88586EE6, 0h3C81AF64F173AE5B},
	{0h3F5C4639D358815A, 0h3BA0FFA0E86B4DCC, 0h3FEFFFFCE08FEF16, 0h3C592E420A03BF59},
	{0h3F5F6A78E659D4B6, 0h3BFCB8A9B355AC80, 0h3FEFFFFC250A346A, 0h3C7D099C02280C58},
	{0h3F61475BF2FD13E2, 0hBC04AE6DED9797CC, 0h3FEFFFFB55C73F56, 0h3C8EE2AE1596963A},
	{0h3F62D97B6824B087, 0hBC09DAE69DD4F97F, 0h3FEFFFFA72C7105B, 0hBC8564EC4A452371},
	{0h3F646B9AD1ABB397, 0hBBFAC1B1950E9DC6, 0h3FEFFFF97C09A803, 0hBC7961EC991858F1},
	{0h3F65FDBA2E9A1066, 0h3BFF1ED8ABAAA608, 0h3FEFFFF8718F06E7, 0h3C6793938EE3FC9A},
	{0h3F678FD97DF7BA51, 0hBC02F2580C9BA856, 0h3FEFFFF753572DAC, 0hBC65DF4D689B3227},
	{0h3F6921F8BECCA4BA, 0h3C02BA407BCAB5B2, 0h3FEFFFF621621D02, 0hBC76ACFCEBC82813},
	{0h3F6AB417F020C310, 0h3BE7FB6C9AE3781A, 0h3FEFFFF4DBAFD5A6, 0hBC8D017DE84EBC3F},
	{0h3F6C463710FC08C9, 0hBBFF621BBEF801CF, 0h3FEFFFF382405860, 0hBC2F949383D834E0},
	{0h3F6DD85620666965, 0h3BE5A1A4ECD8345A, 0h3FEFFFF21513A606, 0h3C7EE48B39CC31CF},
	{0h3F6F6A751D67D871, 0hBC066BDEF183FF59, 0h3FEFFFF09429BF7A, 0hBC8CABD3DED13A63},
	{0h3F707E4A038424C1, 0h3C07E6886ED9BEC7, 0h3FEFFFEEFF82A5A7, 0h3C86EFC1CF23E273},
	{0h3F7147596E27D81F, 0hBC1BBFE9EDBA714A, 0h3FEFFFED571E5989, 0h3C8151C0E15503CF},
	{0h3F721068CE230028, 0h3C06CE44CA79798D, 0h3FEFFFEB9AFCDC25, 0h3C632C5AF9456B9F},
	{0h3F72D97822F996BC, 0h3C13E5A15ED6AA3E, 0h3FEFFFE9CB1E2E8D, 0hBC810F44663FD601},
	{0h3F73A2876C2F95C0, 0h3C003F5805A36F7E, 0h3FEFFFE7E78251DE, 0h3C889B8834C8800C},
	{0h3F746B96A948F720, 0hBBE3FBFF884C87DA, 0h3FEFFFE5F0294744, 0h3C85E809BDC855FC},
	{0h3F7534A5D9C9B4D0, 0hBC18653D3B3F3BF5, 0h3FEFFFE3E5130FF5, 0h3C68D94F3D6CA2D6},
	{0h3F75FDB4FD35C8CB, 0hBC14B73D73E9B437, 0h3FEFFFE1C63FAD33, 0h3C8429D08EB02C47},
	{0h3F76C6C413112D15, 0hBC0C66913985B2A8, 0h3FEFFFDF93AF204E, 0hBC74ADE22D9F9483},
	{0h3F778FD31ADFDBBA, 0hBBF03BF7BEE2893D, 0h3FEFFFDD4D616AA0, 0hBC8422710E8C8595},
	{0h3F7858E21425CECF, 0hBC05AF2BEFB31C3C, 0h3FEFFFDAF3568D90, 0h3C599C62DC3A22AC},
	{0h3F7921F0FE670071, 0h3BFAB967FE6B7A9B, 0h3FEFFFD8858E8A92, 0h3C8359C71883BCF7},
	{0h3F79EAFFD9276AC8, 0hBC1558E4E5CCAFC7, 0h3FEFFFD604096326, 0hBC37D6BDD1C1F436},
	{0h3F7AB40EA3EB0803, 0hBBC7FE2A8E15F257, 0h3FEFFFD36EC718D7, 0hBC75C59FFCFBA7E4},
	{0h3F7B7D1D5E35D25D, 0h3C19CFE67F192CD7, 0h3FEFFFD0C5C7AD3D, 0hBC819D99906D21E9},
	{0h3F7C462C078BC41B, 0h3C19F6DB9A6ADA3C, 0h3FEFFFCE090B21FC, 0hBC80389138F7E5EF},
	{0h3F7D0F3A9F70D78C, 0hBBEA08E48B732DF4, 0h3FEFFFCB389178C4, 0h3C72883B1FE7D578},
	{0h3F7DD84925690709, 0hBC10441C939BD6DA, 0h3FEFFFC8545AB352, 0h3C861157C68F984B},
	{0h3F7EA15798F84CF7, 0hBC1BD41D0FE0C595, 0h3FEFFFC55C66D36F, 0hBC5AB98D6FCF9CD6},
	{0h3F7F6A65F9A2A3C6, 0hBC1DE8C48783F3AE, 0h3FEFFFC250B5DAEF, 0hBC813B48657081CD},
	{0h3F8019BA237602F9, 0hBC22479C7145927D, 0h3FEFFFBF3147CBB3, 0hBC86A078C1216E21},
	{0h3F807E41402C3701, 0hBBC93E58A2A04D27, 0h3FEFFFBBFE1CA7A8, 0hBC7698B82E41CFAE},
	{0h3F80E2C852B5EB46, 0hBC29B8495E4EC41D, 0h3FEFFFB8B73470C8, 0hBC8BC4E4BE396442},
	{0h3F81474F5AD51D17, 0hBC1A0FB850F9330D, 0h3FEFFFB55C8F2917, 0h3C86AF540576EB51},
	{0h3F81ABD6584BC9CB, 0h3C221B927D9670CC, 0h3FEFFFB1EE2CD2A9, 0hBC73EE83959A5F1D},
	{0h3F82105D4ADBEEC0, 0h3C24E6ED5742DCF7, 0h3FEFFFAE6C0D6F9A, 0hBC7102FD2CB5B720},
	{0h3F8274E43247895A, 0hBC046CA3539434EA, 0h3FEFFFAAD6310214, 0h3C8B8629443A759A},
	{0h3F82D96B0E509703, 0hBC01E9131FF52DC9, 0h3FEFFFA72C978C4F, 0hBC822CB000328F91},
	{0h3F833DF1DEB9152D, 0h3C1F5FB935DBF892, 0h3FEFFFA36F41108B, 0h3C655D1C829905C6},
	{0h3F83A278A3430152, 0hBC02C26D82855518, 0h3FEFFF9F9E2D9118, 0h3C6102F90F3495E0},
	{0h3F8406FF5BB058F1, 0h3C26E66FF4BCD327, 0h3FEFFF9BB95D1050, 0h3C87FB680DB05F83},
	{0h3F846B8607C31993, 0h3C291D1AC2A2CED6, 0h3FEFFF97C0CF909B, 0hBC6B418B1F88CF02},
	{0h3F84D00CA73D40C8, 0hBC2FAE7469C8DBD1, 0h3FEFFF93B485146B, 0hBC843E02406FB373},
	{0h3F85349339E0CC25, 0hBBFEC016EA8E8F27, 0h3FEFFF8F947D9E3F, 0hBC42CEFD02EBE75C},
	{0h3F859919BF6FB94B, 0hBC11CA7261E51E18, 0h3FEFFF8B60B930A3, 0h3C797DBE1FDCAB90},
	{0h3F85FDA037AC05E1, 0hBC2FF59BF4B574EE, 0h3FEFFF871937CE2F, 0hBC638DAE49F0BE32},
	{0h3F866226A257AF95, 0h3C23CD7A66DFAFC8, 0h3FEFFF82BDF97986, 0hBC6507B1E2913E3B},
	{0h3F86C6ACFF34B421, 0h3C0B03798BBE7197, 0h3FEFFF7E4EFE3558, 0h3C6EBE425D873A16},
	{0h3F872B334E051144, 0h3C1CAF2DF425EF35, 0h3FEFFF79CC460462, 0hBC86C8D94412B92A},
	{0h3F878FB98E8AC4C8, 0hBC2555202816F3A5, 0h3FEFFF7535D0E96B, 0hBC7C5727FF41299B},
	{0h3F87F43FC087CC7D, 0h3C200A2A3A85D253, 0h3FEFFF708B9EE748, 0hBC37FF8F5CEFE85A},
	{0h3F8858C5E3BE2640, 0hBC1EE9C7105192D8, 0h3FEFFF6BCDB000DA, 0hBC665348E4F5CD16},
	{0h3F88BD4BF7EFCFF3, 0h3C066640846E6109, 0h3FEFFF66FC04390D, 0h3C877F5704F2756C},
	{0h3F8921D1FCDEC784, 0h3C29878EBE836D9D, 0h3FEFFF62169B92DB, 0h3C85DDA3C81FBD0D},
	{0h3F898657F24D0AEA, 0h3C211D4D1D1806D2, 0h3FEFFF5D1D761149, 0h3C0E7B86F31E2875},
	{0h3F89EADDD7FC9825, 0hBC15ADB5ADFD3669, 0h3FEFFF581093B768, 0hBC83EEEE9513AE4C},
	{0h3F8A4F63ADAF6D3E, 0hBBFF838D8DD726DC, 0h3FEFFF52EFF48855, 0hBC6514532E82DE3F},
	{0h3F8AB3E973278849, 0h3C235B145A18353C, 0h3FEFFF4DBB98873A, 0h3C8857663DC92252},
	{0h3F8B186F2826E765, 0hBC26B3B32921E88C, 0h3FEFFF48737FB74E, 0hBC5D462B0C1681E7},
	{0h3F8B7CF4CC6F88B8, 0hBC132C6A46235330, 0h3FEFFF4317AA1BD2, 0hBC86A0039355B637},
	{0h3F8BE17A5FC36A75, 0h3C0C404548EDFC51, 0h3FEFFF3DA817B814, 0hBC82B464E14730C0},
	{0h3F8C45FFE1E48AD9, 0h3C04060E4BD32E79, 0h3FEFFF3824C88F6F, 0hBC8ED820F3FE6980},
	{0h3F8CAA855294E82B, 0h3BDECA8FA79834DE, 0h3FEFFF328DBCA549, 0hBC86CA1AF321DC1C},
	{0h3F8D0F0AB19680BD, 0hBBFE9C612F8A4102, 0h3FEFFF2CE2F3FD15, 0hBC762CCF8BDB122F},
	{0h3F8D738FFEAB52EC, 0hBC1C110BC5257C8C, 0h3FEFFF27246E9A52, 0hBC416D6346F3F55F},
	{0h3F8DD81539955D20, 0hBC2EAF6D880C7F01, 0h3FEFFF21522C808B, 0h3C7A190E2D2EAF6E},
	{0h3F8E3C9A62169DCB, 0h3C26666333E35E32, 0h3FEFFF1B6C2DB358, 0hBC7F4664A9AD833C},
	{0h3F8EA11F77F1136E, 0hBC17A617506AACB8, 0h3FEFFF157272365B, 0h3C644EF643864760},
	{0h3F8F05A47AE6BC91, 0hBBF0935BB936BE66, 0h3FEFFF0F64FA0D45, 0hBC7AC9ACB9BB8D2D},
	{0h3F8F6A296AB997CB, 0hBC2F2943D8FE7033, 0h3FEFFF0943C53BD1, 0hBC847399F361D158},
	{0h3F8FCEAE472BA3BC, 0hBBF3A08B18043960, 0h3FEFFF030ED3C5C7, 0hBC82504B1DC047E8},
	{0h3F90199987FF6F89, 0h3C38DACCEF2E2556, 0h3FEFFEFCC625AEFB, 0h3C4FBB0DD6AF1603},
	{0h3F904BDBE27AA444, 0h3C30C87A06C6956D, 0h3FEFFEF669BAFB4E, 0hBC5B5A4E5318177B},
	{0h3F907E1E32E86F72, 0hBC3F40145DDE0463, 0h3FEFFEEFF993AEAC, 0hBC599DB334BE163B},
	{0h3F90B0607929D07A, 0h3C2F989B780D54E7, 0h3FEFFEE975AFCD0E, 0hBC82DF82B9320ECD},
	{0h3F90E2A2B51FC6CE, 0hBC22CA118AAA212F, 0h3FEFFEE2DE0F5A78, 0h3C59DAA217ACC1B0},
	{0h3F9114E4E6AB51E2, 0h3C110D53D5E0FFC5, 0h3FEFFEDC32B25AFC, 0hBBFBB89D7B0D4487},
	{0h3F9147270DAD7133, 0h3C08769E00E01800, 0h3FEFFED57398D2B7, 0hBC80BB0DB6384CF3},
	{0h3F9179692A072443, 0h3C3D40C977F2FE27, 0h3FEFFECEA0C2C5D2, 0hBC87A22A10E4CB4F},
	{0h3F91ABAB3B996A9D, 0hBC3E21A2EF2391D3, 0h3FEFFEC7BA303882, 0h3C7B209EC7100E1A},
	{0h3F91DDED424543CE, 0h3C22ECDB3D03A70B, 0h3FEFFEC0BFE12F0A, 0h3C78B1483B4090ED},
	{0h3F92102F3DEBAF6F, 0hBC145A1EA37E10EA, 0h3FEFFEB9B1D5ADB7, 0h3C8D5B363C2F4370},
	{0h3F9242712E6DAD1C, 0h3C30317D8CE1D1B9, 0h3FEFFEB2900DB8E4, 0h3C618F6A66301D60},
	{0h3F9274B313AC3C7A, 0h3C3B29E49ACF7E7E, 0h3FEFFEAB5A8954F6, 0h3C80652CFE4CEBFA},
	{0h3F92A6F4ED885D35, 0hBC35A8A13D8F9966, 0h3FEFFEA411488660, 0h3C8B77E2735C69F9},
	{0h3F92D936BBE30EFD, 0h3C2B5F91EE371D64, 0h3FEFFE9CB44B51A1, 0h3C75B43366DF6670},
	{0h3F930B787E9D518D, 0h3C3B620C940DF42A, 0h3FEFFE954391BB43, 0h3C7DDD5377BEEF1A},
	{0h3F933DBA359824A6, 0hBC26C4020B5F32A8, 0h3FEFFE8DBF1BC7DE, 0hBC8CC391831CBCD0},
	{0h3F936FFBE0B4880E, 0h3C24B88026F4E07B, 0h3FEFFE8626E97C13, 0h3C7CDB27525FCAF7},
	{0h3F93A23D7FD37B96, 0hBC3DD9E849A0A5D5, 0h3FEFFE7E7AFADC94, 0hBC8DB1225B06B02C},
	{0h3F93D47F12D5FF12, 0h3C3ADD51EAB25DD4, 0h3FEFFE76BB4FEE1A, 0hBC60C43DAE9E89C6},
	{0h3F9406C0999D1263, 0hBC2CF7CBEEA1DDCF, 0h3FEFFE6EE7E8B56E, 0h3C57ECAC48A7B7BC},
	{0h3F9439021409B56C, 0h3C181352C74C7AE2, 0h3FEFFE6700C53764, 0hBC84F502302AFD49},
	{0h3F946B4381FCE81B, 0h3C3FF9F89FB65BE3, 0h3FEFFE5F05E578DB, 0hBC7B71F7469ECC13},
	{0h3F949D84E357AA66, 0hBC29143373E36698, 0h3FEFFE56F7497EC0, 0hBC8DDF92A8D40B30},
	{0h3F94CFC637FAFC48, 0hBC3A3541BB15D5BA, 0h3FEFFE4ED4F14E0A, 0h3C7E48478B2F0BA1},
	{0h3F9502077FC7DDC5, 0h3C325236A8347D96, 0h3FEFFE469EDCEBBF, 0h3C88FC7557D6BC53},
	{0h3F953448BA9F4EEB, 0h3C2E6ADDE30EC695, 0h3FEFFE3E550C5CF0, 0hBC858FB3AE72192E},
	{0h3F956689E8624FCE, 0hBC2B967A2D3EE5B3, 0h3FEFFE35F77FA6B8, 0hBC6A7661B121429A},
	{0h3F9598CB08F1E089, 0h3C356F9C34C216B4, 0h3FEFFE2D8636CE41, 0h3C6B4243168AB5A4},
	{0h3F95CB0C1C2F0142, 0h3C3C2C42AC4D436C, 0h3FEFFE250131D8C0, 0h3C8ED2D09D5789D3},
	{0h3F95FD4D21FAB226, 0hBC20C0A91C37851C, 0h3FEFFE1C6870CB77, 0h3C889AA14768323E},
	{0h3F962F8E1A35F369, 0hBC344AB93E20133F, 0h3FEFFE13BBF3ABB3, 0h3C86721EEE289B1D},
	{0h3F9661CF04C1C548, 0h3C33D6CC7CE6FF57, 0h3FEFFE0AFBBA7ECE, 0h3C66ECD981464044},
	{0h3F96940FE17F280B, 0hBC384BF8988CC420, 0h3FEFFE0227C54A2D, 0h3C8EEED1D70E13E2},
	{0h3F96C650B04F1BFE, 0h3BA53E382471FA0C, 0h3FEFFDF940141344, 0hBC8A63FC248C2DAC},
	{0h3F96F8917112A179, 0h3C3B6DE0AD6E9445, 0h3FEFFDF044A6DF8F, 0hBC8798CFB498D8B1},
	{0h3F972AD223AAB8DD, 0hBC3CF17A0AD13B4A, 0h3FEFFDE7357DB499, 0h3C409337DEB3FF5A},
	{0h3F975D12C7F86290, 0hBC307D8473495AAE, 0h3FEFFDDE129897F9, 0h3C844E8786DEDB6B},
	{0h3F978F535DDC9F04, 0h3C2B194AD9B1AA97, 0h3FEFFDD4DBF78F52, 0h3C8216679A26323D},
	{0h3F97C193E5386EB4, 0h3C0725118C2860E7, 0h3FEFFDCB919AA053, 0hBC755C1CE37AE6F6},
	{0h3F97F3D45DECD222, 0h3C32FE8CFE80809D, 0h3FEFFDC23381D0B6, 0h3C600D15F9603FED},
	{0h3F982614C7DAC9DB, 0h3C0E95F011AC18C6, 0h3FEFFDB8C1AD2643, 0h3C7E79471744A0CB},
	{0h3F98585522E35674, 0hBC3D5A766C5894C1, 0h3FEFFDAF3C1CA6CE, 0hBC79C0F0834FA422},
	{0h3F988A956EE7788A, 0h3C219DFBD12FF726, 0h3FEFFDA5A2D05835, 0h3C86DBC405FF8E25},
	{0h3F98BCD5ABC830C7, 0hBC3F7D609F14A311, 0h3FEFFD9BF5C84066, 0hBC835167A6CE828D},
	{0h3F98EF15D9667FDA, 0hBC3668DC9BA82A70, 0h3FEFFD9235046557, 0hBC7C3C6E16616FB2},
}
