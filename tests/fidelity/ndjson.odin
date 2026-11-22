package fidelity

import "core:bufio"
import "core:mem/virtual"
import "core:os"

// Streaming NDJSON reader: one line at a time, never the whole file (`playback.ndjson` is 389 MB in the full dump).

Ndjson_Error :: enum u8 {
	None,
	Cannot_Open,
	Read_Failed,
	Empty_Line,
	Out_Of_Memory,
}

// Ndjson_Line_Proc gets one line without its '\n' and returns false to stop. While it runs, `context.allocator` and
// `context.temp_allocator` are an arena freed after the line: decode with `json.unmarshal` and keep nothing.
Ndjson_Line_Proc :: #type proc(line: []byte, ctx: rawptr) -> bool

// ndjson_each calls `each` on every line of `path` in order and returns how many lines it was given (the line that
// stopped it included). A trailing line without '\n' counts; an empty line is an error (NDJSON has none).
ndjson_each :: proc(
	path: string,
	ctx: rawptr,
	each: Ndjson_Line_Proc,
) -> (
	lines: int,
	stopped: bool,
	err: Ndjson_Error,
) {
	f, open_err := os.open(path)
	if open_err != nil {
		return 0, false, .Cannot_Open
	}
	defer os.close(f)

	arena: virtual.Arena
	if virtual.arena_init_growing(&arena) != .None {
		return 0, false, .Out_Of_Memory
	}
	defer virtual.arena_destroy(&arena)
	line_alloc := virtual.arena_allocator(&arena)

	r: bufio.Reader
	bufio.reader_init(&r, os.to_reader(f))
	defer bufio.reader_destroy(&r)

	for {
		line, read_err := bufio.reader_read_bytes(&r, '\n', line_alloc)
		if read_err != nil && read_err != .EOF {
			return lines, false, .Read_Failed
		}
		at_eof := read_err == .EOF
		if len(line) > 0 && line[len(line) - 1] == '\n' {
			line = line[:len(line) - 1]
		} else if at_eof && len(line) == 0 {
			return lines, false, .None
		}
		if len(line) == 0 {
			return lines, false, .Empty_Line
		}
		lines += 1
		keep_going: bool
		{
			context.allocator = line_alloc
			context.temp_allocator = line_alloc
			keep_going = each(line, ctx)
		}
		free_all(line_alloc)
		if !keep_going {
			return lines, true, .None
		}
		if at_eof {
			return lines, false, .None
		}
	}
}
