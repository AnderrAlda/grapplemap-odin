/*
Correctly rounded binary64 atan2, ported from CORE-MATH (#161, ADR 0003 amendment).

Source: https://gitlab.inria.fr/core-math/core-math, commit 333d11d04d73ef165cf217e773b3b3d6372aa66f,
files src/binary64/atan2/atan2.c (cited below as `atan2.c:<lines>`) and src/binary64/atan2/tint.h (`tint.h:<lines>`).
The algorithm, the operation order and every constant are unchanged; the constants are written as `0h` bit literals
because Odin has no C99 hex float literals (the C spelling is in the comments where it helps).

Differences from the C, none of which changes a result in round-to-nearest:
- Only round-to-nearest (the IEEE default, and the only mode Odin code runs in) is supported. The `fenv` handling
  (`feholdexcept`, `fetestexcept`, `feclearexcept`, `feupdateenv`, `fegetexceptflag`), the underflow/overflow flag
  bookkeeping and `errno` are dropped. `fma(t, -0x1p-54, t)` is kept: it returns `t` in round-to-nearest.
- `tint_t` is a struct of `h, m, l, ex, sgn`, and the C union's 128-bit view `_h` is `(h << 64) | m`. The C
  routines write through pointers that may alias their inputs; here they take values and return values. Each C
  routine reads its operands before it overwrites them, so the two are equivalent.
- `tint_tod`'s "Unexpected worst-case found" branch (tint.h:409-416) prints and calls `exit(1)`. It is dropped:
  CORE-MATH's error analysis rules it out, and this function never aborts. The value computed is returned.
- `as_ldexp` uses the portable integer form (tint.h:377-379), not the SSE2 one.
- The disabled `#if 0` block (atan2.c:287-293) is not ported.

Licence of the original (MIT):

Copyright (c) 2024-2025 Paul Zimmermann and Alexei Sibidanov

This file is part of the CORE-MATH project
(https://core-math.gitlabpages.inria.fr/).

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
*/
package core

import "base:intrinsics"

// cr_atan2 is `atan2(y, x)` correctly rounded to nearest, for every binary64 input (CORE-MATH `cr_atan2`,
// atan2.c:487-612), with the special values of C99 Annex F.9.1.4. It does not allocate and has no global
// state. `core` uses it instead of `math.atan2` or the libm (ADR 0003, amendment #161).
cr_atan2 :: proc "contextless" (y0, x0: f64) -> f64 {
	iy := transmute(u64)y0
	ix := transmute(u64)x0
	aiy := iy & ABS_MASK
	if aiy == 0 || aiy >= EXP_MASK {
		return atan2_special(y0, x0)
	}
	aix := ix & ABS_MASK
	if aix == 0 || aix >= EXP_MASK {
		return atan2_special(y0, x0)
	}
	ax := abs(x0)
	ay := abs(y0)
	x := max(ax, ay)
	y := min(ax, ay)
	sy := iy >> 63
	sx := ix >> 63
	gt := b2u(aix < aiy)
	dxy := (aix - aiy) ~ (0 - gt)
	if dxy >= 53 << 52 {
		return atan2_accurate(y0, x0)
	}
	sgn := ASGN[gt ~ sx ~ sy]
	kw := sx << 2 | sy << 1 | gt
	jj := transmute(u64)(y / x + (2 + 1 / 128.0))
	jt := (jj >> (52 - 7)) & 127
	fh := F2[jt][1] * copysign(1, sgn)
	fl := F2[jt][0] * copysign(1, sgn)
	fh += O[kw][0]
	fl += O[kw][1]
	if x < 0h0670000000000000 { 	// 0x1p-920
		x *= 0h7970000000000000 // 0x1p920
		y *= 0h7970000000000000
	}
	if x > 0h7fd0000000000000 { 	// 0x1p1022
		if jt != 0 {
			x *= 0.5
			y *= 0.5
		}
	}
	t0 := T2[jt]
	zn := fma(-t0, x, y)
	zd := fma(t0, y, x)
	z := zn / zd
	z2 := z * z
	z *= copysign(1, sgn)
	dz := (z * z2) * (B[0] + z2 * (B[1] + z2 * B[2]))
	// atan2.c:570-572: bound from 1.1e10 random pairs (round-up mode), plus 2.5%.
	eps := abs(z) * 0h3cc0510000000000 + 0h3a50000000000000 // 0x1.051p-51, 0x1p-90
	rh: f64
	rh, z = fasttwosum(fh, z)
	rl := (fl + dz) + z
	lb := rh + (rl - eps)
	ub := rh + (rl + eps)
	if lb != ub {
		dh := y * t0
		dl := fma(y, t0, -dh)
		e: f64
		dh, e = fasttwosum(x, dh)
		rdh := 1 / dh
		dl += e
		nh := x * t0
		nl := fma(x, t0, -nh)
		dt := y - nh
		y1 := dt + nh
		if y1 == y {
			nh, nl = fasttwosum(dt, -nl)
		} else {
			nh, nl = fasttwosum(dt, (y - y1) - nl)
		}
		zh := nh * rdh
		z2 = zh * zh
		zl := rdh * (fma(dh, -zh, nh) + (nl - (nh * rdh) * dl))
		zl += zh * z2 * ((B2[0] + z2 * B2[1]) + (z2 * z2) * (B2[2] + z2 * B2[3]))
		zh *= copysign(1, sgn)
		zl *= copysign(1, sgn)
		eps = 0h3cd4000000000000 * (abs(zh) * z2 + 0h3cc0000000000000) // 0x1.4p-50, 0x1p-51
		fh, fl = fastsum(fh, fl, zh, zl)
		lb = fh + (fl - eps)
		ub = fh + (fl + eps)
		if lb != ub {
			return atan2_accurate(y0, x0)
		}
	}
	return ub
}

@(private = "file")
ABS_MASK :: 0x7fffffffffffffff // atan2.c:55
@(private = "file")
EXP_MASK :: 0x7ff << 52

// PI_H + PI_L approximates π with error < 2^-108.041; likewise π/2 and π/4 (atan2.c:57-65).
@(private = "file")
PI_H :: 0h400921fb54442d18 // 0x1.921fb54442d18p+1
@(private = "file")
PI_L :: 0h3ca1a62633145c07 // 0x1.1a62633145c07p-53
@(private = "file")
PI_OVER2_H :: 0h3ff921fb54442d18
@(private = "file")
PI_OVER2_L :: 0h3c91a62633145c07

@(private = "file")
fma :: #force_inline proc "contextless" (a, b, c: f64) -> f64 {
	return intrinsics.fused_mul_add(a, b, c)
}

@(private = "file")
copysign :: #force_inline proc "contextless" (mag, sgn: f64) -> f64 {
	return transmute(f64)((transmute(u64)mag & ABS_MASK) | (transmute(u64)sgn & ~u64(ABS_MASK)))
}

@(private = "file")
b2u :: #force_inline proc "contextless" (b: bool) -> u64 {
	return 1 if b else 0
}

// atan2.c:425-429.
@(private = "file")
fasttwosum :: #force_inline proc "contextless" (x, y: f64) -> (s, e: f64) {
	s = x + y
	z := s - x
	e = y - z
	return
}

// atan2.c:431-435.
@(private = "file")
fastsum :: #force_inline proc "contextless" (xh, xl, yh, yl: f64) -> (sh, e: f64) {
	sl: f64
	sh, sl = fasttwosum(xh, yh)
	e = (xl + yl) + sl
	return
}

// atan2.c:437-485: NaN, infinities and zeros.
@(private = "file")
atan2_special :: proc "contextless" (y0, x0: f64) -> f64 {
	iy := transmute(u64)y0
	ix := transmute(u64)x0
	aiy := iy << 1
	aix := ix << 1
	if aiy >= 0x7ff << 53 || aix >= 0x7ff << 53 { 	// NaN or Inf
		if aiy > 0x7ff << 53 || aix > 0x7ff << 53 {
			return y0 + x0
		}
		// Now neither y nor x is NaN, but at least one is +Inf or -Inf.
		if aiy == 0x7ff << 53 && aix == 0x7ff << 53 {
			// atan2(±Inf, -Inf) = ±3π/4, atan2(±Inf, +Inf) = ±π/4
			return copysign(FINF[ix >> 63][1], y0) + copysign(FINF[ix >> 63][0], y0)
		}
		// Now only one of y and x is ±Inf.
		if aix == 0x7ff << 53 {
			if x0 < 0 {
				return copysign(PI_H, y0) + copysign(PI_L, y0)
			}
			return copysign(0, y0)
		}
		// Now y = ±Inf: atan2(±Inf, x) = ±π/2 for finite x.
		return copysign(PI_OVER2_H, y0) + copysign(PI_OVER2_L, y0)
	}
	if aiy == 0 || aix == 0 {
		if aiy == 0 && aix == 0 {
			if ix == 0 { 	// atan2(±0, +0) = ±0
				return y0
			}
			// atan2(±0, -0) = ±π
			return PI_H + PI_L if iy == 0 else -PI_H - PI_L
		}
		// Only one of y and x is zero.
		if aiy == 0 {
			if x0 > 0 { 	// atan2(±0, x) = ±0 for x > 0
				return y0 / x0
			}
			return PI_H + PI_L if iy >> 63 == 0 else -PI_H - PI_L // ±π for x < 0
		}
		// Now only x is zero: atan2(y, ±0) = ±π/2.
		return PI_OVER2_H + PI_OVER2_L if y0 > 0 else -PI_OVER2_H - PI_OVER2_L
	}
	return 0
}

// atan2_accurate is atan2.c:205-421: a type [29,29] rational approximation of atan(z), 0 <= z <= 1, evaluated in
// 192-bit `Tint` arithmetic. Reached when the fast path cannot decide the rounding.
@(private = "file")
atan2_accurate :: proc "contextless" (y, x: f64) -> f64 {
	// atan2.c:214-244: t = y/x; when it underflows to 0, atan2 is t (x > 0) or ±π.
	t := y / x
	if t == 0 {
		if x > 0 {
			return t
		}
		return PI_H + PI_L if y > 0 else -PI_H - PI_L
	}
	// atan2.c:245-273: t exact and |t| <= 0x1.d12ed0af1a27fp-27, x > 0: atan(t) rounds to t.
	corr := fma(t, x, -y)
	if corr == 0 && x > 0 {
		if abs(t) <= 0h3e4d12ed0af1a27f {
			if abs(y) >= 0h06c0000000000000 { 	// 0x1p-915
				return fma(t, -0h3c90000000000000, t) // 0x1p-54
			}
			// |y| < 2^-969: scale y and t by 2^105 so that t*x - y does not underflow.
			corr = fma(t * 0h4680000000000000, x, -y * 0h4680000000000000) // 0x1p105
			if corr == 0 {
				return fma(t, -0h3c90000000000000, t)
			}
		}
	}

	inv := abs(y) > abs(x)
	z := tint_div_d(x, y) if inv else tint_div_d(y, x)

	// atan2.c:302-314: |y/x| < 2^-96, x > 0: atan(y/x) rounds as y/x moved slightly towards zero. The borrow
	// tests are the original's, verbatim.
	if !inv && x > 0 && z.ex <= -96 {
		z.l -= 2
		z.m -= b2u(z.l < 2)
		z.h -= b2u(z.m < 1)
		return tint_tod(z, 1)
	}

	// atan2.c:316-339: z*P(z)/Q(z); the approximation is for z > 0 only.
	sz := z.sgn
	z.sgn = 0
	p := P[29]
	q := Q[29]
	for i := 28; i >= 0; i -= 1 {
		p = tint_mul(p, z)
		q = tint_mul(q, z)
		p = tint_add(p, P[i])
		q = tint_add(q, Q[i])
	}
	p = tint_mul(p, z)
	z = tint_div(p, q)
	err: u64 = 662 // atan2.c:340-358: error bound in ulps when inv = 0 and x > 0
	z.sgn = sz
	// atan2.c:363-384: atan(y/x) = ±π/2 - atan(x/y).
	if inv {
		if z.sgn == 0 {
			z.sgn = 1
			z = tint_add(TINT_PI2, z)
		} else {
			z = tint_add(TINT_PI2, z)
			z.sgn = 1
		}
		err = 524
	}
	// atan2.c:385-408: x < 0, go to the opposite quadrant (±π).
	if x < 0 {
		if z.sgn == 0 {
			z.sgn = 1
			z = tint_add(TINT_PI, z)
			z.sgn = 1
		} else {
			z = tint_add(TINT_PI, z)
		}
		err = 266
	}
	return tint_tod(z, err)
}

// Tint is CORE-MATH's `tint_t` (tint.h:40-59): (-1)^sgn * (h/2^64 + m/2^128 + l/2^192) * 2^ex, with either
// h = m = l = 0 (zero) or the top bit of h set.
@(private = "file")
Tint :: struct {
	h, m, l: u64,
	ex:      i64,
	sgn:     u64,
}

// The C union's 128-bit `_h` view (tint.h:53-58, little-endian layout: m low, h high).
@(private = "file")
tint_hi :: #force_inline proc "contextless" (a: Tint) -> u128 {
	return u128(a.h) << 64 | u128(a.m)
}

@(private = "file")
tint_set_hi :: #force_inline proc "contextless" (a: ^Tint, v: u128) {
	a.h = u64(v >> 64)
	a.m = u64(v & 0xffffffffffffffff)
}

// tint.h:99-154: product with error < 10 ulps.
@(private = "file")
tint_mul :: proc "contextless" (a, b: Tint) -> (r: Tint) {
	r.ex = a.ex + b.ex
	r.sgn = a.sgn ~ b.sgn
	ah, am, al := u128(a.h), u128(a.m), u128(a.l)
	bh, bm, bl := u128(b.h), u128(b.m), u128(b.l)
	rh, rm1, rm2 := ah * bh, ah * bm, am * bh
	rl1, rl2, rl3 := ah * bl, am * bm, al * bh
	h, l, cm: u64
	r.h = u64(rh >> 64)
	r.m = u64(rh & 0xffffffffffffffff)
	// accumulate rm1
	r.l = u64(rm1 & 0xffffffffffffffff)
	h = u64(rm1 >> 64)
	r.m += h
	r.h += b2u(r.m < h)
	// accumulate rm2
	l = u64(rm2 & 0xffffffffffffffff)
	h = u64(rm2 >> 64)
	r.l += l
	cm = b2u(r.l < l)
	r.m += h
	r.h += b2u(r.m < h)
	// accumulate rl1 + rl2 + rl3
	rl1 = (rl1 >> 64) + (rl2 >> 64) + (rl3 >> 64)
	l = u64(rl1 & 0xffffffffffffffff)
	cm += u64(rl1 >> 64)
	r.l += l
	cm += b2u(r.l < l)
	// accumulate cm
	r.m += cm
	r.h += b2u(r.m < cm)
	if r.h >> 63 == 0 { 	// normalize
		r.h = (r.h << 1) | (r.m >> 63)
		r.m = (r.m << 1) | (r.l >> 63)
		r.l = r.l << 1
		r.ex -= 1
	}
	return
}

// tint.h:167-185: compares |a| and |b|.
@(private = "file")
tint_cmp_abs :: proc "contextless" (a, b: Tint) -> int {
	if a.h == 0 {
		return 0 if b.h == 0 else -1
	}
	if b.h == 0 {
		return 1
	}
	if a.ex != b.ex {
		return 1 if a.ex > b.ex else -1
	}
	ah, bh := tint_hi(a), tint_hi(b)
	if ah != bh {
		return 1 if ah > bh else -1
	}
	if a.l != b.l {
		return 1 if a.l > b.l else -1
	}
	return 0
}

// tint.h:187-219: significand (hi, lo) shifted right by k bits.
@(private = "file")
rshift :: proc "contextless" (h: u128, l: u64, k: u64) -> (u128, u64) {
	switch {
	case k == 0:
		return h, l
	case k < 64:
		return h >> k, u64((h << (64 - k)) & 0xffffffffffffffff) | (l >> k)
	case k == 64:
		return h >> k, u64(h & 0xffffffffffffffff)
	case k < 128:
		return h >> k, u64((h >> (k - 64)) & 0xffffffffffffffff)
	case k < 192:
		return 0, u64((h >> (k - 64)) & 0xffffffffffffffff)
	}
	return 0, 0
}

// tint.h:221-252: significand (hi, lo) shifted left by k bits.
@(private = "file")
lshift :: proc "contextless" (h: u128, l: u64, k: u64) -> (u128, u64) {
	switch {
	case k == 0:
		return h, l
	case k < 64:
		return (h << k) | u128(l >> (64 - k)), l << k
	case k == 64:
		return (h << k) | u128(l), 0
	case k < 128:
		return h << k | (u128(l) << (k - 64)), 0
	case k < 192:
		return u128(l) << (k - 64), 0
	}
	return 0, 0
}

// Leading zeros of the 192-bit significand (hi, lo) (tint.h:286-288).
@(private = "file")
clz192 :: #force_inline proc "contextless" (h: u128, l: u64) -> u64 {
	th := u64(h >> 64)
	if th != 0 {
		return u64(intrinsics.count_leading_zeros(th))
	}
	if h != 0 {
		return 64 + u64(intrinsics.count_leading_zeros(u64(h & 0xffffffffffffffff)))
	}
	return 128 + u64(intrinsics.count_leading_zeros(l))
}

// tint.h:254-341: sum with error < 2 ulps.
@(private = "file")
tint_add :: proc "contextless" (a0, b0: Tint) -> (r: Tint) {
	a, b := a0, b0
	switch tint_cmp_abs(a, b) {
	case 0:
		// |a| = |b|: 0 or 2a (exact)
		if a.sgn ~ b.sgn != 0 {
			return TINT_ZERO
		}
		r = a
		r.ex += 1
		return
	case -1:
		a, b = b, a
	}
	// From now on |a| > |b|, thus a.ex >= b.ex.
	sh := u64(a.ex - b.ex)
	th, tl := rshift(tint_hi(b), b.l, sh)
	if a.sgn ~ b.sgn != 0 { 	// opposite signs: subtraction
		tl = a.l - tl
		th = tint_hi(a) - th - u128(b2u(tl > a.l))
		ex := clz192(th, tl)
		if ex <= 1 || sh == 0 {
			rh, rl := lshift(th, tl, ex)
			tint_set_hi(&r, rh)
			r.l = rl
			r.ex = a.ex - i64(ex)
		} else { 	// ex >= 2 and sh >= 1: redo without neglecting the low part of b
			th, tl = lshift(tint_hi(b), b.l, ex - sh)
			rh, rl := lshift(tint_hi(a), a.l, ex)
			tl = rl - tl
			th = rh - th - u128(b2u(tl > rl))
			ex1 := clz192(th, tl)
			rh, rl = lshift(th, tl, ex1)
			tint_set_hi(&r, rh)
			r.l = rl
			r.ex = a.ex - i64(ex + ex1)
		}
	} else { 	// same signs: addition
		ah, al := tint_hi(a), a.l
		rl := al + tl
		cl := b2u(rl < al)
		rh := ah + th
		ch := b2u(rh < ah)
		rh += u128(cl)
		ch += b2u(rh < u128(cl))
		if ch != 0 { 	// at most 1
			r.ex = a.ex + 1
			rl = u64((rh << 63) & 0xffffffffffffffff) | (rl >> 1)
			rh = (u128(ch) << 127) | (rh >> 1)
		} else {
			r.ex = a.ex
		}
		tint_set_hi(&r, rh)
		r.l = rl
	}
	r.sgn = a.sgn
	return
}

// tint.h:343-363: exact conversion of a finite non-zero double.
@(private = "file")
tint_fromd :: proc "contextless" (x: f64) -> (a: Tint) {
	u := transmute(u64)x
	a.sgn = u >> 63
	ax := u & ABS_MASK
	e := i64(ax >> 52)
	if e != 0 { 	// normal; 1 has e = 0x3ff
		a.ex = e - 0x3fe
		a.h = (1 << 63) | (ax << 11)
	} else { 	// subnormal; 2^-1074 has ax = 1
		lz := u64(intrinsics.count_leading_zeros(ax))
		a.ex = -0x3f2 - i64(lz)
		a.h = ax << lz
	}
	return
}

// tint.h:365-381 (portable form): x * 2^i by adding i to the exponent field.
@(private = "file")
as_ldexp :: #force_inline proc "contextless" (x: f64, i: i64) -> f64 {
	return transmute(f64)(transmute(u64)x + u64(i) << 52)
}

// tint.h:383-448: a rounded to nearest. err = 0 converts a value known to be a double (inv_tint); otherwise err
// bounds the error on a.l in ulps.
@(private = "file")
tint_tod :: proc "contextless" (a: Tint, err: u64) -> f64 {
	if a.ex >= 1025 { 	// overflow: |a| >= 2^1024
		return(
			transmute(f64)u64(0xfff0000000000000) if a.sgn != 0 else transmute(f64)u64(0x7ff0000000000000) \
		)
	}
	if a.ex <= -1074 { 	// underflow: |a| < 2^-1074
		tiny := -MIN_SUBNORMAL if a.sgn != 0 else MIN_SUBNORMAL
		if a.ex < -1074 { 	// |a| < 2^-1075
			return tiny * 0.5
		}
		// 2^-1075 <= |a| < 2^-1074; mid: |a| = 2^-1075
		mid := a.h == 1 << 63 && a.m == 0 && a.l == 0
		return tiny * (0.5 if mid else 0.75)
	}
	hh, mm, ll := a.h, a.m, a.l
	ex := a.ex
	low := hh & 0x7ff // low 11 bits of a.h
	if ex <= -1022 { 	// subnormal: 1 <= sh <= 52
		sh := u64(-1021 - ex)
		ll = (mm << (64 - sh)) | (ll >> sh) | b2u(ll > 0)
		mm = (hh << (64 - sh)) | (mm >> sh)
		hh = hh >> sh
		low = hh & 0x7ff
		ex += i64(sh)
	}
	h := f64(hh >> 11) // significant bits of a.h
	l: f64
	if err == 0 { 	// a is a double: low = 0, exact
		l = 0
	} else if low < 0x400 {
		l = 0.25 // round to zero
	} else if low > 0x400 {
		l = 0.75 // round away
	} else {
		l = 0.5 if mm == 0 && ll == 0 else 0.75 // middle case, or round away
	}
	s := SIGN_ONE[a.sgn]
	h = fma(l, s, s * h)
	h *= 0h3cb0000000000000 // 0x1p-52
	// now -1021 <= ex <= 1024, thus 2^(ex-1) does not underflow/overflow
	return h * as_ldexp(1.0, ex - 1)
}

// tint.h:450-492: approximation of 1/A, A non-zero.
@(private = "file")
tint_inv :: proc "contextless" (A: Tint) -> Tint {
	a := tint_tod(A, 0) // exact
	subnormal := abs(a) < 0h0010000000000000 // 0x1p-1022
	if subnormal {
		a *= 0h4340000000000000 // 0x1p53
	}
	r := tint_fromd(1.0 / a) // accurate to about 53 bits
	if subnormal {
		r.ex += 53
	}
	// Newton: r1 = r0 + r0*(1 - a*r0).
	q := tint_mul(A, r)
	q.sgn = 1 - q.sgn
	q = tint_add(TINT_ONE, q)
	q = tint_mul(r, q)
	r = tint_add(r, q)
	return r
}

// tint.h:494-533: approximation of b/a, a non-zero, relative error < 2^-185.53.
@(private = "file")
tint_div :: proc "contextless" (b, a: Tint) -> Tint {
	Y := tint_inv(a)
	r := tint_mul(Y, b)
	// Karp-Markstein: r1 = r0 + y*(b - a*r0).
	Z := tint_mul(a, r)
	Z.sgn = 1 - Z.sgn
	Z = tint_add(b, Z)
	Z = tint_mul(Y, Z)
	r = tint_add(r, Z)
	return r
}

// tint.h:535-543: b/a for doubles.
@(private = "file")
tint_div_d :: proc "contextless" (b, a: f64) -> Tint {
	A := tint_fromd(a)
	B := tint_fromd(b)
	return tint_div(B, A)
}

@(private = "file")
MIN_SUBNORMAL :: 0h0000000000000001 // 0x1p-1074

// tint.h:61-76.
@(private = "file")
TINT_ZERO :: Tint {
	h   = 0,
	m   = 0,
	l   = 0,
	ex  = -1076,
	sgn = 0,
}
@(private = "file")
TINT_ONE :: Tint {
	h   = 0x8000000000000000,
	m   = 0,
	l   = 0,
	ex  = 1,
	sgn = 0,
}
// π with error < 2^-196.96, and π/2 with error < 2^-197.96.
@(private = "file")
TINT_PI :: Tint {
	h   = 0xc90fdaa22168c234,
	m   = 0xc4c6628b80dc1cd1,
	l   = 0x29024e088a67cc74,
	ex  = 2,
	sgn = 0,
}
@(private = "file")
TINT_PI2 :: Tint {
	h   = 0xc90fdaa22168c234,
	m   = 0xc4c6628b80dc1cd1,
	l   = 0x29024e088a67cc74,
	ex  = 1,
	sgn = 0,
}

@(private = "file")
@(rodata)
SIGN_ONE := [2]f64{1.0, -1.0} // tint.h:442

@(private = "file")
@(rodata)
ASGN := [2]f64{0.0, -0.0} // atan2.c:488

// atan2.c:447: {low, high} of π/4 and 3π/4.
@(private = "file")
@(rodata)
FINF := [2][2]f64 {
	{0h3c80000000000000, 0h3fe921fb54442d18}, // 0x1p-55, 0x1.921fb54442d18p-1
	{0h3c90000000000000, 0h4002d97c7f3321d2}, // 0x1p-54, 0x1.2d97c7f3321d2p+1
}

// atan2.c:566 and atan2.c:599-600: odd polynomials for atan(z) - z, fast and second paths.
@(private = "file")
@(rodata)
B := [3]f64{0hbfd55555555554d2, 0h3fc999999860e1ca, 0hbfc248ad469844a1}

@(private = "file")
@(rodata)
B2 := [4]f64{0hbfd5555555555555, 0h3fc999999999755e, 0hbfc24924883596f8, 0h3fbc6f7d73531bc2}

// atan2.c:489-497: T2[j] = j/64, the reduction points of the fast path.
@(private = "file")
@(rodata)
T2 := [65]f64 {
	0h0000000000000000,
	0h3f90000000000000,
	0h3fa0000000000000,
	0h3fa8000000000000,
	0h3fb0000000000000,
	0h3fb4000000000000,
	0h3fb8000000000000,
	0h3fbc000000000000,
	0h3fc0000000000000,
	0h3fc2000000000000,
	0h3fc4000000000000,
	0h3fc6000000000000,
	0h3fc8000000000000,
	0h3fca000000000000,
	0h3fcc000000000000,
	0h3fce000000000000,
	0h3fd0000000000000,
	0h3fd1000000000000,
	0h3fd2000000000000,
	0h3fd3000000000000,
	0h3fd4000000000000,
	0h3fd5000000000000,
	0h3fd6000000000000,
	0h3fd7000000000000,
	0h3fd8000000000000,
	0h3fd9000000000000,
	0h3fda000000000000,
	0h3fdb000000000000,
	0h3fdc000000000000,
	0h3fdd000000000000,
	0h3fde000000000000,
	0h3fdf000000000000,
	0h3fe0000000000000,
	0h3fe0800000000000,
	0h3fe1000000000000,
	0h3fe1800000000000,
	0h3fe2000000000000,
	0h3fe2800000000000,
	0h3fe3000000000000,
	0h3fe3800000000000,
	0h3fe4000000000000,
	0h3fe4800000000000,
	0h3fe5000000000000,
	0h3fe5800000000000,
	0h3fe6000000000000,
	0h3fe6800000000000,
	0h3fe7000000000000,
	0h3fe7800000000000,
	0h3fe8000000000000,
	0h3fe8800000000000,
	0h3fe9000000000000,
	0h3fe9800000000000,
	0h3fea000000000000,
	0h3fea800000000000,
	0h3feb000000000000,
	0h3feb800000000000,
	0h3fec000000000000,
	0h3fec800000000000,
	0h3fed000000000000,
	0h3fed800000000000,
	0h3fee000000000000,
	0h3fee800000000000,
	0h3fef000000000000,
	0h3fef800000000000,
	0h3ff0000000000000,
}

// atan2.c:498-531: {low, high} of atan(T2[j]).
@(private = "file")
@(rodata)
F2 := [65][2]f64 {
	{0h0000000000000000, 0h0000000000000000},
	{0hbca95220c39d4dff, 0h3f8fff555bbb7300},
	{0h3ca2542779d776de, 0h3f9ffd55bba97600},
	{0hbca6061bbe3de53c, 0h3fa7fb818430da40},
	{0hbca639269b0da47e, 0h3faff55bb72cfe00},
	{0hbc84a7663af440f7, 0h3fb3f59f0e7c55a0},
	{0h3cad1824d59f9e13, 0h3fb7ee182602f100},
	{0h3c8bef71e5340b31, 0h3fbbe39ebe6f07c0},
	{0h3cab8cb225e627d0, 0h3fbfd5ba9aac2f60},
	{0h3cab92de9bac94c2, 0h3fc1e1fafb043720},
	{0hbc9d3cb89e62dafd, 0h3fc3d6eee8c66270},
	{0hbca882a55960087a, 0h3fc5c9811e3ec270},
	{0h3c91347b0b4f881d, 0h3fc7b97b4bce5b00},
	{0h3ca873d8079ed0d2, 0h3fc9a6a8e96c8620},
	{0h3c9022f621a5c1cb, 0h3fcb90d7529260a0},
	{0h3ca9c648d1534598, 0h3fcd77d5df205730},
	{0hbc94ea9238610a08, 0h3fcf5b75f92c80e0},
	{0h3ca2c5c8e721970d, 0h3fd09dc597d86360},
	{0h3c630ca4748b1bf9, 0h3fd18bf5a30bf178},
	{0hbca20ef9ba6dbf90, 0h3fd278372057ef48},
	{0h3cae69c5abb498d2, 0h3fd362773707ebc8},
	{0h3c9a8a86f0ea9311, 0h3fd44aa436c2af08},
	{0h3c9db5336feef7f0, 0h3fd530ad9951cd48},
	{0h3c99636a3aa3b840, 0h3fd614840309cfe0},
	{0h3c81ce2a8c848b74, 0h3fd6f61941e4def0},
	{0hbc84b1bbd1ea6db3, 0h3fd7d5604b63b3f8},
	{0hbca4925e8b916e0b, 0h3fd8b24d394a1b28},
	{0h3c79e6c988fd0a77, 0h3fd98cd5454d6b18},
	{0hbcaa49bd836a1700, 0h3fda64eec3cc2400},
	{0hbcaca3cf09c6b5f8, 0h3fdb3a911da65c70},
	{0hbc7cc1ce70934c34, 0h3fdc0db4c94ec9f0},
	{0h3c82e982ddf3872a, 0h3fdcde53432c1350},
	{0hbc82ea406ee84d0f, 0h3fddac670561bb50},
	{0hbcade35847c81979, 0h3fde77eb7f175a38},
	{0hbc6a3992dc382a23, 0h3fdf40dd0b541418},
	{0hbc8b32c949c9d593, 0h3fe0039c73c1a40c},
	{0hbc7d5b495f6349e6, 0h3fe0657e94db30d0},
	{0hbcaf34582f6255fe, 0h3fe0c6145b5b43dc},
	{0h3c9ed42511e3f11d, 0h3fe1255d9bfbd2a8},
	{0hbc91cef189ff9e7f, 0h3fe1835a88be7c14},
	{0hbc5928df287a668f, 0h3fe1e00babdefeb4},
	{0hbcae3bde360c7ddb, 0h3fe23b71e2cc9e6c},
	{0h3c9bd86313ce4fde, 0h3fe2958e59308e30},
	{0hbca8e8a85803cc1d, 0h3fe2ee628406cbcc},
	{0hbc977ef7641c777f, 0h3fe345f01cce37bc},
	{0h3cab73ef3389d02f, 0h3fe39c391cd41718},
	{0h3c7ecf8b492644f0, 0h3fe3f13fb89e96f4},
	{0h3cac1125fd3810c7, 0h3fe445065b795b54},
	{0h3ca2483350fe548b, 0h3fe4978fa3269ee0},
	{0h3c84a33dbeb3796c, 0h3fe4e8de5bb6ec04},
	{0hbca46edd2af69483, 0h3fe538f57b890620},
	{0hbca2bcb93b18b52a, 0h3fe587d81f732fbc},
	{0h3c60028e4bc5e7ca, 0h3fe5d58987169b18},
	{0h3caed487acaf1174, 0h3fe6220d115d7b8c},
	{0hbca2dd4dfd7d1777, 0h3fe66d663923e088},
	{0h3c92bfe3cf3b9d79, 0h3fe6b798920b3d98},
	{0hbc78c34d25aadef6, 0h3fe700a7c5784634},
	{0hbc9f426acf4d3bdb, 0h3fe748978fba8e10},
	{0hbcaafe57dd9ff230, 0h3fe78f6bbd5d3160},
	{0hbc954fbef0e862ab, 0h3fe7d528289fa094},
	{0h3c990227758b11ba, 0h3fe819d0b7158a4c},
	{0h3ca16b66e7fc8b8c, 0h3fe85d69576cc2c4},
	{0hbc855b9a5e177a1b, 0h3fe89ff5ff57f1f8},
	{0h3cac27cfaa9f7a14, 0h3fe8e17aa99cc05c},
	{0h3c81a62633145c07, 0h3fe921fb54442d18},
}

// atan2.c:532-536: {high, low} offsets 0, ±π/2, ±π by octant (kw = sx<<2 | sy<<1 | gt).
@(private = "file")
@(rodata)
O := [8][2]f64 {
	{0h0000000000000000, 0h0000000000000000},
	{0h3ff921fb54442d18, 0h3c91a62633145c07},
	{0h0000000000000000, 0h0000000000000000},
	{0hbff921fb54442d18, 0hbc91a62633145c07},
	{0h400921fb54442d18, 0h3ca1a62633145c07},
	{0h3ff921fb54442d18, 0h3c91a62633145c07},
	{0hc00921fb54442d18, 0hbca1a62633145c07},
	{0hbff921fb54442d18, 0hbc91a62633145c07},
}

// atan2.c:67-170: numerator P of the [29,29] rational approximation z*P(z)/Q(z) of atan(z) on [0, 1].
@(private = "file")
@(rodata)
P := [30]Tint {
	{h = 0x82703f8b53112eca, m = 0x71ce6279d467aa45, l = 0x19c9b28466b6fc0, ex = -10, sgn = 0},
	{h = 0xb3cf74b427d53e03, m = 0xee590b839e751890, l = 0xf2570b12bcb2381a, ex = -8, sgn = 0},
	{h = 0xb08498b17b88c39a, m = 0x11e37821d784d8fa, l = 0x2795b14b84b9d78c, ex = -6, sgn = 0},
	{h = 0xfd4baa7bb52b0d83, m = 0xb25425beb0a04dc3, l = 0x92008d9fb34b68ff, ex = -5, sgn = 0},
	{h = 0x96541948b85fb386, m = 0xe0b815ace425a859, l = 0xbeca17c69bb4f7a0, ex = -3, sgn = 0},
	{h = 0x96aaa5d4baffc590, m = 0xf23db783b6e4ce55, l = 0x2c54e054d3b69f7e, ex = -2, sgn = 0},
	{h = 0x83cd41b5fa862b11, m = 0xad8f9d6e3eb9d833, l = 0x4ef470d801fa03ca, ex = -1, sgn = 0},
	{h = 0xcbbc7752197cc106, m = 0xbc66cfb3edefa6e3, l = 0x568b2f9e4feb8910, ex = -1, sgn = 0},
	{h = 0x8cf8f7c585767042, m = 0xcd92a5b9ac13d8c8, l = 0x43bd4a023dbe04d, ex = 0, sgn = 0},
	{h = 0xafdc36d6b36139bf, m = 0x11df63474e3859d4, l = 0x42b30b2c089a2b6c, ex = 0, sgn = 0},
	{h = 0xc6f8fb1463822519, m = 0x2f9f04cf55c10377, l = 0x1c44675c6d483606, ex = 0, sgn = 0},
	{h = 0xcce79f10f754e315, m = 0x91ce47edcbc8a4ee, l = 0xb2a6f721ac656b42, ex = 0, sgn = 0},
	{h = 0xc090384dbd77132e, m = 0x1dfb4d9a1d595de7, l = 0xe506ca899a394f70, ex = 0, sgn = 0},
	{h = 0xa556ac9eee25e867, m = 0xd84dafa25141d203, l = 0xf1c7c2a5156b3ec3, ex = 0, sgn = 0},
	{h = 0x81bd2677ddfcbc38, m = 0x1df33f27dbb60939, l = 0xcb4c2c73286a6c29, ex = 0, sgn = 0},
	{h = 0xb9ed12169d72e8d9, m = 0xc81d95dcef13c227, l = 0x974b95796b93c332, ex = -1, sgn = 0},
	{h = 0xf2df6da875b666fa, m = 0xc29dd3a69c274c65, l = 0x83b9260976c8f0c5, ex = -2, sgn = 0},
	{h = 0x902d34d4db910ed8, m = 0x6f3ecddfd6af0a9f, l = 0x8e950d7e70a8e9b2, ex = -2, sgn = 0},
	{h = 0x9aefa41961ce1207, m = 0xacd0317666753751, l = 0x3eaf42a53fcc6534, ex = -3, sgn = 0},
	{h = 0x95db9977c5e6e263, m = 0x85367a63fab8a720, l = 0xfc2b63bd115998d8, ex = -4, sgn = 0},
	{h = 0x817cb6d8236d5f4d, m = 0x70c7815f28909d9b, l = 0xc54e97155d12158, ex = -5, sgn = 0},
	{h = 0xc5eec4228c352098, m = 0x789e56be1dee9b67, l = 0xba25bda81292ccc1, ex = -7, sgn = 0},
	{h = 0x840c38ccfcb5dc64, m = 0xb55a44095bf7f312, l = 0x6668b8792d4ecd08, ex = -8, sgn = 0},
	{h = 0x97074af7b286b19e, m = 0xc20aac21f3130f1d, l = 0x369e9fdbdd48528a, ex = -10, sgn = 0},
	{h = 0x9054011c32d4b7a5, m = 0xc68d3c5d525f4af4, l = 0xeeb3c98615dee188, ex = -12, sgn = 0},
	{h = 0xdddb4a2eaab2bb15, m = 0x753761a8f0e9aa8d, l = 0x3f20620cd3e075bb, ex = -15, sgn = 0},
	{h = 0x80ef9a1b3e59abe5, m = 0x18e6afe0651fdf49, l = 0xd1c0329e6a702d9d, ex = -17, sgn = 0},
	{h = 0xca16dd49cd30854c, m = 0xbad8ca379401027c, l = 0x1fc7f47985486f16, ex = -21, sgn = 0},
	{h = 0xa0ba01b8742ba801, m = 0xe6dc14a9516d7f04, l = 0x1f5303d878905d2f, ex = -25, sgn = 0},
	{h = 0x9c0440896ce6515c, m = 0xcf3470fa7f10ac3, l = 0xa9dc80682c111a9d, ex = -59, sgn = 1},
}

// atan2.c:172-203: denominator Q.
@(private = "file")
@(rodata)
Q := [30]Tint {
	{h = 0x82703f8b53112eca, m = 0x71ce6279d467aa45, l = 0x19c9b28466b6fc0, ex = -10, sgn = 0},
	{h = 0xb3cf74b427d53e03, m = 0xee590b839e751890, l = 0xf2570b12bcb238cf, ex = -8, sgn = 0},
	{h = 0xb33c44af0d43c9e8, m = 0xf4426f84614701db, l = 0x979e49dc5b858442, ex = -6, sgn = 0},
	{h = 0x8264d256f0bf4d61, m = 0xee21431cc0f29764, l = 0xce0cc1b593ac9952, ex = -4, sgn = 0},
	{h = 0x9d97c4947687b2ee, m = 0xef4087c49dde5229, l = 0x742bc6e02bfb6df8, ex = -3, sgn = 0},
	{h = 0xa0f888dc7aab949e, m = 0xf623f19ac413db23, l = 0x854744a164f70ecd, ex = -2, sgn = 0},
	{h = 0x8fd9c7172ab0828e, m = 0x1a9f72fadafc3dfb, l = 0xaf96a180ea297178, ex = -1, sgn = 0},
	{h = 0xe38168b78a51ee15, m = 0x604a47815c8091eb, l = 0x9faaa42312e8eb30, ex = -1, sgn = 0},
	{h = 0xa164ccdbb65ee133, m = 0xe623433c5e086402, l = 0xcb228afd335a245f, ex = 0, sgn = 0},
	{h = 0xced0c0cbe44fac2f, m = 0xd7c2adfc7c5dda9e, l = 0xa22b4a311cf5a5b1, ex = 0, sgn = 0},
	{h = 0xf0e6660438c90371, m = 0x3dca1a0f58f0d943, l = 0x8a92b9de68c4488c, ex = 0, sgn = 0},
	{h = 0x8000000000000000, m = 0x0, l = 0x0, ex = 1, sgn = 0},
	{h = 0xf8ea68f9ad849103, m = 0xb257e4bfc606967f, l = 0x818fa2816928c4aa, ex = 0, sgn = 0},
	{h = 0xddc64eeee3506234, m = 0x47a33ea40a2b22e4, l = 0xa6a2c129ace2470a, ex = 0, sgn = 0},
	{h = 0xb52ddfba2d37c8e2, m = 0x24551a9b19fa064a, l = 0x3d78c68b54bc3850, ex = 0, sgn = 0},
	{h = 0x87ac113d26b683a1, m = 0x4e97756c38785b0b, l = 0xf75f0a4506931ba8, ex = 0, sgn = 0},
	{h = 0xba065070b900f3d5, m = 0xe49d8f9f238f1eeb, l = 0x6805d48d67f1dcd9, ex = -1, sgn = 0},
	{h = 0xe902d2a4bfc22441, m = 0x945cfe6c83a5b828, l = 0x519ebb457f8ccca0, ex = -2, sgn = 0},
	{h = 0x84e405c915f7769b, m = 0xfaaf34c3c51dd39, l = 0xa97fa0ae99382c93, ex = -2, sgn = 0},
	{h = 0x896da46c7e6cebb3, m = 0xe0afc0b6db3dbbf5, l = 0x61ccff6e78efff4, ex = -3, sgn = 0},
	{h = 0x801a0c1a0dfefc92, m = 0xf8e0a97902e08d47, l = 0x81898e0b7d8ef0bc, ex = -4, sgn = 0},
	{h = 0xd59d088930df07db, m = 0xa8cb00021849fbaf, l = 0xf80cc91aa0bddf89, ex = -6, sgn = 0},
	{h = 0x9db56a6984b77231, m = 0xcf7c2074e0480959, l = 0x3316ecaa6aa4604e, ex = -7, sgn = 0},
	{h = 0xcb7450d9d62d2e68, m = 0x9787b4265977d004, l = 0xba615cee00a841d7, ex = -9, sgn = 0},
	{h = 0xe12a52e02b64b23e, m = 0x97c9139a8ced716c, l = 0x70a176ad2b5f16d2, ex = -11, sgn = 0},
	{h = 0xd057b6d0900ed30d, m = 0x5e04bb17eb879a5e, l = 0x23ed135b60bea070, ex = -13, sgn = 0},
	{h = 0x9b1f1ca22fef7ae5, m = 0x19a687f0a4073eee, l = 0x5a9ccbc8c14578b, ex = -15, sgn = 0},
	{h = 0xaeba710f053aac3b, m = 0x30ea5d6fb116f775, l = 0x8a9bcfef5698f8f1, ex = -18, sgn = 0},
	{h = 0x84b9ada076cd007d, m = 0x13e55006073f76b1, l = 0x4cf4259968228f3e, ex = -21, sgn = 0},
	{h = 0xcca4b9046786937d, m = 0x233c1e691c127c1f, l = 0xf493e0b7a3de459a, ex = -26, sgn = 0},
}
