package core

import "core:math"
import "core:strconv"
import "core:strings"
import "core:testing"

// Expected values are written from docs/original.md §4.3, §5.3, §5.5, §5.7 and checked by hand against
// reference/GrappleMap/src/math.hpp:73-80,197-209,235-267 and src/positions.hpp:62-169, src/positions.cpp:261-291.
// Comparisons are bit for bit (ADR 0003). Expected floats are f64 literals computed outside Odin (Python on f64), and
// angles reach the procedures through runtime variables, so LLVM does not fold `sin`/`cos` at compile time.

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

// sample_position: every coordinate distinct, one coordinate -0 and the cores off-centre and not aligned with z.
@(private = "file")
sample_position :: proc() -> Position {
	p: Position
	for pl in 0 ..< PLAYER_COUNT {
		for j in Joint {
			k := f64(pl * JOINT_COUNT + int(j))
			p[pl][j] = {k * 0.031 - 0.7, k * 0.017 + 0.05, 1.3 - k * 0.029}
		}
	}
	p[0][.LeftKnee].x = -0.0
	p[0][.Core] = {0.4, 0.9, -0.3}
	p[1][.Core] = {-0.2, 1.1, 0.6}
	return p
}

// on_z_axis: cores at (0, 1, ∓1), so the canonical reorientation is the identity up to signed zeros, and player 1's
// head at x = `head_x`.
@(private = "file")
on_z_axis :: proc(head_x: f64) -> Position {
	p := sample_position()
	p[0][.Core] = {0, 1, -1}
	p[1][.Core] = {0, 1, 1}
	p[1][.Head] = {head_x, 1.6, 0.8}
	return p
}

@(test)
test_rotate_v3_zero_angle_adds_plus_zero :: proc(t: ^testing.T) {
	// The `+ m[12..14]` (= + 0) of the original's matrix product turns -0 into +0.
	a := 0.0
	r := rotate_v3(a, {-0.0, -0.0, -0.0})
	testing.expect_value(t, bits(r.x), bits(0.0))
	testing.expect_value(t, bits(r.y), bits(0.0))
	testing.expect_value(t, bits(r.z), bits(0.0))
	a = -0.0 // sin(-0) = -0, so the matrix holds -sin(-0) = +0 and sin(-0) = -0: still the identity
	r = rotate_v3(a, {-0.0, 2.5, -0.75})
	testing.expect(t, same_v3(r, {0.0, 2.5, -0.75}), "rotate_v3(-0, v)")
}

@(test)
test_rotate_v3_quarter_turn :: proc(t: ^testing.T) {
	// cos(π/2) = 6.123233995736766e-17: x = (c + 0) + 3 = 3, z = (-1 + 0) + 3c = -0.9999999999999998.
	a := math.PI / 2
	r := rotate_v3(a, {1, 2, 3})
	testing.expect_value(t, bits(r.x), bits(3.0))
	testing.expect_value(t, bits(r.y), bits(2.0))
	testing.expect_value(t, bits(r.z), bits(-0.9999999999999998))
}

@(test)
test_rotate_is_rotate_v3_per_joint :: proc(t: ^testing.T) {
	p := sample_position()
	a := 0.7
	r := rotate(a, p)
	for pl in 0 ..< PLAYER_COUNT {
		for j in Joint {
			testing.expect(t, same_v3(r[pl][j], rotate_v3(a, p[pl][j])))
		}
	}
}

@(test)
test_apply_identity_only_clears_negative_zero :: proc(t: ^testing.T) {
	p := sample_position()
	r := apply(Reorientation{}, p)
	want := p
	want[0][.LeftKnee].x = 0
	testing.expect(t, same_position(r, want), "apply({}, p)")
	testing.expect_value(t, bits(r[0][.LeftKnee].x), bits(0.0))
}

@(test)
test_apply_rotates_then_translates :: proc(t: ^testing.T) {
	r := Reorientation {
		offset = {0.5, -0.25, 2},
		angle  = 0.7,
	}
	v := V3{1.25, -0.5, 2.5}
	testing.expect(t, same_v3(apply_v3(r, v), rotate_v3(r.angle, v) + r.offset))
	p := sample_position()
	q := apply(r, p)
	for pl in 0 ..< PLAYER_COUNT {
		for j in Joint {
			testing.expect(t, same_v3(q[pl][j], apply_v3(r, p[pl][j])))
		}
	}
}

@(test)
test_reorient_mirrors_after_translating :: proc(t: ^testing.T) {
	p := sample_position()
	u := Position_Reorientation {
		reorientation = {offset = {0.5, 0, 0}, angle = 0.3},
		mirror = true,
	}
	r := reorient(u, p)
	testing.expect(t, same_position(r, mirror(apply(u.reorientation, p))), "mirror(apply(r, p))")
	testing.expect(
		t,
		!same_position(r, apply(u.reorientation, mirror(p))),
		"not apply(r, mirror(p))",
	)
	testing.expect(
		t,
		same_v3(reorient_v3(u, p[0][.Head]), mirror_v3(apply_v3(u.reorientation, p[0][.Head]))),
	)
}

@(test)
test_reorient_swaps_players_last :: proc(t: ^testing.T) {
	p := sample_position()
	u := Position_Reorientation {
		reorientation = {offset = {0.5, 0.1, -0.2}, angle = -1.1},
		mirror = true,
		swap_players = true,
	}
	testing.expect(
		t,
		same_position(reorient(u, p), swap_players(mirror(apply(u.reorientation, p)))),
	)
	// The V3 overload ignores the swap.
	v := V3{0.3, 1, -0.4}
	testing.expect(t, same_v3(reorient_v3(u, v), mirror_v3(apply_v3(u.reorientation, v))))
	u.mirror = false
	testing.expect(t, same_position(reorient(u, p), swap_players(apply(u.reorientation, p))))
	testing.expect(t, same_v3(reorient_v3(u, v), apply_v3(u.reorientation, v)))
}

@(test)
test_normal_rotation_signed_zeros :: proc(t: ^testing.T) {
	p := sample_position()
	p[1][.Core] = p[0][.Core] // heading (+0, +0): -atan2(+0, +0) = -0
	testing.expect_value(t, bits(normal_rotation(p)), bits(-0.0))
	p[0][.Core] = {0, 1, 0}
	p[1][.Core] = {-0.0, 1, -0.0} // heading (-0 - +0, -0 - +0) = (-0, -0): -atan2(-0, -0) = π (§5.5)
	testing.expect_value(t, bits(normal_rotation(p)), bits(3.141592653589793))
}

@(test)
test_normal_rotation_player1_on_plus_x :: proc(t: ^testing.T) {
	p := sample_position()
	p[0][.Core] = {0, 1, 0}
	p[1][.Core] = {1, 1, 0} // heading (1, 0): -atan2(1, 0) = -π/2
	testing.expect_value(t, bits(normal_rotation(p)), bits(-1.5707963267948966))
}

@(test)
test_normal_translation_is_minus_xz_center :: proc(t: ^testing.T) {
	p := sample_position()
	c := center(p)
	n := normal_translation(p)
	testing.expect(t, same_v3(n, {-c.x, 0, -c.z}))
	testing.expect_value(t, bits(n.y), bits(0.0))
}

@(test)
test_orient_canonically_without_mirror :: proc(t: ^testing.T) {
	p := sample_position()
	u := canonical_reorientation_without_mirror(p)
	testing.expect(t, !u.mirror && !u.swap_players)
	testing.expect_value(t, bits(u.reorientation.angle), bits(normal_rotation(p)))
	testing.expect(
		t,
		same_v3(u.reorientation.offset, normal_translation(rotate(u.reorientation.angle, p))),
		"offset from the centre after rotating",
	)
	q := orient_canonically_without_mirror(p)
	testing.expect(t, same_position(q, reorient(u, p)))
	// Properties of the result (not fidelity tolerances): player 1 straight ahead on +z, centre on the y axis.
	h := heading(q)
	testing.expectf(t, abs(h.x) <= 1e-15 && h.y > 0, "heading %v", h)
	c := center(q)
	testing.expectf(t, abs(c.x) <= 1e-15 && abs(c.z) <= 1e-15, "center %v", c)
	testing.expect_value(t, bits(c.y), bits(center(p).y))
	// Never swaps: player 0's core stays behind (z < 0).
	testing.expect(t, q[0][.Core].z < 0)
}

@(test)
test_canonical_with_mirror_flag :: proc(t: ^testing.T) {
	p := sample_position()
	u := canonical_reorientation_with_mirror(p)
	w := canonical_reorientation_without_mirror(p)
	testing.expect(t, !u.swap_players)
	testing.expect_value(t, bits(u.reorientation.angle), bits(w.reorientation.angle))
	testing.expect(t, same_v3(u.reorientation.offset, w.reorientation.offset))
	testing.expect_value(t, u.mirror, apply(u.reorientation, p)[1][.Head].x >= 0)
	testing.expect(t, same_position(orient_canonically_with_mirror(p), reorient(u, p)))

	q := on_z_axis(0.3) // head at x > 0 → mirrored to x < 0
	testing.expect(t, canonical_reorientation_with_mirror(q).mirror)
	testing.expect(t, orient_canonically_with_mirror(q)[1][.Head].x < 0)

	q = on_z_axis(-0.3)
	testing.expect(t, !canonical_reorientation_with_mirror(q).mirror)
	testing.expect(t, orient_canonically_with_mirror(q)[1][.Head].x < 0)

	q = on_z_axis(0) // x == 0 exactly (+0 after `+ 0` and the -0 offset): `>= 0` mirrors
	testing.expect_value(
		t,
		bits(apply(canonical_reorientation_with_mirror(q).reorientation, q)[1][.Head].x),
		bits(0.0),
	)
	testing.expect(t, canonical_reorientation_with_mirror(q).mirror)
	testing.expect_value(t, bits(orient_canonically_with_mirror(q)[1][.Head].x), bits(-0.0))
}

// Literal bits (#168): tests/fixtures/canonical.txt holds one random asymmetric position and the f64 bit patterns of
// both canonical orientations of it, generated outside Odin by tools/canonical_ref.py (Python floats, correctly
// rounded sin/cos/atan2, the operation order of reorient.odin). The position is read from data, so nothing folds.
CANONICAL_FIXTURE :: #load("../../tests/fixtures/canonical.txt", string)

@(private = "file")
Canonical_Case :: struct {
	input, without_mirror, with_mirror: Position,
}

// parse_canonical_fixture reads the 46 lines `pl joint` + 9 hex bit patterns (in, without, with; x y z each).
@(private = "file")
parse_canonical_fixture :: proc(t: ^testing.T) -> (c: Canonical_Case, ok: bool) {
	text := CANONICAL_FIXTURE
	lines := 0
	for line in strings.split_lines_iterator(&text) {
		if len(line) == 0 || line[0] == '#' {
			continue
		}
		f := line
		pl, _ := strconv.parse_int(strings.split_by_byte_iterator(&f, ' ') or_else "", 10)
		j, _ := strconv.parse_int(strings.split_by_byte_iterator(&f, ' ') or_else "", 10)
		if !testing.expectf(
			t,
			pl >= 0 && pl < PLAYER_COUNT && j >= 0 && j < JOINT_COUNT,
			"bad fixture line %q",
			line,
		) {
			return
		}
		vals: [9]f64
		for i in 0 ..< 9 {
			u, ok_u := strconv.parse_u64_of_base(
				strings.split_by_byte_iterator(&f, ' ') or_else "",
				16,
			)
			if !testing.expectf(t, ok_u, "bad fixture line %q", line) {
				return
			}
			vals[i] = transmute(f64)u
		}
		c.input[pl][Joint(j)] = {vals[0], vals[1], vals[2]}
		c.without_mirror[pl][Joint(j)] = {vals[3], vals[4], vals[5]}
		c.with_mirror[pl][Joint(j)] = {vals[6], vals[7], vals[8]}
		lines += 1
	}
	ok = testing.expectf(t, lines == PLAYER_COUNT * JOINT_COUNT, "fixture has %d joints", lines)
	return
}

@(test)
test_orient_canonically_literal_bits :: proc(t: ^testing.T) {
	c, ok := parse_canonical_fixture(t)
	if !ok {
		return
	}
	// The fixture's mirror case really mirrors (else the two expected positions would be equal).
	testing.expect(t, !same_position(c.without_mirror, c.with_mirror), "fixture cases must differ")
	without := orient_canonically_without_mirror(c.input)
	with_mirror := orient_canonically_with_mirror(c.input)
	for pl in 0 ..< PLAYER_COUNT {
		for j in Joint {
			a := without[pl][j]
			b := with_mirror[pl][j]
			testing.expectf(
				t,
				same_v3(a, c.without_mirror[pl][j]),
				"without_mirror[%d][%v]: %v",
				pl,
				j,
				a,
			)
			testing.expectf(
				t,
				same_v3(b, c.with_mirror[pl][j]),
				"with_mirror[%d][%v]: %v",
				pl,
				j,
				b,
			)
		}
	}
}
