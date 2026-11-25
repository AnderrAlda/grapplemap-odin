package main

import "app:core"
import "core:mem"
import "core:strings"
import "core:testing"

@(test)
test_frames_label :: proc(t: ^testing.T) {
	testing.expect_value(t, frames_label(7), "grapplemap-odin  frame 7")
}

@(test)
test_parse_args :: proc(t: ^testing.T) {
	s, _ := parse_args({"app", "--headless", "--frames", "5"})
	testing.expect(t, s.headless)
	testing.expect_value(t, s.max_frames, 5)
}

@(test)
test_has_memory_problems_detects_leak :: proc(t: ^testing.T) {
	track: mem.Tracking_Allocator
	mem.tracking_allocator_init(&track, context.allocator)
	defer mem.tracking_allocator_destroy(&track)
	alloc := mem.tracking_allocator(&track)

	// This allocation is an intentional, temporary "leak". has_memory_problems does not print,
	// so the test output stays free of misleading "leak:" lines.
	ptr, _ := mem.alloc(16, allocator = alloc)
	testing.expect(
		t,
		has_memory_problems(&track),
		"a live allocation must be reported as a problem",
	)
	mem.free(ptr, alloc)
	testing.expect(t, !has_memory_problems(&track), "no live allocations: no problem")
}

// Two real positions from GrappleMap.txt (the first of each of its first two blocks): they do not match each other.
TINY_POS_A :: "    Q2aAwQJFazuRQGddznKqcxxSRkbTzoJpbsxEToa1FVGgaYDSPnfgB7LGfaCxRle1LbLSf\n    nLOSubdIJKoaVL8QsaUMqOmauNOP1azNAPva9NNPnblOlQAauNFN2ffGdOFe9MbPefdOP\n    v1azIfCljpKozGaGIPC8hlHqyEbHICDOijIcBYhKINJsiuEeF7cdJFGMcjFZOPbwMhQcb\n    BHkKwbhN5QNfyEQNIdfL9R4e1IWO0dcL5SggbJuPLd9MvRSgpKHKibTIsQDbQJ4SMbWLG\n"
TINY_POS_B :: "    DPaUwxULaRrgHtaEvNVYbjuKGFaEwZUHbgt6JaceDeO6d0w7P1cUEcOUgnDEOCeUNNLAi\n    sLxLNa9NFHQhvIWIebeLsDAhgJwHgb1LSCIg7KwGzcJK0BvgEKfOEeZHOM2hcNxMbhyPZ\n    vUazHSCuiOI1zyaEImDegaGyyybEIiDPhvGMBrhUIUJyiyCWFTcxJcHmcEFNO4btMxPYb\n    tHuOlbcRaNcaUDKPFetOXRgbpE4QkfsOnSubzFoP0fIM7SVcFFXKebUI1QFbTKcTccDKx\n"

@(test)
test_parse_args_load :: proc(t: ^testing.T) {
	s, ok := parse_args({"app", "--load", "db.txt"})
	testing.expect(t, ok)
	testing.expect_value(t, s.load_path, "db.txt")

	s, ok = parse_args({"app", "--load", "db.txt", "--headless"})
	testing.expect(t, ok)
	testing.expect(t, s.headless)
	testing.expect_value(t, s.load_path, "db.txt")

	s, ok = parse_args({"app", "--headless", "--load", "db.txt"})
	testing.expect(t, ok)
	testing.expect(t, s.headless)
	testing.expect_value(t, s.load_path, "db.txt")
}

@(test)
test_parse_args_load_missing_value :: proc(t: ^testing.T) {
	_, ok := parse_args({"app", "--headless", "--load"})
	testing.expect(t, !ok, "--load without a file is a usage error")
}

@(test)
test_summary_line :: proc(t: ^testing.T) {
	text := strings.concatenate(
		{"A\ntags: x\n", TINY_POS_A, "T\ntags: y\n", TINY_POS_A, TINY_POS_B},
		context.temp_allocator,
	)
	g, err := core.load_graph(transmute([]byte)text)
	if !testing.expectf(t, err == nil, "load_graph: %v", err) {
		return
	}
	defer core.graph_destroy(&g)
	line := summary_line(&g, context.temp_allocator)
	testing.expect_value(t, line, "blocks=2 positions=3 named=1 transitions=1 nodes=2 anonymous=1")
}

@(test)
test_format_load_error :: proc(t: ^testing.T) {
	a := context.temp_allocator
	testing.expect_value(
		t,
		format_load_error(core.Parse_Error{kind = .Truncated_Block, line = 12, block = 3}, a),
		"error: Truncated_Block at line 12 (block 3)",
	)
	testing.expect_value(
		t,
		format_load_error(
			core.Graph_Error{kind = .Duplicate_Position_Description, line = 21, block = 3},
			a,
		),
		"error: Duplicate_Position_Description at line 21 (block 3)",
	)
	testing.expect_value(
		t,
		format_load_error(
			core.Parse_Error{kind = .Missing_Final_Newline, line = 0, block = core.NO_BLOCK},
			a,
		),
		"error: Missing_Final_Newline",
	)
	testing.expect_value(
		t,
		format_load_error(
			core.Parse_Error{kind = .Truncated_Block, line = 5, block = core.NO_BLOCK},
			a,
		),
		"error: Truncated_Block at line 5",
	)
	testing.expect_value(
		t,
		format_load_error(core.Error(mem.Allocator_Error.Out_Of_Memory), a),
		"error: out of memory (Out_Of_Memory)",
	)
}

#assert(EXIT_LOAD_ERROR != EXIT_IO_ERROR)
#assert(EXIT_LOAD_ERROR != EXIT_USAGE_ERROR)
#assert(EXIT_IO_ERROR != EXIT_USAGE_ERROR)
#assert(
	EXIT_MEMORY_ERROR != EXIT_LOAD_ERROR &&
	EXIT_MEMORY_ERROR != EXIT_IO_ERROR &&
	EXIT_MEMORY_ERROR != EXIT_USAGE_ERROR,
)
