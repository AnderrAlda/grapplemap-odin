package core

import "core:testing"

// Chaser (chaser.odin; src/playback.cpp:178-184, ADR 0007). `pow` comes from libm and is not oracle-checked (ADR 0007
// d5/d6), so bits are only tested where it is exact on every libm: exponent 0 (`pow(x, 0) = 1`) and exponent 1
// (`pow(x, 1) = x`). Elsewhere only comparisons, no tolerance. `1 − 0.8` in Python is 0.19999999999999996.

@(private = "file")
cbits :: proc(x: f64) -> u64 {
	return transmute(u64)x
}

@(private = "file")
pose :: proc(dx: f64) -> (p: Position) {
	for j in Joint {
		k := f64(j)
		p[0][j] = {dx + 0.01 * k, 0.1 + 0.05 * k, 0.02 * k}
		p[1][j] = {dx + 0.6 + 0.03 * k, 0.1 + 0.04 * k, 0.3 - 0.01 * k}
	}
	return
}

@(test)
test_per_second_factor_exact :: proc(t: ^testing.T) {
	testing.expect_value(t, cbits(per_second_factor(CHASER_FACTOR, 0)), 0)

	// `60·dt` must be exactly 1 at run time for this to be an exact case.
	dt := 1.0 / f64(CHASER_REFERENCE_HZ)
	hz := f64(CHASER_REFERENCE_HZ)
	testing.expect(t, hz * dt == 1)
	testing.expect_value(t, cbits(per_second_factor(CHASER_FACTOR, dt)), 0x3fc9999999999998) // 0.19999999999999996
}

@(test)
test_per_second_factor_clamps :: proc(t: ^testing.T) {
	testing.expect_value(t, cbits(per_second_factor(CHASER_FACTOR, -0.5)), 0)
	at_max := per_second_factor(CHASER_FACTOR, CHASER_MAX_DT)
	testing.expect_value(t, cbits(per_second_factor(CHASER_FACTOR, 5)), cbits(at_max))
	testing.expect_value(
		t,
		cbits(per_second_factor(CHASER_FACTOR, CHASER_MAX_DT * 2)),
		cbits(at_max),
	)
}

@(test)
test_per_second_factor_monotone :: proc(t: ^testing.T) {
	prev := per_second_factor(CHASER_FACTOR, 0)
	for dt in ([]f64{0.001, 0.005, 0.01, 0.02, 0.04, 0.07, 0.1}) {
		s := per_second_factor(CHASER_FACTOR, dt)
		testing.expectf(t, s > prev, "factor(%v) = %v, not above %v", dt, s, prev)
		testing.expectf(t, s > 0 && s < 1, "factor(%v) = %v outside (0, 1)", dt, s)
		prev = s
	}
}

@(test)
test_chase :: proc(t: ^testing.T) {
	a, b := pose(0), pose(0.7)
	got := chase(a, b, 0)
	testing.expect(
		t,
		transmute([size_of(Position) / 8]u64)got == transmute([size_of(Position) / 8]u64)a,
	)

	dt := 1.0 / f64(CHASER_REFERENCE_HZ)
	got = chase(a, b, dt)
	want := between(a, b, transmute(f64)u64(0x3fc9999999999998)) // 1 − 0.8
	testing.expect(
		t,
		transmute([size_of(Position) / 8]u64)got == transmute([size_of(Position) / 8]u64)want,
	)
}
