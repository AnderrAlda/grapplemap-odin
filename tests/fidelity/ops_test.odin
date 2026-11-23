package fidelity

import "app:core"
import "core:encoding/json"
import "core:log"
import "core:testing"

// Position transforms of `core` (transform.odin, reorient.odin) against `ops.ndjson` (tools/oracle/README.md):
// `mirror`, `swap_players`, `heading`, `center` and `orient_canonically_with_mirror`/`…_without_mirror` of every
// dumped position, bit for bit. The canonical orientations go through `atan2`, `sin` and `cos` of each position's
// angle: this test is the measurement of the trig bits of ADR 0003 ("Open points").

// Oracle_Position is a position as the dumper writes it: doubles `[player][joint] = [x, y, z]`.
Oracle_Position :: [core.PLAYER_COUNT][core.JOINT_COUNT][3]f64

@(private = "file")
Ops_Record :: struct {
	block:                             int,
	pos:                               int,
	mirror:                            Oracle_Position,
	swap_players:                      Oracle_Position,
	orient_canonically_with_mirror:    Oracle_Position,
	orient_canonically_without_mirror: Oracle_Position,
	heading:                           [2]f64,
	center:                            [3]f64,
}

@(private = "file")
Ops_State :: struct {
	t:         ^testing.T,
	seqs:      []core.Sequence,
	compared:  int,
	last:      [2]int, // (block, pos) of the previous record: records come in that order, each at most once
	have_last: bool,
}

// keep_negative_zero rewrites every JSON number token `-0` as `-0.0`. `json.unmarshal` reads a token without '.' or
// exponent as an integer and converts it to f64, so `-0` (what `%.17g` writes for -0) decodes as +0 and a bit comparison
// would fail on the sign. Assumes the dumper's format: compact NDJSON (no whitespace) with no string values. The copy
// goes to `allocator` (the line's arena in an `Ndjson_Line_Proc`).
keep_negative_zero :: proc(line: []byte, allocator := context.allocator) -> []byte {
	is_end :: proc(line: []byte, i: int) -> bool {
		return i == len(line) || line[i] == ',' || line[i] == ']' || line[i] == '}'
	}
	is_start :: proc(line: []byte, i: int) -> bool {
		return i == 0 || line[i - 1] == ',' || line[i - 1] == '[' || line[i - 1] == ':'
	}
	out := make([dynamic]byte, 0, len(line) + 16, allocator)
	for i := 0; i < len(line); i += 1 {
		append(&out, line[i])
		if line[i] == '-' &&
		   i + 1 < len(line) &&
		   line[i + 1] == '0' &&
		   is_start(line, i) &&
		   is_end(line, i + 2) {
			append(&out, '0', '.', '0')
			i += 1
		}
	}
	return out[:]
}

@(test)
test_keep_negative_zero :: proc(t: ^testing.T) {
	v: struct {
		a, b, c, d: f64,
		e:          [2]f64,
	}
	// The Odin behaviour that makes the rewrite necessary; if Odin fixes it, this tells us the rewrite can go.
	testing.expect_value(t, json.unmarshal_string(`{"a":-0}`, &v), nil)
	testing.expect_value(t, transmute(u64)v.a, 0)

	line := keep_negative_zero(
		transmute([]byte)string(`{"a":-0,"b":-0.5,"c":-0e0,"d":0,"e":[-0,-0]}`),
	)
	defer delete(line)
	testing.expect_value(t, string(line), `{"a":-0.0,"b":-0.5,"c":-0e0,"d":0,"e":[-0.0,-0.0]}`)
	testing.expect_value(t, json.unmarshal(line, &v), nil)
	testing.expect_value(t, transmute(u64)v.a, transmute(u64)f64(-0.0))
	testing.expect_value(t, transmute(u64)v.b, transmute(u64)f64(-0.5))
	testing.expect_value(t, transmute(u64)v.d, 0)
	// A token with an exponent is already a float token: left alone, it keeps its sign.
	testing.expect_value(t, transmute(u64)v.c, transmute(u64)f64(-0.0))
	testing.expect_value(t, transmute(u64)v.e[1], transmute(u64)f64(-0.0))
}

// parse_real_db parses the submodule's DB; a missing or unparsable DB fails the test.
parse_real_db :: proc(t: ^testing.T) -> (seqs: []core.Sequence, ok: bool) {
	db := load_db(t) or_return
	defer delete(db)
	err: core.Error
	seqs, err = core.parse_db(db)
	if !testing.expectf(t, err == nil, "parse_db(%s): %v", db_path(), err) {
		return nil, false
	}
	return seqs, true
}

// expect_position compares `got` with an oracle position bit for bit and reports the first coordinate that differs.
expect_position :: proc(
	t: ^testing.T,
	got: core.Position,
	want: Oracle_Position,
	what: string,
	block, pos: int,
	loc := #caller_location,
) -> bool {
	for p in 0 ..< core.PLAYER_COUNT {
		for j in core.Joint {
			for axis in 0 ..< 3 {
				if !expect_bits(t, got[p][j][axis], want[p][int(j)][axis], what, block, loc) {
					testing.expectf(
						t,
						false,
						"  at position %d player %d joint %v axis %d",
						pos,
						p,
						j,
						axis,
						loc = loc,
					)
					return false
				}
			}
		}
	}
	return true
}

@(test)
test_transforms_match_oracle_ops :: proc(t: ^testing.T) {
	seqs, ok := parse_real_db(t)
	if !ok {
		return
	}
	defer core.sequences_destroy(seqs)

	state := Ops_State {
		t    = t,
		seqs = seqs,
	}
	path := oracle_path("ops.ndjson")
	lines, _, nerr := ndjson_each(path, &state, check_ops_line)
	testing.expectf(t, nerr == .None, "%s: %v", path, nerr)
	testing.expectf(t, lines > 0, "%s: no records", path)
	testing.expect_value(t, state.compared, lines)
	log.infof("%s: %d records compared", path, state.compared)
	// Outside the sample (the full dump), every position must have a record: a truncated file must not pass.
	if oracle_dir() != DEFAULT_ORACLE_DIR {
		positions := 0
		for s in seqs {
			positions += len(s.positions)
		}
		testing.expectf(
			t,
			lines == positions,
			"%s: %d records, %d positions",
			path,
			lines,
			positions,
		)
	}
}

// check_ops_line compares one record; it stops at the first record that differs (one report, not thousands).
@(private = "file")
check_ops_line :: proc(line: []byte, ctx: rawptr) -> bool {
	state := (^Ops_State)(ctx)
	t := state.t
	rec: Ops_Record
	if jerr := json.unmarshal(keep_negative_zero(line), &rec); jerr != nil {
		return testing.expectf(t, false, "ops.ndjson line %d: %v", state.compared + 1, jerr)
	}
	b, k := rec.block, rec.pos
	in_order := !state.have_last || b > state.last[0] || (b == state.last[0] && k > state.last[1])
	if !testing.expectf(
		t,
		in_order && b >= 0 && b < len(state.seqs) && k >= 0 && k < len(state.seqs[b].positions),
		"ops.ndjson: (block %d, pos %d) out of order or range (previous %v)",
		b,
		k,
		state.last,
	) {
		return false
	}
	state.last, state.have_last = {b, k}, true
	p := state.seqs[b].positions[k]

	ok := expect_position(t, core.mirror(p), rec.mirror, "mirror, block", b, k)
	ok &= expect_position(t, core.swap_players(p), rec.swap_players, "swap_players, block", b, k)
	h := core.heading(p)
	ok &= expect_bits(t, h.x, rec.heading[0], "heading x, block", b)
	ok &= expect_bits(t, h.y, rec.heading[1], "heading z, block", b)
	c := core.center(p)
	for axis in 0 ..< 3 {
		ok &= expect_bits(t, c[axis], rec.center[axis], "center, block", b)
	}
	ok &= expect_position(
		t,
		core.orient_canonically_with_mirror(p),
		rec.orient_canonically_with_mirror,
		"orient_canonically_with_mirror, block",
		b,
		k,
	)
	ok &= expect_position(
		t,
		core.orient_canonically_without_mirror(p),
		rec.orient_canonically_without_mirror,
		"orient_canonically_without_mirror, block",
		b,
		k,
	)
	if !ok {
		// The angle tells a wrong `atan2` (angle off) from a wrong `sin`/`cos` (same angle, rotation off).
		a := core.normal_rotation(p)
		testing.expectf(
			t,
			false,
			"  at block %d pos %d (normal_rotation %.17g, 0x%016x)",
			b,
			k,
			a,
			transmute(u64)a,
		)
	}
	state.compared += 1
	return ok
}
