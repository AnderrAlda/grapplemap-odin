package fidelity

import "app:core"
import "core:bytes"
import "core:encoding/json"
import "core:log"
import "core:testing"

// Graph construction of `core` (graph.odin) against `graph.ndjson` and `meta.json` (tools/oracle/README.md):
// counts, the node numbering (named first, lowest index wins, anonymous nodes in order front, back, next front…),
// every dumped node's description and position, every dumped transition's ends and reorientations, bit for bit.
// The `index` line holds the pairs of **all** transitions even in the sample, so the numbering is checked whole.

@(private = "file")
Graph_Meta :: struct {
	index_consistent: bool, // the `.index` pairs equal loadGraph's numbering (tools/oracle/README.md)
	counts:           struct {
		named_positions: int,
		transitions:     int,
		nodes:           int,
		anonymous_nodes: int,
	},
}

@(private = "file")
Node_Line :: struct {
	index:       int,
	block:       Maybe(int), // null for an anonymous node
	description: []string,
	position_q:  [core.PLAYER_COUNT][core.JOINT_COUNT][3]int,
}

@(private = "file")
Transition_Line :: struct {
	index:              int,
	block:              int,
	from, to:           int,
	reorientation_from: Oracle_Reorientation,
	reorientation_to:   Oracle_Reorientation,
}

@(private = "file")
Index_Line :: struct {
	pairs: [][2]int,
}

@(private = "file")
Graph_State :: struct {
	t:           ^testing.T,
	g:           ^core.Graph,
	seqs:        []core.Sequence,
	nodes:       int, // node lines checked
	transitions: int, // transition lines checked
	pairs:       int, // index pairs checked (-1 until the index line)
}

@(test)
test_graph_matches_oracle :: proc(t: ^testing.T) {
	db, ok := load_db(t)
	if !ok {
		return
	}
	defer delete(db)
	g, err := core.load_graph(db)
	if !testing.expectf(t, err == nil, "load_graph(%s): %v", db_path(), err) {
		return
	}
	defer core.graph_destroy(&g)
	seqs, perr := core.parse_db(db)
	if !testing.expectf(t, perr == nil, "parse_db: %v", perr) {
		return
	}
	defer core.sequences_destroy(seqs)

	meta: Graph_Meta
	if !read_json(t, "meta.json", &meta, context.temp_allocator) {
		return
	}
	// The `index` pairs come from the original's `.index` file; this makes them `loadGraph`'s numbering.
	testing.expect(t, meta.index_consistent, "meta.json: index_consistent is not true")
	c := meta.counts
	testing.expect(t, c.nodes > 0 && c.transitions > 0, "meta.json: counts missing")
	testing.expect_value(t, len(g.nodes), c.nodes)
	testing.expect_value(t, g.named_count, c.named_positions)
	testing.expect_value(t, len(g.nodes) - g.named_count, c.anonymous_nodes)
	testing.expect_value(t, len(g.edges), c.transitions)

	state := Graph_State {
		t     = t,
		g     = &g,
		seqs  = seqs,
		pairs = -1,
	}
	path := oracle_path("graph.ndjson")
	_, _, nerr := ndjson_each(path, &state, check_graph_ndjson_line)
	testing.expectf(t, nerr == .None, "%s: %v", path, nerr)
	testing.expectf(
		t,
		state.nodes > 0 && state.transitions > 0,
		"%s: no nodes or transitions",
		path,
	)
	testing.expect_value(t, state.pairs, len(g.edges))
	log.infof(
		"%s: %d nodes, %d transitions, %d pairs checked",
		path,
		state.nodes,
		state.transitions,
		state.pairs,
	)
}

// check_graph_ndjson_line decodes one line by its type; it stops at the first mismatch.
@(private = "file")
check_graph_ndjson_line :: proc(line: []byte, ctx: rawptr) -> bool {
	state := (^Graph_State)(ctx)
	t := state.t
	g := state.g
	switch {
	case bytes.has_prefix(line, transmute([]byte)string(`{"type":"node",`)):
		// Not rewritten by keep_negative_zero: it has strings, and only integer coordinates.
		nl: Node_Line
		if jerr := json.unmarshal(line, &nl); jerr != nil {
			return testing.expectf(t, false, "graph.ndjson node: %v", jerr)
		}
		i := nl.index
		if !testing.expectf(t, i >= 0 && i < len(g.nodes), "node %d: out of range", i) {
			return false
		}
		n := g.nodes[i]
		b, named := nl.block.?
		ok := testing.expectf(t, named == (i < g.named_count), "node %d: named %v", i, named)
		if named {
			ok &= testing.expectf(
				t,
				b >= 0 && b < len(state.seqs) && n.line_nr == state.seqs[b].line_nr,
				"node %d: block %d, line_nr %d",
				i,
				b,
				n.line_nr,
			)
		} else {
			ok &= testing.expect_value(t, n.line_nr, core.NO_LINE)
		}
		ok &= testing.expectf(
			t,
			equal_strings(n.description, nl.description),
			"node %d: description %v, want %v",
			i,
			n.description,
			nl.description,
		)
		want := to_oracle_position(decode_position_q(nl.position_q))
		ok = ok && expect_position(t, n.position, want, "node position, node", i, 0)
		state.nodes += 1
		return ok
	case bytes.has_prefix(line, transmute([]byte)string(`{"type":"transition",`)):
		tl: Transition_Line
		if jerr := json.unmarshal(keep_negative_zero(line), &tl); jerr != nil {
			return testing.expectf(t, false, "graph.ndjson transition: %v", jerr)
		}
		i, b := tl.index, tl.block
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
		ok := testing.expectf(
			t,
			e.sequence.line_nr == state.seqs[b].line_nr,
			"edge %d: line_nr %d, block %d has %d",
			i,
			e.sequence.line_nr,
			b,
			state.seqs[b].line_nr,
		)
		ok &= testing.expectf(
			t,
			e.from.node == tl.from,
			"edge %d from: %d, want %d",
			i,
			e.from.node,
			tl.from,
		)
		ok &= testing.expectf(
			t,
			e.to.node == tl.to,
			"edge %d to: %d, want %d",
			i,
			e.to.node,
			tl.to,
		)
		ok = ok && expect_reorientation(t, e.from.reorientation, tl.reorientation_from, b)
		ok = ok && expect_reorientation(t, e.to.reorientation, tl.reorientation_to, b)
		state.transitions += 1
		return ok
	case bytes.has_prefix(line, transmute([]byte)string(`{"type":"index",`)):
		il: Index_Line
		if jerr := json.unmarshal(line, &il); jerr != nil {
			return testing.expectf(t, false, "graph.ndjson index: %v", jerr)
		}
		if !testing.expect_value(t, len(il.pairs), len(g.edges)) {
			return false
		}
		for pair, i in il.pairs {
			e := g.edges[i]
			if !check_end_node(t, g, i, "from", e.from.node, pair[0], e.sequence.positions[0]) ||
			   !check_end_node(
					   t,
					   g,
					   i,
					   "to",
					   e.to.node,
					   pair[1],
					   e.sequence.positions[len(e.sequence.positions) - 1],
				   ) {
				return false
			}
		}
		state.pairs = len(il.pairs)
		return true
	}
	return testing.expectf(t, false, "graph.ndjson: unknown line type: %.40s", string(line))
}

// check_end_node: the end of edge `i` is node `want`. A mismatch is a discrete decision, never a tolerance (ADR 0003
// decision 6): the report says whether the expected node also matches, for diagnosis.
@(private = "file")
check_end_node :: proc(
	t: ^testing.T,
	g: ^core.Graph,
	i: int,
	which: string,
	got, want: int,
	end: core.Position,
) -> bool {
	if got == want {
		return true
	}
	also := false
	if want >= 0 && want < len(g.nodes) {
		_, also = core.is_reoriented(g.nodes[want].position, end)
	}
	return testing.expectf(
		t,
		false,
		"edge %d %s: node %d, want %d (expected node matches too: %v)",
		i,
		which,
		got,
		want,
		also,
	)
}

@(private = "file")
equal_strings :: proc(a, b: []string) -> bool {
	if len(a) != len(b) {
		return false
	}
	for s, k in a {
		if s != b[k] {
			return false
		}
	}
	return true
}
