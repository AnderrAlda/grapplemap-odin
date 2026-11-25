package core

import "core:slice"
import "core:strings"
import "core:testing"

// Graph JSON reader (json_read.odin, ADR 0005). Documents are text built from the writer's layout so every line
// number and block index below can be read off `golden()`:
//   1 `{`  2 schema_version  3 next_id  4 `"positions":[`  5 entry 0 (id 1)  6 entry 1 (id 2)  7 `],`
//   8 `"transitions":[`  9 entry 2 (id 3)  10 entry 3 (id 4)  11 `]`  12 `}`

@(private = "file")
cat :: proc(parts: ..string) -> string {
	return strings.concatenate(parts, context.temp_allocator)
}

// grid(first): all coordinates 0 except the first (player 0, LeftToe, x) = `first`.
@(private = "file")
grid :: proc(first: int) -> string {
	zero := "[0,0,0]"
	head := cat(
		"[",
		strings.repeat("[0,0,0],", JOINT_COUNT - 1, context.temp_allocator),
		zero,
		"]",
	)
	if first == 0 {
		return cat("[", head, ",", head, "]")
	}
	changed, _ := strings.replace(
		head,
		"[0,0,0]",
		cat("[", itoa(first), ",0,0]"),
		1,
		context.temp_allocator,
	)
	return cat("[", changed, ",", head, "]")
}

@(private = "file")
itoa :: proc(v: int) -> string {
	buf: [24]byte
	n := 0
	x := v
	if x == 0 {
		return "0"
	}
	for x > 0 {
		buf[len(buf) - 1 - n] = byte('0' + x % 10)
		x /= 10
		n += 1
	}
	return strings.clone(string(buf[len(buf) - n:]), context.temp_allocator)
}

@(private = "file")
golden :: proc() -> string {
	g, h, i := grid(0), grid(1), grid(3000)
	return cat(
		"{\n\"schema_version\":1,\n\"next_id\":5,\n\"positions\":[\n",
		`{"id":1,"description":["A","tags: x"],"position":`,
		g,
		"},\n",
		`{"id":2,"description":["B"],"position":`,
		h,
		"}\n],\n\"transitions\":[\n",
		`{"id":3,"description":["A to B","properties: detailed"],"positions":[`,
		g,
		",",
		g,
		"]},\n",
		`{"id":4,"description":["C","properties: bidirectional"],"positions":[`,
		g,
		",",
		i,
		"]}\n]\n}\n",
	)
}

@(private = "file")
sub :: proc(doc, old, new: string) -> string {
	out, _ := strings.replace(doc, old, new, 1, context.temp_allocator)
	return out
}

@(private = "file")
expect_error :: proc(
	t: ^testing.T,
	doc: string,
	kind: Json_Error_Kind,
	line, block: int,
	loc := #caller_location,
) {
	g, err := load_graph_json(transmute([]byte)doc)
	defer graph_destroy(&g)
	e, is_json := err.(Json_Error)
	if !testing.expectf(t, is_json, "want Json_Error %v, got %v", kind, err, loc = loc) {
		return
	}
	testing.expect_value(t, e, Json_Error{kind = kind, line = line, block = block}, loc = loc)
	testing.expect(
		t,
		g.nodes == nil && g.edges == nil && g.arena.total_reserved == 0,
		"graph not zero",
		loc = loc,
	)
}

@(private = "file")
load_ok :: proc(t: ^testing.T, doc: string, loc := #caller_location) -> (g: Graph, ok: bool) {
	err: Error
	g, err = load_graph_json(transmute([]byte)doc)
	if !testing.expectf(t, err == nil, "load_graph_json: %v", err, loc = loc) {
		return {}, false
	}
	return g, true
}

@(private = "file")
reexport :: proc(t: ^testing.T, g: ^Graph, loc := #caller_location) -> string {
	b, err := export_json(g, context.temp_allocator)
	testing.expectf(t, err == nil, "export_json: %v", err, loc = loc)
	return string(b)
}

@(test)
json_read_round_trip :: proc(t: ^testing.T) {
	doc := golden()
	g, ok := load_ok(t, doc)
	if !ok {
		return
	}
	testing.expect_value(t, reexport(t, &g), doc)
	testing.expect_value(t, len(g.nodes), 3) // A, B and the anonymous end of C
	testing.expect_value(t, g.named_count, 2)
	testing.expect_value(t, len(g.edges), 2)

	// JSON → txt → JSON: ids are block numbers on import, which is what `golden()` uses.
	txt, err := export_txt(&g, context.temp_allocator)
	testing.expect_value(t, err, nil)
	h, err2 := load_graph(txt)
	testing.expect_value(t, err2, nil)
	testing.expect_value(t, reexport(t, &h), doc)
	graph_destroy(&h)

	graph_destroy(&g)
	testing.expect_value(t, g.arena.total_reserved, 0)
}

@(test)
json_read_empty_graph :: proc(t: ^testing.T) {
	doc := "{\n\"schema_version\":1,\n\"next_id\":1,\n\"positions\":[],\n\"transitions\":[]\n}\n"
	g, ok := load_ok(t, doc)
	if !ok {
		return
	}
	defer graph_destroy(&g)
	testing.expect_value(t, len(g.nodes), 0)
	testing.expect_value(t, reexport(t, &g), doc)
}

@(test)
json_read_any_whitespace_and_key_order :: proc(t: ^testing.T) {
	doc := golden()
	spaced, _ := strings.replace_all(doc, ",", ",\r\n\t", context.temp_allocator)
	spaced, _ = strings.replace_all(spaced, "[", "[ \n", context.temp_allocator)
	spaced, _ = strings.replace_all(spaced, "{", "{ ", context.temp_allocator)
	g, ok := load_ok(t, spaced)
	if ok {
		testing.expect_value(t, reexport(t, &g), doc)
		graph_destroy(&g)
	}

	zero := grid(0)
	shuffled := cat(
		`{"transitions":[],"next_id":2,"positions":[{"description":["A"],"position":`,
		zero,
		`,"id":1}],"schema_version":1}`,
	)
	want := cat(
		"{\n\"schema_version\":1,\n\"next_id\":2,\n\"positions\":[\n{\"id\":1,\"description\":[\"A\"],\"position\":",
		zero,
		"}\n],\n\"transitions\":[]\n}\n",
	)
	g2, ok2 := load_ok(t, shuffled)
	if ok2 {
		testing.expect_value(t, reexport(t, &g2), want)
		graph_destroy(&g2)
	}
}

@(test)
json_read_strings :: proc(t: ^testing.T) {
	Case :: struct {
		raw, want: string,
	}
	cases := [?]Case {
		{`"\"\\\/\b\f\n\r\té"`, "\"\\/\b\f\n\r\té"},
		{`"😀"`, "😀"},
		{`"\\n"`, "\\n"},
		{`"é😀"`, "é😀"},
		{`"\u0000"`, "\x00"},
	}
	for c in cases {
		doc := cat(
			`{"schema_version":1,"next_id":2,"positions":[{"id":1,"description":[`,
			c.raw,
			`],"position":`,
			grid(0),
			`}],"transitions":[]}`,
		)
		g, ok := load_ok(t, doc)
		if !ok {
			continue
		}
		testing.expect_value(t, g.nodes[0].description[0], c.want)
		graph_destroy(&g)
	}
	bad := [?]struct {
		raw:  string,
		kind: Json_Error_Kind,
	} {
		{`"\ud83d"`, .Syntax},
		{`"\ude00"`, .Syntax},
		{`"\ud83dx"`, .Syntax},
		{`"\ud83dA"`, .Syntax},
		{"\"a\x01\"", .Syntax},
		{`"abc`, .Syntax},
		{`"\q"`, .Syntax},
		{`"\u12"`, .Syntax},
		{"\"\xff\"", .Invalid_Utf8},
		{"\"\xc3\"", .Invalid_Utf8},
	}
	for c in bad {
		doc := cat(
			`{"schema_version":1,"next_id":2,"positions":[{"id":1,"description":[`,
			c.raw,
			`],"position":`,
			grid(0),
			`}],"transitions":[]}`,
		)
		g, err := load_graph_json(transmute([]byte)doc)
		e, _ := err.(Json_Error)
		testing.expectf(t, e.kind == c.kind && err != nil, "%q: got %v", c.raw, err)
		graph_destroy(&g)
	}
}

@(test)
json_read_errors :: proc(t: ^testing.T) {
	doc := golden()
	h := grid(1)
	Case :: struct {
		name:        string,
		doc:         string,
		kind:        Json_Error_Kind,
		line, block: int,
	}
	cases := [?]Case {
		{
			"unknown top key",
			sub(doc, `"next_id":5,`, `"next_id":5,"extra":1,`),
			.Unknown_Key,
			3,
			NO_BLOCK,
		},
		{"unknown entry key", sub(doc, `{"id":2,`, `{"id":2,"x":1,`), .Unknown_Key, 6, 1},
		{"missing next_id", sub(doc, "\"next_id\":5,\n", ""), .Missing_Key, 11, NO_BLOCK},
		{"missing position", sub(doc, cat(`,"position":`, h), ""), .Missing_Key, 6, 1},
		{
			"repeated key",
			sub(doc, `"next_id":5,`, `"next_id":5,"next_id":5,`),
			.Syntax,
			3,
			NO_BLOCK,
		},
		{
			"schema 2",
			sub(doc, `"schema_version":1`, `"schema_version":2`),
			.Bad_Schema_Version,
			2,
			NO_BLOCK,
		},
		{"q = -1", sub(doc, "[1,0,0]", "[-1,0,0]"), .Coordinate_Out_Of_Range, 6, 1},
		{"q = 3844", sub(doc, "[1,0,0]", "[3844,0,0]"), .Coordinate_Out_Of_Range, 6, 1},
		{"fraction", sub(doc, "[1,0,0]", "[1.5,0,0]"), .Syntax, 6, 1},
		{"exponent", sub(doc, "[1,0,0]", "[1e3,0,0]"), .Syntax, 6, 1},
		{"leading zero", sub(doc, "[1,0,0]", "[01,0,0]"), .Syntax, 6, 1},
		{
			"empty description",
			sub(doc, `"description":["B"]`, `"description":[]`),
			.Empty_Description,
			6,
			1,
		},
		{
			"duplicate description",
			sub(doc, `["B"]`, `["A","tags: x"]`),
			.Duplicate_Description,
			6,
			1,
		},
		{"id 0", sub(doc, `{"id":2,`, `{"id":0,`), .Duplicate_Id, 6, 1},
		{"id = next_id", sub(doc, `{"id":2,`, `{"id":5,`), .Duplicate_Id, 6, 1},
		{"id across arrays", sub(doc, `{"id":4,`, `{"id":1,`), .Duplicate_Id, 10, 3},
		{"one position", sub(doc, cat(",", grid(0), "]},"), "]},"), .Syntax, 9, 2},
		{"22 joints", sub(doc, "[0,0,0],", ""), .Syntax, 5, 0},
		{"trailing garbage", cat(doc, "x"), .Syntax, 13, NO_BLOCK},
		{"BOM", cat("\xef\xbb\xbf", doc), .Syntax, 1, NO_BLOCK},
		{"empty input", "", .Syntax, 1, NO_BLOCK},
		{"string for array", sub(doc, `"transitions":[`, `"transitions":"`), .Syntax, 8, NO_BLOCK},
	}
	for c in cases {
		testing.expect(t, c.doc != doc, c.name)
		expect_error(t, c.doc, c.kind, c.line, c.block)
	}
}

@(test)
json_read_equal_name_other_lines_is_valid :: proc(t: ^testing.T) {
	g, ok := load_ok(t, sub(golden(), `["B"]`, `["A"]`))
	if ok {
		testing.expect_value(t, g.named_count, 2)
		graph_destroy(&g)
	}
}

@(test)
json_read_truncated_never_panics :: proc(t: ^testing.T) {
	doc := golden()
	// Cutting only the final "\n" still leaves a valid document.
	for n in 0 ..< len(doc) - 1 {
		g, err := load_graph_json(transmute([]byte)doc[:n])
		if err == nil {
			testing.expectf(t, false, "prefix of %d bytes loaded", n)
			graph_destroy(&g)
		}
		free_all(context.temp_allocator)
	}
}

@(test)
json_read_data :: proc(t: ^testing.T) {
	doc := sub(sub(golden(), `"next_id":5`, `"next_id":100`), `{"id":3,`, `{"id":40,`)
	g, ok := load_ok(t, doc)
	if !ok {
		return
	}
	defer graph_destroy(&g)
	testing.expect_value(t, g.next_id, 100)
	testing.expect_value(t, g.nodes[0].id, 1)
	testing.expect_value(t, g.nodes[0].line_nr, NO_LINE)
	testing.expect_value(t, g.nodes[2].id, NO_ID)
	testing.expect_value(t, g.edges[0].sequence.id, 40)
	testing.expect_value(t, g.edges[0].sequence.line_nr, NO_LINE)
	testing.expect(
		t,
		g.edges[0].sequence.detailed && !g.edges[0].sequence.bidirectional,
		"edge 0 flags",
	)
	testing.expect(
		t,
		!g.edges[1].sequence.detailed && g.edges[1].sequence.bidirectional,
		"edge 1 flags",
	)
	testing.expect(t, slice.equal(g.nodes[0].description, []string{"A", "tags: x"}), "description")
	// x = z = −2 with q = 0; q = 1 on LeftToe x of B is 0.001 − 2.
	testing.expect_value(t, g.nodes[0].position[0][.LeftToe], V3{-2, 0, -2})
	testing.expect_value(
		t,
		g.nodes[1].position[0][.LeftToe][0],
		f64(1) / QUANT_SCALE - ENCODING_OFFSET_XZ,
	)
}
