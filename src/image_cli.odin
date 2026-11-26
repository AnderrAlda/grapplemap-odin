package main

import "app:core"
import "app:render"
import "core:fmt"
import "core:strconv"
import "core:strings"
import rl "vendor:raylib"

// `--image <entity> <out.png> [--size WxH] [--heading N|E|S|W] [--mirror] [--swap] [--load <file>]`: the
// reference-path image of a named position, as `tools/oracle/images/images.cpp` (spec phase 3, "UX"). Two options
// are left out of the usage line, for `./build.sh golden-measure` (tools/golden/README.md): `--grid quads|lines` and
// `--depth raylib|16` (render.Image_Options; default render.IMAGE_OPTIONS_DEFAULT).

DEFAULT_DB_PATH :: "reference/GrappleMap/GrappleMap.txt" // the database when there is no `--load`
IMAGE_MAX_SIDE :: 4096 // largest `--size` side: the 2× render texture stays within common GL limits
IMAGE_EXTENSION :: ".png" // raylib's ExportImage picks the format by extension
HEADING_CODES :: "NESW" // Heading::N, E, S, W (src/headings.hpp:9), index = heading

Image_Args :: struct {
	entity:   string,
	out_path: string,
	width:    int,
	height:   int,
	heading:  int, // 0..3 = N, E, S, W
	mirror:   bool,
	swap:     bool,
	opts:     render.Image_Options,
}

// parse_image_arg handles `args[i^]` if it is one of the image options, advancing `i` past its values. `handled` is
// false for any other argument; `ok` is false for a missing or malformed value.
@(private)
parse_image_arg :: proc(args: []string, i: ^int, img: ^Image_Args) -> (handled, ok: bool) {
	value :: proc(args: []string, i: ^int) -> (string, bool) {
		if i^ + 1 >= len(args) || strings.has_prefix(args[i^ + 1], "--") {
			return "", false
		}
		i^ += 1
		return args[i^], true
	}
	handled = true // before any `or_return`, which only sets `ok`
	switch args[i^] {
	case "--image":
		img.entity = value(args, i) or_return
		img.out_path = value(args, i) or_return
		return true, strings.has_suffix(img.out_path, IMAGE_EXTENSION)
	case "--size":
		s := value(args, i) or_return
		img.width, img.height = parse_size(s) or_return
	case "--heading":
		h := value(args, i) or_return
		img.heading = strings.index(HEADING_CODES, h)
		return true, len(h) == 1 && img.heading >= 0
	case "--grid":
		switch value(args, i) or_return {
		case "quads":
			img.opts.grid = .Quads
		case "lines":
			img.opts.grid = .Lines
		case:
			return true, false
		}
	case "--depth":
		switch value(args, i) or_return {
		case "raylib":
			img.opts.depth = .Raylib
		case "16":
			img.opts.depth = .Bits16
		case:
			return true, false
		}
	case "--mirror":
		img.mirror = true
	case "--swap":
		img.swap = true
	case:
		return false, true
	}
	return true, true
}

// parse_size reads `WxH`, both sides in 1..IMAGE_MAX_SIDE.
@(private)
parse_size :: proc(s: string) -> (w, h: int, ok: bool) {
	x := strings.index_byte(s, 'x')
	if x < 0 {
		return
	}
	w = strconv.parse_int(s[:x], 10) or_return
	h = strconv.parse_int(s[x + 1:], 10) or_return
	ok = 0 < w && w <= IMAGE_MAX_SIDE && 0 < h && h <= IMAGE_MAX_SIDE
	return
}

// image_node_position is the position `entity` names (`core.named_entity`). A transition or an unknown name prints
// the error and returns EXIT_USAGE_ERROR.
@(private)
image_node_position :: proc(g: ^core.Graph, entity: string) -> (p: core.Position, code: int) {
	e, found := core.named_entity(g, entity)
	if !found {
		fmt.eprintfln("error: --image: no position named %q", entity)
		return {}, EXIT_USAGE_ERROR
	}
	n, is_node := e.(core.Entity_Node)
	if !is_node {
		fmt.eprintfln("error: --image: %q is a transition; only positions are supported", entity)
		return {}, EXIT_USAGE_ERROR
	}
	return g.nodes[n.node].position, 0
}

// run_image loads the database, resolves the entity (both before any window) and writes the image through a hidden
// window. Returns the exit code.
@(private)
run_image :: proc(state: ^App_State, img: Image_Args) -> int {
	path := state.load_path if state.load_path != "" else DEFAULT_DB_PATH
	g, code := load_summary(path)
	if code != 0 {
		return code
	}
	defer core.graph_destroy(&g)
	node: core.Position
	node, code = image_node_position(&g, img.entity)
	if code != 0 {
		return code
	}
	pos := render.image_position(node, img.mirror, img.swap)
	pixels := make([]u8, 3 * img.width * img.height)
	defer delete(pixels)

	rl.SetTraceLogLevel(.WARNING)
	rl.SetConfigFlags({.WINDOW_HIDDEN})
	rl.InitWindow(i32(img.width), i32(img.height), WINDOW_TITLE)
	if !rl.IsWindowReady() {
		// No CloseWindow here: raylib never set up rlgl, and closing would dereference its null GL procs.
		fmt.eprintln("error: --image: no GL context")
		return EXIT_RENDER_ERROR
	}
	defer rl.CloseWindow()
	scene: render.Reference_Renderer
	if err := render.reference_init(&scene); err != .None {
		fmt.eprintfln("error: reference renderer: %v", err)
		return EXIT_RENDER_ERROR
	}
	defer render.reference_destroy(&scene)
	if used := render.effective_grid_style(&scene, img.opts.grid); used != img.opts.grid {
		fmt.eprintfln(
			"warning: --image: this GL context has no %d-px lines; grid drawn as %v",
			render.GRID_LINE_WIDTH_PX,
			used,
		)
	}
	if err := render.render_image(
		&scene,
		pos,
		img.heading,
		img.width,
		img.height,
		img.opts,
		pixels,
	); err != .None {
		fmt.eprintfln("error: --image: %v", err)
		return EXIT_RENDER_ERROR
	}
	image := rl.Image {
		data    = raw_data(pixels),
		width   = i32(img.width),
		height  = i32(img.height),
		mipmaps = 1,
		format  = .UNCOMPRESSED_R8G8B8,
	}
	if !rl.ExportImage(image, strings.clone_to_cstring(img.out_path, context.temp_allocator)) {
		fmt.eprintfln("error: cannot write %s", img.out_path)
		return EXIT_IO_ERROR
	}
	return 0
}
