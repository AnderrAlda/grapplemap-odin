package fidelity

import "app:core"
import "core:log"
import "core:math/rand"
import "core:testing"
import "core:time"

// Robustness over the real DB: seeded random corruptions (independent of ODIN_TEST_RANDOM_SEED). `parse_db` must
// return a value or an error, never panic, and free everything (the runner fails on leaks).

@(private = "file")
MUTATION_SEED :: 138
@(private = "file")
MUTATION_CASES :: 200

@(private = "file")
Mutation :: enum {
	Truncate,
	Flip_Byte,
	Swap_Lines,
}

@(test)
test_parse_db_survives_mutations :: proc(t: ^testing.T) {
	db, ok := load_db(t)
	if !ok {
		return
	}
	defer delete(db)

	starts := line_starts(db)
	defer delete(starts)
	if !testing.expect(t, len(starts) - 1 >= 2, "DB has fewer than 2 lines") {
		return
	}

	state := rand.create(MUTATION_SEED)
	context.random_generator = rand.default_random_generator(&state)
	buf := make([]byte, len(db))
	defer delete(buf)

	parsed, rejected, deep_rejected: int
	for _ in 0 ..< MUTATION_CASES {
		input := mutate(buf, db, starts[:])
		seqs, err := core.parse_db(input)
		if err == nil {
			core.sequences_destroy(seqs)
			parsed += 1
		} else {
			testing.expect(t, seqs == nil, "parse_db returned sequences with an error")
			rejected += 1
			if pe, is_parse := err.(core.Parse_Error);
			   is_parse && pe.kind != .Missing_Final_Newline {
				deep_rejected += 1
			}
		}
		free_all(context.temp_allocator)
	}
	// Both outcomes occur with this seed, and rejections come from inside the parse, not only the final-newline check.
	testing.expectf(
		t,
		parsed > 0 && deep_rejected > 0,
		"parsed %d, rejected %d (%d past the final-newline check)",
		parsed,
		rejected,
		deep_rejected,
	)
}

// line_starts: the start offset of every line of `db`, plus the end of the last one (`db` ends in '\n', so every
// `starts[k + 1]` is a line end).
@(private = "file")
line_starts :: proc(db: []byte) -> [dynamic]int {
	starts := make([dynamic]int)
	append(&starts, 0)
	for c, k in db {
		if c == '\n' {
			append(&starts, k + 1)
		}
	}
	return starts
}

// mutate copies `db` into `buf` (same length) and applies one random mutation; it returns the input to parse.
@(private = "file")
mutate :: proc(buf, db: []byte, starts: []int) -> []byte {
	line_count := len(starts) - 1
	copy(buf, db)
	input := buf[:]
	switch Mutation(rand.int_max(len(Mutation))) {
	case .Truncate:
		// Cut anywhere but keep a final '\n': otherwise parse_db stops at Missing_Final_Newline before parsing.
		k := rand.int_max(len(buf))
		buf[k] = '\n'
		input = buf[:k + 1]
	case .Flip_Byte:
		k := rand.int_max(len(buf))
		v := byte(rand.int_max(255)) // any byte but the current one
		if v >= buf[k] {
			v += 1
		}
		buf[k] = v
	case .Swap_Lines:
		a := rand.int_max(line_count)
		b := rand.int_max(line_count)
		if a > b {
			a, b = b, a
		}
		if a != b {
			// [a][middle][b] → [b][middle][a], same total length.
			la := db[starts[a]:starts[a + 1]]
			mid := db[starts[a + 1]:starts[b]]
			lb := db[starts[b]:starts[b + 1]]
			n := starts[a]
			n += copy(buf[n:], lb)
			n += copy(buf[n:], mid)
			copy(buf[n:], la)
		}
	}
	return input
}

// The graph over mutants of a sample of the DB (a full `load_graph` takes about a minute under test flags, and the
// DB holds its ~600 named positions first, so any prefix with a transition is slow): blocks
// [0, SAMPLE_NAMED_BLOCKS) (named positions) then SAMPLE_TRANSITION_BLOCKS blocks from SAMPLE_TRANSITION_FIRST
// (the first transition), concatenated in that order; blocks end where a description line follows a position line.
// Sizes and case count keep one `load_graph` of the sample ≲ 0.5 s with ASan and this test under 30 s (#173); the
// cost grows about quadratically with the transitions (150 of them: 17 s per load).
// Every mutant `parse_db` accepts also goes through `load_graph`: an error, or a graph whose edge ends and steps are
// in range; never a panic or a leak.
@(private = "file")
SAMPLE_NAMED_BLOCKS :: 40
@(private = "file")
SAMPLE_TRANSITION_FIRST :: 601
@(private = "file")
SAMPLE_TRANSITION_BLOCKS :: 20
@(private = "file")
GRAPH_MUTATION_CASES :: 120

@(test)
test_load_graph_survives_mutations :: proc(t: ^testing.T) {
	db_full, ok := load_db(t)
	if !ok {
		return
	}
	defer delete(db_full)
	db := db_sample(db_full)
	defer delete(db)
	if !testing.expect(t, db != nil, "the DB has too few blocks for the sample") {
		return
	}

	// The unmutated sample: transitions and anonymous nodes, and every edge in two `in_out` lists.
	{
		start := time.tick_now()
		g, err := core.load_graph(db)
		elapsed := time.tick_since(start)
		if !testing.expectf(t, err == nil, "load_graph(sample): %v", err) {
			return
		}
		defer core.graph_destroy(&g)
		log.infof(
			"load_graph(sample): %v, %d nodes (%d anonymous), %d edges",
			elapsed,
			len(g.nodes),
			len(g.nodes) - g.named_count,
			len(g.edges),
		)
		testing.expectf(
			t,
			len(g.edges) > 0 && len(g.nodes) > g.named_count,
			"sample: %d edges, %d anonymous nodes",
			len(g.edges),
			len(g.nodes) - g.named_count,
		)
		in_out := 0
		for n in g.nodes {
			in_out += len(n.in_out)
		}
		testing.expect_value(t, in_out, 2 * len(g.edges))
		free_all(context.temp_allocator)
	}

	starts := line_starts(db)
	defer delete(starts)
	state := rand.create(MUTATION_SEED)
	context.random_generator = rand.default_random_generator(&state)
	buf := make([]byte, len(db))
	defer delete(buf)

	graphs, rejected: int
	for _ in 0 ..< GRAPH_MUTATION_CASES {
		input := mutate(buf, db, starts[:])
		seqs, perr := core.parse_db(input)
		core.sequences_destroy(seqs)
		free_all(context.temp_allocator)
		if perr != nil {
			continue
		}
		g, err := core.load_graph(input)
		if err == nil {
			expect_graph_in_range(t, g)
			core.graph_destroy(&g)
			graphs += 1
		} else {
			testing.expect(
				t,
				g.nodes == nil && g.edges == nil,
				"load_graph returned a graph with an error",
			)
			rejected += 1
		}
		free_all(context.temp_allocator)
	}
	log.infof(
		"%d mutants of a %d-block sample: %d graphs, %d rejected",
		GRAPH_MUTATION_CASES,
		SAMPLE_NAMED_BLOCKS + SAMPLE_TRANSITION_BLOCKS,
		graphs,
		rejected,
	)
	testing.expectf(t, graphs > 0, "no mutant reached a graph (%d rejected)", rejected)
}

// db_sample: the sample described above, allocated; nil if the DB has too few blocks.
@(private = "file")
db_sample :: proc(db: []byte) -> []byte {
	// Start offset of every block, then len(db).
	starts := make([dynamic]int, context.temp_allocator)
	append(&starts, 0)
	prev_position := false
	line_start := 0
	for c, k in db {
		if k == line_start {
			position := c == ' '
			if !position && prev_position {
				append(&starts, k)
			}
			prev_position = position
		}
		if c == '\n' {
			line_start = k + 1
		}
	}
	append(&starts, len(db))
	last := SAMPLE_TRANSITION_FIRST + SAMPLE_TRANSITION_BLOCKS
	if len(starts) <= last {
		return nil
	}
	named := db[:starts[SAMPLE_NAMED_BLOCKS]]
	transitions := db[starts[SAMPLE_TRANSITION_FIRST]:starts[last]]
	out := make([]byte, len(named) + len(transitions))
	copy(out, named)
	copy(out[len(named):], transitions)
	return out
}

@(private = "file")
expect_graph_in_range :: proc(t: ^testing.T, g: core.Graph) {
	nodes, edges := len(g.nodes), len(g.edges)
	for e, i in g.edges {
		testing.expectf(
			t,
			e.from.node >= 0 && e.from.node < nodes && e.to.node >= 0 && e.to.node < nodes,
			"edge %d: ends %d, %d of %d nodes",
			i,
			e.from.node,
			e.to.node,
			nodes,
		)
	}
	for n, i in g.nodes {
		for list in ([][]core.Step{n.incoming, n.outgoing, n.in_out}) {
			for st in list {
				testing.expectf(
					t,
					st.seq >= 0 && st.seq < edges,
					"node %d: step %v of %d edges",
					i,
					st,
					edges,
				)
			}
		}
	}
}
