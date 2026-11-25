package core

import "core:math"
import "core:mem"
import "core:slice"
import "core:strings"
import "core:testing"

// Graph JSON writer (json.odin, ADR 0005). Graphs are built by hand (slices in the temp allocator; export never
// touches `Graph.arena`) so every id, description and coordinate is explicit.

@(private = "file")
cat :: proc(parts: ..string) -> string {
	return strings.concatenate(parts, context.temp_allocator)
}

// grid_position: every coordinate is `q = 0`: x = z = −2, y = 0. Its JSON is `grid_json()`.
@(private = "file")
grid_position :: proc() -> (p: Position) {
	for pl in 0 ..< PLAYER_COUNT {
		for j in Joint {
			p[pl][j] = {-2, 0, -2}
		}
	}
	return
}

// grid_json: the JSON of `grid_position()` (temp allocator), `[[[0,0,0],…23],[…]]`.
@(private = "file")
grid_json :: proc() -> string {
	player := cat(
		"[",
		strings.repeat("[0,0,0],", JOINT_COUNT - 1, context.temp_allocator),
		"[0,0,0]]",
	)
	return cat("[", player, ",", player, "]")
}

@(private = "file")
desc :: proc(lines: ..string) -> []string {
	out := make([]string, len(lines), context.temp_allocator)
	copy(out, lines)
	return out
}

@(private = "file")
node :: proc(id: int, d: []string, p := Position{}) -> Node {
	return {id = id, position = p, description = d}
}

@(private = "file")
edge :: proc(id: int, d: []string, ps: ..Position) -> Edge {
	out := make([]Position, len(ps), context.temp_allocator)
	copy(out, ps)
	return {sequence = {id = id, description = d, positions = out}}
}

@(private = "file")
hand_graph :: proc(nodes: []Node, edges: []Edge, named_count: int, next_id: int) -> Graph {
	return {nodes = nodes, edges = edges, named_count = named_count, next_id = next_id}
}

@(private = "file")
export_ok :: proc(t: ^testing.T, g: ^Graph, loc := #caller_location) -> (s: string, ok: bool) {
	b, err := export_json(g, context.temp_allocator)
	if !testing.expectf(t, err == nil, "export_json: %v", err, loc = loc) {
		return "", false
	}
	return string(b), true
}

// expect_json_error: exporting `g` fails with `kind` at `block` (`line = 0`), returns nil and allocates nothing.
@(private = "file")
expect_json_error :: proc(
	t: ^testing.T,
	g: ^Graph,
	kind: Json_Error_Kind,
	block: int,
	loc := #caller_location,
) {
	track: mem.Tracking_Allocator
	mem.tracking_allocator_init(&track, context.allocator)
	defer mem.tracking_allocator_destroy(&track)
	out, err := export_json(g, mem.tracking_allocator(&track))
	je, ok := err.(Json_Error)
	testing.expectf(t, ok, "expected Json_Error, got %v", err, loc = loc)
	if ok {
		testing.expect_value(t, je.kind, kind, loc = loc)
		testing.expect_value(t, je.block, block, loc = loc)
		testing.expect_value(t, je.line, 0, loc = loc)
	}
	testing.expect(t, out == nil, "result must be nil on error", loc = loc)
	testing.expect_value(t, track.total_allocation_count, 0, loc = loc)
	testing.expect_value(t, len(track.allocation_map), 0, loc = loc)
	if out != nil {
		delete(out, mem.tracking_allocator(&track))
	}
}

@(test)
test_json_golden_bytes :: proc(t: ^testing.T) {
	g := hand_graph(
		{node(1, desc("A", "tags: x"), grid_position())},
		{edge(2, desc("T"), grid_position(), grid_position())},
		1,
		3,
	)
	got, ok := export_ok(t, &g)
	if !ok {
		return
	}
	p := grid_json()
	want := cat(
		"{\n\"schema_version\":1,\n\"next_id\":3,\n\"positions\":[\n",
		`{"id":1,"description":["A","tags: x"],"position":`,
		p,
		"}\n],\n\"transitions\":[\n",
		`{"id":2,"description":["T"],"positions":[`,
		p,
		",",
		p,
		"]}\n]\n}\n",
	)
	testing.expect_value(t, got, want)
}

@(test)
test_json_two_entries_comma :: proc(t: ^testing.T) {
	g := hand_graph(
		{node(1, desc("A"), grid_position()), node(2, desc("B"), grid_position())},
		{
			edge(3, desc("T"), grid_position(), grid_position()),
			edge(4, desc("U"), grid_position(), grid_position()),
		},
		2,
		5,
	)
	got, ok := export_ok(t, &g)
	if !ok {
		return
	}
	testing.expect_value(
		t,
		strings.count(got, "}},\n{\"id\":") + strings.count(got, "]},\n{\"id\":"),
		2,
	)
	testing.expect(t, strings.has_suffix(got, "]}\n]\n}\n"), "ending")
	testing.expect_value(t, strings.count(got, "\n"), 12)
}

@(test)
test_json_empty_graph :: proc(t: ^testing.T) {
	g := hand_graph(nil, nil, 0, 1)
	got, ok := export_ok(t, &g)
	if !ok {
		return
	}
	testing.expect_value(
		t,
		got,
		"{\n\"schema_version\":1,\n\"next_id\":1,\n\"positions\":[],\n\"transitions\":[]\n}\n",
	)
}

@(test)
test_json_only_transitions_one_line_positions :: proc(t: ^testing.T) {
	g := hand_graph(nil, {edge(1, desc("T"), grid_position(), grid_position())}, 0, 2)
	got, ok := export_ok(t, &g)
	if !ok {
		return
	}
	testing.expect(t, strings.contains(got, "\"positions\":[],\n\"transitions\":[\n{"), got)
}

@(test)
test_json_escaping :: proc(t: ^testing.T) {
	line := "q\" b\\ n\\n r\r t\t c\x01 f\x0c \x08 \x1f / ¼ \x7f"
	g := hand_graph({node(1, desc(line, ""), grid_position())}, nil, 1, 2)
	got, ok := export_ok(t, &g)
	if !ok {
		return
	}
	want := `"description":["q\" b\\ n\\n r\r t\t c\u0001 f\f \b \u001f / ¼ ` + "\x7f" + `",""]`
	testing.expectf(t, strings.contains(got, want), "escaped line not found in %q", got)
}

@(test)
test_json_quantization_edges :: proc(t: ^testing.T) {
	lo, hi: Position
	for pl in 0 ..< PLAYER_COUNT {
		for j in Joint {
			lo[pl][j] = {-2, 0, -2}
			hi[pl][j] = {
				f64(Q_MAX) / QUANT_SCALE - 2,
				f64(Q_MAX) / QUANT_SCALE,
				f64(Q_MAX) / QUANT_SCALE - 2,
			}
		}
	}
	g := hand_graph({node(1, desc("L"), lo), node(2, desc("H"), hi)}, nil, 2, 3)
	got, ok := export_ok(t, &g)
	if !ok {
		return
	}
	testing.expect(t, strings.contains(got, "[0,0,0]"))
	testing.expect(t, strings.contains(got, "[3843,3843,3843]"))
	testing.expect(t, !strings.contains(got, "3844"))
}

@(test)
test_json_matches_txt_digits :: proc(t: ^testing.T) {
	// The same graph through export_txt and export_json: decode both, same 138 integers per position.
	s := cat("A\n", pos_text(1), "B\n", pos_text(9))
	g, err := load_graph(transmute([]byte)s)
	if !testing.expectf(t, err == nil, "load_graph: %v", err) {
		return
	}
	defer graph_destroy(&g)
	got, ok := export_ok(t, &g)
	if !ok {
		return
	}
	txt, terr := export_txt(&g, context.temp_allocator)
	if !testing.expectf(t, terr == nil, "export_txt: %v", terr) {
		return
	}
	digits := "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
	rest := string(txt)
	json_rest := got
	for _ in 0 ..< 2 {
		// txt: skip the description line, take the 4 position lines.
		nl := strings.index_byte(rest, '\n')
		rest = rest[nl + 1:]
		all_digits := make([dynamic]byte, context.temp_allocator)
		for _ in 0 ..< 4 {
			end := strings.index_byte(rest, '\n')
			append(&all_digits, ..transmute([]byte)rest[4:end])
			rest = rest[end + 1:]
		}
		want := make([dynamic]int, context.temp_allocator)
		for k := 0; k < len(all_digits); k += 2 {
			hi := strings.index_byte(digits, all_digits[k])
			lo := strings.index_byte(digits, all_digits[k + 1])
			append(&want, hi * 62 + lo)
		}
		// json: every integer between `"position":` and the closing `}`.
		start := strings.index(json_rest, `"position":`) + len(`"position":`)
		end := start + strings.index_byte(json_rest[start:], '}')
		have := make([dynamic]int, context.temp_allocator)
		cur := -1
		for c in json_rest[start:end] {
			if c >= '0' && c <= '9' {
				cur = max(cur, 0) * 10 + int(c - '0')
			} else if cur >= 0 {
				append(&have, cur)
				cur = -1
			}
		}
		testing.expect_value(t, len(want), PLAYER_COUNT * JOINT_COUNT * len(V3))
		testing.expect(t, slice.equal(have[:], want[:]), "JSON and txt integers differ")
		json_rest = json_rest[end:]
	}
}

@(test)
test_json_skips_anonymous_and_keeps_ids :: proc(t: ^testing.T) {
	// Node order, then edge order; ids as stored (not indices); anonymous node 2 not written.
	g := hand_graph(
		{
			node(7, desc("A"), grid_position()),
			node(3, desc("B"), grid_position()),
			node(NO_ID, nil, grid_position()),
		},
		{
			edge(9, desc("T"), grid_position(), grid_position()),
			edge(5, desc("U"), grid_position(), grid_position()),
		},
		2,
		10,
	)
	got, ok := export_ok(t, &g)
	if !ok {
		return
	}
	i7 := strings.index(got, `{"id":7,`)
	i3 := strings.index(got, `{"id":3,`)
	i9 := strings.index(got, `{"id":9,`)
	i5 := strings.index(got, `{"id":5,`)
	testing.expect(t, 0 < i7 && i7 < i3 && i3 < i9 && i9 < i5, "order")
	testing.expect_value(t, strings.count(got, `{"id":`), 4)
	testing.expect(t, strings.contains(got, "\"next_id\":10,"))
}

@(test)
test_json_errors :: proc(t: ^testing.T) {
	ok_node := node(1, desc("A"), grid_position())
	bad_pos := grid_position()
	bad_pos[1][.Head] = {1000, 0, 0}
	nan_pos := grid_position()
	nan_pos[0][.Head].y = math.nan_f64()

	{ 	// empty description on a named node
		g := hand_graph({ok_node, node(2, nil, grid_position())}, nil, 2, 3)
		expect_json_error(t, &g, .Empty_Description, 1)
	}
	{ 	// empty description on an edge: block = written nodes + index
		g := hand_graph({ok_node}, {edge(2, nil, grid_position(), grid_position())}, 1, 3)
		expect_json_error(t, &g, .Empty_Description, 1)
	}
	{
		g := hand_graph({ok_node, node(2, desc("A"), grid_position())}, nil, 2, 3)
		expect_json_error(t, &g, .Duplicate_Description, 1)
	}
	{
		g := hand_graph({node(1, desc("A"), bad_pos)}, nil, 1, 2)
		expect_json_error(t, &g, .Coordinate_Out_Of_Range, 0)
	}
	{
		g := hand_graph({ok_node}, {edge(2, desc("T"), grid_position(), nan_pos)}, 1, 3)
		expect_json_error(t, &g, .Coordinate_Out_Of_Range, 1)
	}
	{ 	// repeated id
		g := hand_graph({ok_node, node(1, desc("B"), grid_position())}, nil, 2, 3)
		expect_json_error(t, &g, .Duplicate_Id, 1)
	}
	{ 	// id 0, id >= next_id
		g := hand_graph({node(0, desc("A"), grid_position())}, nil, 1, 2)
		expect_json_error(t, &g, .Duplicate_Id, 0)
		g = hand_graph({node(2, desc("A"), grid_position())}, nil, 1, 2)
		expect_json_error(t, &g, .Duplicate_Id, 0)
	}
	{ 	// an edge repeating a node's id
		g := hand_graph({ok_node}, {edge(1, desc("T"), grid_position(), grid_position())}, 1, 2)
		expect_json_error(t, &g, .Duplicate_Id, 1)
	}
	{
		g := hand_graph({node(1, desc("ok", "bad\xff"), grid_position())}, nil, 1, 2)
		expect_json_error(t, &g, .Invalid_Utf8, 0)
	}
}

@(test)
test_json_no_leaks :: proc(t: ^testing.T) {
	g := hand_graph({node(1, desc("A"), grid_position())}, nil, 1, 2)
	track: mem.Tracking_Allocator
	mem.tracking_allocator_init(&track, context.allocator)
	defer mem.tracking_allocator_destroy(&track)
	out, err := export_json(&g, mem.tracking_allocator(&track))
	testing.expect(t, err == nil)
	testing.expect_value(t, track.total_allocation_count, 1)
	delete(out, mem.tracking_allocator(&track))
	testing.expect_value(t, len(track.allocation_map), 0)
}
