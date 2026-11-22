package fidelity

import "app:core"
import "core:math/rand"
import "core:testing"

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

	// Start offset of every line, plus len(db) as the end of the last one.
	starts := make([dynamic]int)
	defer delete(starts)
	append(&starts, 0)
	for c, k in db {
		if c == '\n' {
			append(&starts, k + 1)
		}
	}
	line_count := len(starts) - 1
	if !testing.expect(t, line_count >= 2, "DB has fewer than 2 lines") {
		return
	}

	state := rand.create(MUTATION_SEED)
	context.random_generator = rand.default_random_generator(&state)
	buf := make([]byte, len(db))
	defer delete(buf)

	runs, parsed, rejected: int
	for _ in 0 ..< MUTATION_CASES {
		copy(buf, db)
		input := buf[:]
		switch Mutation(rand.int_max(len(Mutation))) {
		case .Truncate:
			input = buf[:rand.int_max(len(buf))]
		case .Flip_Byte:
			buf[rand.int_max(len(buf))] = byte(rand.int_max(256))
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
		seqs, err := core.parse_db(input)
		if err == nil {
			core.sequences_destroy(seqs)
			parsed += 1
		} else {
			testing.expect(t, seqs == nil, "parse_db returned sequences with an error")
			rejected += 1
		}
		free_all(context.temp_allocator)
		runs += 1
	}
	testing.expect_value(t, runs, MUTATION_CASES)
	// Both outcomes occur with this seed: the cases reach the parser's success and error paths.
	testing.expectf(t, parsed > 0 && rejected > 0, "parsed %d, rejected %d", parsed, rejected)
}
