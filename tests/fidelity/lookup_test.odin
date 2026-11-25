package fidelity

import "app:core"
import "core:testing"

// Lookups by name of `core` (lookup.odin, src/metadata.cpp:66-124) over the shared DB graph. Named block = node
// index (§2.2, §10.2). Values that depend on the DB are computed from the graph, except those block numbers.

@(test)
test_lookups_db :: proc(t: ^testing.T) {
	g, ok := shared_graph(t)
	if !ok {
		return
	}
	// §10.2 duplicate_description: 249 and 477 share the lookup name `spiderweb w/o leg over head`; the lower wins.
	n, found := core.node_by_desc(g, "spiderweb w/o leg over head")
	testing.expectf(t, found && n == 249, "spiderweb: %v, %v", n, found)
	if testing.expect(t, len(g.nodes) > 477 && len(g.nodes[477].description) > 0) {
		testing.expect_value(t, g.nodes[477].description[0], "spiderweb\\nw/o leg\\nover head")
	}
	n, found = core.node_by_desc(g, "¼ clinch")
	testing.expectf(t, found && n == 200, "¼ clinch: %v, %v", n, found)

	// The first `...` edge in index order (136 of them).
	first_dots := -1
	for e, i in g.edges {
		if e.sequence.description[0] == "..." {
			first_dots = i
			break
		}
	}
	s, sfound := core.step_by_desc(g, "...")
	testing.expectf(
		t,
		first_dots >= 0 && sfound && s == core.Step{first_dots, false},
		"...: %v, %v (first at %v)",
		s,
		sfound,
		first_dots,
	)
	s, sfound = core.step_by_desc(g, "t0")
	testing.expectf(t, sfound && s == core.Step{0, false}, "t0: %v, %v", s, sfound)
	// `from` takes the first `...` that starts at the node (or, bidirectional, ends there).
	if first_dots >= 0 {
		from := g.edges[first_dots].from.node
		s, sfound = core.step_by_desc(g, "...", from)
		testing.expectf(
			t,
			sfound && s == core.Step{first_dots, false},
			"... from %v: %v, %v",
			from,
			s,
			sfound,
		)
	}

	n, found = core.node_by_desc(g, "p124")
	testing.expectf(t, found && n == 124, "p124: %v, %v", n, found)
	n, found = core.node_by_desc(g, "p65536")
	testing.expectf(t, found && n == 0, "p65536: %v, %v", n, found)

	if testing.expect(t, len(g.nodes) > 3 && g.nodes[3].line_nr != core.NO_LINE) {
		line := g.nodes[3].line_nr
		buf: [24]u8
		name := fmt_l(buf[:], line)
		e, efound := core.named_entity(g, name)
		testing.expectf(
			t,
			efound && e == core.Named_Entity(core.Entity_Node{3}),
			"%s: %v, %v",
			name,
			e,
			efound,
		)
	}
	e, efound := core.named_entity(g, "last-trans")
	testing.expectf(
		t,
		efound && e == core.Named_Entity(core.Step{len(g.edges) - 1, false}),
		"last-trans: %v, %v",
		e,
		efound,
	)

	// The 5 named positions no transition touches (§10.2), found by name.
	isolated := [?]struct {
		block: int,
		name:  string,
	} {
		{111, "kung fu move w/ leg trapped"},
		{250, "standing vs darce"},
		{292, "completed o-soto-gari"},
		{306, "butterflies engaged w/ over/under body lock"},
		{546, "full domination top lock half"},
	}
	for it in isolated {
		n, found = core.node_by_desc(g, it.name)
		testing.expectf(
			t,
			found && n == it.block,
			"%q: %v, %v; want %v",
			it.name,
			n,
			found,
			it.block,
		)
	}
}

// "l" + decimal(line) in `buf`.
@(private = "file")
fmt_l :: proc(buf: []u8, line: int) -> string {
	i := len(buf)
	v := line
	for {
		i -= 1
		buf[i] = u8('0' + v % 10)
		v /= 10
		if v == 0 {
			break
		}
	}
	i -= 1
	buf[i] = 'l'
	return string(buf[i:])
}
