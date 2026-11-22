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

	// Start offset of every line, plus the end of the last one (load_db's DB ends in '\n', so every
	// `starts[k + 1]` below is a line end).
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

	parsed, rejected, deep_rejected: int
	for _ in 0 ..< MUTATION_CASES {
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
