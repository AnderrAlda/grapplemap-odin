#!/usr/bin/env python3
"""Correctly rounded binary64 atan2 reference for src/core/cr_atan2_test.odin (#161).

Python standard library only. The inputs are exact (Decimal(float) is exact). atan2 is evaluated with
`decimal` at PREC significant digits, then rounded to binary64 once by float(str(d)), which CPython rounds
correctly. The precision doubles (PREC, 2 PREC, ...) until two consecutive precisions round to the same binary64
(tiny |y/x| near the subnormal range needs ~600 digits); the script stops if MAX_PREC is reached first.

Usage:
  tools/cr_atan2_ref.py --fixture ATAN2_WC > tests/fixtures/cr_atan2.txt
      # the whole fixture: sections "edge" (EDGE below), "worst" (a selection of CORE-MATH's
      # src/binary64/atan2/atan2.wc, see worst_pairs) and "random" (--random 1000 161)
  tools/cr_atan2_ref.py < pairs.txt         # lines "y,x" as C99 hex floats (CORE-MATH's atan2.wc format)
  tools/cr_atan2_ref.py --random N SEED     # N random finite pairs (fixed seed, mixed scales and signs)
Output: one line per pair, "y_bits x_bits atan2_bits" as 16-digit hex (the test fixture format).
Only for finite, non-zero y and x: the special values are written by hand in the test (C99 Annex F).
"""

import decimal
import math
import random
import struct
import sys
from decimal import Decimal

PREC = 200
WORST_STEP = 128  # every WORST_STEP-th finite pair of atan2.wc, plus every pair from its "GNU libc" section on
RANDOM_N, RANDOM_SEED = 1000, 161

# Subnormal inputs, y/x overflow and underflow, the tiny-y/x shortcuts of atan2_accurate, the 2^-920 and 2^1022
# rescaling of the fast path, |x/y| >= 2^53 and the octant boundaries.
EDGE = """
0x1p-1074,0x1p-1074
0x1p-1074,0x1p+0
0x1p-1074,-0x1p+0
-0x1p-1074,-0x1p+0
0x1p-1074,0x1p+1023
-0x1p-1074,0x1.fffffffffffffp+1023
0x1p-1074,-0x1.fffffffffffffp+1023
0x1.fffffffffffffp+1023,0x1p-1074
0x1.fffffffffffffp+1023,-0x1p-1074
-0x1.fffffffffffffp+1023,0x1p-1074
0x1.fffffffffffffp+1023,0x1.fffffffffffffp+1023
-0x1.fffffffffffffp+1023,-0x1.fffffffffffffp+1023
0x1.8p+1023,0x1.1p+1023
-0x1.1p+1023,0x1.8p+1023
0x0.fffffffffffffp-1022,0x1p-1022
0x1.8p-1070,0x1.4p-1072
0x0.123456789abcdp-1022,-0x0.0000000abcdefp-1022
0x1p-1000,0x1p+60
0x1.23456789abcdep-1030,0x1.fp+20
-0x1.23456789abcdep-1030,0x1.fp+20
0x1.23456789abcdep-1030,-0x1.fp+20
0x1.8000000000003p-51,0x1.0000000000003p+0
-0x1.8000000000003p-51,0x1.0000000000003p+0
0x1.8000000000003p-51,-0x1.0000000000003p+0
-0x1.8000000000003p-51,-0x1.0000000000003p+0
0x1p-30,0x1p+0
0x1.d12ed0af1a27fp-27,0x1p+0
0x1.d12ed0af1a280p-27,0x1p+0
0x1.5p-28,0x1.3p+0
0x1.8p+1,0x1.8p+1
-0x1p+0,0x1p+0
0x1p+0,-0x1p+0
0x1.0000000000001p+0,0x1p+0
0x1p+0,0x1.0000000000001p+0
0x1p-500,0x1p+500
0x1.5p-500,0x1.3p+500
-0x1.5p-500,-0x1.3p+500
0x1.1p-925,0x1.7p-923
0x1p+0,0x1p+53
0x1p+0,0x1.0000000000001p+53
0x1p+60,0x1p+0
-0x1p+60,-0x1.fp+0
0x1.fffffffffffffp-1,0x1p+0
"""
MAX_PREC = 6400


def bits(f):
    return struct.unpack("<Q", struct.pack("<d", f))[0]


def from_bits(u):
    return struct.unpack("<d", struct.pack("<Q", u))[0]


def atan_unit(t):
    """atan(t) for 0 <= t <= 1 at the current context precision."""
    if t == 0:
        return Decimal(0)
    # Halve the argument k times: atan(t) = 2 atan(t / (1 + sqrt(1 + t^2))).
    k = 0
    while t > Decimal("1e-3"):
        t = t / (1 + (1 + t * t).sqrt())
        k += 1
    # Taylor series t - t^3/3 + t^5/5 - ...
    t2 = t * t
    term = t
    s = Decimal(0)
    n = 1
    prec = decimal.getcontext().prec
    eps = Decimal(10) ** (-(prec + 5))
    # 0 < t <= 1e-3, so each term is at least 10^6 times smaller than the previous one: prec/6 + 2 terms
    # suffice. The bound makes a mistake fail loudly instead of looping.
    for _ in range(prec // 6 + 10):
        d = term / n
        if abs(d) < eps * abs(s if s else t):
            break
        s += d
        term = -term * t2
        n += 2
    else:
        raise RuntimeError("atan series did not converge")
    return s * (1 << k)


def atan2_dec(y, x):
    """Exact-input atan2(y, x) for finite non-zero y, x, at the current context precision."""
    pi = 4 * atan_unit(Decimal(1))
    ay, ax = abs(y), abs(x)
    a = atan_unit(ay / ax) if ay <= ax else pi / 2 - atan_unit(ax / ay)
    if x < 0:
        a = pi - a
    return a if y > 0 else -a


def cr_atan2(yf, xf):
    if not finite_nonzero(yf, xf):
        sys.exit(f"only finite non-zero inputs (special values are written by hand): y={yf!r} x={xf!r}")
    prev = None
    prec = PREC
    while prec <= MAX_PREC:
        with decimal.localcontext() as ctx:
            ctx.prec = prec
            ctx.Emin = -999999
            ctx.Emax = 999999
            r = bits(float(str(atan2_dec(Decimal(yf), Decimal(xf)))))
        if r == prev:
            return from_bits(r)
        prev = r
        prec *= 2
    sys.exit(f"no agreement up to {MAX_PREC} digits for y={yf.hex()} x={xf.hex()}")


def parse_hex(s):
    s = s.strip()
    neg = s.startswith("-")
    s = s.lstrip("+-")
    v = float.fromhex(s)
    return -v if neg else v


def random_pairs(n, seed):
    rng = random.Random(seed)
    pairs = []
    while len(pairs) < n:
        kind = rng.randrange(4)
        if kind == 0:  # the DB's range: body coordinates, |d| < 4 m
            y, x = rng.uniform(-4, 4), rng.uniform(-4, 4)
        elif kind == 1:  # near the octant boundaries |y| ~ |x|
            x = rng.uniform(-2, 2)
            y = x * (1 + rng.uniform(-1e-6, 1e-6)) * rng.choice((1, -1))
        else:  # random bit patterns with a bounded exponent spread (kind 2), or any (kind 3)
            spread = 60 if kind == 2 else 2000
            e = rng.randint(-spread // 2, spread // 2)
            ex = max(-1074, min(1023, e + rng.randint(-spread // 2, spread // 2)))
            y = math.ldexp(rng.uniform(1, 2), max(-1074, min(1023, e))) * rng.choice((1, -1))
            x = math.ldexp(rng.uniform(1, 2), ex) * rng.choice((1, -1))
        if finite_nonzero(y, x):
            pairs.append((y, x))
    return pairs


def parse_pairs(lines):
    pairs = []
    for line in lines:
        line = line.split("#")[0].strip()
        if line:
            ys, xs = line.split(",")
            pairs.append((parse_hex(ys), parse_hex(xs)))
    return pairs


def finite_nonzero(y, x):
    return y != 0 and x != 0 and math.isfinite(y) and math.isfinite(x)


def worst_pairs(path):
    pairs, tail = [], []
    in_tail = False
    for line in open(path):
        if line.startswith("# test inputs from the GNU libc"):
            in_tail = True
        if line.startswith("#") or "nan" in line or "inf" in line:
            continue
        for y, x in parse_pairs([line]):
            if finite_nonzero(y, x):
                (tail if in_tail else pairs).append((y, x))
    return pairs[::WORST_STEP] + tail


def emit(pairs):
    for y, x in pairs:
        print(f"{bits(y):016x} {bits(x):016x} {bits(cr_atan2(y, x)):016x}", flush=True)


def fixture(wc_path):
    print("# Correctly rounded atan2 cases for src/core/cr_atan2_test.odin (#161): \"y x atan2\" as binary64 bits.")
    print("# Generated by: tools/cr_atan2_ref.py --fixture <core-math>/src/binary64/atan2/atan2.wc")
    print("# CORE-MATH commit 333d11d04d73ef165cf217e773b3b3d6372aa66f (worst cases: atan2.wc, MIT).")
    print("# section edge")
    emit(parse_pairs(EDGE.splitlines()))
    print("# section worst")
    emit(worst_pairs(wc_path))
    print("# section random")
    emit(random_pairs(RANDOM_N, RANDOM_SEED))


def main():
    if len(sys.argv) == 3 and sys.argv[1] == "--fixture":
        fixture(sys.argv[2])
        return
    if len(sys.argv) == 4 and sys.argv[1] == "--random":
        pairs = random_pairs(int(sys.argv[2]), int(sys.argv[3]))
    else:
        # Zeros, infinities and NaN are skipped (with a note on stderr): the test writes them by hand.
        pairs = []
        for y, x in parse_pairs(sys.stdin):
            if finite_nonzero(y, x):
                pairs.append((y, x))
            else:
                print(f"skipped non-finite or zero input: {y!r}, {x!r}", file=sys.stderr)
    emit(pairs)


if __name__ == "__main__":
    main()
