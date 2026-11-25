package fidelity

import "app:core"
import "core:bytes"
import "core:encoding/json"
import "core:log"
import "core:testing"

// `inverse` and `compose` of `core` (reorient.odin) against `compose.ndjson` (tools/oracle/README.md): for every dumped
// transition (`seq` = edge index), on its two end reorientations `Ef`, `Et`: `inverse(Ef)`, `inverse(Et)`,
// `compose(Ef, Et)` and `compose(inverse(Ef), Et)`, bit for bit. Every line is checked, and their number is that of the
// transition lines of `graph.ndjson` (the same transitions, in the sample and in the full dump), so an empty or
// truncated file cannot pass.

@(private = "file")
Compose_Line :: struct {
	block:                   int,
	seq:                     int,
	inverse_from:            Oracle_Reorientation,
	inverse_to:              Oracle_Reorientation,
	compose_from_to:         Oracle_Reorientation,
	compose_inverse_from_to: Oracle_Reorientation,
}

@(private = "file")
Compose_State :: struct {
	t:        ^testing.T,
	g:        ^core.Graph,
	seqs:     []core.Sequence,
	compared: int, // lines whose four results matched
}

@(test)
test_compose_inverse_match_oracle :: proc(t: ^testing.T) {
	seqs, ok := parse_real_db(t)
	if !ok {
		return
	}
	defer core.sequences_destroy(seqs)
	g, gok := shared_graph(t)
	if !gok {
		return
	}

	state := Compose_State {
		t    = t,
		g    = g,
		seqs = seqs,
	}
	path := oracle_path("compose.ndjson")
	lines, _, nerr := ndjson_each(path, &state, check_compose_line)
	testing.expectf(t, nerr == .None, "%s: %v", path, nerr)
	testing.expectf(t, lines > 0, "%s: empty", path)
	testing.expect_value(t, state.compared, lines)

	graph_path := oracle_path("graph.ndjson")
	transitions := 0
	_, _, gerr := ndjson_each(graph_path, &transitions, count_transition_line)
	testing.expectf(t, gerr == .None, "%s: %v", graph_path, gerr)
	testing.expect_value(t, lines, transitions)
	log.infof("%s: %d transitions checked", path, state.compared)
}

@(private = "file")
count_transition_line :: proc(line: []byte, ctx: rawptr) -> bool {
	if bytes.has_prefix(line, transmute([]byte)string(`{"type":"transition",`)) {
		(^int)(ctx)^ += 1
	}
	return true
}

// check_compose_line compares one line; it stops at the first mismatch.
@(private = "file")
check_compose_line :: proc(line: []byte, ctx: rawptr) -> bool {
	state := (^Compose_State)(ctx)
	t := state.t
	g := state.g
	cl: Compose_Line
	if jerr := json.unmarshal(keep_negative_zero(line), &cl); jerr != nil {
		return testing.expectf(t, false, "compose.ndjson: %v", jerr)
	}
	i, b := cl.seq, cl.block
	if !testing.expectf(
		t,
		i >= 0 && i < len(g.edges) && b >= 0 && b < len(state.seqs),
		"transition %d (block %d): out of range",
		i,
		b,
	) {
		return false
	}
	e := g.edges[i]
	if !testing.expectf(
		t,
		e.sequence.line_nr == state.seqs[b].line_nr,
		"edge %d: line_nr %d, block %d has %d",
		i,
		e.sequence.line_nr,
		b,
		state.seqs[b].line_nr,
	) {
		return false
	}
	ef := e.from.reorientation
	et := e.to.reorientation
	ok := expect_reorientation(t, core.inverse(ef), cl.inverse_from, b)
	ok &= expect_reorientation(t, core.inverse(et), cl.inverse_to, b)
	ok &= expect_reorientation(t, core.compose(ef, et), cl.compose_from_to, b)
	ok &= expect_reorientation(
		t,
		core.compose(core.inverse(ef), et),
		cl.compose_inverse_from_to,
		b,
	)
	if ok {
		state.compared += 1
	}
	return ok
}
