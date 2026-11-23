package core

import "core:testing"

// Expected values from reference/GrappleMap/src/positions.hpp:49-54 and src/positions.cpp:198-259 (docs/original.md
// §2.3). Floats are f64 literals computed outside Odin: the boundary 0.04 (Python: `0.04 * 0.04 == 0.0016` and the
// next double up squares to 0.0016000000000000007) and atan2(0.1, -1) = 3.0419240010986313 (tools/cr_atan2_ref.py,
// correctly rounded). Angles and displacements reach the procedures through runtime variables.

@(private = "file")
bits :: proc(x: f64) -> u64 {
	return transmute(u64)x
}

// base_position: asymmetric (every coordinate linear in the joint number, so mirror and swap are far from any
// rigid image), heads not on a signed zero.
@(private = "file")
base_position :: proc() -> Position {
	p: Position
	for pl in 0 ..< PLAYER_COUNT {
		for j in Joint {
			k := f64(pl * JOINT_COUNT + int(j))
			p[pl][j] = {k * 0.031 - 0.7, k * 0.017 + 0.05, 1.3 - k * 0.029}
		}
	}
	p[0][.Head] = {0.3, 1.6, -0.2}
	p[1][.Head] = {-0.4, 1.5, 0.9}
	return p
}

@(test)
test_distance_squared :: proc(t: ^testing.T) {
	// (to − from) = (1, -2, 2): 1 + 4 + 4.
	testing.expect_value(t, distance_squared({1, 2, 3}, {2, 0, 5}), 9)
	testing.expect_value(
		t,
		head2head(base_position()),
		distance_squared({0.3, 1.6, -0.2}, {-0.4, 1.5, 0.9}),
	)
}

@(test)
test_angle_v2 :: proc(t: ^testing.T) {
	v := V2{0.1, -1}
	testing.expect_value(t, bits(angle_v2(v)), bits(3.0419240010986313))
}

@(test)
test_basically_same :: proc(t: ^testing.T) {
	a := base_position()
	a[1][.LeftHand].x = 0 // b.x − a.x is then exactly the displacement
	testing.expect(t, basically_same(a, a))

	moved :: proc(a: Position, dx: f64) -> Position {
		b := a
		b[1][.LeftHand].x = dx
		return b
	}
	more, less := 0.05, 0.03
	testing.expect(t, !basically_same(a, moved(a, more)))
	testing.expect(t, basically_same(a, moved(a, less)))
	// Exactly at the threshold: 0.04² is the double 0.0016, and the comparison is a strict `>`.
	at, above := 0.04, 0.04000000000000001
	testing.expect(t, basically_same(a, moved(a, at)))
	testing.expect(t, !basically_same(a, moved(a, above)))
	// Player 0 is checked too.
	b := a
	b[0][.LeftToe].y += more
	testing.expect(t, !basically_same(a, b))
}

@(test)
test_is_reoriented_prefilter :: proc(t: ^testing.T) {
	a := base_position()
	a[0][.Head] = {0, 1.6, 0}
	a[1][.Head] = {0, 1.6, 2}
	// Player 1's head 3.9 cm farther along the head-to-head line: same angle, zero offset, every joint within 4 cm,
	// but head2head goes from 4 to 2.039² (Δ ≈ 0.157 > 0.05).
	far, near := 2.039, 2.01
	b := a
	b[1][.Head].z = far
	testing.expect(t, basically_same(a, b))
	_, ok := is_reoriented(a, b)
	testing.expect(t, !ok)
	// Δ ≈ 0.0401: the filter lets it through and the first attempt matches.
	b[1][.Head].z = near
	u: Position_Reorientation
	u, ok = is_reoriented(a, b)
	testing.expect(t, ok)
	testing.expect(t, !u.swap_players && !u.mirror)
	// The pre-filter's strict `>` at exactly 0.05 is not observable. A match needs player 1's head within 4 cm after
	// aligning player 0's heads, so |d_a − d_b| ≤ 0.04. With d_a² − d_b² = 0.05, both head2head values are then
	// ≥ 0.36. Doubles that large are multiples of 2⁻⁵⁴, but 0.05 needs a 2⁻⁵⁶ step: no such pair differs by
	// exactly 0.05.
}

@(test)
test_is_reoriented_identity :: proc(t: ^testing.T) {
	p := base_position()
	u, ok := is_reoriented(p, p)
	testing.expect(t, ok)
	testing.expect(t, !u.swap_players && !u.mirror)
	testing.expect_value(t, bits(u.reorientation.angle), 0)
	for axis in 0 ..< 3 {
		testing.expect_value(t, bits(u.reorientation.offset[axis]), 0)
	}
}

// expect_case: `is_reoriented(a, b)` matches with the given flags, and the reorientation it gives maps `a` onto `b`.
@(private = "file")
expect_case :: proc(t: ^testing.T, a, b: Position, swap, mirror: bool, loc := #caller_location) {
	u, ok := is_reoriented(a, b)
	testing.expect(t, ok, loc = loc)
	testing.expect_value(t, u.swap_players, swap, loc = loc)
	testing.expect_value(t, u.mirror, mirror, loc = loc)
	testing.expect(t, basically_same(reorient(u, a), b), loc = loc)
}

@(test)
test_is_reoriented_four_attempts :: proc(t: ^testing.T) {
	a := base_position()
	r := Reorientation {
		offset = {0.25, 0, -1.1},
	}
	angle := 0.7
	r.angle = angle
	ra := apply(r, a)
	expect_case(t, a, ra, swap = false, mirror = false)
	u, _ := is_reoriented(a, ra)
	testing.expect(t, basically_same(apply(u.reorientation, a), ra))
	expect_case(t, a, mirror(ra), swap = false, mirror = true)
	expect_case(t, a, swap_players(ra), swap = true, mirror = false)
	// Both flags at once. (Mirror and swap commute on a position, so this case cannot tell which copy is mirrored.)
	expect_case(t, a, swap_players(mirror(ra)), swap = true, mirror = true)
}

@(test)
test_is_reoriented_attempt_order :: proc(t: ^testing.T) {
	p := base_position()
	// Left/right symmetric: mirror(sym) is sym (up to signed zeros), so it matches with and without mirror.
	sym: Position
	for pl in 0 ..< PLAYER_COUNT {
		for j in Joint {
			sym[pl][j] = (p[pl][j] + mirror_v3(p[pl][mirror_joint(j)])) / 2
		}
	}
	testing.expect(t, basically_same(mirror(sym), sym))
	expect_case(t, sym, sym, swap = false, mirror = false)
	// Player 1 is player 0 turned half a turn about the y axis: matches with and without swap.
	half: Position
	half[0] = p[0]
	for j in Joint {
		v := p[0][j]
		half[1][j] = {-v.x, v.y, -v.z}
	}
	_, swapped_ok := is_reoriented(half, swap_players(half))
	testing.expect(t, swapped_ok)
	expect_case(t, half, half, swap = false, mirror = false)
}

@(test)
test_is_reoriented_angle_not_wrapped :: proc(t: ^testing.T) {
	a := base_position()
	a[0][.Head] = {0, 1.6, 0}
	a[1][.Head] = {0.1, 1.6, -1}
	// atan2(-0.1, -1) − atan2(0.1, -1) = −2·3.0419240010986313, below −π: kept as is, not wrapped to ≈ 0.199.
	want := -6.0838480021972625
	b := rotate(want, a)
	b[0][.Head] = {0, 1.6, 0}
	b[1][.Head] = {-0.1, 1.6, -1}
	u, ok := is_reoriented(a, b)
	testing.expect(t, ok)
	testing.expect(t, !u.swap_players && !u.mirror)
	testing.expect_value(t, bits(u.reorientation.angle), bits(-6.0838480021972625))
}

@(test)
test_is_reoriented_no_match :: proc(t: ^testing.T) {
	a := base_position()
	b := a
	b[0][.LeftToe].y += 0.5
	_, ok := is_reoriented(a, b)
	testing.expect(t, !ok)
}
