package core

// Node matching of the original (docs/original.md §2.3): is a position the same as another up to a reorientation,
// a mirror and a swap of the players? Pure: values in, values out, nothing allocated. The operation order is the
// original's (ADR 0003 decisions 2 and 4), so every decision near a threshold is the original's decision. The
// trigonometry is `cr_atan2` here and `cr_sin`/`cr_cos` through `rotate_v3`/`apply`. The original's debug `assert`s
// are compiled out (`-DNDEBUG`) and not ported.

// distance_squared is `distanceSquared(V3, V3)` (src/math.hpp:190): `inner_prod(to − from, to − from)`, summed
// x, y, z left to right (`inner_prod(BasicV3)`, src/math.hpp:66-68).
distance_squared :: proc(from, to: V3) -> f64 {
	d := to - from
	return d.x * d.x + d.y * d.y + d.z * d.z
}

// basically_same is `basicallySame` (src/positions.hpp:49-54): every joint, player 0 then player 1 in `Joint`
// order, within 4 cm. Strict `>`: a squared distance of exactly `BASICALLY_SAME_SQ` passes.
basically_same :: proc(a, b: Position) -> bool {
	for pl in 0 ..< PLAYER_COUNT {
		for j in Joint {
			if distance_squared(a[pl][j], b[pl][j]) > BASICALLY_SAME_SQ {
				return false
			}
		}
	}
	return true
}

// head2head is the lambda of `is_reoriented` (src/positions.cpp:235-236): the squared distance between the heads.
head2head :: proc(p: Position) -> f64 {
	return distance_squared(p[0][.Head], p[1][.Head])
}

// angle_v2 is `angle(V2)` (src/math.hpp:267): `atan2(v.x, v.y)`.
angle_v2 :: proc(v: V2) -> f64 {
	return cr_atan2(v.x, v.y)
}

// is_reoriented_without_mirror_and_swap is src/positions.cpp:198-211: the rotation that aligns the head-to-head
// lines (the difference of two `atan2`, not wrapped into (−π, π]) and the translation that takes player 0's head of
// `a` to that of `b`. `xyz(yrot(angleOff) * V4(a0h, 1))` is exactly `rotate_v3`.
@(private = "file")
is_reoriented_without_mirror_and_swap :: proc(a, b: Position) -> (Reorientation, bool) {
	a0h, a1h := a[0][.Head], a[1][.Head]
	b0h, b1h := b[0][.Head], b[1][.Head]
	db, da := b1h - b0h, a1h - a0h
	angle_off := angle_v2({db.x, db.z}) - angle_v2({da.x, da.z})
	r := Reorientation {
		offset = b0h - rotate_v3(angle_off, a0h),
		angle  = angle_off,
	}
	return r, basically_same(apply(r, a), b)
}

// is_reoriented_without_swap is src/positions.cpp:213-230: first `b` as is, then `mirror(b)`.
@(private = "file")
is_reoriented_without_swap :: proc(a, b: Position) -> (Position_Reorientation, bool) {
	if r, ok := is_reoriented_without_mirror_and_swap(a, b); ok {
		return {reorientation = r}, true
	}
	if r, ok := is_reoriented_without_mirror_and_swap(a, mirror(b)); ok {
		return {reorientation = r, mirror = true}, true
	}
	return {}, false
}

// is_reoriented is `is_reoriented(Position const & a, Position b)` (src/positions.cpp:233-259), with the original's
// argument order: `a` the node's position, `b` the sequence end. `u` maps `a` onto `b` (`reorient(u, a) ≈ b`).
// Pre-filter on the head-to-head distance (invariant under reorientations), then four attempts in order: as is,
// mirrored, swapped, swapped and mirrored (the mirror of the swapped copy). The first that passes wins.
is_reoriented :: proc(a, b: Position) -> (u: Position_Reorientation, ok: bool) {
	if abs(head2head(a) - head2head(b)) > HEAD_PREFILTER_SQ {
		return {}, false
	}
	if u, ok = is_reoriented_without_swap(a, b); ok {
		return u, true
	}
	if u, ok = is_reoriented_without_swap(a, swap_players(b)); ok {
		u.swap_players = true
		return u, true
	}
	return {}, false
}
