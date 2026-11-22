package core

import "core:math/rand"
import "core:strings"
import "core:testing"

// Rules the implementation must follow (decided with the plan of #137, docs/original.md §1):
//  - Line rule: first byte ' ' -> position line; anything else (even empty) -> description line.
//  - A position = 4 consecutive lines of 4 spaces + 69 base62 bytes + '\n' (74 bytes each, 296 total).
//  - Precedence: (1) Missing_Final_Newline on the whole file first; (2) then lines in order, first error wins.
//  - Error `line` is 1-based, `block` is 0-based:
//      Missing_Final_Newline:     line = last line, block = NO_BLOCK.
//      Block_Without_Description: line = first position line, block = NO_BLOCK (none started yet).
//      Truncated_Block:           the file ends inside the 4 lines of a position; line = its first line;
//                                 block = index of the sequence it would belong to.
//      Bad_Position_Layout:       a ' ' line that is not 4 spaces + 69 bytes + '\n' (line = that line, even
//                                 near the end of the file), or a group of 4 position lines broken by a
//                                 non-position line (line = first line of the incomplete group).
//      Bad_Base62_Digit:          line = the line holding the bad byte.
//      Invalid_Utf8:              line = the description line; block = number of sequences started so far.
//    block of position errors = index of the sequence the position starts (sequences started so far) or extends.

@(private = "file")
Q :: [2][JOINT_COUNT][3]int

@(private = "file")
@(rodata)
ALPHABET := "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"

@(private = "file")
POS_BYTES :: 296

@(private = "file")
LINE_BYTES :: 74

// encode_position_q: the 4 lines of §1.3 for the quantized coordinates q (temp allocator).
@(private = "file")
encode_position_q :: proc(q: Q) -> string {
	sb := strings.builder_make(context.temp_allocator)
	n := 0
	for p in 0 ..< 2 {
		for j in 0 ..< JOINT_COUNT {
			for a in 0 ..< 3 {
				for d in ([2]int{q[p][j][a] / 62, q[p][j][a] % 62}) {
					if n % 69 == 0 {
						strings.write_string(&sb, "    ")
					}
					strings.write_byte(&sb, ALPHABET[d])
					n += 1
					if n % 69 == 0 {
						strings.write_byte(&sb, '\n')
					}
				}
			}
		}
	}
	return strings.to_string(sb)
}

@(private = "file")
sample_q :: proc(v: int) -> (q: Q) {
	for p in 0 ..< 2 {
		for j in 0 ..< JOINT_COUNT {
			for a in 0 ..< 3 {
				q[p][j][a] = (v + p * 7 + j * 3 + a) % (Q_MAX + 1)
			}
		}
	}
	return
}

@(private = "file")
pos_text :: proc(v := 0) -> string {
	return encode_position_q(sample_q(v))
}

@(private = "file")
cat :: proc(parts: ..string) -> string {
	return strings.concatenate(parts, context.temp_allocator)
}

@(private = "file")
with_byte :: proc(s: string, idx: int, b: byte) -> string {
	c := transmute([]byte)strings.clone(s, context.temp_allocator)
	c[idx] = b
	return string(c)
}

@(private = "file")
dq :: proc(q: int, axis: int) -> f64 {
	v := f64(q) / QUANT_SCALE
	if axis != 1 {
		v -= ENCODING_OFFSET_XZ
	}
	return v
}

@(private = "file")
check_position :: proc(t: ^testing.T, got: Position, q: Q, loc := #caller_location) {
	for p in 0 ..< 2 {
		for j in 0 ..< JOINT_COUNT {
			for a in 0 ..< 3 {
				g := transmute(u64)got[p][Joint(j)][a]
				w := transmute(u64)dq(q[p][j][a], a)
				if g != w {
					testing.expectf(
						t,
						false,
						"p%d j%d axis%d: got %v want %v",
						p,
						j,
						a,
						got[p][Joint(j)][a],
						dq(q[p][j][a], a),
						loc = loc,
					)
					return
				}
			}
		}
	}
}

@(private = "file")
parse_ok :: proc(t: ^testing.T, s: string, loc := #caller_location) -> []Sequence {
	seqs, err := parse_db(transmute([]byte)s)
	testing.expectf(t, err == nil, "unexpected error %v", err, loc = loc)
	return seqs
}

@(private = "file")
expect_parse_error :: proc(
	t: ^testing.T,
	s: string,
	kind: Parse_Error_Kind,
	line, block: int,
	loc := #caller_location,
) {
	seqs, err := parse_db(transmute([]byte)s)
	if err == nil {
		sequences_destroy(seqs)
	}
	pe, ok := err.(Parse_Error)
	testing.expectf(t, ok, "expected Parse_Error, got %v", err, loc = loc)
	if ok {
		testing.expect_value(t, pe.kind, kind, loc = loc)
		testing.expect_value(t, pe.line, line, loc = loc)
		testing.expect_value(t, pe.block, block, loc = loc)
		testing.expect(t, seqs == nil, "result must be nil on error", loc = loc)
	}
}

@(test)
test_parse_decode_alphabet :: proc(t: ^testing.T) {
	// Hand-written first line: "aa" = 0, "99" = 3843 (Q_MAX), "zA" = 25*62+26 = 1576, "Z0" = 51*62+52 = 3214.
	good := pos_text()
	line0 := cat("    aa99zAZ0", good[12:LINE_BYTES])
	s := cat("n\n", line0, good[LINE_BYTES:])
	seqs := parse_ok(t, s)
	defer sequences_destroy(seqs)
	if len(seqs) != 1 {
		testing.expect_value(t, len(seqs), 1)
		return
	}
	first := seqs[0].positions[0][0][Joint(0)] // x, y, z of joint 0; then x of joint 1 = "Z0"
	testing.expect_value(t, transmute(u64)first.x, transmute(u64)dq(0, 0))
	testing.expect_value(t, transmute(u64)first.y, transmute(u64)dq(Q_MAX, 1))
	testing.expect_value(t, transmute(u64)first.z, transmute(u64)dq(1576, 2))
	testing.expect_value(
		t,
		transmute(u64)seqs[0].positions[0][0][Joint(1)].x,
		transmute(u64)dq(3214, 0),
	)
}

@(test)
test_parse_decode_full_grid :: proc(t: ^testing.T) {
	// 84 positions x 46 slots per axis >= 3844 consecutive values: every q on every axis is decoded.
	POSITIONS :: 84
	sb := strings.builder_make(context.temp_allocator)
	strings.write_string(&sb, "grid\n")
	qs: [POSITIONS]Q
	seen: [3][Q_MAX + 1]bool
	for i in 0 ..< POSITIONS {
		for p in 0 ..< 2 {
			for j in 0 ..< JOINT_COUNT {
				for a in 0 ..< 3 {
					q := (i * 46 + p * 23 + j + a * 1000) % (Q_MAX + 1)
					qs[i][p][j][a] = q
					seen[a][q] = true
				}
			}
		}
		strings.write_string(&sb, encode_position_q(qs[i]))
	}
	for a in 0 ..< 3 {
		for q in 0 ..= Q_MAX {
			testing.expectf(t, seen[a][q], "test grid misses q=%d axis=%d", q, a)
		}
	}
	seqs := parse_ok(t, strings.to_string(sb))
	defer sequences_destroy(seqs)
	if len(seqs) != 1 || len(seqs[0].positions) != POSITIONS {
		testing.expect_value(t, len(seqs), 1)
		return
	}
	for i in 0 ..< POSITIONS {
		check_position(t, seqs[0].positions[i], qs[i])
	}
}

@(test)
test_parse_structure :: proc(t: ^testing.T) {
	a, b, c := pos_text(1), pos_text(2), pos_text(3)
	// A named position, a transition of 3 (consecutive positions merge), then two lines of description.
	s := cat("A\n", a, "T\n", a, b, c, "x\n\nz\n", b)
	seqs := parse_ok(t, s)
	defer sequences_destroy(seqs)
	if !testing.expect_value(t, len(seqs), 3) {
		return
	}
	testing.expect_value(t, len(seqs[0].positions), 1)
	testing.expect_value(t, len(seqs[1].positions), 3)
	testing.expect_value(t, len(seqs[2].positions), 1)
	testing.expect_value(t, seqs[0].line_nr, 1)
	testing.expect_value(t, seqs[1].line_nr, 6)
	testing.expect_value(t, seqs[2].line_nr, 6 + 12 + 3)
	testing.expect_value(t, len(seqs[0].description), 1)
	testing.expect_value(t, seqs[0].description[0], "A")
	testing.expect_value(t, len(seqs[2].description), 3)
	testing.expect_value(t, seqs[2].description[1], "")
	testing.expect_value(t, seqs[2].description[2], "z")
	check_position(t, seqs[1].positions[0], sample_q(1))
	check_position(t, seqs[1].positions[1], sample_q(2))
	check_position(t, seqs[1].positions[2], sample_q(3))
	check_position(t, seqs[2].positions[0], sample_q(2))
	testing.expect(t, !seqs[0].detailed && !seqs[0].bidirectional)
}

@(test)
test_parse_description_bytes :: proc(t: ^testing.T) {
	p := pos_text()
	s := cat("\n", "he said \"hi\" ¼\r\n", `back\nslash`, "\n", p)
	seqs := parse_ok(t, s)
	defer sequences_destroy(seqs)
	if !testing.expect_value(t, len(seqs), 1) {
		return
	}
	d := seqs[0].description
	if !testing.expect_value(t, len(d), 3) {
		return
	}
	testing.expect_value(t, d[0], "")
	testing.expect_value(t, d[1], "he said \"hi\" ¼\r")
	testing.expect_value(t, d[2], `back\nslash`)
	testing.expect_value(t, seqs[0].line_nr, 3)
}

@(test)
test_parse_empty_and_trailing :: proc(t: ^testing.T) {
	seqs := parse_ok(t, "")
	testing.expect_value(t, len(seqs), 0)
	sequences_destroy(seqs)
	// Only descriptions: nothing to build.
	seqs = parse_ok(t, "just\ntext\n")
	testing.expect_value(t, len(seqs), 0)
	sequences_destroy(seqs)
	// Trailing description lines after the last position are dropped.
	seqs = parse_ok(t, cat("A\n", pos_text(), "tail\nmore\n"))
	defer sequences_destroy(seqs)
	if testing.expect_value(t, len(seqs), 1) {
		testing.expect_value(t, len(seqs[0].description), 1)
	}
}

@(test)
test_parse_does_not_alias_input :: proc(t: ^testing.T) {
	buf := transmute([]byte)strings.clone(cat("Name\n", pos_text()), context.temp_allocator)
	seqs, err := parse_db(buf)
	testing.expect(t, err == nil)
	defer sequences_destroy(seqs)
	buf[0] = 'X'
	if len(seqs) == 1 {
		testing.expect_value(t, seqs[0].description[0], "Name")
	}
}

@(test)
test_tags_and_properties :: proc(t: ^testing.T) {
	desc := []string {
		"tags: b a",
		"name",
		"tags:\tc  a \r",
		"properties: detailed",
		"xtags: no",
		"tags:a\vB\fd",
	}
	tags, err := tags_in_desc(desc)
	defer delete(tags)
	testing.expect(t, err == .None)
	// Bytewise order: "B" < "a"; "tags:a" is a prefix match with no separator after the colon.
	want := []string{"B", "a", "b", "c", "d"}
	if testing.expect_value(t, len(tags), len(want)) {
		for w, i in want {
			testing.expect_value(t, tags[i], w)
		}
	}
	props, err2 := properties_in_desc(desc)
	defer delete(props)
	testing.expect(t, err2 == .None)
	if testing.expect_value(t, len(props), 1) {
		testing.expect_value(t, props[0], "detailed")
	}
	none, err3 := tags_in_desc([]string{"only name"})
	defer delete(none)
	testing.expect(t, err3 == .None)
	testing.expect_value(t, len(none), 0)
}

@(test)
test_properties_flags_in_parse :: proc(t: ^testing.T) {
	p := pos_text()
	s := cat(
		"A\nproperties: detailed\n",
		p,
		"properties: bidirectional  detailed\nB\n",
		p,
		"C\ntags: detailed\n",
		p,
	)
	seqs := parse_ok(t, s)
	defer sequences_destroy(seqs)
	if !testing.expect_value(t, len(seqs), 3) {
		return
	}
	testing.expect(t, seqs[0].detailed && !seqs[0].bidirectional)
	testing.expect(t, seqs[1].detailed && seqs[1].bidirectional)
	testing.expect(t, !seqs[2].detailed && !seqs[2].bidirectional)
}

@(test)
test_parse_error_bad_base62 :: proc(t: ^testing.T) {
	p := pos_text()
	// '!' in the second position line (line 3), first sequence.
	expect_parse_error(t, cat("A\n", with_byte(p, LINE_BYTES + 10, '!')), .Bad_Base62_Digit, 3, 0)
	// A tab replacing a digit keeps the length: still a bad digit.
	expect_parse_error(t, cat("A\n", with_byte(p, 20, '\t')), .Bad_Base62_Digit, 2, 0)
	// First line of the second sequence's position.
	expect_parse_error(t, cat("A\n", p, "B\n", with_byte(p, 4, '-')), .Bad_Base62_Digit, 7, 1)
	// Second position of the same sequence extends block 0.
	expect_parse_error(
		t,
		cat("A\n", p, with_byte(p, 3 * LINE_BYTES + 72, '_')),
		.Bad_Base62_Digit,
		9,
		0,
	)
}

@(test)
test_parse_error_truncated :: proc(t: ^testing.T) {
	p := pos_text()
	expect_parse_error(t, cat("A\n", p[:3 * LINE_BYTES]), .Truncated_Block, 2, 0)
	expect_parse_error(t, cat("A\n", p, p[:2 * LINE_BYTES]), .Truncated_Block, 6, 0)
	expect_parse_error(t, cat("A\n", p, "B\n", p[:LINE_BYTES]), .Truncated_Block, 7, 1)
}

@(test)
test_parse_error_missing_final_newline :: proc(t: ^testing.T) {
	p := pos_text()
	expect_parse_error(t, cat("A\n", p[:POS_BYTES - 1]), .Missing_Final_Newline, 5, NO_BLOCK)
	expect_parse_error(t, "abc", .Missing_Final_Newline, 1, NO_BLOCK)
	expect_parse_error(t, cat("A\n", p, "tail"), .Missing_Final_Newline, 6, NO_BLOCK)
}

@(test)
test_parse_error_block_without_description :: proc(t: ^testing.T) {
	expect_parse_error(t, pos_text(), .Block_Without_Description, 1, NO_BLOCK)
}

@(test)
test_parse_error_layout :: proc(t: ^testing.T) {
	p := pos_text()
	line2 := p[LINE_BYTES:2 * LINE_BYTES] // a full valid position line
	short := cat(p[:LINE_BYTES], line2[:LINE_BYTES - 2], "\n", p[2 * LINE_BYTES:]) // 68 digits on line 2
	long := cat(p[:LINE_BYTES], line2[:LINE_BYTES - 1], "a\n", p[2 * LINE_BYTES:]) // 70 digits on line 2
	expect_parse_error(t, cat("A\n", short), .Bad_Position_Layout, 3, 0)
	expect_parse_error(t, cat("A\n", long), .Bad_Position_Layout, 3, 0)
	// Indent of 3 spaces + 70 digits: right length, wrong indent.
	indent := cat("   a", p[4:])
	expect_parse_error(t, cat("A\n", indent), .Bad_Position_Layout, 2, 0)
	// A run of 3 position lines followed by a description, plenty of bytes left.
	expect_parse_error(t, cat("A\n", p[:3 * LINE_BYTES], "other\n", p), .Bad_Position_Layout, 2, 0)
	// CRLF file: the first position line is 75 bytes.
	crlf, _ := strings.replace_all(cat("A\n", p), "\n", "\r\n", context.temp_allocator)
	expect_parse_error(t, crlf, .Bad_Position_Layout, 2, 0)
}

@(test)
test_parse_error_invalid_utf8 :: proc(t: ^testing.T) {
	p := pos_text()
	expect_parse_error(t, cat("A\n\xff\n", p), .Invalid_Utf8, 2, 0)
	expect_parse_error(t, cat("A\n", p, "B\xc3\n", p), .Invalid_Utf8, 6, 1)
}

@(test)
test_parse_robustness_prefixes :: proc(t: ^testing.T) {
	file := cat(
		"A\n",
		pos_text(1),
		pos_text(2),
		"B\nproperties: detailed\n",
		pos_text(3),
		"C\n",
		pos_text(4),
	)
	for n in 0 ..= len(file) {
		prefix := file[:n]
		seqs, err := parse_db(transmute([]byte)prefix)
		if err == nil {
			sequences_destroy(seqs)
		} else if n > 0 && prefix[n - 1] != '\n' {
			pe, _ := err.(Parse_Error)
			testing.expectf(t, pe.kind == .Missing_Final_Newline, "prefix %d: %v", n, err)
		}
		if n % 64 == 0 {
			free_all(context.temp_allocator)
		}
	}
}

@(test)
test_parse_robustness_mutations :: proc(t: ^testing.T) {
	file := cat(
		"A\n",
		pos_text(1),
		pos_text(2),
		"B\nproperties: detailed\n",
		pos_text(3),
		"tail\n",
	)
	state := rand.create(137)
	gen := rand.default_random_generator(&state)
	context.random_generator = gen
	for _ in 0 ..< 1500 {
		c := transmute([]byte)strings.clone(file, context.temp_allocator)
		for _ in 0 ..< 1 + rand.int_max(3) {
			c[rand.int_max(len(c))] = byte(rand.int_max(256))
		}
		seqs, err := parse_db(c)
		if err == nil {
			for s in seqs {
				testing.expect(t, len(s.description) >= 1 && len(s.positions) >= 1)
			}
			sequences_destroy(seqs)
		}
		free_all(context.temp_allocator)
	}
}

@(test)
test_encoder_layout :: proc(t: ^testing.T) {
	p := pos_text(5)
	testing.expect_value(t, len(p), POS_BYTES)
	for l in 0 ..< 4 {
		testing.expect_value(t, p[l * LINE_BYTES:l * LINE_BYTES + 4], "    ")
		testing.expect_value(t, p[(l + 1) * LINE_BYTES - 1], '\n')
	}
}
