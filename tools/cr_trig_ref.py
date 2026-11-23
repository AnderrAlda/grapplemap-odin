#!/usr/bin/env python3
"""Correctly rounded sin/cos reference values for src/core/cr_sin_cos_test.odin (#162).

Writes tests/fixtures/cr_sin_cos.txt: one line per input, `x sin(x) cos(x)` as f64 bit patterns in hex,
then `# category`. Python standard library only: the values are computed with `decimal` at PREC digits
(argument reduction with a PREC-digit pi, then Taylor series) and rounded once to f64 by `float(Decimal)`,
which is correctly rounded. PREC leaves > 1,000 bits after the round bit, far more than the hardest
binary64 cases need (< 120 identical bits after the round bit).

Usage: python3 tools/cr_trig_ref.py <core-math checkout> > tests/fixtures/cr_sin_cos.txt
The checkout gives the hard-to-round inputs (src/binary64/sin/sin.wc, src/binary64/cos/cos.wc); use the commit
cited in src/core/cr_sin_cos.odin.
"""

import math
import random
import struct
import sys
from decimal import Decimal as D
from decimal import getcontext

PREC = 750  # digits; |x| < 2^1024 ~ 1.8e308 needs ~309 integer digits before the fraction starts
getcontext().prec = PREC
SEED = 162


def compute_pi():
    # The pi() recipe from the Python `decimal` documentation.
    getcontext().prec += 10
    three = D(3)
    lasts, t, s, n, na, d, da = 0, three, 3, 1, 0, 0, 24
    while s != lasts:
        lasts = s
        n, na = n + na, na + 8
        d, da = d + da, da + 32
        t = (t * n) / d
        s += t
    getcontext().prec -= 10
    return +s


PI = compute_pi()
HALF_PI = PI / 2


def bits(x):
    return struct.unpack("<Q", struct.pack("<d", x))[0]


def from_bits(u):
    return struct.unpack("<d", struct.pack("<Q", u))[0]


def taylor_sin_cos(r):
    s = c = D(0)
    term = D(1)
    eps = D(10) ** -(PREC - 5)
    n = 0
    while True:
        q = n % 4
        if q == 0:
            c += term
        elif q == 1:
            s += term
        elif q == 2:
            c -= term
        else:
            s -= term
        n += 1
        term = term * r / n
        if n > 4 and abs(term) < eps:
            return s, c


def sin_cos(x):
    """Correctly rounded (sin(x), cos(x)) for finite x."""
    if x == 0:
        return x, 1.0  # sin(±0) = ±0
    dx = D(x)  # exact
    k = int((dx / HALF_PI).to_integral_value())
    r = dx - k * HALF_PI  # |r| <= pi/4 (+ rounding)
    s, c = taylor_sin_cos(r)
    s, c = [(s, c), (c, -s), (-s, -c), (-c, s)][k % 4]
    return float(s), float(c)


HARD_29 = [  # #140: the 29 DB positions where glibc 2.39's sin (s) or cos (c) is not correctly rounded
    0xC00753B6D36465B2, 0x3FD4CB3ED61921EE, 0xBFD7BCAED0F49649, 0xBFCA6C41C2EDC308, 0xBFCA6C41C2EDC308,
    0xBFCA6C41C2EDC308, 0xBFCA6C41C2EDC308, 0xC003786C9F737033, 0xBFF195B743F9EEC7, 0xC0056B031EA14569,
    0xBFF58EED22D696D2, 0xBFF5A5C8B171A0B5, 0xBFDBE40019C02287, 0x3FF0E8D0F8D2F5A1, 0x40080CCAE24D1134,
    0x4001C5798798F53F, 0x4001C5798798F53F, 0x4001C5798798F53F, 0x3FC96D2AA2E0E044, 0x3FEF2FE66FCF8585,
    0x3FF76FB6327F651F, 0xBFF00FC68A6F5B41, 0x3FE9DD8D5158576D, 0x3FF110B0663C6A5B, 0xC0019BE12E24C758,
    0xC0009AB806C49220, 0xBFF3469D4083569E, 0xBFE35B9A2ED3F102, 0xBFFD4A1CA13BB76A,
]

COS_EXCEPTIONS = ["0x1.8000000000009p-23", "0x1.8000000000024p-22", "0x1.800000000009p-21", "0x1.20000000000f3p-20"]


def wc_inputs(path):
    out = []
    for line in open(path):
        line = line.split("#")[0].strip()
        if "0x" not in line:  # +0, -0, ±1, ±inf, qnan/snan: the special values have their own tests
            continue
        x = float.fromhex(line.split()[0])
        if math.isfinite(x) and x != 0:
            out.append(x)
    return out


def inputs(core_math):
    rng = random.Random(SEED)
    cases = []

    def add(cat, xs):
        for x in xs:
            cases.append((x, cat))

    # Small |x|: subnormals, the tiny-|x| fast paths (2^-26 for sin, 2^-27 for cos) and the 2^-16 switch.
    add("tiny", [from_bits(1), from_bits(0x000FFFFFFFFFFFFF), 2.0**-1022, 2.0**-1000, 2.0**-60])
    for e in (-27, -26, -16, 31):
        b = 2.0**e
        add("boundary", [math.nextafter(b, 0), b, math.nextafter(b, math.inf)])
    # Multiples of pi/2 (rounded to f64) and their neighbours.
    for k in list(range(1, 33)) + [10**3, 10**6, 2**20, 2**30, 2**40]:
        m = float(k * HALF_PI)
        add("pi/2-multiple", [math.nextafter(m, 0), m, math.nextafter(m, math.inf)])
    # Large |x| around the binades the plan names, and the maximum finite value.
    for e in (20, 100, 1023):
        b = 2.0**e
        add("large", [math.nextafter(b, 0), b, math.nextafter(b, math.inf), b * (1 + rng.random())])
    add("large", [sys.float_info.max, math.nextafter(sys.float_info.max, 0)])
    # The DB angles where glibc 2.39 fails, and cos's special-cased hard inputs.
    add("glibc-2.39", [from_bits(u) for u in HARD_29])
    add("cos-exception", [float.fromhex(h) for h in COS_EXCEPTIONS])
    # CORE-MATH's hard-to-round inputs (fixed sample of each list).
    for name in ("sin", "cos"):
        xs = wc_inputs(f"{core_math}/src/binary64/{name}/{name}.wc")
        small = [x for x in xs if abs(x) < 2.0**31]
        big = [x for x in xs if abs(x) >= 2.0**31]
        add(f"{name}.wc", rng.sample(small, 150) + rng.sample(big, 50))
    # Random inputs: >= 1,000 in [-4pi, 4pi] and >= 200 large (random exponent >= 31, random sign).
    four_pi = float(4 * PI)
    add("random", [rng.uniform(-four_pi, four_pi) for _ in range(1000)])
    big = []
    for _ in range(200):
        e = rng.randint(31, 1023)
        x = from_bits(((e + 1023) << 52) | rng.getrandbits(52))
        big.append(-x if rng.random() < 0.5 else x)
    add("random-large", big)
    # Negated copies of the non-random categories (sin is odd, cos even: checks the sign handling).
    cases += [(-x, cat + "-neg") for x, cat in cases if not cat.startswith("random") and x != 0]
    return cases


def main():
    if len(sys.argv) != 2:
        sys.exit(__doc__)
    print(f"# Generated by tools/cr_trig_ref.py (seed {SEED}, {PREC} digits). x sin(x) cos(x) as f64 bits.")
    for x, cat in inputs(sys.argv[1]):
        s, c = sin_cos(x)
        print(f"{bits(x):016x} {bits(s):016x} {bits(c):016x} # {cat}")


if __name__ == "__main__":
    main()
