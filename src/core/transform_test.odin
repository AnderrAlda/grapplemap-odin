package core

import "core:testing"

// Expected values are written from docs/original.md §4.3, §5.1, §5.2, §5.6, §6.1 and checked by hand against
// reference/GrappleMap/src/positions.hpp:36-145 and src/math.hpp:193. Comparisons are bit for bit (ADR 0003).
// Expected floats are literals computed as f64 outside Odin: Odin folds constant expressions with more precision
// than f64, so `0.4 - 0.1` written in a test is not the runtime result.

@(private = "file")
bits :: proc(x: f64) -> u64 {
	return transmute(u64)x
}

@(private = "file")
same_v3 :: proc(a, b: V3) -> bool {
	return bits(a.x) == bits(b.x) && bits(a.y) == bits(b.y) && bits(a.z) == bits(b.z)
}

@(private = "file")
same_position :: proc(a, b: Position) -> bool {
	for pl in 0 ..< PLAYER_COUNT {
		for j in Joint {
			if !same_v3(a[pl][j], b[pl][j]) {
				return false
			}
		}
	}
	return true
}

// sample_position: every coordinate distinct (player, joint and axis can be told apart), x = +0 on one joint.
@(private = "file")
sample_position :: proc() -> Position {
	p: Position
	for pl in 0 ..< PLAYER_COUNT {
		for j in Joint {
			k := f64(pl * JOINT_COUNT + int(j))
			p[pl][j] = {k * 0.031 - 0.7, k * 0.017 + 0.05, 1.3 - k * 0.029}
		}
	}
	p[0][.LeftKnee].x = 0
	return p
}

@(test)
test_mirror_v3_negates_x_only :: proc(t: ^testing.T) {
	testing.expect(t, same_v3(mirror_v3({0.25, -1.5, 2}), {-0.25, -1.5, 2}))
	testing.expect_value(t, bits(mirror_v3({0, 0, 0}).x), bits(-0.0))
	testing.expect_value(t, bits(mirror_v3({-0.0, 0, 0}).x), bits(0.0))
}

@(test)
test_mirror_swaps_left_right_and_keeps_players :: proc(t: ^testing.T) {
	p := sample_position()
	m := mirror(p)
	testing.expect(t, same_position(mirror(m), p), "mirror is an involution")
	for pl in 0 ..< PLAYER_COUNT {
		testing.expect(t, same_v3(m[pl][.LeftHand], mirror_v3(p[pl][.RightHand])))
		testing.expect(t, same_v3(m[pl][.RightHand], mirror_v3(p[pl][.LeftHand])))
		testing.expect(t, same_v3(m[pl][.LeftToe], mirror_v3(p[pl][.RightToe])))
		for j in ([]Joint{.Core, .Neck, .Head}) {
			testing.expect(
				t,
				same_v3(m[pl][j], mirror_v3(p[pl][j])),
				"Core/Neck/Head keep their index",
			)
		}
		for j in Joint {
			testing.expect(t, same_v3(m[pl][mirror_joint(j)], mirror_v3(p[pl][j])))
		}
	}
	// x = +0 on player 0's LeftKnee becomes -0 on its RightKnee.
	testing.expect_value(t, bits(m[0][.RightKnee].x), bits(-0.0))
}

@(test)
test_swap_players :: proc(t: ^testing.T) {
	p := sample_position()
	s := swap_players(p)
	testing.expect(t, same_position(swap_players(s), p), "swap_players is an involution")
	testing.expect(t, same_v3(s[0][.Head], p[1][.Head]))
	testing.expect(t, same_v3(s[1][.LeftToe], p[0][.LeftToe]))
	// Bitwise −h only because the two cores differ: with equal cores a − b = +0 but −(b − a) = −0.
	h, hs := heading(p), heading(swap_players(p))
	testing.expect_value(t, bits(hs.x), bits(-h.x))
	testing.expect_value(t, bits(hs.y), bits(-h.y))
	testing.expect(t, same_v3(center(s), center(p)))
}

@(test)
test_heading_is_core_difference_xz :: proc(t: ^testing.T) {
	p: Position
	p[0][.Core] = {0.1, 0.9, -0.3}
	p[1][.Core] = {0.4, 0.2, 0.5}
	h := heading(p)
	testing.expect_value(t, bits(h.x), bits(0.30000000000000004)) // 0.4 − 0.1
	testing.expect_value(t, bits(h.y), bits(0.8)) // 0.5 − −0.3
	p[1][.Head] = {5, 5, 5}
	testing.expect_value(t, heading(p), h)
}

@(test)
test_center_is_core_midpoint :: proc(t: ^testing.T) {
	p: Position
	p[0][.Core] = {0.1, 0.9, -0.3}
	p[1][.Core] = {0.4, 0.2, 0.5}
	c := center(p)
	testing.expect(t, same_v3(c, {0.25, 0.55, 0.1}), "y is kept")
	p[0][.Head] = {5, 5, 5}
	testing.expect(t, same_v3(center(p), c))
}

@(private = "file")
one_joint :: proc(v: V3) -> Position {
	p: Position
	p[1][.RightFingers] = v
	return p
}

@(test)
test_between_endpoints :: proc(t: ^testing.T) {
	// s = 0: -0 + (0 − -0)·0 = -0 + +0 = +0 (§6.1).
	r := between(one_joint({-0.0, 1, 2}), one_joint({0, 1, 2}), 0)
	testing.expect_value(t, bits(r[1][.RightFingers].x), bits(0.0))
	// s = 1 is not always b: −1.463 + (1.39 + 1.463)·1 = 1.3899999999999997.
	r = between(one_joint({-1.463, 0, 0}), one_joint({1.39, 0, 0}), 1)
	testing.expect_value(t, bits(r[1][.RightFingers].x), bits(1.3899999999999997))
	testing.expect(t, bits(r[1][.RightFingers].x) != bits(1.39))
}

@(test)
test_between_formula_and_no_clamp :: proc(t: ^testing.T) {
	a, b := one_joint({0.1, 0.5, -1}), one_joint({0.3, 1, 1})
	// a + (b − a)·s = 0.15, while a·(1 − s) + b·s = 0.15000000000000002.
	r := between(a, b, 0.25)
	testing.expect_value(t, bits(r[1][.RightFingers].x), bits(0.15))
	testing.expect(t, same_v3(between(a, b)[1][.RightFingers], {0.2, 0.75, 0}), "s = 0.5")
	testing.expect(t, same_v3(between(a, b, 2)[1][.RightFingers], {0.5, 1.5, 3}))
	testing.expect(t, same_v3(between(a, b, -1)[1][.RightFingers], {-0.09999999999999998, 0, -3}))
	// Every joint of both players, not just one.
	p, q := sample_position(), swap_players(sample_position())
	m := between(p, q, 0.75)
	for pl in 0 ..< PLAYER_COUNT {
		for j in Joint {
			testing.expect(t, same_v3(m[pl][j], p[pl][j] + (q[pl][j] - p[pl][j]) * 0.75))
		}
	}
}
