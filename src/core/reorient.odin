package core

// Reorientations and canonical orientation of the original (docs/original.md §4.3, §5.3, §5.5, §5.7). Pure: values
// in, values out, nothing allocated. The operation order is the original's, never rewritten (ADR 0003 decision 4: no
// FMA, no reassociation), so the results are bit-identical. The trigonometry is `core`'s own correctly rounded `cr_atan2`,
// `cr_sin` and `cr_cos`, never the libm or `core:math` (ADR 0003, amendment #161): the original's glibc 2.27 behaves
// as correctly rounded on every angle of the DB, measured by the fidelity tests (#140).

// rotate_v3 is `yrot(a) * v` (src/math.hpp:73-80, 197-209): the 4×4 matrix `yrot(a)` times `V4(v, 1)`, keeping xyz.
// Each component is the original's sum, left to right, with the matrix entries written literally. The `0 *` and `+ 0`
// terms MUST NOT be simplified away: they decide the sign of zero (the trailing `+ 0` is the original's `+ m[12]`/`m[13]`/`m[14]`, which turns
// -0 into +0). `cos(a)` and `sin(a)` are computed once; the original calls them twice, with the same bits.
rotate_v3 :: proc(a: f64, v: V3) -> V3 {
	// The literal entries 0 and 1 of `yrot(a)` and of its translation column, not magic numbers.
	ZERO :: f64(0)
	ONE :: f64(1)
	c := cr_cos(a)
	s := cr_sin(a)
	ns := -s // m[2] = -sin(a)
	return {
		((c * v.x + ZERO * v.y) + s * v.z) + ZERO,
		((ZERO * v.x + ONE * v.y) + ZERO * v.z) + ZERO,
		((ns * v.x + ZERO * v.y) + c * v.z) + ZERO,
	}
}

// rotate is `rotate(a, Position)` (src/positions.hpp:160-163): `rotate_v3` per joint.
rotate :: proc(a: f64, p: Position) -> Position {
	r: Position
	for pl in 0 ..< PLAYER_COUNT {
		for j in Joint {
			r[pl][j] = rotate_v3(a, p[pl][j])
		}
	}
	return r
}

// apply_v3 is `apply(Reorientation, V3)` (src/math.hpp:252-255): rotate, then translate.
apply_v3 :: proc(r: Reorientation, v: V3) -> V3 {
	return rotate_v3(r.angle, v) + r.offset
}

// apply is `apply(Reorientation, Position)` (src/positions.hpp:62-66): `apply_v3` per joint. Even the identity
// reorientation is not a no-op: it turns -0 into +0 (§5.3).
apply :: proc(r: Reorientation, p: Position) -> Position {
	q: Position
	for pl in 0 ..< PLAYER_COUNT {
		for j in Joint {
			q[pl][j] = apply_v3(r, p[pl][j])
		}
	}
	return q
}

// reorient is `PositionReorientation::operator()(Position)` (src/positions.hpp:82-88): apply, then mirror, then swap.
reorient :: proc(u: Position_Reorientation, p: Position) -> Position {
	q := apply(u.reorientation, p)
	if u.mirror {
		q = mirror(q)
	}
	if u.swap_players {
		q = swap_players(q)
	}
	return q
}

// reorient_v3 is `PositionReorientation::operator()(V3)` (src/positions.hpp:90-95): apply, then mirror; the swap
// does not apply to a point.
reorient_v3 :: proc(u: Position_Reorientation, v: V3) -> V3 {
	w := apply_v3(u.reorientation, v)
	if u.mirror {
		w = mirror_v3(w)
	}
	return w
}

// normal_rotation is `normalRotation` (src/positions.hpp:137-140): `-angle(heading(p))`, with
// `angle(V2 v) = atan2(v.x, v.y)` (src/math.hpp:267). Equal cores give -0; a heading of (-0, -0) gives π (§5.5).
normal_rotation :: proc(p: Position) -> f64 {
	h := heading(p)
	return -cr_atan2(h.x, h.y)
}

// normal_translation is `normalTranslation` (src/positions.hpp:169): `y0(-xz(center(p)))`
// (src/math.hpp:40, 110, 137), y the literal +0.
normal_translation :: proc(p: Position) -> V3 {
	c := center(p)
	return {-c.x, 0, -c.z}
}

// canonical_reorientation_without_mirror is src/positions.cpp:272-281: the normal rotation, then the normal
// translation of the position already rotated (the centre is taken after rotating).
canonical_reorientation_without_mirror :: proc(p: Position) -> Position_Reorientation {
	angle := normal_rotation(p)
	return {reorientation = {offset = normal_translation(rotate(angle, p)), angle = angle}}
}

// canonical_reorientation_with_mirror is src/positions.cpp:261-270: the same reorientation, mirrored when player 1's
// head ends up at x >= 0 (so +0 mirrors).
canonical_reorientation_with_mirror :: proc(p: Position) -> Position_Reorientation {
	u := canonical_reorientation_without_mirror(p)
	u.mirror = apply(u.reorientation, p)[1][.Head].x >= 0
	return u
}

// orient_canonically_without_mirror is src/positions.cpp:283-286.
orient_canonically_without_mirror :: proc(p: Position) -> Position {
	return reorient(canonical_reorientation_without_mirror(p), p)
}

// orient_canonically_with_mirror is src/positions.cpp:288-291.
orient_canonically_with_mirror :: proc(p: Position) -> Position {
	return reorient(canonical_reorientation_with_mirror(p), p)
}
