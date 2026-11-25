package core

import "core:math"
import "core:slice"
import "core:strings"

// Writer of `GrappleMap.txt`: the original's `save(g, ostream)` (src/persistence.cpp:241-251) with the position
// writer of `operator<<(ostream, Position)` (:118-144) and of `Sequence` (:146-151). The whole graph is checked
// before anything is allocated (ADR 0005 decisions 5, 8), so a failed export allocates nothing.

// BASE62_DIGITS is `base62digits` (src/persistence.cpp:13), the inverse of `base62_value` (parse.odin).
@(private = "file")
@(rodata)
BASE62_DIGITS := "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"

@(private = "file")
OUT_RADIX :: 62 // src/persistence.cpp:131-132
@(private = "file")
OUT_LINES :: 4 // `for (int i = 0; i != 4; ++i)`, src/persistence.cpp:140
@(private = "file")
OUT_INDENT :: "    " // src/persistence.cpp:141
@(private = "file")
OUT_DIGITS :: PLAYER_COUNT * JOINT_COUNT * len(V3) * 2 // 276
@(private = "file")
OUT_LINE_DIGITS :: OUT_DIGITS / OUT_LINES // `n = s.size() / 4` = 69, src/persistence.cpp:138
@(private = "file")
OUT_POSITION_BYTES :: OUT_LINES * (len(OUT_INDENT) + OUT_LINE_DIGITS + 1) // 296

// export_txt writes `g` as the original's `save` does, into one buffer on `allocator` (free with `delete`):
//  1. every node with a non-empty description, in node order (anonymous nodes have none and are skipped): its
//     description lines, each + '\n', then its position (src/persistence.cpp:243-247);
//  2. every edge in order: its sequence's description lines + '\n', then every position (:146-151, :249).
// A position is, per player and joint in `Joint` order (the inverse of parse.odin's decoder, `playerJoints`),
// `x + 2`, `y`, `z + 2`, each as two base62 digits of `int(round(d * 1000))`, cut in 4 lines of 69 digits after
// 4 spaces. The operation order is the original's: `(x + 2) * 1000`, not `x * 1000 + 2000` (ADR 0003 d4).
// `math.round_f64` is Go's `math.Round` (core/math/math.odin of the pinned toolchain): half away from zero, as
// `std::round`.
//
// Errors (`Export_Error`, `line = 0`; `block` = 0-based index of the block in the output: written nodes first,
// then edges), first one stops; within a block, in this order:
//  - a node with `index < named_count`, or an edge, with an empty description → `Empty_Description`;
//  - a description line starting with ' ' → `Description_Starts_With_Space`; containing '\n' →
//    `Description_Has_Newline` (either would not load back as the same block, §1.7). '\r' is written verbatim;
//  - a written node whose whole description equals an earlier written node's → `Duplicate_Description`
//    (ADR 0005 d5);
//  - a coordinate whose `round((d + offset) * 1000)` is outside 0…Q_MAX, or NaN → `Coordinate_Out_Of_Range`,
//    checked on the f64 before any conversion to int (the original only asserts `< 4000`, compiled out; §1.5,
//    ADR 0005 d8).
// A graph returned by `load_graph` never triggers any of them.
export_txt :: proc(g: ^Graph, allocator := context.allocator) -> (out: []byte, err: Error) {
	size := check_graph(g) or_return
	if size == 0 {
		return nil, nil
	}
	out = make([]byte, size, allocator) or_return
	n := 0
	for &x in g.nodes {
		if len(x.description) == 0 {
			continue
		}
		n = write_description(out, n, x.description)
		n = write_position(out, n, x.position)
	}
	for &e in g.edges {
		n = write_description(out, n, e.sequence.description)
		for &p in e.sequence.positions {
			n = write_position(out, n, p)
		}
	}
	assert(n == size)
	return out, nil
}

// check_graph applies the rules of export_txt and returns the size of the output.
@(private = "file")
check_graph :: proc(g: ^Graph) -> (size: int, err: Error) {
	block := 0
	for &x, i in g.nodes {
		if len(x.description) == 0 && i >= g.named_count {
			continue
		}
		size += check_description(x.description, block) or_return
		for &y in g.nodes[:i] {
			if len(y.description) != 0 && slice.equal(y.description, x.description) {
				return 0, Export_Error{kind = .Duplicate_Description, block = block}
			}
		}
		check_position(&x.position, block) or_return
		size += OUT_POSITION_BYTES
		block += 1
	}
	for &e in g.edges {
		size += check_description(e.sequence.description, block) or_return
		for &p in e.sequence.positions {
			check_position(&p, block) or_return
		}
		size += len(e.sequence.positions) * OUT_POSITION_BYTES
		block += 1
	}
	return size, nil
}

// check_description returns the bytes the description takes in the output.
@(private = "file")
check_description :: proc(desc: []string, block: int) -> (size: int, err: Error) {
	if len(desc) == 0 {
		return 0, Export_Error{kind = .Empty_Description, block = block}
	}
	for line in desc {
		if strings.has_prefix(line, " ") {
			return 0, Export_Error{kind = .Description_Starts_With_Space, block = block}
		}
		if strings.contains_rune(line, '\n') {
			return 0, Export_Error{kind = .Description_Has_Newline, block = block}
		}
		size += len(line) + 1
	}
	return size, nil
}

@(private = "file")
check_position :: proc(p: ^Position, block: int) -> Error {
	for pl in 0 ..< PLAYER_COUNT {
		for j in Joint {
			for axis in 0 ..< len(V3) {
				if _, ok := quantize(p[pl][j][axis], axis); !ok {
					return Export_Error{kind = .Coordinate_Out_Of_Range, block = block}
				}
			}
		}
	}
	return nil
}

// quantize is the original's `g(d)` on `x + 2`, `y`, `z + 2` (src/persistence.cpp:122-135). `ok = false` when the
// rounded value is outside 0…Q_MAX or NaN (`!(r >= 0 && r <= Q_MAX)` is true for NaN).
@(private)
quantize :: proc(v: f64, axis: int) -> (q: int, ok: bool) {
	d := v if axis == 1 else v + ENCODING_OFFSET_XZ
	r := math.round_f64(d * QUANT_SCALE)
	if !(r >= 0 && r <= Q_MAX) {
		return 0, false
	}
	return int(r), true
}

@(private = "file")
write_description :: proc(out: []byte, n: int, desc: []string) -> int {
	n := n
	for line in desc {
		n += copy(out[n:], line)
		out[n] = '\n'
		n += 1
	}
	return n
}

// write_position writes the 4 lines of a position already checked by check_position.
@(private = "file")
write_position :: proc(out: []byte, n: int, p: Position) -> int {
	n := n
	k := 0 // digits written
	for pl in 0 ..< PLAYER_COUNT {
		for j in Joint {
			for axis in 0 ..< len(V3) {
				q, ok := quantize(p[pl][j][axis], axis)
				assert(ok, "write_position on an unchecked position")
				for d in ([2]int{q / OUT_RADIX, q % OUT_RADIX}) {
					if k % OUT_LINE_DIGITS == 0 {
						n += copy(out[n:], OUT_INDENT)
					}
					out[n] = BASE62_DIGITS[d]
					n += 1
					k += 1
					if k % OUT_LINE_DIGITS == 0 {
						out[n] = '\n'
						n += 1
					}
				}
			}
		}
	}
	return n
}
