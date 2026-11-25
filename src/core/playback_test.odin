package core

import "core:math"
import "core:mem"
import "core:slice"
import "core:testing"

// Playback (playback.odin: `follow`, `frames`, `smoothen`; src/graph_util.cpp:60-108, src/paths.cpp:8-52). Graphs are
// hand-made `Graph` values whose slices live in the temp allocator (playback never touches `Graph.arena`), so the end
// reorientations are chosen freely. Expected bits are literals computed with Python doubles, e.g. for the segment
// boundary and `smoothen`:
//
//     a, b = 0.2, 0.9; a + (b - a) * 1.0                        # 0.8999999999999999 = 0x3feccccccccccccc
//     lag = 0.6 + y if 0.6 + y < 0.83 else 0.83; last * lag + p * (1 - lag)

@(private = "file")
bits :: proc(x: f64) -> u64 {
	return transmute(u64)x
}

// uniform: every joint of both players at `{x, y, z}`.
@(private = "file")
uniform :: proc(x: f64, y: f64 = 0.5, z: f64 = 0.25) -> (p: Position) {
	for pl in 0 ..< PLAYER_COUNT {
		for j in Joint {
			p[pl][j] = {x, y, z}
		}
	}
	return
}

// varied: a non-degenerate position (distinct joints and players), shifted by `dx` in x.
@(private = "file")
varied :: proc(dx: f64) -> (p: Position) {
	for j in Joint {
		k := f64(j)
		p[0][j] = {dx + 0.01 * k, 0.1 + 0.05 * k, 0.02 * k}
		p[1][j] = {dx + 0.6 + 0.03 * k, 0.1 + 0.04 * k, 0.3 - 0.01 * k}
	}
	return
}

@(private = "file")
desc :: proc(lines: ..string) -> []string {
	return slice.clone(lines, context.temp_allocator)
}

@(private = "file")
seq_edge :: proc(
	d: []string,
	from, to: Reoriented_Node,
	positions: ..Position,
	detailed := false,
) -> Edge {
	return {
		sequence = {
			description = d,
			positions = slice.clone(positions, context.temp_allocator),
			detailed = detailed,
		},
		from = from,
		to = to,
	}
}

@(private = "file")
at :: proc(node: int, r := Position_Reorientation{}) -> Reoriented_Node {
	return {node = node, reorientation = r}
}

@(private = "file")
hand_graph :: proc(nodes: []Node, edges: []Edge) -> Graph {
	return {
		nodes = slice.clone(nodes, context.temp_allocator),
		edges = slice.clone(edges, context.temp_allocator),
	}
}

@(private = "file")
anon_nodes :: proc(n: int) -> []Node {
	return make([]Node, n, context.temp_allocator)
}

@(private = "file")
expect_same_bits :: proc(t: ^testing.T, got, want: Position, loc := #caller_location) -> bool {
	g := transmute([size_of(Position) / 8]u64)got
	w := transmute([size_of(Position) / 8]u64)want
	return testing.expect(t, g == w, "positions differ in their bits", loc = loc)
}

@(private = "file")
expect_same_reorientation :: proc(
	t: ^testing.T,
	got, want: Position_Reorientation,
	loc := #caller_location,
) {
	testing.expect_value(
		t,
		bits(got.reorientation.angle),
		bits(want.reorientation.angle),
		loc = loc,
	)
	testing.expect_value(
		t,
		transmute([3]u64)got.reorientation.offset,
		transmute([3]u64)want.reorientation.offset,
		loc = loc,
	)
	testing.expect_value(t, got.mirror, want.mirror, loc = loc)
	testing.expect_value(t, got.swap_players, want.swap_players, loc = loc)
}

// A rotation, a translation, a mirror and a swap: the stored frame of an edge that differs from its neighbour's.
@(private = "file")
TURN :: Position_Reorientation {
	reorientation = {offset = {0.3, 0, -0.2}, angle = 1.1},
	mirror = true,
	swap_players = true,
}

// line_graph: one edge 0 → 1 through `A`, `B`, `C` (x = 0.2, 0.9, 1.3), identity end reorientations.
@(private = "file")
line_graph :: proc(detailed := false) -> Graph {
	return hand_graph(
		anon_nodes(2),
		{
			seq_edge(
				desc("line"),
				at(0),
				at(1),
				uniform(0.2),
				uniform(0.9),
				uniform(1.3),
				detailed = detailed,
			),
		},
	)
}

@(test)
test_follow_frame_counts :: proc(t: ^testing.T) {
	g := line_graph()
	f, next, err := follow(&g, at(0), 0, 11, context.temp_allocator)
	testing.expect_value(t, err, nil)
	testing.expect_value(t, len(f), 2 * 12)
	testing.expect_value(t, next.node, 1)

	steps, ferr := frames(&g, {{seq = 0}}, 11, context.temp_allocator)
	testing.expect_value(t, ferr, nil)
	if testing.expect_value(t, len(steps), 1) {
		testing.expect_value(t, len(steps[0].frames), 2 * 12 - 1)
	}

	// `detailed`: 11 / 2 = 5 by integer division, 6 frames per segment.
	gd := line_graph(detailed = true)
	steps, ferr = frames(&gd, {{seq = 0}}, 11, context.temp_allocator)
	testing.expect_value(t, ferr, nil)
	if testing.expect_value(t, len(steps), 1) {
		testing.expect_value(t, len(steps[0].frames), 2 * 6 - 1)
	}

	// fpp = 1 + detailed → 0: one frame per segment at `0 / 0.0` = NaN (the original's `howfar / double(0)`).
	steps, ferr = frames(&gd, {{seq = 0}}, 1, context.temp_allocator)
	testing.expect_value(t, ferr, nil)
	if testing.expect_value(t, len(steps), 1) && testing.expect_value(t, len(steps[0].frames), 1) {
		testing.expect(t, math.is_nan(steps[0].frames[0][0][.Head].x), "k / 0 must be NaN")
	}
}

@(test)
test_follow_segment_boundary_repeats :: proc(t: ^testing.T) {
	g := line_graph()
	f, _, err := follow(&g, at(0), 0, 1, context.temp_allocator)
	testing.expect_value(t, err, nil)
	if !testing.expect_value(t, len(f), 4) {
		return
	}
	expect_same_bits(t, f[0], uniform(0.2))
	// between(A, B, 1) = 0.2 + (0.9 - 0.2) * 1 is not B ...
	testing.expect_value(t, bits(f[1][1][.Neck].x), 0x3feccccccccccccc)
	// ... and between(B, C, 0) is B (0.9 = 0x3feccccccccccccd).
	testing.expect_value(t, bits(f[2][1][.Neck].x), 0x3feccccccccccccd)
	expect_same_bits(t, f[2], uniform(0.9))
}

@(test)
test_frames_drops_last_frame_per_step :: proc(t: ^testing.T) {
	g := hand_graph(
		anon_nodes(3),
		{
			seq_edge(desc("one"), at(0), at(1), uniform(0.2), uniform(0.9)),
			seq_edge(desc("two"), at(1), at(2), uniform(0.9), uniform(1.3)),
		},
	)
	steps, err := frames(&g, {{seq = 0}, {seq = 1}}, 2, context.temp_allocator)
	testing.expect_value(t, err, nil)
	if !testing.expect_value(t, len(steps), 2) {
		return
	}
	testing.expect_value(t, len(steps[0].frames), 2)
	testing.expect_value(t, len(steps[1].frames), 2)
	// The kept frames are k = 0, 1 of 2; k = 2 (0.2 + 0.7 · 1, not bit-equal to 0.9) is dropped.
	expect_same_bits(t, steps[0].frames[0], uniform(0.2))
	expect_same_bits(t, steps[0].frames[1], between(uniform(0.2), uniform(0.9), 0.5))
	expect_same_bits(t, steps[1].frames[0], uniform(0.9))
}

@(test)
test_follow_direction_by_node :: proc(t: ^testing.T) {
	// Edge 1 goes 1 → 2 but is listed `reverse = true`: `frames` walks it forwards (direction by node equality,
	// `step.reverse` only picks the start node of the path).
	g := hand_graph(
		anon_nodes(3),
		{
			seq_edge(desc("one"), at(0), at(1), uniform(0.2), uniform(0.9)),
			seq_edge(desc("two"), at(1), at(2), uniform(0.9), uniform(1.3)),
		},
	)
	steps, err := frames(&g, {{seq = 0}, {seq = 1, reverse = true}}, 1, context.temp_allocator)
	testing.expect_value(t, err, nil)
	if testing.expect_value(t, len(steps), 2) && testing.expect_value(t, len(steps[1].frames), 1) {
		expect_same_bits(t, steps[1].frames[0], uniform(0.9))
	}

	// A reversed first step starts at its `to` and is walked backwards.
	steps, err = frames(&g, {{seq = 0, reverse = true}}, 1, context.temp_allocator)
	testing.expect_value(t, err, nil)
	if testing.expect_value(t, len(steps), 1) && testing.expect_value(t, len(steps[0].frames), 1) {
		expect_same_bits(t, steps[0].frames[0], uniform(0.9))
	}

	// `from` is tested first: a self-loop is walked forwards.
	loop := hand_graph(
		anon_nodes(1),
		{seq_edge(desc("loop"), at(0), at(0), uniform(0.2), uniform(0.9), uniform(0.2))},
	)
	f, next, ferr := follow(&loop, at(0), 0, 1, context.temp_allocator)
	testing.expect_value(t, ferr, nil)
	testing.expect_value(t, next.node, 0)
	if testing.expect_value(t, len(f), 4) {
		expect_same_bits(t, f[0], uniform(0.2))
		expect_same_bits(t, f[2], uniform(0.9))
	}
}

@(private = "file")
expect_not_connected :: proc(t: ^testing.T, err: Error, seq: int, loc := #caller_location) {
	ge, ok := err.(Graph_Error)
	if testing.expectf(t, ok, "expected Graph_Error, got %v", err, loc = loc) {
		testing.expect_value(t, ge.kind, Graph_Error_Kind.Step_Not_Connected, loc = loc)
		testing.expect_value(t, ge.block, seq, loc = loc)
		testing.expect_value(t, ge.line, 0, loc = loc)
	}
}

@(test)
test_follow_not_connected :: proc(t: ^testing.T) {
	g := hand_graph(
		anon_nodes(4),
		{
			seq_edge(desc("one"), at(0), at(1), uniform(0.2), uniform(0.9)),
			seq_edge(desc("two"), at(2), at(3), uniform(0.9), uniform(1.3)),
		},
	)
	track: mem.Tracking_Allocator
	mem.tracking_allocator_init(&track, context.allocator)
	defer mem.tracking_allocator_destroy(&track)
	alloc := mem.tracking_allocator(&track)

	f, _, err := follow(&g, at(0), 1, 11, alloc)
	expect_not_connected(t, err, 1)
	testing.expect(t, f == nil)
	for seq in ([]int{-1, 2, 99}) {
		f, _, err = follow(&g, at(0), seq, 11, alloc)
		expect_not_connected(t, err, seq)
		testing.expect(t, f == nil)
	}

	// The second step does not touch node 1: everything allocated for the first is freed.
	steps, ferr := frames(&g, {{seq = 0}, {seq = 1}}, 11, alloc)
	expect_not_connected(t, ferr, 1)
	testing.expect(t, steps == nil)
	steps, ferr = frames(&g, {{seq = 0}, {seq = 7}}, 11, alloc)
	expect_not_connected(t, ferr, 7)
	testing.expect(t, steps == nil)
	testing.expect_value(t, len(track.allocation_map), 0)
	testing.expect_value(t, len(track.bad_free_array), 0)
}

@(test)
test_follow_carries_reorientation :: proc(t: ^testing.T) {
	// Edge 1 is stored in another frame: its positions are `reorient(TURN, ·)` of what follows node 1.
	n1 := varied(0.4)
	g := hand_graph(
		anon_nodes(3),
		{
			seq_edge(desc("one"), at(0), at(1), varied(0), n1),
			seq_edge(
				desc("two"),
				at(1, TURN),
				at(2, TURN),
				reorient(TURN, n1),
				reorient(TURN, varied(0.8)),
			),
		},
	)
	start := Position_Reorientation {
		reorientation = {offset = {0.1, 0, 0.05}, angle = 0.3},
	}
	f, next, err := follow(&g, at(1, start), 1, 3, context.temp_allocator)
	testing.expect_value(t, err, nil)
	r := compose(inverse(TURN), start)
	testing.expect_value(t, next.node, 2)
	expect_same_reorientation(t, next.reorientation, compose(TURN, r))
	if !testing.expect_value(t, len(f), 4) {
		return
	}
	testing.expect(t, basically_same(f[0], reorient(start, n1)), "step starts where the node is")
	// Keyframes reoriented first, then interpolated: bit-exact, and not what the other order gives.
	a, b := reorient(r, reorient(TURN, n1)), reorient(r, reorient(TURN, varied(0.8)))
	expect_same_bits(t, f[1], between(a, b, f64(1) / f64(3)))
	mutant := reorient(
		r,
		between(reorient(TURN, n1), reorient(TURN, varied(0.8)), f64(1) / f64(3)),
	)
	testing.expect(t, mutant != f[1], "chosen case must tell the two orders apart")

	// Chained through `frames`: the first frame of step 2 is (basically) the dropped last frame of step 1.
	steps, ferr := frames(&g, {{seq = 0}, {seq = 1}}, 3, context.temp_allocator)
	testing.expect_value(t, ferr, nil)
	if testing.expect_value(t, len(steps), 2) {
		testing.expect(t, basically_same(steps[1].frames[0], n1), "step 2 continues step 1")
		testing.expect(
			t,
			basically_same(steps[1].frames[2], between(n1, varied(0.8), f64(2) / f64(3))),
			"step 2 goes on in step 1's frame",
		)
	}
}

@(test)
test_frames_captions :: proc(t: ^testing.T) {
	nodes := anon_nodes(3)
	nodes[1].description = desc(`end\nnode`, "second line")
	g := hand_graph(
		nodes,
		{
			seq_edge(desc(`plain\nname\n`, "more"), at(0), at(1), uniform(0.2), uniform(0.9)),
			seq_edge(desc("..."), at(0), at(1), uniform(0.2), uniform(0.9)),
			seq_edge(desc("..."), at(1), at(2), uniform(0.9), uniform(1.3)),
			seq_edge(desc("...", "x"), at(2), at(1), uniform(1.3), uniform(0.9)),
		},
	)
	cases := []struct {
		path: []Step,
		want: string,
	} {
		{{{seq = 0}}, "plain name "},
		{{{seq = 1}}, "end node"},
		{{{seq = 2}}, "..."},
		// Reached backwards (from node 1): still the stored `to`, node 1.
		{{{seq = 3, reverse = true}}, "end node"},
		// Backwards over an edge whose `to` (node 2) is anonymous: kept.
		{{{seq = 2, reverse = true}}, "..."},
	}
	track: mem.Tracking_Allocator
	mem.tracking_allocator_init(&track, context.allocator)
	defer mem.tracking_allocator_destroy(&track)
	alloc := mem.tracking_allocator(&track)
	for c in cases {
		steps, err := frames(&g, c.path, 1, alloc)
		testing.expect_value(t, err, nil)
		if testing.expect_value(t, len(steps), 1) {
			testing.expect_value(t, steps[0].caption, c.want)
		}
		frames_destroy(steps, alloc)
	}
	testing.expect_value(t, len(track.allocation_map), 0)
	testing.expect_value(t, len(track.bad_free_array), 0)
}

@(test)
test_frames_empty_path :: proc(t: ^testing.T) {
	g := line_graph()
	track: mem.Tracking_Allocator
	mem.tracking_allocator_init(&track, context.allocator)
	defer mem.tracking_allocator_destroy(&track)
	steps, err := frames(&g, nil, 11, mem.tracking_allocator(&track))
	testing.expect_value(t, err, nil)
	testing.expect(t, steps == nil)
	testing.expect_value(t, track.total_allocation_count, 0)
}

@(private = "file")
one_frame :: proc(p: Position) -> []Frame_Step {
	fs := make([]Position, 1, context.temp_allocator)
	fs[0] = p
	steps := make([]Frame_Step, 1, context.temp_allocator)
	steps[0] = {
		frames = fs,
	}
	return steps
}

@(test)
test_smoothen_one_frame :: proc(t: ^testing.T) {
	// The first frame is computed, not copied: p·lag + p·(1 − lag) with lag = 0.83 (y = 0.5) is 1 ulp below 0.789.
	steps := one_frame(uniform(0.789, 0.5))
	smoothen(steps)
	testing.expect_value(t, bits(steps[0].frames[0][0][.LeftToe].x), 0x3fe93f7ced916872)
	testing.expect_value(t, bits(steps[0].frames[0][1][.Head].z), bits(0.25)) // 0.25·0.83 + 0.25·0.17

	// y = 0.23: 0.6 + y == 0.83, not below it → 0.83 (same value either way).
	steps = one_frame(uniform(0.789, 0.23))
	smoothen(steps)
	testing.expect_value(t, bits(steps[0].frames[0][0][.Core].x), 0x3fe93f7ced916872)

	// y = 0.05: lag = 0.6 + y = 0.65; 0.456 becomes 0.45599999999999996.
	steps = one_frame(uniform(0.456, 0.05))
	smoothen(steps)
	testing.expect_value(t, bits(steps[0].frames[0][1][.Neck].x), 0x3fdd2f1a9fbe76c8)
	// y = 0.1: lag = 0.7; 0.789 stays (with 0.83 it would move).
	steps = one_frame(uniform(0.789, 0.1))
	smoothen(steps)
	testing.expect_value(t, bits(steps[0].frames[0][0][.Neck].x), 0x3fe93f7ced916873)

	// NaN y: `std::min(0.83, NaN)` is 0.83 (NaN < 0.83 is false), so x still moves by 1 ulp.
	steps = one_frame(uniform(0.789, math.nan_f64()))
	smoothen(steps)
	testing.expect_value(t, bits(steps[0].frames[0][0][.Head].x), 0x3fe93f7ced916872)
}

@(test)
test_smoothen_state_crosses_steps :: proc(t: ^testing.T) {
	a := make([]Position, 1, context.temp_allocator)
	b := make([]Position, 1, context.temp_allocator)
	a[0], b[0] = uniform(0.5), uniform(1.0)
	steps := []Frame_Step{{frames = a}, {frames = b}}
	smoothen(steps)
	// 0.5·0.83 + 1.0·0.17 = 0.585 (0x3fe2b851eb851eb8); smoothed alone, step 2 would stay at 1.0.
	testing.expect_value(t, bits(b[0][0][.Head].x), 0x3fe2b851eb851eb8)
	testing.expect_value(t, bits(a[0][0][.Head].x), bits(0.5))

	alone := []Frame_Step{{frames = slice.clone([]Position{uniform(1.0)}, context.temp_allocator)}}
	smoothen(alone)
	testing.expect_value(t, bits(alone[0].frames[0][0][.Head].x), bits(1.0))
}

@(test)
test_smoothen_empty :: proc(t: ^testing.T) {
	smoothen(nil)
	empty_first := []Frame_Step {
		{},
		{frames = slice.clone([]Position{uniform(0.789)}, context.temp_allocator)},
	}
	smoothen(empty_first)
	testing.expect_value(t, bits(empty_first[1].frames[0][0][.Head].x), bits(0.789))
	// A later empty step is skipped; the state carries over it.
	later := []Frame_Step {
		{frames = slice.clone([]Position{uniform(0.5)}, context.temp_allocator)},
		{},
		{frames = slice.clone([]Position{uniform(1.0)}, context.temp_allocator)},
	}
	smoothen(later)
	testing.expect_value(t, bits(later[2].frames[0][0][.Head].x), 0x3fe2b851eb851eb8)
}
