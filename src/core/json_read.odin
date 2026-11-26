package core

import "core:mem"
import "core:mem/virtual"
import "core:slice"
import "core:strings"
import "core:unicode/utf8"

// Reader of the graph JSON (ADR 0005), by hand, not `core:encoding/json`. Schema-driven recursive descent over the
// bytes: it accepts any RFC 8259 whitespace and any key order (the writer's layout binds the writer only), and
// nothing is built but what the schema asks for, so the depth is bounded by the schema.

@(private = "file")
SUPPORTED_SCHEMA_VERSION :: 1

@(private = "file")
Json_Reader :: struct {
	data:  []byte,
	i:     int,
	line:  int, // 1-based line of `i` (only whitespace holds newlines: raw control bytes are rejected in strings)
	block: int, // entry being read (document order: positions and transitions as they appear) or NO_BLOCK
	arena: mem.Allocator, // the graph's
}

// Entry_Meta is where an entry started, kept for the checks that need the whole file (ids vs `next_id`).
@(private = "file")
Entry_Meta :: struct {
	line, block: int,
}

// load_graph_json reads the graph JSON of ADR 0005 into a fresh growing arena, as `load_graph` does for the text
// DB: strings are copied (nothing points into `data`), the result is freed with `graph_destroy`, and on error the
// arena is destroyed and a zero `Graph` returned. The first error stops (`Json_Error`: `line` = 1-based line where
// the offending token starts, `block` = index of the entry or NO_BLOCK). Ids and `next_id` come from the file
// (never recomputed, ADR 0005 d3), `line_nr` is `NO_LINE` (d7), `detailed`/`bidirectional` come from the
// description lines as in `parse_db`. Scratch goes to `context.temp_allocator` (the caller frees it).
load_graph_json :: proc(data: []byte) -> (g: Graph, err: Error) {
	if arena_err := virtual.arena_init_growing(&g.arena); arena_err != .None {
		return {}, arena_err
	}
	err = read_graph(&g, data)
	if err != nil {
		virtual.arena_destroy(&g.arena)
		return {}, err
	}
	return g, nil
}

@(private = "file")
read_graph :: proc(g: ^Graph, data: []byte) -> Error {
	r := Json_Reader {
		data  = data,
		line  = 1,
		block = NO_BLOCK,
		arena = virtual.arena_allocator(&g.arena),
	}
	positions := make([dynamic]Sequence, context.temp_allocator) or_return
	transitions := make([dynamic]Sequence, context.temp_allocator) or_return
	pos_meta := make([dynamic]Entry_Meta, context.temp_allocator) or_return
	trans_meta := make([dynamic]Entry_Meta, context.temp_allocator) or_return
	next_block := 0
	next_id := 0
	seen: [4]bool // schema_version, next_id, positions, transitions

	expect(&r, '{') or_return
	if !accept(&r, '}') {
		for {
			key := read_key(&r) or_return
			expect(&r, ':') or_return
			idx :=
				slice.linear_search(
					[]string{"schema_version", "next_id", "positions", "transitions"},
					key,
				) or_else -1
			if idx < 0 {
				return fail(&r, .Unknown_Key)
			}
			if seen[idx] {
				return fail(&r, .Syntax)
			}
			seen[idx] = true
			switch idx {
			case 0:
				version := read_int(&r) or_return
				if version != SUPPORTED_SCHEMA_VERSION {
					return fail(&r, .Bad_Schema_Version)
				}
			case 1:
				next_id = read_int(&r) or_return
				if next_id < 1 {
					return fail(&r, .Syntax)
				}
			case 2:
				read_entries(&r, false, &positions, &pos_meta, &next_block) or_return
			case 3:
				read_entries(&r, true, &transitions, &trans_meta, &next_block) or_return
			}
			if accept(&r, ',') {
				continue
			}
			expect(&r, '}') or_return
			break
		}
	}
	for s in seen {
		if !s {
			return fail(&r, .Missing_Key)
		}
	}
	skip_ws(&r)
	if r.i < len(r.data) {
		return fail(&r, .Syntax)
	}

	// Ids need `next_id`, which may come after the entries: unique across both arrays, in 1 ..< next_id.
	used := make([]bool, next_id, context.temp_allocator) or_return
	for list, k in ([2][]Sequence{positions[:], transitions[:]}) {
		metas := pos_meta[:] if k == 0 else trans_meta[:]
		for s, n in list {
			if s.id <= 0 || s.id >= next_id || used[s.id] {
				return Json_Error {
					kind = .Duplicate_Id,
					line = metas[n].line,
					block = metas[n].block,
				}
			}
			used[s.id] = true
		}
	}

	seqs := make([]Sequence, len(positions) + len(transitions), context.temp_allocator) or_return
	copy(seqs, positions[:])
	copy(seqs[len(positions):], transitions[:])
	build(g, seqs) or_return
	g.next_id = next_id
	return nil
}

@(private = "file")
fail :: proc(r: ^Json_Reader, kind: Json_Error_Kind) -> Error {
	return Json_Error{kind = kind, line = r.line, block = r.block}
}

@(private = "file")
skip_ws :: proc(r: ^Json_Reader) {
	for r.i < len(r.data) {
		switch r.data[r.i] {
		case '\n':
			r.line += 1
			r.i += 1
		case ' ', '\t', '\r':
			r.i += 1
		case:
			return
		}
	}
}

// accept consumes `c` if it is the next token.
@(private = "file")
accept :: proc(r: ^Json_Reader, c: byte) -> bool {
	skip_ws(r)
	if r.i < len(r.data) && r.data[r.i] == c {
		r.i += 1
		return true
	}
	return false
}

@(private = "file")
expect :: proc(r: ^Json_Reader, c: byte) -> Error {
	if !accept(r, c) {
		return fail(r, .Syntax)
	}
	return nil
}

@(private = "file")
read_key :: proc(r: ^Json_Reader) -> (key: string, err: Error) {
	s := read_string(r) or_return
	return string(s[:]), nil
}

// read_string reads one JSON string into the temp allocator: every RFC 8259 escape (`\uXXXX` with surrogate pairs
// to UTF-8); raw bytes < 0x20 → `Syntax`, raw bytes that are not valid UTF-8 → `Invalid_Utf8`.
@(private = "file")
read_string :: proc(r: ^Json_Reader) -> (out: [dynamic]byte, err: Error) {
	expect(r, '"') or_return
	out = make([dynamic]byte, context.temp_allocator) or_return
	for {
		if r.i >= len(r.data) {
			return nil, fail(r, .Syntax)
		}
		c := r.data[r.i]
		switch {
		case c == '"':
			r.i += 1
			return out, nil
		case c < 0x20:
			return nil, fail(r, .Syntax)
		case c == '\\':
			r.i += 1
			read_escape(r, &out) or_return
		case c < 0x80:
			append(&out, c) or_return
			r.i += 1
		case:
			rn, size := utf8.decode_rune(r.data[r.i:])
			if rn == utf8.RUNE_ERROR && size <= 1 {
				return nil, fail(r, .Invalid_Utf8)
			}
			append(&out, ..r.data[r.i:r.i + size]) or_return
			r.i += size
		}
	}
}

@(private = "file")
read_escape :: proc(r: ^Json_Reader, out: ^[dynamic]byte) -> Error {
	if r.i >= len(r.data) {
		return fail(r, .Syntax)
	}
	c := r.data[r.i]
	r.i += 1
	switch c {
	case '"', '\\', '/':
		append(out, c) or_return
	case 'b':
		append(out, '\b') or_return
	case 'f':
		append(out, '\f') or_return
	case 'n':
		append(out, '\n') or_return
	case 'r':
		append(out, '\r') or_return
	case 't':
		append(out, '\t') or_return
	case 'u':
		u := read_hex4(r) or_return
		if u >= 0xDC00 && u <= 0xDFFF {
			return fail(r, .Syntax) // lone low surrogate
		}
		if u >= 0xD800 && u <= 0xDBFF {
			if r.i + 1 >= len(r.data) || r.data[r.i] != '\\' || r.data[r.i + 1] != 'u' {
				return fail(r, .Syntax) // lone high surrogate
			}
			r.i += 2
			low := read_hex4(r) or_return
			if low < 0xDC00 || low > 0xDFFF {
				return fail(r, .Syntax)
			}
			u = 0x10000 + (u - 0xD800) << 10 + (low - 0xDC00)
		}
		buf, n := utf8.encode_rune(rune(u))
		append(out, ..buf[:n]) or_return
	case:
		return fail(r, .Syntax)
	}
	return nil
}

@(private = "file")
read_hex4 :: proc(r: ^Json_Reader) -> (u: int, err: Error) {
	if r.i + 4 > len(r.data) {
		return 0, fail(r, .Syntax)
	}
	for k in 0 ..< 4 {
		c := r.data[r.i + k]
		d: int
		switch c {
		case '0' ..= '9':
			d = int(c - '0')
		case 'a' ..= 'f':
			d = int(c - 'a') + 10
		case 'A' ..= 'F':
			d = int(c - 'A') + 10
		case:
			return 0, fail(r, .Syntax)
		}
		u = u * 16 + d
	}
	r.i += 4
	return u, nil
}

// read_int reads a JSON integer: `-`? digits, no leading zero, no fraction or exponent, no overflow of `int`.
@(private = "file")
read_int :: proc(r: ^Json_Reader) -> (v: int, err: Error) {
	skip_ws(r)
	neg := r.i < len(r.data) && r.data[r.i] == '-'
	if neg {
		r.i += 1
	}
	start := r.i
	for r.i < len(r.data) && r.data[r.i] >= '0' && r.data[r.i] <= '9' {
		d := int(r.data[r.i] - '0')
		if v > (max(int) - d) / 10 {
			return 0, fail(r, .Syntax)
		}
		v = v * 10 + d
		r.i += 1
	}
	digits := r.i - start
	if digits == 0 || (digits > 1 && r.data[start] == '0') {
		return 0, fail(r, .Syntax)
	}
	if r.i < len(r.data) {
		switch r.data[r.i] {
		case '.', 'e', 'E':
			return 0, fail(r, .Syntax)
		}
	}
	return -v if neg else v, nil
}

// read_entries reads `"positions"` (entries with `position`) or `"transitions"` (entries with `positions`).
@(private = "file")
read_entries :: proc(
	r: ^Json_Reader,
	is_transition: bool,
	out: ^[dynamic]Sequence,
	metas: ^[dynamic]Entry_Meta,
	next_block: ^int,
) -> Error {
	expect(r, '[') or_return
	if accept(r, ']') {
		return nil
	}
	for {
		skip_ws(r)
		meta := Entry_Meta {
			line  = r.line,
			block = next_block^,
		}
		r.block = meta.block
		next_block^ += 1
		seq := read_entry(r, is_transition) or_return
		if !is_transition {
			for prev in out^ {
				if slice.equal(prev.description, seq.description) {
					return Json_Error {
						kind = .Duplicate_Description,
						line = meta.line,
						block = meta.block,
					}
				}
			}
		}
		append(out, seq) or_return
		append(metas, meta) or_return
		r.block = NO_BLOCK
		if accept(r, ',') {
			continue
		}
		return expect(r, ']')
	}
}

@(private = "file")
read_entry :: proc(r: ^Json_Reader, is_transition: bool) -> (seq: Sequence, err: Error) {
	seen: [3]bool // id, description, position(s)
	positions_key := "positions" if is_transition else "position"
	seq.line_nr = NO_LINE
	expect(r, '{') or_return
	if !accept(r, '}') {
		for {
			key := read_key(r) or_return
			expect(r, ':') or_return
			idx :=
				0 if key == "id" else 1 if key == "description" else 2 if key == positions_key else -1
			if idx < 0 {
				return {}, fail(r, .Unknown_Key)
			}
			if seen[idx] {
				return {}, fail(r, .Syntax)
			}
			seen[idx] = true
			switch idx {
			case 0:
				seq.id = read_int(r) or_return
			case 1:
				seq.description = read_description(r) or_return
			case 2:
				seq.positions = read_positions(r, is_transition) or_return
			}
			if accept(r, ',') {
				continue
			}
			expect(r, '}') or_return
			break
		}
	}
	for s in seen {
		if !s {
			return {}, fail(r, .Missing_Key)
		}
	}
	props := properties_in_desc(seq.description, context.temp_allocator) or_return
	_, seq.detailed = slice.binary_search(props, "detailed")
	_, seq.bidirectional = slice.binary_search(props, "bidirectional")
	return seq, nil
}

@(private = "file")
read_description :: proc(r: ^Json_Reader) -> (desc: []string, err: Error) {
	expect(r, '[') or_return
	lines := make([dynamic]string, context.temp_allocator) or_return
	if !accept(r, ']') {
		for {
			s := read_string(r) or_return
			append(&lines, strings.clone(string(s[:]), r.arena) or_return) or_return
			if accept(r, ',') {
				continue
			}
			expect(r, ']') or_return
			break
		}
	}
	if len(lines) == 0 {
		return nil, fail(r, .Empty_Description)
	}
	desc = slice.clone(lines[:], r.arena) or_return
	return desc, nil
}

// read_positions: one position (a named position's `position`) or an array of ≥ 2 (a transition's `positions`).
@(private = "file")
read_positions :: proc(r: ^Json_Reader, is_transition: bool) -> (out: []Position, err: Error) {
	if !is_transition {
		out = make([]Position, 1, r.arena) or_return
		out[0] = read_position(r) or_return
		return out, nil
	}
	list := make([dynamic]Position, context.temp_allocator) or_return
	expect(r, '[') or_return
	for {
		p := read_position(r) or_return
		append(&list, p) or_return
		if accept(r, ',') {
			continue
		}
		expect(r, ']') or_return
		break
	}
	if len(list) < 2 {
		return nil, fail(r, .Syntax)
	}
	out = slice.clone(list[:], r.arena) or_return
	return out, nil
}

// read_position reads `[[[x,y,z] × 23] × 2]`, each coordinate an integer in 0…Q_MAX.
@(private = "file")
read_position :: proc(r: ^Json_Reader) -> (pos: Position, err: Error) {
	expect(r, '[') or_return
	for pl in 0 ..< PLAYER_COUNT {
		if pl > 0 {
			expect(r, ',') or_return
		}
		expect(r, '[') or_return
		for j in Joint {
			if j != min(Joint) {
				expect(r, ',') or_return
			}
			expect(r, '[') or_return
			for axis in 0 ..< len(V3) {
				if axis > 0 {
					expect(r, ',') or_return
				}
				q := read_int(r) or_return
				if q < 0 || q > Q_MAX {
					return {}, fail(r, .Coordinate_Out_Of_Range)
				}
				pos[pl][j][axis] = dequantize(q, axis)
			}
			expect(r, ']') or_return
		}
		expect(r, ']') or_return
	}
	expect(r, ']') or_return
	return pos, nil
}
