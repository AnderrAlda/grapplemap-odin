package core

import "core:mem/virtual"
import "core:slice"
import "core:testing"

// Lookups by name (lookup.odin, src/metadata.cpp:66-124) over hand-made graphs built with `build`. Head-to-head
// distance grows with `d` in `gap_position`, so `gap_position(1)`, `gap_position(2)`... are different nodes.

@(private = "file")
gp :: proc(d: f64) -> (p: Position) {
	for j in Joint {
		k := f64(j)
		p[0][j] = {0.01 * k, 0.1 + 0.05 * k, 0.02 * k}
		p[1][j] = {d + 0.03 * k, 0.1 + 0.04 * k, -0.01 * k}
	}
	return
}

@(private = "file")
mk :: proc(desc: []string, line_nr: int, bidirectional: bool, ps: ..Position) -> Sequence {
	return {
		description = slice.clone(desc, context.temp_allocator),
		positions = slice.clone(ps, context.temp_allocator),
		line_nr = line_nr,
		bidirectional = bidirectional,
	}
}

@(private = "file")
build_lookup :: proc(
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
expect_node :: proc(t: ^testing.T, g: ^Graph, desc: string, want: int, loc := #caller_location) {
	n, ok := node_by_desc(g, desc)
	testing.expectf(
		t,
		ok && n == want,
		"node_by_desc(%q) = %v, %v; want %v",
		desc,
		n,
		ok,
		want,
		loc = loc,
	)
}

@(private = "file")
expect_no_node :: proc(t: ^testing.T, g: ^Graph, desc: string, loc := #caller_location) {
	n, ok := node_by_desc(g, desc)
	testing.expectf(t, !ok, "node_by_desc(%q) = %v, want not found", desc, n, loc = loc)
}

@(test)
test_first_line_matches :: proc(t: ^testing.T) {
	testing.expect(t, first_line_matches("a\\nb", "a b"), "backslash-n is a space")
	testing.expect(t, !first_line_matches("a\\nb", "a\\nb"), "the original text no longer matches")
	testing.expect(t, first_line_matches("\\\\n", "\\ "), "backslash, then backslash-n")
	testing.expect(t, !first_line_matches("\\\\n", "\\\\n"), "no overlapping replacement")
	testing.expect(t, first_line_matches("a\\", "a\\"), "a trailing lone backslash is itself")
	testing.expect(t, first_line_matches("a\\n", "a "), "trailing backslash-n")
	testing.expect(t, !first_line_matches("a\\nb", "a b "), "desc longer")
	testing.expect(t, !first_line_matches("a\\nb", "a"), "desc shorter")
	testing.expect(t, first_line_matches("", ""), "empty vs empty")
	testing.expect(t, !first_line_matches("", "a"), "empty line vs text")
	testing.expect(t, !first_line_matches("Ab", "ab"), "case-sensitive")
	testing.expect(t, !first_line_matches("a b", " a b"), "no trimming")
}

// Named nodes 0..4, then the anonymous ends of one edge: 5 and 6.
@(private = "file")
nodes_graph :: proc(t: ^testing.T) -> (g: Graph, ok: bool) {
	seqs := []Sequence {
		mk({"Alpha\\nBeta"}, 10, false, gp(1)),
		mk({"Dup", "second line"}, 11, false, gp(2)),
		mk({"Dup"}, 12, false, gp(3)),
		mk({"p1"}, 13, false, gp(4)),
		mk({""}, 14, false, gp(5)),
		mk({"T"}, 15, false, gp(6), gp(7)),
	}
	return build_lookup(t, seqs)
}

@(test)
test_node_by_desc_names :: proc(t: ^testing.T) {
	g, ok := nodes_graph(t)
	if !ok {
		return
	}
	defer graph_destroy(&g)
	testing.expect_value(t, len(g.nodes), 7)
	expect_node(t, &g, "Alpha Beta", 0)
	expect_no_node(t, &g, "Alpha\\nBeta")
	expect_no_node(t, &g, "alpha beta")
	expect_no_node(t, &g, " Alpha Beta")
	expect_no_node(t, &g, "Alpha Beta ")
	expect_node(t, &g, "Dup", 1) // lowest index wins
	expect_node(t, &g, "", 4) // a named position whose first line is empty; anonymous nodes 5, 6 never match
	expect_no_node(t, &g, "Missing")
}

@(test)
test_node_by_desc_index :: proc(t: ^testing.T) {
	g, ok := nodes_graph(t)
	if !ok {
		return
	}
	defer graph_destroy(&g)
	expect_node(t, &g, "p0", 0)
	expect_node(t, &g, "p006", 6) // like stoul: leading zeros allowed
	expect_node(t, &g, "p1", 1) // before any name lookup: the node named "p1" (3) is unreachable by name
	expect_no_node(t, &g, "p7") // == len(nodes): not handed out
	expect_node(t, &g, "p65536", 0) // wrapped to u16 like the original
	expect_no_node(t, &g, "p65537x")
	expect_no_node(t, &g, "p1x") // not all digits: name lookup, no such name
	expect_no_node(t, &g, "p") // too short: name lookup
	expect_no_node(t, &g, "p9999999999999999999999999") // does not fit a u64
	expect_no_node(t, &g, "P1")
}

// Named nodes 0..2 ("N0".."N2"), anonymous 3; edges:
// 0 "Move" N0→N1 · 1 "Move" N1→N2 · 2 "Bi" N2→N0 bidirectional · 3 "t4" N0→N1 · 4 "Other" N0→N2
// 5 "Loop" N1→N1 · 6 "N1" N0→N2 · 7 "l999" N0→N1 · 8 "Line" N1→N0 (line 200)
@(private = "file")
steps_graph :: proc(t: ^testing.T) -> (g: Graph, ok: bool) {
	a, b, c := gp(1), gp(2), gp(3)
	seqs := []Sequence {
		mk({"N0"}, 100, false, a),
		mk({"N1"}, 101, false, b),
		mk({"N2"}, 102, false, c),
		mk({"Move"}, 103, false, a, b),
		mk({"Move"}, 104, false, b, c),
		mk({"Bi"}, 105, true, c, a),
		mk({"t4"}, 106, false, a, b),
		mk({"Other"}, 107, false, a, c),
		mk({"Loop"}, 108, false, b, gp(4), b),
		mk({"N1"}, 109, false, a, c),
		mk({"l999"}, 110, false, a, b),
		mk({"Line"}, 200, false, b, a),
	}
	return build_lookup(t, seqs)
}

@(private = "file")
expect_step :: proc(
	t: ^testing.T,
	g: ^Graph,
	desc: string,
	from: Maybe(int),
	want: Step,
	loc := #caller_location,
) {
	s, ok := step_by_desc(g, desc, from)
	testing.expectf(
		t,
		ok && s == want,
		"step_by_desc(%q, %v) = %v, %v; want %v",
		desc,
		from,
		s,
		ok,
		want,
		loc = loc,
	)
}

@(private = "file")
expect_no_step :: proc(
	t: ^testing.T,
	g: ^Graph,
	desc: string,
	from: Maybe(int) = nil,
	loc := #caller_location,
) {
	s, ok := step_by_desc(g, desc, from)
	testing.expectf(t, !ok, "step_by_desc(%q, %v) = %v, want not found", desc, from, s, loc = loc)
}

@(test)
test_step_by_desc :: proc(t: ^testing.T) {
	g, ok := steps_graph(t)
	if !ok {
		return
	}
	defer graph_destroy(&g)
	if !testing.expect_value(t, len(g.edges), 9) {
		return
	}
	expect_step(t, &g, "Move", nil, {0, false}) // first candidate
	expect_step(t, &g, "Move", 0, {0, false})
	expect_step(t, &g, "Move", 1, {1, false}) // edge 0 starts elsewhere: the search goes on
	expect_no_step(t, &g, "Move", 2) // edge 1 ends at 2 but is not bidirectional
	expect_step(t, &g, "Bi", 2, {2, false})
	expect_step(t, &g, "Bi", 0, {2, true}) // bidirectional, entered from its `to`
	expect_no_step(t, &g, "Bi", 1)
	expect_step(t, &g, "t3", nil, {3, false}) // "t" + index; the edge is named "t4"
	expect_no_step(t, &g, "t03")
	expect_no_step(t, &g, "t")
	expect_no_step(t, &g, "t9")
	expect_no_step(t, &g, "t-1")
	expect_step(t, &g, "t4", nil, {3, false}) // by name (edge 3) before by index (edge 4)
	expect_step(t, &g, "t0", nil, {0, false})
	expect_step(t, &g, "Loop", 1, {5, false}) // self-loop
	expect_no_step(t, &g, "Loop", 3) // the middle position is another node: not an end
	expect_no_step(t, &g, "move")
}

@(private = "file")
expect_entity :: proc(
	t: ^testing.T,
	g: ^Graph,
	s: string,
	want: Named_Entity,
	loc := #caller_location,
) {
	e, ok := named_entity(g, s)
	testing.expectf(
		t,
		ok && e == want,
		"named_entity(%q) = %v, %v; want %v",
		s,
		e,
		ok,
		want,
		loc = loc,
	)
}

@(test)
test_named_entity :: proc(t: ^testing.T) {
	g, ok := steps_graph(t)
	if !ok {
		return
	}
	defer graph_destroy(&g)
	expect_entity(t, &g, "last-trans", Step{8, false})
	expect_entity(t, &g, "l100", Entity_Node{0}) // the node on line 100
	expect_entity(t, &g, "l200", Step{8, false}) // no node on that line: the edge
	expect_entity(t, &g, "l103", Step{0, false})
	expect_entity(t, &g, "l999", Step{7, false}) // no line 999: falls through to the transition named "l999"
	expect_entity(t, &g, "N1", Step{6, false}) // a transition and a node both named N1: the transition
	expect_entity(t, &g, "N0", Entity_Node{0})
	expect_entity(t, &g, "p2", Entity_Node{2}) // through the node lookup
	expect_entity(t, &g, "Move", Step{0, false})
	e, found := named_entity(&g, "nothing")
	testing.expectf(t, !found, "got %v", e)
	_, found = named_entity(&g, "l5")
	testing.expect(t, !found, "l5: no line, no name")
}

@(test)
test_named_entity_line_on_node_and_edge :: proc(t: ^testing.T) {
	a, b := gp(1), gp(2)
	seqs := []Sequence{mk({"A"}, 7, false, a), mk({"T"}, 7, false, a, b)}
	g, ok := build_lookup(t, seqs)
	if !ok {
		return
	}
	defer graph_destroy(&g)
	expect_entity(t, &g, "l7", Entity_Node{0}) // nodes before edges
	expect_entity(t, &g, "l4294967303", Entity_Node{0}) // 2^32 + 7 truncated to u32: line 7
}

@(test)
test_named_entity_line_overflow_is_a_name :: proc(t: ^testing.T) {
	name := "l9999999999999999999999999"
	seqs := []Sequence{mk({"A"}, 1, false, gp(1)), mk({name}, 2, false, gp(1), gp(2))}
	g, ok := build_lookup(t, seqs)
	if !ok {
		return
	}
	defer graph_destroy(&g)
	expect_entity(t, &g, name, Step{0, false}) // does not fit a u64: not an `l` name, found as a transition name
}

@(test)
test_named_entity_line_falls_to_node :: proc(t: ^testing.T) {
	seqs := []Sequence{mk({"l77"}, 5, false, gp(1))}
	g, ok := build_lookup(t, seqs)
	if !ok {
		return
	}
	defer graph_destroy(&g)
	expect_entity(t, &g, "l77", Entity_Node{0})
	_, found := named_entity(&g, "last-trans")
	testing.expect(t, !found, "no edges")
}
