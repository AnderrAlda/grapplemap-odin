package fidelity

import "app:core"
import "core:encoding/json"
import "core:slice"
import "core:testing"

// Parser fidelity: `core.parse_db` of the real DB against `sequences.ndjson` and `meta.json` (tools/oracle/README.md).
// `refs`/`notes` are derived by the dumper (the original has no parser for them) and not compared.

@(private = "file")
Meta :: struct {
	counts: struct {
		blocks:    int,
		positions: int,
	},
}

@(private = "file")
Q_Position :: [core.PLAYER_COUNT][core.JOINT_COUNT][3]int

@(private = "file")
Sequence_Record :: struct {
	index:         int,
	kind:          string,
	line_nr:       int,
	description:   []string,
	tags:          []string,
	properties:    []string,
	detailed:      bool,
	bidirectional: bool,
	positions_q:   []Q_Position,
}

@(private = "file")
Sequences_State :: struct {
	t:        ^testing.T,
	seqs:     []core.Sequence,
	compared: int,
}

@(test)
test_parse_db_matches_oracle_sequences :: proc(t: ^testing.T) {
	db, ok := load_db(t)
	if !ok {
		return
	}
	defer delete(db)
	seqs, err := core.parse_db(db)
	if !testing.expectf(t, err == nil, "parse_db(%s): %v", db_path(), err) {
		return
	}
	defer core.sequences_destroy(seqs)

	meta: Meta
	if !read_json(t, "meta.json", &meta, context.temp_allocator) {
		return
	}
	positions := 0
	for s in seqs {
		positions += len(s.positions)
	}
	testing.expect(t, meta.counts.blocks > 0, "meta.json: counts.blocks missing")
	testing.expect_value(t, len(seqs), meta.counts.blocks)
	testing.expect_value(t, positions, meta.counts.positions)

	state := Sequences_State {
		t    = t,
		seqs = seqs,
	}
	path := oracle_path("sequences.ndjson")
	lines, _, nerr := ndjson_each(path, &state, check_sequence_line)
	testing.expectf(t, nerr == .None, "%s: %v", path, nerr)
	testing.expectf(t, lines > 0, "%s: no records", path)
	testing.expect_value(t, state.compared, lines)
}

// check_sequence_line compares one record; it stops at the first record that differs (one report, not thousands).
@(private = "file")
check_sequence_line :: proc(line: []byte, ctx: rawptr) -> bool {
	state := (^Sequences_State)(ctx)
	t := state.t
	rec: Sequence_Record
	if jerr := json.unmarshal(line, &rec); jerr != nil {
		return testing.expectf(t, false, "sequences.ndjson record %d: %v", state.compared, jerr)
	}
	if !testing.expectf(
		t,
		rec.index >= 0 && rec.index < len(state.seqs),
		"sequences.ndjson: index %d out of range (%d sequences)",
		rec.index,
		len(state.seqs),
	) {
		return false
	}
	s := state.seqs[rec.index]
	i := rec.index
	ok := true
	ok &= testing.expectf(
		t,
		slice.equal(s.description, rec.description),
		"block %d description: got %q, want %q",
		i,
		s.description,
		rec.description,
	)
	ok &= testing.expectf(
		t,
		s.line_nr == rec.line_nr,
		"block %d line_nr: got %d, want %d",
		i,
		s.line_nr,
		rec.line_nr,
	)
	kind := "position" if len(s.positions) == 1 else "transition"
	ok &= testing.expectf(t, kind == rec.kind, "block %d kind: got %s, want %s", i, kind, rec.kind)
	tags, terr := core.tags_in_desc(s.description)
	ok &= testing.expectf(
		t,
		terr == nil && slice.equal(tags, rec.tags),
		"block %d tags: got %q, want %q",
		i,
		tags,
		rec.tags,
	)
	props, perr := core.properties_in_desc(s.description)
	ok &= testing.expectf(
		t,
		perr == nil && slice.equal(props, rec.properties),
		"block %d properties: got %q, want %q",
		i,
		props,
		rec.properties,
	)
	ok &= testing.expectf(
		t,
		s.detailed == rec.detailed,
		"block %d detailed: got %v, want %v",
		i,
		s.detailed,
		rec.detailed,
	)
	ok &= testing.expectf(
		t,
		s.bidirectional == rec.bidirectional,
		"block %d bidirectional: got %v, want %v",
		i,
		s.bidirectional,
		rec.bidirectional,
	)
	if !testing.expectf(
		t,
		len(s.positions) == len(rec.positions_q),
		"block %d: got %d positions, want %d",
		i,
		len(s.positions),
		len(rec.positions_q),
	) {
		return false
	}
	positions: for q, k in rec.positions_q {
		for p in 0 ..< core.PLAYER_COUNT {
			for j in core.Joint {
				for axis in 0 ..< 3 {
					want := f64(q[p][int(j)][axis]) / core.QUANT_SCALE
					if axis != 1 {
						want -= core.ENCODING_OFFSET_XZ
					}
					if !expect_bits(t, s.positions[k][p][j][axis], want, "coordinate", i) {
						testing.expectf(
							t,
							false,
							"  at position %d player %d joint %v axis %d",
							k,
							p,
							j,
							axis,
						)
						ok = false
						break positions
					}
				}
			}
		}
	}
	state.compared += 1
	return ok
}
