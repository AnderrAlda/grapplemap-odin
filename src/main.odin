package main

import "app:core"
import "app:render"
import "core:fmt"
import "core:mem"
import "core:os"
import "core:strconv"
import rl "vendor:raylib"

WINDOW_WIDTH :: 1280
WINDOW_HEIGHT :: 720
WINDOW_TITLE :: "grapplemap-odin"
TARGET_FPS :: 60
TRACK_LEAKS :: ODIN_DEBUG

// Process exit codes, all distinct. 0 = success; 1/2 are left to the runtime and the shell.
EXIT_MEMORY_ERROR :: 3 // the leak tracker found a leak or a bad free (debug builds only)
EXIT_LOAD_ERROR :: 4 // `--load`: the file was read but is not a valid database
EXIT_IO_ERROR :: 5 // `--load`: the file could not be read
EXIT_USAGE_ERROR :: 6 // bad command line (e.g. `--load` without a file)
BACKGROUND :: rl.Color{24, 26, 32, 255}

// App_State holds all mutable application state; it is passed explicitly.
App_State :: struct {
	headless:   bool,
	max_frames: int,
	load_path:  string, // `--load <file>`; "" = none
}

// frames_label returns the text shown on the placeholder screen.
frames_label :: proc(frame: int, allocator := context.temp_allocator) -> string {
	return fmt.aprintf("grapplemap-odin  frame %d", frame, allocator = allocator)
}

main :: proc() {
	track: mem.Tracking_Allocator
	if TRACK_LEAKS {
		mem.tracking_allocator_init(&track, context.allocator)
		context.allocator = mem.tracking_allocator(&track)
	}

	code := run_app(os.args)

	if TRACK_LEAKS {
		has_problems := report_leaks(&track)
		mem.tracking_allocator_destroy(&track)
		if has_problems {
			code = EXIT_MEMORY_ERROR
		}
	}
	if code != 0 {
		os.exit(code)
	}
}

// run_app is everything `main` does except the leak report; it returns the exit code. All exits go through
// `main` so the leak report always runs.
@(private)
run_app :: proc(args: []string) -> int {
	state, ok := parse_args(args)
	if !ok {
		fmt.eprintln("error: --load needs a file")
		return EXIT_USAGE_ERROR
	}
	if state.load_path == "" {
		run(&state, nil)
		return 0
	}
	g, code := load_summary(state.load_path)
	if code != 0 {
		return code
	}
	defer core.graph_destroy(&g)
	// Headless stops here, before any raylib call.
	if !state.headless {
		run(&state, &g)
	}
	return 0
}

// load_summary loads the database at `path` and prints its summary line to stdout; the caller frees the graph with
// `core.graph_destroy`. On failure it prints the error to stderr and returns EXIT_IO_ERROR or EXIT_LOAD_ERROR (and
// no graph).
@(private)
load_summary :: proc(path: string) -> (g: core.Graph, code: int) {
	data, read_err := os.read_entire_file(path, context.allocator)
	if read_err != nil {
		fmt.eprintfln("error: cannot read %s: %s", path, os.error_string(read_err))
		return {}, EXIT_IO_ERROR
	}
	defer delete(data)

	// `load_graph` leaves its scratch in the temp allocator for the caller to free.
	defer free_all(context.temp_allocator)
	err: core.Error
	g, err = core.load_graph(data)
	if err != nil {
		fmt.eprintln(format_load_error(err, context.temp_allocator))
		return {}, EXIT_LOAD_ERROR
	}
	fmt.println(summary_line(&g, context.temp_allocator))
	return g, 0
}

// summary_line is the one-line `--load` report (docs/original.md §10.1 counts): `blocks` = named positions +
// transitions, `positions` = every position of every block, `anonymous` = nodes that are not named positions.
@(private)
summary_line :: proc(g: ^core.Graph, allocator := context.allocator) -> string {
	positions := g.named_count
	for e in g.edges {
		positions += len(e.sequence.positions)
	}
	return fmt.aprintf(
		"blocks=%d positions=%d named=%d transitions=%d nodes=%d anonymous=%d",
		g.named_count + len(g.edges),
		positions,
		g.named_count,
		len(g.edges),
		len(g.nodes),
		len(g.nodes) - g.named_count,
		allocator = allocator,
	)
}

// format_load_error renders a `core.Error` as `error: <kind> at line <n> (block <b>)`; line 0 and `NO_BLOCK` are
// omitted.
@(private)
format_load_error :: proc(err: core.Error, allocator := context.allocator) -> string {
	located :: proc(kind: any, line, block: int, allocator: mem.Allocator) -> string {
		b := fmt.aprintf("error: %v", kind, allocator = allocator)
		if line != 0 {
			b = fmt.aprintf("%s at line %d", b, line, allocator = allocator)
		}
		if block != core.NO_BLOCK {
			b = fmt.aprintf("%s (block %d)", b, block, allocator = allocator)
		}
		return b
	}
	switch e in err {
	case core.Parse_Error:
		return located(e.kind, e.line, e.block, allocator)
	case core.Graph_Error:
		return located(e.kind, e.line, e.block, allocator)
	case core.Json_Error:
		return fmt.aprintf("error: %v", e, allocator = allocator)
	case core.Export_Error:
		return fmt.aprintf("error: %v", e, allocator = allocator)
	case mem.Allocator_Error:
		return fmt.aprintf("error: out of memory (%v)", e, allocator = allocator)
	}
	return fmt.aprintf("error: %v", err, allocator = allocator)
}

// has_memory_problems reports whether the tracker holds a live allocation or a bad free.
// It does not print anything.
@(private)
has_memory_problems :: proc(track: ^mem.Tracking_Allocator) -> bool {
	return len(track.allocation_map) > 0 || len(track.bad_free_array) > 0
}

// report_leaks prints every live allocation and bad free to stderr.
// It returns true if there was at least one leak or bad free.
@(private)
report_leaks :: proc(track: ^mem.Tracking_Allocator) -> bool {
	for _, leak in track.allocation_map {
		fmt.eprintfln("leak: %v bytes at %v", leak.size, leak.location)
	}
	for bad in track.bad_free_array {
		fmt.eprintfln("bad free at %v", bad.location)
	}
	return has_memory_problems(track)
}

// parse_args reads `--headless`, `--frames N` and `--load <file>` from the command line. `ok` is false for
// `--load` without a file; the other flags are lenient.
@(private)
parse_args :: proc(args: []string) -> (state: App_State, ok: bool) {
	for i := 1; i < len(args); i += 1 {
		switch args[i] {
		case "--headless":
			state.headless = true
		case "--load":
			if i + 1 >= len(args) {
				return state, false
			}
			i += 1
			state.load_path = args[i]
		case "--frames":
			if i + 1 < len(args) {
				i += 1
				state.max_frames, _ = strconv.parse_int(args[i])
			}
		}
	}
	return state, true
}

// run opens the window. With a graph it shows node 0 through the reference path (render/reference.odin) with the
// interactive viewer's camera; without one, the placeholder screen (the viewer shell is #201).
@(private)
run :: proc(state: ^App_State, g: ^core.Graph) {
	rl.SetConfigFlags({.MSAA_4X_HINT})
	if state.headless {
		rl.SetConfigFlags({.WINDOW_HIDDEN})
	}
	rl.InitWindow(WINDOW_WIDTH, WINDOW_HEIGHT, WINDOW_TITLE)
	defer rl.CloseWindow()
	rl.SetTargetFPS(TARGET_FPS)

	scene: render.Reference_Renderer
	show := g != nil && len(g.nodes) > 0
	if show {
		if err := render.reference_init(&scene); err != .None {
			fmt.eprintfln("error: reference renderer: %v", err)
			show = false
		}
	}
	defer if show {
		render.reference_destroy(&scene)
	}
	pos: core.Position
	cam: render.Camera
	if show {
		pos = g.nodes[0].position
		cam = render.viewer_camera(pos)
	}

	frame := 0
	for !rl.WindowShouldClose() {
		rl.BeginDrawing()
		if show {
			aspect := f64(rl.GetRenderWidth()) / f64(rl.GetRenderHeight())
			if err := render.draw_scene(&scene, pos, cam, aspect, render.COLOR_BACKGROUND_WHITE);
			   err != nil {
				fmt.eprintfln("error: draw: %v", err)
			}
		} else {
			rl.ClearBackground(BACKGROUND)
			rl.DrawText(fmt.ctprintf("%s", frames_label(frame)), 32, 32, 24, rl.RAYWHITE)
		}
		rl.EndDrawing()
		free_all(context.temp_allocator)
		frame += 1
		if state.max_frames > 0 && frame >= state.max_frames {
			break
		}
	}
}
