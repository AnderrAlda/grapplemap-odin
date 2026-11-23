package core

import "core:strconv"
import "core:strings"
import "core:testing"

// Expected values come from tests/fixtures/cr_sin_cos.txt, generated outside Odin by tools/cr_trig_ref.py
// (Python `decimal` at 750 digits, rounded once to f64): `python3 tools/cr_trig_ref.py <core-math checkout> >
// tests/fixtures/cr_sin_cos.txt`. Comparisons are bit for bit (ADR 0003).

@(private = "file")
FIXTURE := #load("../../tests/fixtures/cr_sin_cos.txt", string)

@(private = "file")
bits :: proc(x: f64) -> u64 {
	return transmute(u64)x
}

@(private = "file")
from_bits :: proc(u: u64) -> f64 {
	return transmute(f64)u
}

@(private = "file")
Fixture_Counts :: struct {
	cases, sin_bad, cos_bad: int,
	random, random_large:    int,
	sin_wc, cos_wc, glibc:   int,
}

// check_fixture runs cr_sin/cr_cos over every fixture line and logs the first mismatches.
@(private = "file")
check_fixture :: proc(t: ^testing.T) -> (c: Fixture_Counts) {
	text := FIXTURE
	for line in strings.split_lines_iterator(&text) {
		if len(line) == 0 || line[0] == '#' {
			continue
		}
		f := line
		xs, _ := strings.split_by_byte_iterator(&f, ' ')
		ss, _ := strings.split_by_byte_iterator(&f, ' ')
		cs, _ := strings.split_by_byte_iterator(&f, ' ')
		cat := strings.trim_prefix(f, "# ")
		xu, ok_x := strconv.parse_u64_of_base(xs, 16)
		su, ok_s := strconv.parse_u64_of_base(ss, 16)
		cu, ok_c := strconv.parse_u64_of_base(cs, 16)
		if !testing.expectf(t, ok_x && ok_s && ok_c, "bad fixture line %q", line) {
			continue
		}
		c.cases += 1
		switch {
		case cat == "random":
			c.random += 1
		case cat == "random-large":
			c.random_large += 1
		case strings.has_prefix(cat, "sin.wc"):
			c.sin_wc += 1
		case strings.has_prefix(cat, "cos.wc"):
			c.cos_wc += 1
		case cat == "glibc-2.39":
			c.glibc += 1
		}
		x := from_bits(xu)
		if got := bits(cr_sin(x)); got != su {
			c.sin_bad += 1
			if c.sin_bad <= 10 {
				testing.expectf(
					t,
					false,
					"cr_sin(0x%16x) = 0x%16x, want 0x%16x (%s)",
					xu,
					got,
					su,
					cat,
				)
			}
		}
		if got := bits(cr_cos(x)); got != cu {
			c.cos_bad += 1
			if c.cos_bad <= 10 {
				testing.expectf(
					t,
					false,
					"cr_cos(0x%16x) = 0x%16x, want 0x%16x (%s)",
					xu,
					got,
					cu,
					cat,
				)
			}
		}
	}
	return
}

@(test)
test_cr_sin_cos_fixture :: proc(t: ^testing.T) {
	c := check_fixture(t)
	testing.expectf(t, c.sin_bad == 0, "cr_sin: %d of %d cases differ", c.sin_bad, c.cases)
	testing.expectf(t, c.cos_bad == 0, "cr_cos: %d of %d cases differ", c.cos_bad, c.cases)
	// The plan's minimum coverage (docs/plans/162-cr-sin-cos.md): the fixture must not shrink silently.
	testing.expect(t, c.random >= 1000)
	testing.expect(t, c.random_large >= 200)
	testing.expect(t, c.sin_wc >= 20)
	testing.expect(t, c.cos_wc >= 20)
	testing.expect_value(t, c.glibc, 29)
}

@(test)
test_cr_sin_cos_special_values :: proc(t: ^testing.T) {
	ZERO :: 0h0000000000000000
	NEG_ZERO :: 0h8000000000000000
	ONE :: 0h3FF0000000000000
	testing.expect_value(t, bits(cr_sin(ZERO)), bits(ZERO))
	testing.expect_value(t, bits(cr_sin(NEG_ZERO)), bits(NEG_ZERO))
	testing.expect_value(t, bits(cr_cos(ZERO)), bits(ONE))
	testing.expect_value(t, bits(cr_cos(NEG_ZERO)), bits(ONE))

	specials := [?]f64 {
		0h7FF0000000000000,
		0hFFF0000000000000,
		0h7FF8000000000000,
		0hFFF8000000000001,
		0h7FF0000000000001,
	}
	for x in specials {
		s, c := cr_sin(x), cr_cos(x)
		// Upstream: sin returns the positive quiet NaN; cos returns x with the quiet bit set (sign and payload kept).
		testing.expect_value(t, bits(s), u64(0x7FF8000000000000))
		testing.expect_value(t, bits(c), bits(x) | (u64(1) << 51))
	}

	// Subnormals and the tiny-|x| fast paths: sin(x) rounds to x and cos(x) to 1.
	tiny := [?]f64 {
		0h0000000000000001,
		0h000FFFFFFFFFFFFF,
		0h0010000000000000,
		0h3C90000000000000,
		0h3E3FFFFFFFFFFFFF,
	}
	for x in tiny {
		testing.expect_value(t, bits(cr_sin(x)), bits(x))
		testing.expect_value(t, bits(cr_sin(-x)), bits(-x))
		testing.expect_value(t, bits(cr_cos(x)), bits(ONE))
		testing.expect_value(t, bits(cr_cos(-x)), bits(ONE))
	}
}
