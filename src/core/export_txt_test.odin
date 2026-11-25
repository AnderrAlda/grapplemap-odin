package core

import "core:math"
import "core:mem"
import "core:strings"
import "core:testing"

// Export to `GrappleMap.txt` (export_txt.odin, `save`, src/persistence.cpp:118-151, :241-251). Text inputs go
// through `load_graph` on texts made with `pos_text` (parse_test.odin); error cases on hand-built `Graph`s whose
// slices live in the temp allocator (export never touches `Graph.arena`).

@(private = "file")
LINE_DIGITS :: 69

@(private = "file")
cat :: proc(parts: ..string) -> string {
	return strings.concatenate(parts, context.temp_allocator)
}

// export_loaded: `export_txt(load_graph(s))` as a string (temp allocator); `ok = false` on any error.
@(private = "file")
export_loaded :: proc(
	t: ^testing.T,
	s: string,
	loc := #caller_location,
) -> (
	out: string,
	ok: bool,
) {
	g, err := load_graph(transmute([]byte)s)
	if !testing.expectf(t, err == nil, "load_graph: %v", err, loc = loc) {
		return "", false
	}
	defer graph_destroy(&g)
	b, eerr := export_txt(&g, context.temp_allocator)
	if !testing.expectf(t, eerr == nil, "export_txt: %v", eerr, loc = loc) {
		return "", false
	}
	return string(b), true
}

// expect_export_error: exporting `g` fails with `kind` at `block` (`line = 0`), returns nil and allocates nothing
// that is left behind (a tracking allocator checks it).
@(private = "file")
expect_export_error :: proc(
	t: ^testing.T,
	g: ^Graph,
	kind: Export_Error_Kind,
	block: int,
	loc := #caller_location,
) {
	track: mem.Tracking_Allocator
	mem.tracking_allocator_init(&track, context.allocator)
	defer mem.tracking_allocator_destroy(&track)
	out, err := export_txt(g, mem.tracking_allocator(&track))
	ee, ok := err.(Export_Error)
	testing.expectf(t, ok, "expected Export_Error, got %v", err, loc = loc)
	if ok {
		testing.expect_value(t, ee.kind, kind, loc = loc)
		testing.expect_value(t, ee.block, block, loc = loc)
		testing.expect_value(t, ee.line, 0, loc = loc)
	}
	testing.expect(t, out == nil, "result must be nil on error", loc = loc)
	testing.expect_value(t, len(track.allocation_map), 0, loc = loc)
	if out != nil {
		delete(out, mem.tracking_allocator(&track))
	}
}

// grid_position: every coordinate is `q = 0` ("aa"): x = z = −2, y = 0.
@(private = "file")
grid_position :: proc() -> (p: Position) {
	for pl in 0 ..< PLAYER_COUNT {
		for j in Joint {
			p[pl][j] = {-2, 0, -2}
		}
	}
	return
}

@(private = "file")
desc :: proc(lines: ..string) -> []string {
	out := make([]string, len(lines), context.temp_allocator)
	copy(out, lines)
	return out
}

@(private = "file")
node :: proc(d: []string, p := Position{}) -> Node {
	return {position = p, description = d, line_nr = 0}
}

@(private = "file")
edge :: proc(d: []string, a, b: Position) -> Edge {
	ps := make([]Position, 2, context.temp_allocator)
	ps[0], ps[1] = a, b
	return {sequence = {description = d, positions = ps}}
}

@(private = "file")
hand_graph :: proc(nodes: []Node, edges: []Edge, named_count: int) -> Graph {
	return {nodes = nodes, edges = edges, named_count = named_count}
}

@(test)
test_export_empty :: proc(t: ^testing.T) {
	g: Graph
	out, err := export_txt(&g)
	testing.expect(t, err == nil)
	testing.expect_value(t, len(out), 0)
	delete(out)
}

@(test)
test_export_round_trip_text :: proc(t: ^testing.T) {
	// Two named positions and a transition between them: the file comes back byte for byte.
	s := cat(
		"\n", // a first description line ""
		"Closed guard ¼ \"q\"\n",
		"tags: guard top\n",
		pos_text(1),
		"B\r\n", // '\r' is written verbatim
		"ref: x\n",
		pos_text(2),
		"Escape\n",
		`with a literal \n inside`,
		"\n",
		"properties: detailed bidirectional\n",
		pos_text(1),
		pos_text(5),
		pos_text(2),
	)
	out, ok := export_loaded(t, s)
	if ok {
		testing.expect(t, out == s, "export differs from the input")
	}
}

@(test)
test_export_writer_order :: proc(t: ^testing.T) {
	// A transition before the named position: the named position is written first (§1.5). Description lines
	// with no positions after them are dropped by the parser.
	s := cat("T\n", pos_text(1), pos_text(2), "A\n", pos_text(3), "dangling\n")
	out, ok := export_loaded(t, s)
	if ok {
		testing.expect(
			t,
			out == cat("A\n", pos_text(3), "T\n", pos_text(1), pos_text(2)),
			"named positions must come first",
		)
	}
}

@(test)
test_export_skips_anonymous_nodes :: proc(t: ^testing.T) {
	// No named position: the ends of the transition become anonymous nodes, which have no description.
	s := cat("T\n", pos_text(1), pos_text(2))
	out, ok := export_loaded(t, s)
	if ok {
		testing.expect(t, out == s, "only the transition block is written")
	}
}

@(test)
test_export_edge_coordinates :: proc(t: ^testing.T) {
	// q = 0 and q = 3843 (Q_MAX, absent from the DB) on every axis, in the 4 × 69 layout.
	line_lo := cat("    ", strings.repeat("a", LINE_DIGITS, context.temp_allocator), "\n")
	line_hi := cat("    ", strings.repeat("9", LINE_DIGITS, context.temp_allocator), "\n")
	lo := strings.repeat(line_lo, 4, context.temp_allocator)
	hi := strings.repeat(line_hi, 4, context.temp_allocator)
	s := cat("lo\n", lo, "hi\n", hi, "t\n", lo, hi)
	out, ok := export_loaded(t, s)
	if ok {
		testing.expect(t, out == s, "edge coordinates must round-trip")
	}
}

@(test)
test_export_full_grid :: proc(t: ^testing.T) {
	// Every q in 0…3843 on every axis: the decoded f64 `(62·d0 + d1) / 1000 (− 2)` encodes back to its digits.
	POSITIONS :: 84 // 84 × 46 slots per axis ≥ 3844
	ALPHABET :: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
	sb := strings.builder_make(context.temp_allocator)
	strings.write_string(&sb, "grid\n")
	alphabet := ALPHABET
	for i in 0 ..< POSITIONS {
		n := 0
		for p in 0 ..< PLAYER_COUNT {
			for j in 0 ..< JOINT_COUNT {
				for a in 0 ..< 3 {
					q := (i * 46 + p * 23 + j + a * 1000) % (Q_MAX + 1)
					for d in ([2]int{q / 62, q % 62}) {
						if n % LINE_DIGITS == 0 {
							strings.write_string(&sb, "    ")
						}
						strings.write_byte(&sb, alphabet[d])
						n += 1
						if n % LINE_DIGITS == 0 {
							strings.write_byte(&sb, '\n')
						}
					}
				}
			}
		}
	}
	s := strings.to_string(sb)
	out, ok := export_loaded(t, s)
	if ok {
		testing.expect(t, out == s, "grid values must round-trip")
	}
}

@(test)
test_export_rounding :: proc(t: ^testing.T) {
	// `int(std::round((x + 2) * 1000))`, half away from zero. Expected digits computed outside Odin (Python
	// `Decimal(v).quantize(1, ROUND_HALF_UP)` on the exact product):
	//   x = −1.9975 → (x + 2) · 1000 = 2.4999999999999467 → 2 "ac" (x · 1000 + 2000 would give 3 "ad");
	//   y = 0.0025 → 2.5 → 3 "ad" (round-half-even would give 2);  z = −1.9995 → 0.49999999999994493 → 0 "aa";
	//   y = 0.0019 → 1.9 → 2 "ac" (truncation would give 1);       x = −2.0004 → −0.4 → −0 → 0 "aa";
	//   y = 1.0005 → 1000.5 → 1001 "qj";                           z = 1.8435 → 3843.4999999999995 → 3843 "99".
	p := grid_position()
	p[0][.LeftToe] = {-1.9975, 0.0025, -1.9995}
	p[0][.RightToe] = {-2.0004, 0.0019, -2}
	p[0][.LeftHeel] = {-2, 1.0005, 1.8435}
	nodes := []Node{node(desc("R"), p)}
	g := hand_graph(nodes, nil, 1)
	out, err := export_txt(&g, context.temp_allocator)
	if !testing.expectf(t, err == nil, "export_txt: %v", err) {
		return
	}
	rest := strings.repeat("a", LINE_DIGITS - 18, context.temp_allocator)
	line := cat("    ", strings.repeat("a", LINE_DIGITS, context.temp_allocator), "\n")
	want := cat("R\n", "    acadaa", "aaacaa", "aaqj99", rest, "\n", line, line, line)
	testing.expectf(t, string(out) == want, "got\n%s\nwant\n%s", string(out), want)
}

@(test)
test_export_allocator :: proc(t: ^testing.T) {
	track: mem.Tracking_Allocator
	mem.tracking_allocator_init(&track, context.allocator)
	defer mem.tracking_allocator_destroy(&track)
	nodes := []Node{node(desc("A"), grid_position())}
	g := hand_graph(nodes, nil, 1)
	out, err := export_txt(&g, mem.tracking_allocator(&track))
	testing.expect(t, err == nil)
	testing.expect_value(t, len(out), 2 + 4 * (4 + LINE_DIGITS + 1))
	_, found := track.allocation_map[raw_data(out)]
	testing.expect(t, found, "the result must be on the given allocator")
	delete(out, mem.tracking_allocator(&track))
	testing.expect_value(t, len(track.allocation_map), 0)
}

@(test)
test_export_error_description_starts_with_space :: proc(t: ^testing.T) {
	nodes := []Node{node(desc("A")), node(desc("B", " indented"))}
	g := hand_graph(nodes, nil, 2)
	expect_export_error(t, &g, .Description_Starts_With_Space, 1)
}

@(test)
test_export_error_description_has_newline :: proc(t: ^testing.T) {
	nodes := []Node{node(desc("A\nB"))}
	g := hand_graph(nodes, nil, 1)
	expect_export_error(t, &g, .Description_Has_Newline, 0)
}

@(test)
test_export_error_empty_description_node :: proc(t: ^testing.T) {
	nodes := []Node{node(desc("A")), node(nil)}
	g := hand_graph(nodes, nil, 2)
	expect_export_error(t, &g, .Empty_Description, 1)
}

@(test)
test_export_error_empty_description_edge :: proc(t: ^testing.T) {
	// Blocks in the output: named node 0, the anonymous node is not written, edges 1 and 2.
	p := grid_position()
	nodes := []Node{node(desc("A"), p), node(nil, p)}
	edges := []Edge{edge(desc("T"), p, p), edge(nil, p, p)}
	g := hand_graph(nodes, edges, 1)
	expect_export_error(t, &g, .Empty_Description, 2)
}

@(test)
test_export_error_duplicate_description :: proc(t: ^testing.T) {
	// The whole description counts: "A" + "x" and "A" + "y" differ; the later duplicate is reported.
	nodes := []Node {
		node(desc("A", "x")),
		node(desc("A", "y")),
		node(desc("B")),
		node(desc("A", "y")),
	}
	g := hand_graph(nodes, nil, 4)
	expect_export_error(t, &g, .Duplicate_Description, 3)
}

@(test)
test_export_duplicate_edge_description_is_fine :: proc(t: ^testing.T) {
	p := grid_position()
	edges := []Edge{edge(desc("T"), p, p), edge(desc("T"), p, p)}
	g := hand_graph(nil, edges, 0)
	out, err := export_txt(&g, context.temp_allocator)
	testing.expectf(t, err == nil, "export_txt: %v", err)
	testing.expect_value(t, len(out), 2 * (2 + 2 * 4 * (4 + LINE_DIGITS + 1)))
}

@(test)
test_export_error_coordinate_too_big :: proc(t: ^testing.T) {
	// y = 3.8435 → 3843.5 → 3844, one past Q_MAX. In an edge: block = named nodes + edge index.
	p := grid_position()
	bad := p
	bad[1][.Head].y = 3.8435
	nodes := []Node{node(desc("A"), p)}
	edges := []Edge{edge(desc("T"), p, p), edge(desc("U"), p, bad)}
	g := hand_graph(nodes, edges, 1)
	expect_export_error(t, &g, .Coordinate_Out_Of_Range, 2)
}

@(test)
test_export_error_coordinate_negative :: proc(t: ^testing.T) {
	// x = −2.0006 → −0.6 → −1.
	p := grid_position()
	p[0][.Core].x = -2.0006
	nodes := []Node{node(desc("A"), p)}
	g := hand_graph(nodes, nil, 1)
	expect_export_error(t, &g, .Coordinate_Out_Of_Range, 0)
}

@(test)
test_export_error_coordinate_nan :: proc(t: ^testing.T) {
	p := grid_position()
	p[1][.Neck].z = math.nan_f64()
	nodes := []Node{node(desc("A"), p)}
	g := hand_graph(nodes, nil, 1)
	expect_export_error(t, &g, .Coordinate_Out_Of_Range, 0)
}

@(test)
test_export_error_first_wins :: proc(t: ^testing.T) {
	// The first block in output order with an error is reported; within a block, the description first.
	p := grid_position()
	bad := p
	bad[0][.Head].x = 100
	nodes := []Node{node(desc("A"), p), node(desc(" B"), bad), node(desc("C\n"))}
	g := hand_graph(nodes, nil, 3)
	expect_export_error(t, &g, .Description_Starts_With_Space, 1)
}
