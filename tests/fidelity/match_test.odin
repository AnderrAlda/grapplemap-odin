package fidelity

import "app:core"
import "core:bytes"
import "core:encoding/json"
import "core:log"
import "core:testing"

// Node matching of `core` (match.odin) against `graph.ndjson` (tools/oracle/README.md): for every transition,
// `is_reoriented(node position, sequence end)` (the original's argument order, src/graph.cpp:216) matches and gives
// `reorientation_from` (first position) and `reorientation_to` (last position) bit for bit. The lowest-index rule
// and the numbering of anonymous nodes are graph_test.odin's.

@(private = "file")
Graph_Node :: struct {
	index:      int,
	block:      Maybe(int), // null for an anonymous node
	position_q: [core.PLAYER_COUNT][core.JOINT_COUNT][3]int,
}

// Oracle_Reorientation is a `PositionReorientation` as the dumper writes it (graph.ndjson, compose.ndjson).
Oracle_Reorientation :: struct {
	translation: [3]f64,
	angle:       f64,
	swap:        bool,
	mirror:      bool,
}

@(private = "file")
Graph_Transition :: struct {
	block:              int,
	from, to:           int,
	reorientation_from: Oracle_Reorientation,
	reorientation_to:   Oracle_Reorientation,
}

@(private = "file")
Match_State :: struct {
	t:           ^testing.T,
	seqs:        []core.Sequence,
	nodes:       map[int]core.Position,
	transitions: int, // transition lines seen
	compared:    int, // transitions whose two ends matched
}

@(test)
test_node_matching_matches_oracle_graph :: proc(t: ^testing.T) {
	seqs, ok := parse_real_db(t)
	if !ok {
		return
	}
	defer core.sequences_destroy(seqs)

	state := Match_State {
		t     = t,
		seqs  = seqs,
		// Made here, with the test's allocator: a map keeps the allocator it was made with, so the inserts in
		// `check_graph_line` (where `context.allocator` is the per-line arena) never land in the arena.
		nodes = make(map[int]core.Position),
	}
	defer delete(state.nodes)
	path := oracle_path("graph.ndjson")
	_, _, nerr := ndjson_each(path, &state, check_graph_line)
	testing.expectf(t, nerr == .None, "%s: %v", path, nerr)
	testing.expectf(t, state.transitions > 0, "%s: no transitions", path)
	testing.expect_value(t, state.compared, state.transitions)
	log.infof("%s: %d nodes, %d transitions compared", path, len(state.nodes), state.compared)
}

// check_graph_line decodes one line by its type; it stops at the first mismatch (one report, not thousands).
@(private = "file")
check_graph_line :: proc(line: []byte, ctx: rawptr) -> bool {
	state := (^Match_State)(ctx)
	t := state.t
	switch {
	case bytes.has_prefix(line, transmute([]byte)string(`{"type":"node",`)):
		// Not rewritten by keep_negative_zero: it has strings, and only integer coordinates.
		node: Graph_Node
		if jerr := json.unmarshal(line, &node); jerr != nil {
			return testing.expectf(t, false, "graph.ndjson node: %v", jerr)
		}
		p := decode_position_q(node.position_q)
		if b, named := node.block.?; named {
			if !testing.expectf(
				t,
				b >= 0 && b < len(state.seqs),
				"node %d: block %d",
				node.index,
				b,
			) {
				return false
			}
			want := to_oracle_position(state.seqs[b].positions[0])
			if !expect_position(t, p, want, "named node position, block", b, 0) {
				return false
			}
		}
		if !testing.expectf(t, node.index not_in state.nodes, "node %d: repeated", node.index) {
			return false
		}
		state.nodes[node.index] = p
		return true
	case bytes.has_prefix(line, transmute([]byte)string(`{"type":"transition",`)):
		state.transitions += 1
		tr: Graph_Transition
		if jerr := json.unmarshal(keep_negative_zero(line), &tr); jerr != nil {
			return testing.expectf(t, false, "graph.ndjson transition: %v", jerr)
		}
		b := tr.block
		if !testing.expectf(t, b >= 0 && b < len(state.seqs), "transition: block %d", b) {
			return false
		}
		positions := state.seqs[b].positions
		ok := check_end(t, state, tr.from, positions[0], tr.reorientation_from, b, "from")
		ok =
			ok &&
			check_end(t, state, tr.to, positions[len(positions) - 1], tr.reorientation_to, b, "to")
		if ok {
			state.compared += 1
		}
		return ok
	case bytes.has_prefix(line, transmute([]byte)string(`{"type":"index",`)):
		return true // the `.index` pairs are #142's
	}
	return testing.expectf(t, false, "graph.ndjson: unknown line type: %.40s", string(line))
}

// check_end: `is_reoriented(nodes[node], end)` matches and equals `want` bit for bit.
@(private = "file")
check_end :: proc(
	t: ^testing.T,
	state: ^Match_State,
	node: int,
	end: core.Position,
	want: Oracle_Reorientation,
	block: int,
	which: string,
) -> bool {
	a, found := state.nodes[node]
	if !testing.expectf(t, found, "block %d %s: node %d not in graph.ndjson", block, which, node) {
		return false
	}
	u, matched := core.is_reoriented(a, end)
	if !testing.expectf(t, matched, "block %d %s: node %d does not match", block, which, node) {
		return false
	}
	ok := expect_reorientation(t, u, want, block)
	if !ok {
		testing.expectf(t, false, "  at block %d end %s (node %d)", block, which, node)
	}
	return ok
}

// to_oracle_position: a `core.Position` in the dumper's layout, for `expect_position`.
to_oracle_position :: proc(p: core.Position) -> Oracle_Position {
	o: Oracle_Position
	for pl in 0 ..< core.PLAYER_COUNT {
		for j in core.Joint {
			o[pl][int(j)] = p[pl][j]
		}
	}
	return o
}

// decode_position_q: the dumper's quantized `position_q` with the parser's formula (parse.odin), so the same bits.
decode_position_q :: proc(q: [core.PLAYER_COUNT][core.JOINT_COUNT][3]int) -> (p: core.Position) {
	for pl in 0 ..< core.PLAYER_COUNT {
		for j in core.Joint {
			for axis in 0 ..< 3 {
				v := f64(q[pl][int(j)][axis]) / core.QUANT_SCALE
				p[pl][j][axis] = v if axis == 1 else v - core.ENCODING_OFFSET_XZ
			}
		}
	}
	return
}

// expect_reorientation: `u` equals the oracle's `want` bit for bit (angle, translation, swap, mirror).
expect_reorientation :: proc(
	t: ^testing.T,
	u: core.Position_Reorientation,
	want: Oracle_Reorientation,
	block: int,
	loc := #caller_location,
) -> bool {
	r := u.reorientation
	ok := expect_bits(t, r.angle, want.angle, "angle, block", block, loc)
	for axis in 0 ..< 3 {
		ok &= expect_bits(
			t,
			r.offset[axis],
			want.translation[axis],
			"translation, block",
			block,
			loc,
		)
	}
	ok &= testing.expectf(t, u.swap_players == want.swap, "swap, block %d", block, loc = loc)
	ok &= testing.expectf(t, u.mirror == want.mirror, "mirror, block %d", block, loc = loc)
	return ok
}
