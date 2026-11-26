package main

import "app:core"
import "app:render"
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
	EXIT_RENDER_ERROR != EXIT_MEMORY_ERROR &&
	EXIT_RENDER_ERROR != EXIT_LOAD_ERROR &&
	EXIT_RENDER_ERROR != EXIT_IO_ERROR &&
	EXIT_RENDER_ERROR != EXIT_USAGE_ERROR,
)
#assert(
	EXIT_MEMORY_ERROR != EXIT_LOAD_ERROR &&
	EXIT_MEMORY_ERROR != EXIT_IO_ERROR &&
	EXIT_MEMORY_ERROR != EXIT_USAGE_ERROR,
)

@(test)
test_load_summary :: proc(t: ^testing.T) {
	// The caller owns the graph: destroying it leaves nothing behind (the test's tracking allocator checks).
	g, code := load_summary(#directory + "/../tests/fixtures/canonical.txt")
	testing.expect_value(t, code, 0)
	core.graph_destroy(&g)
}

@(test)
test_load_summary_io_error :: proc(t: ^testing.T) {
	g, code := load_summary(#directory + "/../tests/fixtures/does-not-exist.txt")
	testing.expect_value(t, code, EXIT_IO_ERROR)
	testing.expect_value(t, len(g.nodes), 0)
}

@(test)
test_parse_args_image :: proc(t: ^testing.T) {
	s, ok := parse_args({"app", "--image", "p96", "out.png"})
	testing.expect(t, ok)
	img, has := s.image.?
	if !testing.expect(t, has, "--image sets the image arguments") {
		return
	}
	testing.expect_value(t, img.entity, "p96")
	testing.expect_value(t, img.out_path, "out.png")
	testing.expect_value(t, img.width, render.IMAGE_DEFAULT_WIDTH)
	testing.expect_value(t, img.height, render.IMAGE_DEFAULT_HEIGHT)
	testing.expect_value(t, img.heading, 0)
	testing.expect(t, !img.mirror && !img.swap)
	testing.expect_value(t, img.opts, render.IMAGE_OPTIONS_DEFAULT)

	s, ok = parse_args(
		{
			"app",
			"--size",
			"320x240",
			"--image",
			"l12",
			"a.png",
			"--heading",
			"E",
			"--mirror",
			"--swap",
		},
	)
	testing.expect(t, ok)
	img = s.image.? or_else {}
	testing.expect_value(t, img.entity, "l12")
	testing.expect_value(t, img.width, 320)
	testing.expect_value(t, img.height, 240)
	testing.expect_value(t, img.heading, 1)
	testing.expect(t, img.mirror && img.swap)

	s, ok = parse_args({"app", "--image", "p1", "a.png", "--grid", "lines", "--depth", "16"})
	testing.expect(t, ok)
	img = s.image.? or_else {}
	testing.expect_value(t, img.opts, render.Image_Options{grid = .Lines, depth = .Bits16})
	s, ok = parse_args({"app", "--image", "p1", "a.png", "--grid", "quads", "--depth", "raylib"})
	testing.expect(t, ok)
	testing.expect_value(
		t,
		(s.image.? or_else {}).opts,
		render.Image_Options{grid = .Quads, depth = .Raylib},
	)

	for h, i in ([]string{"N", "E", "S", "W"}) {
		s, ok = parse_args({"app", "--image", "p1", "a.png", "--heading", h})
		testing.expect(t, ok)
		testing.expect_value(t, (s.image.? or_else {}).heading, i)
	}

	s, ok = parse_args({"app", "--load", "db.txt"})
	testing.expect(t, ok)
	_, has = s.image.?
	testing.expect(t, !has, "no --image: no image arguments")
}

@(test)
test_parse_args_image_errors :: proc(t: ^testing.T) {
	bad := [][]string {
		{"app", "--image"},
		{"app", "--image", "p96"},
		{"app", "--image", "p96", "--size", "320x240"},
		{"app", "--image", "p96", "out.jpg"},
		{"app", "--image", "p96", "out.png", "--size"},
		{"app", "--image", "p96", "out.png", "--size", "480"},
		{"app", "--image", "p96", "out.png", "--size", "0x10"},
		{"app", "--image", "p96", "out.png", "--size", "10x-1"},
		{"app", "--image", "p96", "out.png", "--size", "480x360x2"},
		{"app", "--image", "p96", "out.png", "--size", "100000x10"},
		{"app", "--image", "p96", "out.png", "--heading", "Q"},
		{"app", "--image", "p96", "out.png", "--heading"},
		{"app", "--image", "p96", "out.png", "--headless"},
		{"app", "--headless", "--image", "p96", "out.png"},
		{"app", "--image", "p96", "out.png", "--grid", "dots"},
		{"app", "--image", "p96", "out.png", "--grid"},
		{"app", "--image", "p96", "out.png", "--depth", "24"},
		{"app", "--mirror"},
		{"app", "--size", "320x240"},
	}
	for args in bad {
		_, ok := parse_args(args)
		testing.expectf(t, !ok, "%v must be a usage error", args)
	}
}

@(test)
test_image_node_position :: proc(t: ^testing.T) {
	text := strings.concatenate(
		{"A\ntags: x\n", TINY_POS_A, "T\ntags: y\n", TINY_POS_A, TINY_POS_B},
		context.temp_allocator,
	)
	g, err := core.load_graph(transmute([]byte)text)
	if !testing.expectf(t, err == nil, "load_graph: %v", err) {
		return
	}
	defer core.graph_destroy(&g)

	p, code := image_node_position(&g, "p0")
	testing.expect_value(t, code, 0)
	testing.expect(t, p == g.nodes[0].position)
	_, code = image_node_position(&g, "A")
	testing.expect_value(t, code, 0)
	_, code = image_node_position(&g, "t0")
	testing.expect_value(t, code, EXIT_USAGE_ERROR)
	_, code = image_node_position(&g, "no such position")
	testing.expect_value(t, code, EXIT_USAGE_ERROR)
}

@(test)
test_run_app_image_exits_before_window :: proc(t: ^testing.T) {
	missing := #directory + "/../tests/fixtures/does-not-exist.txt"
	testing.expect_value(
		t,
		run_app({"app", "--image", "p0", "out.png", "--load", missing}),
		EXIT_IO_ERROR,
	)
	testing.expect_value(
		t,
		run_app({"app", "--image", "p0", "out.png", "--headless"}),
		EXIT_USAGE_ERROR,
	)
}
