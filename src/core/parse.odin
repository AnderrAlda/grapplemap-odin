package core

import "core:mem"
import "core:slice"
import "core:strings"
import "core:unicode/utf8"

// Parser of `GrappleMap.txt` (docs/original.md §1.1-§1.4, §1.7) with the strict position layout of ADR 0005
// decision 8. Works on bytes; no file system (src/core/CLAUDE.md).

// Sequence is one block of the file (`Sequence`, src/positions.hpp:11; `readSeqs`, src/persistence.cpp:58-116).
Sequence :: struct {
	id:            int, // stable id (ADR 0005 d3): 1-based block number in the file
	description:   []string, // lines verbatim, first = name; never empty
	positions:     []Position, // ≥ 1; 1 = named position, ≥ 2 = transition (the graph decides)
	line_nr:       int, // 0-based line of the first position line (tools/oracle/README.md, "Dumper")
	detailed:      bool, // `detailed` in properties_in_desc (src/persistence.cpp:84)
	bidirectional: bool, // `bidirectional` in properties_in_desc (src/persistence.cpp:85)
}

@(private = "file")
POSITION_LINES :: 4 // a position is 4 text lines (src/persistence.cpp:140-141)
@(private = "file")
POSITION_INDENT :: 4 // "    " before the digits of each line (src/persistence.cpp:141)
@(private = "file")
DIGITS_PER_LINE :: PLAYER_COUNT * JOINT_COUNT * len(V3) * 2 / POSITION_LINES // 69 (§1.3)
@(private = "file")
BASE62 :: 62 // digit radix (src/persistence.cpp:13-23)

@(private = "file")
TAGS_PREFIX :: "tags:" // src/graph_util.cpp:147-164
@(private = "file")
PROPERTIES_PREFIX :: "properties:" // src/metadata.cpp:37-54

// parse_db parses a whole file. On error nothing is returned and everything allocated is freed; the first error
// stops. Description strings are copied: the result does not point into `data`. Free with `sequences_destroy`.
// Scratch goes to `context.temp_allocator` (the caller frees it).
parse_db :: proc(data: []byte, allocator := context.allocator) -> (seqs: []Sequence, err: Error) {
	if len(data) == 0 {
		return nil, nil
	}
	if data[len(data) - 1] != '\n' {
		return nil, Parse_Error {
			kind = .Missing_Final_Newline,
			line = count_lines(data),
			block = NO_BLOCK,
		}
	}
	out := make([dynamic]Sequence, allocator) or_return
	err = parse_into(&out, data, allocator)
	if err == nil {
		// A failed shrink leaves `out` intact, so the error path below still frees it once.
		if _, shrink_err := shrink(&out); shrink_err != .None {
			err = shrink_err
		}
	}
	if err != nil {
		sequences_destroy(out[:], allocator)
		return nil, err
	}
	return out[:], nil
}

// sequences_destroy frees a success result of parse_db with the same allocator.
sequences_destroy :: proc(seqs: []Sequence, allocator := context.allocator) {
	for s in seqs {
		for line in s.description {
			delete(line, allocator)
		}
		delete(s.description, allocator)
		delete(s.positions, allocator)
	}
	delete(seqs, allocator)
}

// tags_in_desc: tokens of every `tags:` line, sorted bytewise and unique (`set<string>`). The strings are
// sub-slices of `desc`; free only the returned slice. Scratch goes to `context.temp_allocator`.
tags_in_desc :: proc(
	desc: []string,
	allocator := context.allocator,
) -> (
	[]string,
	mem.Allocator_Error,
) {
	return prefixed_tokens(desc, TAGS_PREFIX, allocator)
}

// properties_in_desc: same as tags_in_desc for `properties:` lines.
properties_in_desc :: proc(
	desc: []string,
	allocator := context.allocator,
) -> (
	[]string,
	mem.Allocator_Error,
) {
	return prefixed_tokens(desc, PROPERTIES_PREFIX, allocator)
}

@(private = "file")
prefixed_tokens :: proc(
	desc: []string,
	prefix: string,
	allocator: mem.Allocator,
) -> (
	out: []string,
	err: mem.Allocator_Error,
) {
	tokens := make([dynamic]string, context.temp_allocator) or_return
	for line in desc {
		if !strings.has_prefix(line, prefix) {
			continue
		}
		rest := line[len(prefix):]
		for len(rest) > 0 {
			start := 0
			for start < len(rest) && is_c_space(rest[start]) {
				start += 1
			}
			end := start
			for end < len(rest) && !is_c_space(rest[end]) {
				end += 1
			}
			if end > start {
				append(&tokens, rest[start:end]) or_return
			}
			rest = rest[end:]
		}
	}
	slice.sort(tokens[:])
	unique := slice.unique(tokens[:])
	return slice.clone(unique, allocator)
}

// is_c_space is C `isspace` in the "C" locale, the separator of `istringstream >>`.
@(private = "file")
is_c_space :: proc(c: byte) -> bool {
	return c == ' ' || c == '\t' || c == '\n' || c == '\v' || c == '\f' || c == '\r'
}

@(private = "file")
count_lines :: proc(data: []byte) -> int {
	n := 1
	for c in data {
		if c == '\n' {
			n += 1
		}
	}
	return n
}

@(private = "file")
parse_into :: proc(out: ^[dynamic]Sequence, data: []byte, allocator: mem.Allocator) -> Error {
	pending := make([dynamic]string, context.temp_allocator) or_return
	// Positions of the last sequence; its `positions` always aliases them, so sequences_destroy frees them.
	positions: [dynamic]Position
	positions.allocator = allocator
	last_was_position := false
	line := 0 // 0-based index of the line at `i`
	i := 0
	for i < len(data) {
		if data[i] != ' ' {
			end := i
			for data[end] != '\n' {
				end += 1
			}
			text := string(data[i:end])
			if !utf8.valid_string(text) {
				return Parse_Error{kind = .Invalid_Utf8, line = line + 1, block = len(out)}
			}
			append(&pending, text) or_return
			last_was_position = false
			i = end + 1
			line += 1
			continue
		}
		block := len(out) - 1 if last_was_position else len(out)
		if !last_was_position {
			if len(pending) == 0 {
				return Parse_Error {
					kind = .Block_Without_Description,
					line = line + 1,
					block = NO_BLOCK,
				}
			}
			start_sequence(out, pending[:], line, allocator) or_return
			clear(&pending)
			positions = make([dynamic]Position, allocator) or_return
		}
		pos := decode_position(data, &i, &line, block) or_return
		append(&positions, pos) or_return
		out[len(out) - 1].positions = positions[:]
		// Trim the last sequence's spare capacity once it is closed: a description line or the end of the file.
		if i >= len(data) || data[i] != ' ' {
			_ = shrink(&positions) or_return
			out[len(out) - 1].positions = positions[:]
		}
		last_was_position = true
	}
	return nil
}

@(private = "file")
start_sequence :: proc(
	out: ^[dynamic]Sequence,
	desc: []string,
	line: int,
	allocator: mem.Allocator,
) -> Error {
	append(out, Sequence{id = len(out) + 1, line_nr = line}) or_return
	seq := &out[len(out) - 1]
	seq.description = make([]string, len(desc), allocator) or_return
	for text, k in desc {
		seq.description[k] = strings.clone(text, allocator) or_return
	}
	props := properties_in_desc(desc, context.temp_allocator) or_return
	_, seq.detailed = slice.binary_search(props, "detailed")
	_, seq.bidirectional = slice.binary_search(props, "bidirectional")
	return nil
}

// decode_position reads one position at `data[i^:]` (`decodePosition`, src/persistence.cpp:33-56) on the strict
// 4 × 69 layout and advances `i` and `line` (0-based) past it. `Truncated_Block` when the file ends inside the 4
// lines (the original aborts with < 296 bytes left, src/persistence.cpp:89); a wrong-length line before that is a
// layout error, so a short last line is reported as what it is.
@(private = "file")
decode_position :: proc(
	data: []byte,
	i: ^int,
	line: ^int,
	block: int,
) -> (
	pos: Position,
	err: Error,
) {
	first := line^ + 1
	digits: [POSITION_LINES * DIGITS_PER_LINE]int
	for l in 0 ..< POSITION_LINES {
		if i^ >= len(data) {
			return {}, Parse_Error{kind = .Truncated_Block, line = first, block = block}
		}
		if data[i^] != ' ' {
			// The run of position lines ends inside the group (not a multiple of 4): report its first line.
			return {}, Parse_Error{kind = .Bad_Position_Layout, line = first, block = block}
		}
		end := i^
		for data[end] != '\n' {
			end += 1
		}
		row := data[i^:end]
		layout_error := Parse_Error {
			kind  = .Bad_Position_Layout,
			line  = line^ + 1,
			block = block,
		}
		if len(row) != POSITION_INDENT + DIGITS_PER_LINE {
			return {}, layout_error
		}
		for c in row[:POSITION_INDENT] {
			if c != ' ' {
				return {}, layout_error
			}
		}
		for c, k in row[POSITION_INDENT:] {
			d, ok := base62_value(c)
			if !ok {
				return {}, Parse_Error{kind = .Bad_Base62_Digit, line = line^ + 1, block = block}
			}
			digits[l * DIGITS_PER_LINE + k] = d
		}
		i^ = end + 1
		line^ += 1
	}
	n := 0
	for p in 0 ..< PLAYER_COUNT {
		for j in Joint {
			for axis in 0 ..< len(V3) {
				q := BASE62 * digits[n] + digits[n + 1]
				n += 2
				v := f64(q) / QUANT_SCALE
				pos[p][j][axis] = v if axis == 1 else v - ENCODING_OFFSET_XZ
			}
		}
	}
	return pos, nil
}

@(private = "file")
base62_value :: proc(c: byte) -> (int, bool) {
	switch c {
	case 'a' ..= 'z':
		return int(c - 'a'), true
	case 'A' ..= 'Z':
		return int(c - 'A') + 26, true
	case '0' ..= '9':
		return int(c - '0') + 52, true
	}
	return 0, false
}
