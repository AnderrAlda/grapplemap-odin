package core

import "core:mem/virtual"
import "core:slice"
import "core:strings"
import "core:testing"

// Graph construction (graph.odin, src/graph.cpp:279-302). Text inputs go through `load_graph`; rotated and
// near-threshold cases through `build` with hand-made sequences (temp allocator; the graph's own data in its arena).

// gap_position: a non-degenerate position whose head-to-head squared distance grows with `d`. Values of `d` whose
// squares differ by more than HEAD_PREFILTER_SQ never match each other.
@(private = "file")
gap_position :: proc(d: f64) -> (p: Position) {
	for j in Joint {
		k := f64(j)
		p[0][j] = {0.01 * k, 0.1 + 0.05 * k, 0.02 * k}
		p[1][j] = {d + 0.03 * k, 0.1 + 0.04 * k, -0.01 * k}
	}
	return
}

@(private = "file")
translated :: proc(p: Position, v: V3) -> (q: Position) {
	for pl in 0 ..< PLAYER_COUNT {
		for j in Joint {
			q[pl][j] = p[pl][j] + v
		}
	}
	return
}

// A rotation, a mirror and a swap: the reorientation used to make "the same position, elsewhere".
@(private = "file")
TURN :: Position_Reorientation {
	reorientation = {offset = {0.3, 0, -0.2}, angle = 1.1},
	mirror = true,
	swap_players = true,
}

@(private = "file")
matches :: proc(a, b: Position) -> bool {
	_, ok := is_reoriented(a, b)
	return ok
}

@(private = "file")
seq_of :: proc(desc: []string, positions: ..Position) -> Sequence {
	return {
		description = slice.clone(desc, context.temp_allocator),
		positions = slice.clone(positions, context.temp_allocator),
	}
}

@(private = "file")
build_seqs :: proc(
	t: ^testing.T,
	seqs: []Sequence,
	loc := #caller_location,
) -> (
	g: Graph,
	ok: bool,
) {
	if !testing.expect_value(
		t,
		virtual.arena_init_growing(&g.arena),
		virtual.Allocator_Error.None,
		loc = loc,
	) {
		return {}, false
	}
	err := build(&g, seqs)
	if !testing.expectf(t, err == nil, "build: %v", err, loc = loc) {
		graph_destroy(&g)
		return {}, false
	}
	return g, true
}

@(private = "file")
load_text :: proc(t: ^testing.T, s: string, loc := #caller_location) -> (g: Graph, ok: bool) {
	err: Error
	g, err = load_graph(transmute([]byte)s)
	if !testing.expectf(t, err == nil, "load_graph: %v", err, loc = loc) {
		return {}, false
	}
	return g, true
}

@(private = "file")
expect_same_bits :: proc(t: ^testing.T, got, want: Position, loc := #caller_location) {
	g := transmute([size_of(Position) / 8]u64)got
	w := transmute([size_of(Position) / 8]u64)want
	testing.expect(t, g == w, "positions differ in their bits", loc = loc)
}

@(private = "file")
expect_zero_reorientation :: proc(
	t: ^testing.T,
	u: Position_Reorientation,
	loc := #caller_location,
) {
	r := u.reorientation
	testing.expect_value(t, transmute(u64)r.angle, 0, loc = loc)
	testing.expect_value(t, transmute([3]u64)r.offset, [3]u64{}, loc = loc)
	testing.expect(t, !u.mirror && !u.swap_players, "mirror/swap set", loc = loc)
}

@(test)
test_graph_empty :: proc(t: ^testing.T) {
	g, ok := load_text(t, "")
	if !ok {
		return
	}
	defer graph_destroy(&g)
	testing.expect_value(t, len(g.nodes), 0)
	testing.expect_value(t, len(g.edges), 0)
	testing.expect_value(t, g.named_count, 0)
}

@(test)
test_graph_named_nodes_first :: proc(t: ^testing.T) {
	// A transition before the named position: the named node is still 0, the edge 0, and both ends match it.
	s := strings.concatenate(
		{"T\n", pos_text(1), pos_text(2), "A\nmore\n", pos_text(3)},
		context.temp_allocator,
	)
	g, ok := load_text(t, s)
	if !ok {
		return
	}
	defer graph_destroy(&g)
	if !testing.expect_value(t, len(g.nodes), 1) || !testing.expect_value(t, len(g.edges), 1) {
		return
	}
	testing.expect_value(t, g.named_count, 1)
	n := g.nodes[0]
	testing.expect_value(t, len(n.description), 2)
	testing.expect_value(t, n.description[0], "A")
	testing.expect_value(t, n.line_nr, 11) // 0-based line of its first position line ("T" = 0, "A" = 9)
	testing.expect(
		t,
		n.incoming == nil && n.outgoing == nil && n.in_out == nil,
		"in/out are #173's",
	)
	e := g.edges[0]
	testing.expect_value(t, e.from.node, 0)
	testing.expect_value(t, e.to.node, 0)
	testing.expect_value(t, e.sequence.description[0], "T")
	testing.expect_value(t, len(e.sequence.positions), 2)
}

@(test)
test_graph_duplicate_description :: proc(t: ^testing.T) {
	p := pos_text()
	// Lines: block 0 = 1-2 description, 3-6 position; block 1 = 7, 8-15; block 2 = 16, 17-20; block 3 starts at
	// line 21. Block 2 sits between the duplicates, so comparing only with the last node pushed would miss it.
	// Releasing the arena on this error path is not observable here (virtual memory, outside the tracking allocator
	// and LeakSanitizer; `load_graph` returns `{}` either way): no test verifies it.
	s := strings.concatenate(
		{"A\nB\n", p, "T\n", p, p, "X\n", p, "A\nB\n", p},
		context.temp_allocator,
	)
	g, err := load_graph(transmute([]byte)s)
	testing.expect_value(
		t,
		err,
		Error(Graph_Error{kind = .Duplicate_Position_Description, line = 21, block = 3}),
	)
	testing.expect(
		t,
		g.nodes == nil && g.edges == nil && g.arena.curr_block == nil,
		"graph must be zero on error",
	)
}

@(test)
test_graph_same_first_line_is_not_duplicate :: proc(t: ^testing.T) {
	p := pos_text()
	s := strings.concatenate({"A\nB\n", p, "A\nC\n", p}, context.temp_allocator)
	g, ok := load_text(t, s)
	if !ok {
		return
	}
	defer graph_destroy(&g)
	testing.expect_value(t, len(g.nodes), 2)
	testing.expect_value(t, g.named_count, 2)
}

@(test)
test_graph_parse_error_unchanged :: proc(t: ^testing.T) {
	p := pos_text()
	s := strings.concatenate({"A\n", p[:len(p) - 1]}, context.temp_allocator) // no final newline
	s2 := strings.concatenate({"A\n", p, p[:80]}, context.temp_allocator) // truncated position
	for input in ([]string{s, s2}) {
		want_seqs, want := parse_db(transmute([]byte)input)
		testing.expect(t, want != nil && want_seqs == nil, "the input must be a parse error")
		g, err := load_graph(transmute([]byte)input)
		testing.expect_value(t, err, want)
		testing.expect(
			t,
			g.arena.curr_block == nil && g.nodes == nil,
			"graph must be zero on error",
		)
	}
}

@(test)
test_graph_named_never_merged :: proc(t: ^testing.T) {
	a := gap_position(1)
	seqs := []Sequence{seq_of({"A"}, a), seq_of({"B"}, reorient(TURN, a))}
	testing.expect(t, matches(a, reorient(TURN, a)), "the two positions must match")
	g, ok := build_seqs(t, seqs)
	if !ok {
		return
	}
	defer graph_destroy(&g)
	testing.expect_value(t, len(g.nodes), 2)
	testing.expect_value(t, g.named_count, 2)
}

@(test)
test_graph_anonymous_numbering :: proc(t: ^testing.T) {
	named := gap_position(0.5)
	f0 := gap_position(1)
	f0[0][.LeftKnee].x = -0.0 // kept as is in the anonymous node
	b0 := gap_position(1.5)
	f1 := gap_position(2)
	b1 := reorient(TURN, f0) // matches the node created for f0
	seqs := []Sequence {
		seq_of({"T0"}, f0, b0),
		seq_of({"N"}, named),
		seq_of({"T1"}, f1, gap_position(2.5), b1),
	}
	g, ok := build_seqs(t, seqs)
	if !ok {
		return
	}
	defer graph_destroy(&g)
	if !testing.expect_value(t, len(g.nodes), 4) || !testing.expect_value(t, len(g.edges), 2) {
		return
	}
	testing.expect_value(t, g.named_count, 1)
	for n in 1 ..< 4 {
		testing.expect_value(t, g.nodes[n].line_nr, NO_LINE)
		testing.expect(t, g.nodes[n].description == nil, "anonymous node with a description")
	}
	expect_same_bits(t, g.nodes[1].position, f0)
	expect_same_bits(t, g.nodes[2].position, b0)
	expect_same_bits(t, g.nodes[3].position, f1)
	e0, e1 := g.edges[0], g.edges[1]
	testing.expect_value(t, e0.from.node, 1)
	testing.expect_value(t, e0.to.node, 2)
	testing.expect_value(t, e1.from.node, 3)
	testing.expect_value(t, e1.to.node, 1)
	expect_zero_reorientation(t, e0.from.reorientation)
	expect_zero_reorientation(t, e0.to.reorientation)
	expect_zero_reorientation(t, e1.from.reorientation)
	want, matched := is_reoriented(f0, b1)
	testing.expect(t, matched, "b1 must match f0")
	testing.expect_value(t, e1.to.reorientation, want)
	testing.expect(t, e1.to.reorientation.swap_players, "the found reorientation, not a zero one")
	testing.expect_value(t, e1.sequence.description[0], "T1")
	testing.expect_value(t, len(e1.sequence.positions), 3)
}

@(test)
test_graph_lowest_index_wins :: proc(t: ^testing.T) {
	a := gap_position(1)
	b := translated(a, {0.01, 0, 0})
	end := b // exactly node 1, also within the threshold of node 0
	testing.expect(t, matches(a, end) && matches(b, end), "both nodes must match")
	seqs := []Sequence{seq_of({"A"}, a), seq_of({"B"}, b), seq_of({"T"}, end, gap_position(2))}
	g, ok := build_seqs(t, seqs)
	if !ok {
		return
	}
	defer graph_destroy(&g)
	if !testing.expect_value(t, len(g.edges), 1) {
		return
	}
	testing.expect_value(t, g.edges[0].from.node, 0)
	testing.expect_value(t, g.edges[0].to.node, 2)
}

@(test)
test_graph_self_loop :: proc(t: ^testing.T) {
	a := gap_position(1)
	seqs := []Sequence{seq_of({"T"}, a, gap_position(2), reorient(TURN, a))}
	g, ok := build_seqs(t, seqs)
	if !ok {
		return
	}
	defer graph_destroy(&g)
	testing.expect_value(t, len(g.nodes), 1)
	if testing.expect_value(t, len(g.edges), 1) {
		testing.expect_value(t, g.edges[0].from.node, 0)
		testing.expect_value(t, g.edges[0].to.node, 0)
	}
}

@(test)
test_graph_edge_flags :: proc(t: ^testing.T) {
	a, b := gap_position(1), gap_position(2)
	seqs := []Sequence{seq_of({"T0"}, a, b), seq_of({"T1"}, b, a), seq_of({"T2"}, a, a)}
	seqs[0].detailed = true
	seqs[1].bidirectional = true
	seqs[2].detailed = true
	seqs[2].bidirectional = true
	g, ok := build_seqs(t, seqs)
	if !ok {
		return
	}
	defer graph_destroy(&g)
	if !testing.expect_value(t, len(g.edges), 3) {
		return
	}
	for e, i in g.edges {
		testing.expect_value(t, e.sequence.detailed, seqs[i].detailed)
		testing.expect_value(t, e.sequence.bidirectional, seqs[i].bidirectional)
	}
}

@(test)
test_graph_destroy_releases_arena :: proc(t: ^testing.T) {
	s := strings.concatenate(
		{"A\n", pos_text(1), "T\n", pos_text(1), pos_text(2)},
		context.temp_allocator,
	)
	g, ok := load_text(t, s)
	if !ok {
		return
	}
	// `arena_destroy` zeroes `total_reserved` unconditionally, so it is checked before; the OS-level release of the
	// blocks is the stdlib's (`arena_growing_free_last_memory_block`).
	testing.expect(
		t,
		g.arena.total_reserved > 0 && g.arena.curr_block != nil,
		"the graph lives in its arena",
	)
	graph_destroy(&g)
	testing.expect(t, g.nodes == nil && g.edges == nil && g.named_count == 0, "graph not zeroed")
	testing.expect(t, g.arena.curr_block == nil && g.arena.total_reserved == 0, "arena not zeroed")
}
