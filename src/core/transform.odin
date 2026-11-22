package core

// Trig-free position transforms of the original (docs/original.md §4.3, §5.1, §5.2, §5.6, §6.1). Pure: values in,
// values out, nothing allocated. The operation order is the original's, never rewritten (ADR 0003 decision 4: no FMA,
// no reassociation), so the results are bit-identical. Odin's array operators act per component, like `BasicV3`'s
// (src/math.hpp:135-183). Rotations and anything with trigonometry are #140.

// mirror_v3 is `mirror(V3)` (src/positions.hpp:36): x negated (exact; +0 becomes -0).
mirror_v3 :: proc(v: V3) -> V3 {
	return {-v.x, v.y, v.z}
}

// mirror is `mirror(Position)` (src/positions.cpp:130-136): every joint mirrored, then left ↔ right swapped per
// player (the ten `swapLimbs` swaps, src/positions.cpp:77-89, are the `mirror_joint` permutation). The players are
// not swapped.
mirror :: proc(p: Position) -> Position {
	r: Position
	for pl in 0 ..< PLAYER_COUNT {
		for j in Joint {
			r[pl][mirror_joint(j)] = mirror_v3(p[pl][j])
		}
	}
	return r
}

// swap_players is `swap_players(Position &)` (src/positions.hpp:68-71), returning a copy instead of swapping in place.
swap_players :: proc(p: Position) -> Position {
	return {p[1], p[0]}
}

// heading is `heading(Position)` (src/positions.hpp:132-135): `xz(p[1][Core] − p[0][Core])`.
heading :: proc(p: Position) -> V2 {
	d := p[1][.Core] - p[0][.Core]
	return {d.x, d.z}
}

// center is `center(Position)` (src/positions.hpp:142-145): the midpoint `(a + b) / 2` of the two cores
// (`between(V3, V3)`, src/math.hpp:193).
center :: proc(p: Position) -> V3 {
	return (p[0][.Core] + p[1][.Core]) / 2
}

// between is `between(Position, Position, s)` (src/positions.hpp:42-47): per joint `a + (b − a)·s` (§6.1). Not
// clamped (s outside [0, 1] extrapolates) and not `a·(1 − s) + b·s`, so s = 1 is not always b and s = 0 turns a = -0
// into +0 unless b < 0.
between :: proc(a, b: Position, s: f64 = 0.5) -> Position {
	r: Position
	for pl in 0 ..< PLAYER_COUNT {
		for j in Joint {
			r[pl][j] = a[pl][j] + (b[pl][j] - a[pl][j]) * s
		}
	}
	return r
}
