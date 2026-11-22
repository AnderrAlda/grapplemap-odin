package fidelity

import "app:core"
import "core:encoding/json"
import "core:testing"

// `core.between` against `between.ndjson` (tools/oracle/README.md): every consecutive pair of every transition at
// s = 0.25, 0.5, 0.75, bit for bit. `seq` is the original's `SeqNum`; not compared (no graph yet, #142).

@(private = "file")
Between_Record :: struct {
	block:    int,
	seq:      int,
	pos:      int,
	s:        f64,
	position: Oracle_Position,
}

@(private = "file")
BETWEEN_S := [3]f64{0.25, 0.5, 0.75}

@(private = "file")
Between_State :: struct {
	t:         ^testing.T,
	seqs:      []core.Sequence,
	compared:  int,
	last:      [3]int, // (block, pos, index of s) of the previous record: records come in that order
	have_last: bool,
}

@(test)
test_between_matches_oracle :: proc(t: ^testing.T) {
	seqs, ok := parse_real_db(t)
	if !ok {
		return
	}
	defer core.sequences_destroy(seqs)

	state := Between_State {
		t    = t,
		seqs = seqs,
	}
	path := oracle_path("between.ndjson")
	lines, _, nerr := ndjson_each(path, &state, check_between_line)
	testing.expectf(t, nerr == .None, "%s: %v", path, nerr)
	testing.expectf(t, lines > 0, "%s: no records", path)
	testing.expect_value(t, state.compared, lines)
	// Outside the sample (the full dump), every pair at every s must have a record.
	if oracle_dir() != DEFAULT_ORACLE_DIR {
		want := 0
		for s in seqs {
			if len(s.positions) > 1 {
				want += len(BETWEEN_S) * (len(s.positions) - 1)
			}
		}
		testing.expectf(t, lines == want, "%s: %d records, want %d", path, lines, want)
	}
}

@(private = "file")
check_between_line :: proc(line: []byte, ctx: rawptr) -> bool {
	state := (^Between_State)(ctx)
	t := state.t
	rec: Between_Record
	if jerr := json.unmarshal(keep_negative_zero(line), &rec); jerr != nil {
		return testing.expectf(t, false, "between.ndjson line %d: %v", state.compared + 1, jerr)
	}
	si := -1
	for v, i in BETWEEN_S {
		if transmute(u64)v == transmute(u64)rec.s {
			si = i
		}
	}
	b, k := rec.block, rec.pos
	if !testing.expectf(t, si >= 0, "between.ndjson: block %d pos %d: s = %.17g", b, k, rec.s) {
		return false
	}
	key := [3]int{b, k, si}
	in_order :=
		!state.have_last ||
		b > state.last[0] ||
		(b == state.last[0] && (k > state.last[1] || (k == state.last[1] && si > state.last[2])))
	if !testing.expectf(
		t,
		in_order && b >= 0 && b < len(state.seqs),
		"between.ndjson: (block %d, pos %d, s %v) out of order or range (previous %v)",
		b,
		k,
		rec.s,
		state.last,
	) {
		return false
	}
	positions := state.seqs[b].positions
	if !testing.expectf(
		t,
		len(positions) > 1 && k >= 0 && k + 1 < len(positions),
		"between.ndjson: block %d (%d positions) has no pair at pos %d",
		b,
		len(positions),
		k,
	) {
		return false
	}
	state.last, state.have_last = key, true
	got := core.between(positions[k], positions[k + 1], rec.s)
	if !expect_position(t, got, rec.position, "between, block", b, k) {
		testing.expectf(t, false, "  at s = %v", rec.s)
		return false
	}
	state.compared += 1
	return true
}
