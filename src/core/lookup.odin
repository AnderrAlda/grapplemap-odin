package core

// Lookups by name of the original (§2.8; `src/metadata.cpp:66-124`, `src/util.hpp:70-86`), over a built `Graph`,
// quirks included. Pure: nothing is allocated. Two deliberate divergences, both of undefined behaviour of the
// original: an index that is out of range is "not found" (never handed out), and a `p<N>` that does not fit a
// `u64` is "not found" (the original's `stoul` throws `out_of_range` and the program dies). A third, in
// `named_entity`: an `l<N>` that does not fit a `u64` is not an `l` name (the original dies likewise).

// Entity_Node is the `NodeNum` alternative of the original's `variant<NodeNum, Step>`: a struct so that a bare
// `int` member is not mistaken for something else at call sites.
Entity_Node :: struct {
	node: int,
}

// Named_Entity is `variant<NodeNum, Step>` (`src/metadata.hpp:9-13`), what `named_entity` finds.
Named_Entity :: union {
	Entity_Node,
	Step,
}

// numbered: `s` is `prefix` + one or more ASCII digits (`len(s) >= 2`). `n` is the value like `stoul` (decimal,
// leading zeros allowed) and `fits` is false when it does not fit a `u64` (`n` is then meaningless).
@(private)
numbered :: proc(s: string, prefix: byte) -> (n: u64, shape, fits: bool) {
	if len(s) < 2 || s[0] != prefix {
		return
	}
	for c in transmute([]byte)s[1:] {
		if c < '0' || c > '9' {
			return
		}
	}
	shape, fits = true, true
	for c in transmute([]byte)s[1:] {
		d := u64(c - '0')
		if n > (max(u64) - d) / 10 {
			return 0, true, false
		}
		n = n * 10 + d
	}
	return
}

// first_line_matches is `replace_all(description.front(), "\\n", " ") == desc` (`src/metadata.cpp:68,86`) without
// building the replaced string: a backslash followed by `n` stands for one space (non-overlapping, left to right,
// as boost's `replace_all`); every other byte compares as is. Case-sensitive, no trimming.
@(private)
first_line_matches :: proc(line, desc: string) -> bool {
	i, j := 0, 0
	for i < len(line) {
		if j >= len(desc) {
			return false
		}
		if line[i] == '\\' && i + 1 < len(line) && line[i + 1] == 'n' {
			if desc[j] != ' ' {
				return false
			}
			i += 2
		} else {
			if line[i] != desc[j] {
				return false
			}
			i += 1
		}
		j += 1
	}
	return j == len(desc)
}

// node_by_desc is `nodeByDesc` (`src/metadata.cpp:81-94`). `p<digits>` is the node
// index, **before and instead of** any name lookup (a node named `p1` is reachable only as index 1); the number is
// wrapped to `u16` like the original's `uint16_t(...)` (`p65536` is node 0). Divergences: a number that does not
// fit a `u64` or an index `>= len(g.nodes)` is "not found". Otherwise the first node, in index order, with a
// non-empty description whose first line matches (see `first_line_matches`); anonymous nodes are skipped.
node_by_desc :: proc(g: ^Graph, desc: string) -> (node: int, ok: bool) {
	if n, shape, fits := numbered(desc, 'p'); shape {
		if !fits {
			return 0, false
		}
		idx := int(u16(n))
		if idx >= len(g.nodes) {
			return 0, false
		}
		return idx, true
	}
	for nd, i in g.nodes {
		if len(nd.description) != 0 && first_line_matches(nd.description[0], desc) {
			return i, true
		}
	}
	return 0, false
}

// step_by_desc is `stepByDesc` (`src/metadata.cpp:66-79`). Edges in index order; an edge is a candidate if the first
// line of its description matches (see `first_line_matches`) **or** `desc` is exactly `"t" + decimal(index)` (`t07`
// never matches edge 7). Without `from` the first candidate is `{seq, false}`. With `from`: `{seq, false}` if the
// edge starts at node `from`; `{seq, true}` if it is bidirectional and ends at `from`; otherwise **the search goes
// on** with the next candidate. Nodes compare by index (reorientation ignored). The parser never yields an empty
// description (the original's UB case, §2.8, cannot happen here).
step_by_desc :: proc(g: ^Graph, desc: string, from: Maybe(int) = nil) -> (step: Step, ok: bool) {
	t_index := -1
	if n, shape, fits := numbered(desc, 't'); shape && fits && (desc[1] != '0' || len(desc) == 2) {
		if n <= u64(max(int)) {
			t_index = int(n)
		}
	}
	for e, i in g.edges {
		if i != t_index &&
		   !(len(e.sequence.description) != 0 &&
				   first_line_matches(e.sequence.description[0], desc)) {
			continue
		}
		f, has_from := from.?
		if !has_from || e.from.node == f {
			return {i, false}, true
		}
		if e.sequence.bidirectional && e.to.node == f {
			return {i, true}, true
		}
	}
	return {}, false
}

// named_entity is `namedEntity` (`src/metadata.cpp:107-124`), in this order:
//  1. `last-trans`: the last edge, `{len(edges) - 1, false}` (divergence: no edges is "not found").
//  2. `l<digits>`: the first node whose `line_nr` is N, else the first edge whose `sequence.line_nr` is N. N is
//     truncated to `u32` like `optional<uint32_t>`; one that does not fit a `u64` is not an `l` name. **No early
//     return**: with no hit it falls through.
//  3. `step_by_desc` (transitions win over nodes), 4. `node_by_desc` (including `p<N>`).
named_entity :: proc(g: ^Graph, s: string) -> (e: Named_Entity, ok: bool) {
	if s == "last-trans" {
		if len(g.edges) == 0 {
			return nil, false
		}
		return Step{len(g.edges) - 1, false}, true
	}
	if n, shape, fits := numbered(s, 'l'); shape && fits {
		line := int(u32(n))
		for nd, i in g.nodes {
			if nd.line_nr == line {
				return Entity_Node{i}, true
			}
		}
		for ed, i in g.edges {
			if ed.sequence.line_nr == line {
				return Step{i, false}, true
			}
		}
	}
	if step, found := step_by_desc(g, s); found {
		return step, true
	}
	if node, found := node_by_desc(g, s); found {
		return Entity_Node{node}, true
	}
	return nil, false
}
