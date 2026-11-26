package core

import "core:slice"
import "core:testing"

// Timed playback (timed.odin; src/playback.cpp:102-176, src/graph_util.cpp:232-245). Hand-made graphs in the temp
// allocator, as in playback_test.odin. Expected `how_far`/`wait` bits are literals computed with a Python port of
// `Playback::progress` (same operations, Python doubles), e.g.:
//
//     hf = 0.0; hf += 0.33 * 5; seconds = (hf - 1) / 5; hf = 0.0; hf += seconds * 5   # 0.6500000000000001
//     wait = 0.8; wait -= 0.5                                                          # 0.30000000000000004

@(private = "file")
tbits :: proc(x: f64) -> u64 {
	return transmute(u64)x
}

// line_position: every joint of both players at `{x, 0.5, 0.25}`.
@(private = "file")
line_position :: proc(x: f64) -> (p: Position) {
	for pl in 0 ..< PLAYER_COUNT {
		for j in Joint {
			p[pl][j] = {x, 0.5, 0.25}
		}
	}
	return
}

// shape: a non-degenerate position (distinct joints and players), shifted by `dx` in x.
@(private = "file")
shape :: proc(dx: f64) -> (p: Position) {
	for j in Joint {
		k := f64(j)
		p[0][j] = {dx + 0.01 * k, 0.1 + 0.05 * k, 0.02 * k}
		p[1][j] = {dx + 0.6 + 0.03 * k, 0.1 + 0.04 * k, 0.3 - 0.01 * k}
	}
	return
}

@(private = "file")
edge_of :: proc(from, to: Reoriented_Node, positions: []Position, detailed := false) -> Edge {
	return {
		sequence = {
			description = slice.clone([]string{"step"}, context.temp_allocator),
			positions = slice.clone(positions, context.temp_allocator),
			detailed = detailed,
			bidirectional = true,
		},
		from = from,
		to = to,
	}
}

@(private = "file")
graph_of :: proc(node_count: int, edges: []Edge) -> Graph {
	return {
		nodes = make([]Node, node_count, context.temp_allocator),
		edges = slice.clone(edges, context.temp_allocator),
	}
}

@(private = "file")
node_at :: proc(node: int, r := Position_Reorientation{}) -> Reoriented_Node {
	return {node = node, reorientation = r}
}

@(private = "file")
SPIN :: Position_Reorientation {
	reorientation = {offset = {0.3, 0, -0.2}, angle = 1.1},
	mirror = true,
	swap_players = true,
}

@(private = "file")
TILT :: Position_Reorientation {
	reorientation = {offset = {-0.1, 0, 0.4}, angle = -0.7},
}

@(private = "file")
expect_reorientation :: proc(
	t: ^testing.T,
	got, want: Position_Reorientation,
	loc := #caller_location,
) {
	testing.expect_value(
		t,
		tbits(got.reorientation.angle),
		tbits(want.reorientation.angle),
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

@(private = "file")
expect_position_bits :: proc(t: ^testing.T, got, want: Position, loc := #caller_location) -> bool {
	g := transmute([size_of(Position) / 8]u64)got
	w := transmute([size_of(Position) / 8]u64)want
	return testing.expect(t, g == w, "positions differ in their bits", loc = loc)
}

@(private = "file")
expect_state :: proc(
	t: ^testing.T,
	p: Timed_Playback,
	i, segment: int,
	how_far: u64,
	wait: u64 = 0,
	at_end := false,
	loc := #caller_location,
) {
	testing.expect_value(t, p.i, i, loc = loc)
	testing.expect_value(t, p.segment, segment, loc = loc)
	testing.expectf(
		t,
		tbits(p.how_far) == how_far,
		"how_far %v (%x), want %x",
		p.how_far,
		tbits(p.how_far),
		how_far,
		loc = loc,
	)
	testing.expectf(
		t,
		tbits(p.wait) == wait,
		"wait %v (%x), want %x",
		p.wait,
		tbits(p.wait),
		wait,
		loc = loc,
	)
	testing.expect_value(t, p.at_end, at_end, loc = loc)
}

@(private = "file")
expect_unconnected :: proc(t: ^testing.T, err: Error, seq: int, loc := #caller_location) {
	ge, ok := err.(Graph_Error)
	if testing.expectf(t, ok, "expected Graph_Error, got %v", err, loc = loc) {
		testing.expect_value(t, ge.kind, Graph_Error_Kind.Step_Not_Connected, loc = loc)
		testing.expect_value(t, ge.block, seq, loc = loc)
		testing.expect_value(t, ge.line, 0, loc = loc)
	}
}

// Bits used below (Python `float.hex`).
@(private = "file")
B_0 :: 0x0000000000000000
@(private = "file")
B_1 :: 0x3ff0000000000000
@(private = "file")
B_HALF :: 0x3fe0000000000000
@(private = "file")
B_QUARTER :: 0x3fd0000000000000
@(private = "file")
B_0_8 :: 0x3fe999999999999a // 0.8

// steps_graph: edge 0 is 0 → 1 with 4 positions (3 segments); edge 1 is 1 → 2 with 3 positions (2 segments),
// detailed; edge 2 is 2 → 0 with 2 positions (1 segment), detailed; edge 3 is a self-loop on node 3.
@(private = "file")
steps_graph :: proc() -> Graph {
	return graph_of(
		4,
		{
			edge_of(
				node_at(0, SPIN),
				node_at(1, TILT),
				{shape(0), shape(0.2), shape(0.4), shape(0.6)},
			),
			edge_of(
				node_at(1),
				node_at(2, SPIN),
				{shape(0.6), shape(0.7), shape(0.8)},
				detailed = true,
			),
			edge_of(
				node_at(2),
				node_at(0),
				{line_position(0.1), line_position(0.9)},
				detailed = true,
			),
			edge_of(node_at(3, TILT), node_at(3, SPIN), {shape(1), shape(1.5)}),
		},
	)
}

@(private = "file")
one_step :: proc(seq: int, reverse := false) -> []Reoriented_Step {
	return slice.clone(
		[]Reoriented_Step{{step = {seq = seq, reverse = reverse}}},
		context.temp_allocator,
	)
}

@(test)
test_connect_ends :: proc(t: ^testing.T) {
	g := steps_graph()
	n := node_at(0, TILT)

	// Forwards from its `from` node: `compose(inverse(Ef), N)`.
	r, err := connect(&g, n, {seq = 0})
	testing.expect_value(t, err, nil)
	testing.expect_value(t, r.step, Step{seq = 0})
	expect_reorientation(t, r.reorientation, compose(inverse(SPIN), TILT))

	// Reversed from its `to` node: the step's own start end is the edge's `to`.
	r, err = connect(&g, node_at(1, SPIN), {seq = 0, reverse = true})
	testing.expect_value(t, err, nil)
	testing.expect_value(t, r.step, Step{seq = 0, reverse = true})
	expect_reorientation(t, r.reorientation, compose(inverse(TILT), SPIN))

	// Incoming (not reversed, `to == n`): second branch, `Et`.
	r, err = connect(&g, node_at(1, SPIN), {seq = 0})
	testing.expect_value(t, err, nil)
	expect_reorientation(t, r.reorientation, compose(inverse(TILT), SPIN))
	// Its exit is the edge's `to`, i.e. back on node 1.
	exit := step_exit(&g, r)
	testing.expect_value(t, exit.node, 1)
	expect_reorientation(t, exit.reorientation, compose(TILT, r.reorientation))

	// Self-loop forwards: the first branch (`from`) wins.
	r, err = connect(&g, node_at(3), {seq = 3})
	testing.expect_value(t, err, nil)
	expect_reorientation(t, r.reorientation, compose(inverse(TILT), Position_Reorientation{}))
	// Self-loop reversed: the step's start end is the edge's `to`.
	r, err = connect(&g, node_at(3), {seq = 3, reverse = true})
	testing.expect_value(t, err, nil)
	expect_reorientation(t, r.reorientation, compose(inverse(SPIN), Position_Reorientation{}))
}

@(test)
test_connect_step_exit :: proc(t: ^testing.T) {
	g := steps_graph()
	r, err := connect(&g, node_at(0, TILT), {seq = 0})
	testing.expect_value(t, err, nil)
	exit := step_exit(&g, r)
	testing.expect_value(t, exit.node, 1)
	expect_reorientation(t, exit.reorientation, compose(TILT, r.reorientation))

	r, err = connect(&g, node_at(2), {seq = 1, reverse = true})
	testing.expect_value(t, err, nil)
	exit = step_exit(&g, r)
	testing.expect_value(t, exit.node, 1)
	expect_reorientation(t, exit.reorientation, compose(Position_Reorientation{}, r.reorientation))
}

@(test)
test_connect_not_connected :: proc(t: ^testing.T) {
	g := steps_graph()
	_, err := connect(&g, node_at(2), {seq = 0})
	expect_unconnected(t, err, 0)
	for seq in ([]int{-1, len(g.edges), 99}) {
		_, err = connect(&g, node_at(0), {seq = seq})
		expect_unconnected(t, err, seq)
	}
}

@(test)
test_timed_init_empty_path :: proc(t: ^testing.T) {
	g := steps_graph()
	_, err := timed_init(&g, nil)
	ge, ok := err.(Graph_Error)
	if testing.expectf(t, ok, "expected Graph_Error, got %v", err) {
		testing.expect_value(t, ge.kind, Graph_Error_Kind.Empty_Path)
		testing.expect_value(t, ge.block, NO_BLOCK)
	}
}

@(test)
test_timed_reset :: proc(t: ^testing.T) {
	g := steps_graph()
	p, err := timed_init(&g, one_step(0))
	testing.expect_value(t, err, nil)
	testing.expect(t, p.loop)
	expect_state(t, p, 0, 0, B_0)

	// Reversed first step: its last segment, `how_far = 1`.
	p, err = timed_init(&g, one_step(0, reverse = true), loop = false)
	testing.expect_value(t, err, nil)
	testing.expect(t, !p.loop)
	expect_state(t, p, 0, 2, B_1)

	p.i, p.segment, p.how_far, p.wait, p.at_end = 0, 0, 0.3, 0.5, true
	timed_reset(&p, &g)
	expect_state(t, p, 0, 2, B_1)
}

@(test)
test_timed_progress_forwards :: proc(t: ^testing.T) {
	g := steps_graph()
	p, _ := timed_init(&g, one_step(0))
	timed_progress(&p, &g, 0.1)
	expect_state(t, p, 0, 0, B_HALF)

	// Crossing a segment boundary: the leftover `(hf − 1) / 5` goes into the next segment.
	p, _ = timed_init(&g, one_step(0))
	timed_progress(&p, &g, 0.25)
	expect_state(t, p, 0, 1, B_QUARTER)
	p, _ = timed_init(&g, one_step(0))
	timed_progress(&p, &g, 0.33)
	expect_state(t, p, 0, 1, 0x3fe4ccccccccccce) // 0.6500000000000001

	// Exactly reaching 1 moves on (`hf < 1` is the only stay).
	p, _ = timed_init(&g, one_step(0))
	timed_progress(&p, &g, 0.2)
	expect_state(t, p, 0, 1, B_0)
	p, _ = timed_init(&g, one_step(0))
	timed_progress(&p, &g, 0.1)
	timed_progress(&p, &g, 0.1)
	expect_state(t, p, 0, 1, B_0)

	// `seconds = 0` changes nothing.
	timed_progress(&p, &g, 0)
	expect_state(t, p, 0, 1, B_0)
}

@(test)
test_timed_progress_detailed :: proc(t: ^testing.T) {
	g := steps_graph()
	// Edge 1 is detailed: 10 segments per second.
	p, _ := timed_init(&g, one_step(1))
	timed_progress(&p, &g, 0.13)
	expect_state(t, p, 0, 1, 0x3fd3333333333334) // 0.30000000000000004

	// Detailed one-segment step, then a normal one: the leftover is consumed at 5 segments per second.
	path := slice.clone(
		[]Reoriented_Step{{step = {seq = 2}}, {step = {seq = 0}}},
		context.temp_allocator,
	)
	p, _ = timed_init(&g, path)
	timed_progress(&p, &g, 0.07)
	expect_state(t, p, 0, 0, 0x3fe6666666666667) // 0.7000000000000001
	p, _ = timed_init(&g, path)
	timed_progress(&p, &g, 0.13)
	expect_state(t, p, 1, 0, 0x3fc3333333333334) // 0.15000000000000002 (0.3… at 10 segments per second)
}

@(test)
test_timed_progress_reversed :: proc(t: ^testing.T) {
	g := steps_graph()
	p, _ := timed_init(&g, one_step(0, reverse = true))
	timed_progress(&p, &g, 0.1)
	expect_state(t, p, 0, 2, B_HALF)
	p, _ = timed_init(&g, one_step(0, reverse = true))
	timed_progress(&p, &g, 0.25)
	expect_state(t, p, 0, 1, 0x3fe8000000000000) // 0.75
	p, _ = timed_init(&g, one_step(0, reverse = true))
	timed_progress(&p, &g, 0.33)
	expect_state(t, p, 0, 1, 0x3fd6666666666664) // 0.34999999999999987

	// A reversed second step starts at its last segment, `how_far = 1`.
	path := slice.clone(
		[]Reoriented_Step{{step = {seq = 2}}, {step = {seq = 1, reverse = true}}},
		context.temp_allocator,
	)
	p, _ = timed_init(&g, path)
	timed_progress(&p, &g, 0.1)
	expect_state(t, p, 1, 1, B_1)
	timed_progress(&p, &g, 0.05)
	expect_state(t, p, 1, 1, B_HALF)
}

@(test)
test_timed_progress_end_and_loop :: proc(t: ^testing.T) {
	g := steps_graph()
	p, _ := timed_init(&g, one_step(0))
	// 0.7 s on a 0.6 s step: at the end, `wait = 0.8`, the 0.1 s leftover discarded.
	timed_progress(&p, &g, 0.7)
	expect_state(t, p, 0, 2, B_1, B_0_8, true)
	// Less than the pause: only `wait` decreases.
	timed_progress(&p, &g, 0.5)
	expect_state(t, p, 0, 2, B_1, 0x3fd3333333333334, true) // 0.30000000000000004
	// After the pause: `reset`, `wait = PAUSE_BEFORE`, the rest discarded.
	timed_progress(&p, &g, 0.5)
	expect_state(t, p, 0, 0, B_0, B_0_8)
	timed_progress(&p, &g, 0.5)
	expect_state(t, p, 0, 0, B_0, 0x3fd3333333333334)

	p, _ = timed_init(&g, one_step(0))
	timed_progress(&p, &g, 0.7)
	timed_progress(&p, &g, 0.9)
	expect_state(t, p, 0, 0, B_0, B_0_8)
}

@(test)
test_timed_progress_no_loop_and_huge :: proc(t: ^testing.T) {
	g := steps_graph()
	p, _ := timed_init(&g, one_step(0))
	timed_progress(&p, &g, 100)
	expect_state(t, p, 0, 2, B_1, B_0_8, true)

	p, _ = timed_init(&g, one_step(0), loop = false)
	for _ in 0 ..< 3 {
		timed_progress(&p, &g, 100)
	}
	expect_state(t, p, 0, 2, B_1, B_0, true)

	// A huge step over a multi-step path never leaves `how_far` outside [0, 1].
	path := slice.clone(
		[]Reoriented_Step {
			{step = {seq = 0}},
			{step = {seq = 1}},
			{step = {seq = 2, reverse = true}},
		},
		context.temp_allocator,
	)
	p, _ = timed_init(&g, path)
	timed_progress(&p, &g, 100)
	expect_state(t, p, 2, 0, B_0, B_0_8, true)
}

@(test)
test_timed_at :: proc(t: ^testing.T) {
	g := steps_graph()
	path := slice.clone(
		[]Reoriented_Step{{step = {seq = 0}, reorientation = SPIN}},
		context.temp_allocator,
	)
	p, _ := timed_init(&g, path)
	ps := g.edges[0].sequence.positions
	expect_position_bits(t, timed_at(&p, &g), reorient(SPIN, ps[0]))

	p.segment, p.how_far = 1, 1
	expect_position_bits(t, timed_at(&p, &g), reorient(SPIN, between(ps[1], ps[2], 1)))

	// Interpolate, then reorient (src/graph_util.hpp:260-268).
	p.segment, p.how_far = 2, 0.5
	expect_position_bits(t, timed_at(&p, &g), reorient(SPIN, between(ps[2], ps[3], 0.5)))
}

@(private = "file")
seek_path :: proc() -> []Reoriented_Step {
	// 0.6 s (3 segments at 5/s), then 0.2 s (2 segments at 10/s, reversed).
	return slice.clone(
		[]Reoriented_Step{{step = {seq = 0}}, {step = {seq = 1, reverse = true}}},
		context.temp_allocator,
	)
}

@(test)
test_timed_duration :: proc(t: ^testing.T) {
	g := steps_graph()
	testing.expect_value(t, tbits(timed_duration(seek_path(), &g)), B_0_8)
	testing.expect_value(t, timed_duration(nil, &g), 0)
}

@(test)
test_timed_seek :: proc(t: ^testing.T) {
	g := steps_graph()
	p, _ := timed_init(&g, seek_path())
	p.wait, p.at_end = 0.5, true

	timed_seek(&p, &g, 0)
	expect_state(t, p, 0, 0, B_0)
	timed_seek(&p, &g, -3)
	expect_state(t, p, 0, 0, B_0)
	timed_seek(&p, &g, 0.125)
	expect_state(t, p, 0, 0, 0x3fe4000000000000) // 0.625
	timed_seek(&p, &g, 0.5)
	expect_state(t, p, 0, 2, B_HALF)
	// The reversed second step: `segment = segments − 1 − k`, `how_far = 1 − f`.
	timed_seek(&p, &g, 0.625)
	expect_state(t, p, 1, 1, 0x3fe7fffffffffffe) // 0.7499999999999998
	timed_seek(&p, &g, 0.75)
	expect_state(t, p, 1, 0, 0x3fdffffffffffffc) // 0.4999999999999998
	// The end, and beyond.
	timed_seek(&p, &g, 0.8)
	expect_state(t, p, 1, 0, B_0)
	timed_seek(&p, &g, 5)
	expect_state(t, p, 1, 0, B_0)

	p, _ = timed_init(&g, one_step(0))
	timed_seek(&p, &g, 0.6)
	expect_state(t, p, 0, 2, B_1)
}

@(test)
test_timed_elapsed_inverts_seek :: proc(t: ^testing.T) {
	g := steps_graph()
	p, _ := timed_init(&g, seek_path())
	for x in ([]f64{0, 0.125, 0.25, 0.5, 0.625, 0.6875, 0.75, 0.8}) {
		timed_seek(&p, &g, x)
		testing.expectf(
			t,
			timed_elapsed(&p, &g) == x,
			"elapsed(seek(%v)) = %v",
			x,
			timed_elapsed(&p, &g),
		)
	}
}
