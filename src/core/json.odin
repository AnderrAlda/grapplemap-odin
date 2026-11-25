package core

import "core:slice"
import "core:strconv"
import "core:unicode/utf8"

// Writer of the graph JSON (ADR 0005), by hand, not `core:encoding/json`: the layout is a format commitment.
// Exactly (every `\n` below is a byte; no other whitespace):
//
//	{\n
//	"schema_version":1,\n
//	"next_id":N,\n
//	"positions":[\n
//	{"id":I,"description":["…","…"],"position":[[[x,y,z],…23],[…]]},\n
//	…\n
//	],\n
//	"transitions":[\n
//	{"id":I,"description":["…"],"positions":[[[[x,y,z],…],[…]],…]},\n
//	…\n
//	]\n
//	}\n
//
// Entries are separated by `,\n`, the last has none; an empty array is `"positions":[],` / `"transitions":[]` on one
// line. Coordinates are the original's quantization (`quantize`, shared with export_txt), plain decimal integers.

@(private = "file")
JSON_SCHEMA_VERSION :: 1
@(private = "file")
@(rodata)
HEX_DIGITS := "0123456789abcdef"

// export_json writes `g` as the graph JSON into one buffer on `allocator` (free with `delete`):
// `positions` = nodes with a non-empty description in node order (anonymous ones are skipped), `transitions` =
// edges in order. Strings are JSON-escaped (RFC 8259): `"` `\` and `\b \f \n \r \t` short forms, other bytes below
// 0x20 as `\u00xx` (lowercase), everything else verbatim.
//
// Errors (`Json_Error`, `line = 0`, `block` = 0-based index of the entry in the output: positions, then
// transitions), the first stops; checked before allocating, so a failed export allocates nothing:
//  - empty description of a node with `index < named_count`, or of an edge → `Empty_Description`; a line that is not valid UTF-8 → `Invalid_Utf8`;
//  - a written node whose whole description equals an earlier written node's → `Duplicate_Description`;
//  - a coordinate outside 0…Q_MAX after rounding, or NaN → `Coordinate_Out_Of_Range`;
//  - an id `<= 0`, `>= g.next_id` or already used by an earlier entry → `Duplicate_Id`.
// A graph from `load_graph` never triggers any of them.
export_json :: proc(g: ^Graph, allocator := context.allocator) -> (out: []byte, err: Error) {
	size := check_json(g) or_return
	out = make([]byte, size, allocator) or_return
	w := Json_Writer {
		buf = out,
	}
	write_json(&w, g)
	assert(w.n == size)
	return out, nil
}

// write_json emits the whole document; with `w.buf == nil` it only counts.
@(private = "file")
write_json :: proc(w: ^Json_Writer, g: ^Graph) {
	put(w, "{\n\"schema_version\":")
	put_int(w, JSON_SCHEMA_VERSION)
	put(w, ",\n\"next_id\":")
	put_int(w, g.next_id)
	put(w, ",\n\"positions\":[")
	first := true
	for &x, i in g.nodes {
		if len(x.description) == 0 && i >= g.named_count {
			continue
		}
		put_separator(w, &first)
		put_entry_head(w, x.id, x.description)
		put(w, ",\"position\":")
		put_position(w, &x.position)
		put(w, "}")
	}
	put(w, "],\n\"transitions\":[" if first else "\n],\n\"transitions\":[")
	first = true
	for &e in g.edges {
		put_separator(w, &first)
		put_entry_head(w, e.sequence.id, e.sequence.description)
		put(w, ",\"positions\":[")
		for &p, i in e.sequence.positions {
			if i > 0 {
				put(w, ",")
			}
			put_position(w, &p)
		}
		put(w, "]}")
	}
	put(w, "]\n}\n" if first else "\n]\n}\n")
}

// Json_Writer fills `buf`, which `check_json` sized exactly; `buf = nil` makes it only count (`n`).
@(private = "file")
Json_Writer :: struct {
	buf: []byte,
	n:   int,
}

@(private = "file")
put :: proc(w: ^Json_Writer, s: string) {
	if w.buf != nil {
		copy(w.buf[w.n:], s)
	}
	w.n += len(s)
}

@(private = "file")
put_byte :: proc(w: ^Json_Writer, b: byte) {
	if w.buf != nil {
		w.buf[w.n] = b
	}
	w.n += 1
}

@(private = "file")
put_int :: proc(w: ^Json_Writer, v: int) {
	tmp: [24]byte
	put(w, strconv.write_int(tmp[:], i64(v), 10))
}

// put_separator starts an entry: the first one after `[` needs a `\n`, the next ones `,\n`.
@(private = "file")
put_separator :: proc(w: ^Json_Writer, first: ^bool) {
	put(w, "\n" if first^ else ",\n")
	first^ = false
}

@(private = "file")
put_entry_head :: proc(w: ^Json_Writer, id: int, desc: []string) {
	put(w, "{\"id\":")
	put_int(w, id)
	put(w, ",\"description\":[")
	for line, i in desc {
		if i > 0 {
			put(w, ",")
		}
		put_string(w, line)
	}
	put(w, "]")
}

@(private = "file")
put_string :: proc(w: ^Json_Writer, s: string) {
	put_byte(w, '"')
	for c in transmute([]byte)s {
		switch c {
		case '"':
			put(w, "\\\"")
		case '\\':
			put(w, "\\\\")
		case '\b':
			put(w, "\\b")
		case '\f':
			put(w, "\\f")
		case '\n':
			put(w, "\\n")
		case '\r':
			put(w, "\\r")
		case '\t':
			put(w, "\\t")
		case 0 ..< 0x20:
			put(w, "\\u00")
			put_byte(w, HEX_DIGITS[c >> 4])
			put_byte(w, HEX_DIGITS[c & 0xf])
		case:
			put_byte(w, c)
		}
	}
	put_byte(w, '"')
}

// put_position writes `[[[x,y,z],…23],[…]]` of a position already checked by check_position_json.
@(private = "file")
put_position :: proc(w: ^Json_Writer, p: ^Position) {
	put(w, "[")
	for pl in 0 ..< PLAYER_COUNT {
		put(w, "[" if pl == 0 else ",[")
		for j in Joint {
			if j != min(Joint) {
				put(w, ",")
			}
			put(w, "[")
			for axis in 0 ..< len(V3) {
				q, ok := quantize(p[pl][j][axis], axis)
				assert(ok, "put_position on an unchecked position")
				if axis > 0 {
					put(w, ",")
				}
				put_int(w, q)
			}
			put(w, "]")
		}
		put(w, "]")
	}
	put(w, "]")
}

// check_json applies the rules of export_json and returns the size of the output, by running the writer in
// counting mode (so the size cannot drift from the bytes).
@(private = "file")
check_json :: proc(g: ^Graph) -> (size: int, err: Error) {
	seen := make([]bool, max(g.next_id, 0), context.temp_allocator) or_return
	block := 0
	for &x, i in g.nodes {
		if len(x.description) == 0 && i >= g.named_count {
			continue
		}
		check_entry(g, x.id, x.description, seen, block) or_return
		for &y in g.nodes[:i] {
			if len(y.description) != 0 && slice.equal(y.description, x.description) {
				return 0, Json_Error{kind = .Duplicate_Description, block = block}
			}
		}
		check_position_json(&x.position, block) or_return
		block += 1
	}
	for &e in g.edges {
		check_entry(g, e.sequence.id, e.sequence.description, seen, block) or_return
		for &p in e.sequence.positions {
			check_position_json(&p, block) or_return
		}
		block += 1
	}
	// Counting pass: the same writer with no buffer.
	w: Json_Writer
	write_json(&w, g)
	return w.n, nil
}

@(private = "file")
check_entry :: proc(g: ^Graph, id: int, desc: []string, seen: []bool, block: int) -> Error {
	if len(desc) == 0 {
		return Json_Error{kind = .Empty_Description, block = block}
	}
	for line in desc {
		if !utf8.valid_string(line) {
			return Json_Error{kind = .Invalid_Utf8, block = block}
		}
	}
	if id <= 0 || id >= g.next_id {
		return Json_Error{kind = .Duplicate_Id, block = block}
	}
	if seen[id] {
		return Json_Error{kind = .Duplicate_Id, block = block}
	}
	seen[id] = true
	return nil
}

@(private = "file")
check_position_json :: proc(p: ^Position, block: int) -> Error {
	for pl in 0 ..< PLAYER_COUNT {
		for j in Joint {
			for axis in 0 ..< len(V3) {
				if _, ok := quantize(p[pl][j][axis], axis); !ok {
					return Json_Error{kind = .Coordinate_Out_Of_Range, block = block}
				}
			}
		}
	}
	return nil
}
