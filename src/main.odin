package main

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
EXIT_MEMORY_ERROR :: 3
BACKGROUND :: rl.Color{24, 26, 32, 255}

// App_State holds all mutable application state; it is passed explicitly.
App_State :: struct {
	headless:   bool,
	max_frames: int,
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

	state := parse_args(os.args)
	run(&state)

	if TRACK_LEAKS {
		has_problems := report_leaks(&track)
		mem.tracking_allocator_destroy(&track)
		if has_problems {
			os.exit(EXIT_MEMORY_ERROR)
		}
	}
}

// report_leaks prints every live allocation and bad free to stderr.
// It returns true if there was at least one leak or bad free.
@(private)
report_leaks :: proc(track: ^mem.Tracking_Allocator) -> (has_problems: bool) {
	for _, leak in track.allocation_map {
		fmt.eprintfln("leak: %v bytes at %v", leak.size, leak.location)
		has_problems = true
	}
	for bad in track.bad_free_array {
		fmt.eprintfln("bad free at %v", bad.location)
		has_problems = true
	}
	return
}

// parse_args reads `--headless` and `--frames N` from the command line.
@(private)
parse_args :: proc(args: []string) -> App_State {
	state := App_State{}
	for i := 1; i < len(args); i += 1 {
		switch args[i] {
		case "--headless":
			state.headless = true
		case "--frames":
			if i + 1 < len(args) {
				i += 1
				state.max_frames, _ = strconv.parse_int(args[i])
			}
		}
	}
	return state
}

@(private)
run :: proc(state: ^App_State) {
	rl.SetConfigFlags({.MSAA_4X_HINT})
	if state.headless {
		rl.SetConfigFlags({.WINDOW_HIDDEN})
	}
	rl.InitWindow(WINDOW_WIDTH, WINDOW_HEIGHT, WINDOW_TITLE)
	defer rl.CloseWindow()
	rl.SetTargetFPS(TARGET_FPS)

	frame := 0
	for !rl.WindowShouldClose() {
		rl.BeginDrawing()
		rl.ClearBackground(BACKGROUND)
		rl.DrawText(fmt.ctprintf("%s", frames_label(frame)), 32, 32, 24, rl.RAYWHITE)
		rl.EndDrawing()
		free_all(context.temp_allocator)
		frame += 1
		if state.max_frames > 0 && frame >= state.max_frames {
			break
		}
	}
}
