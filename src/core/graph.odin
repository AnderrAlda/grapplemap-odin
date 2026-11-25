package core

import "core:mem/virtual"
import "core:slice"

// The graph of the original (docs/original.md §2.1, §2.2, §2.4, §2.6, §2.7): named positions and the anonymous
// nodes created for unmatched sequence ends are the nodes; every sequence of ≥ 2 positions is an edge. Built in
// `Graph.arena`; nodes and edges refer to each other by index (src/core/CLAUDE.md).

// NO_LINE is the `line_nr` of an anonymous node: the original's empty `optional<unsigned>` (src/graph.cpp:222-233).
NO_LINE :: -1

// Step is `Reversible<SeqNum>` (src/graph.hpp:44-47): a sequence index and the direction it is played in.
Step :: struct {
	seq:     int,
	reverse: bool,
}

// Reoriented_Node is `Reoriented<NodeNum>` (src/graph.hpp:56-58): `reorient(reorientation, nodes[node].position)`
// is the sequence end, up to `basically_same`.
Reoriented_Node :: struct {
	node:          int,
	reorientation: Position_Reorientation,
}

// Node is `Graph::Node` (src/graph.hpp:40-52): a `NamedPosition` plus its incident sequences. An anonymous node has
// `description = nil` and `line_nr = NO_LINE`. `incoming`/`outgoing`/`in_out` are the original's `in`/`out`/`in_out`
// (`in` is an Odin keyword), filled by #173 (`nil` until then).
Node :: struct {
	position:                   Position,
	description:                []string,
	line_nr:                    int, // as `Sequence.line_nr`, or NO_LINE
	incoming, outgoing, in_out: []Step,
}

// Edge is `Graph::Edge` (src/graph.hpp:54-66): the sequence as parsed (positions, `detailed`, `bidirectional`
// untouched, §2.7) and its two end nodes. `from` may equal `to` (the original does not enforce its own
// "no identity transitions" invariant, §10.3).
Edge :: struct {
	sequence: Sequence,
	from, to: Reoriented_Node,
}

// Graph holds only slices into `arena`, never a `[dynamic]` or an allocator: `load_graph` returns it by value, and
// anything holding `arena_allocator(&arena)` would point at the old copy. Do not copy a `Graph` after `load_graph`
// and destroy both. Indices are `int`: past 65535 nodes or sequences they do not wrap, unlike the original's
// `uint16_t` (§2.1); the DB is far from that.
Graph :: struct {
	arena:       virtual.Arena,
	nodes:       []Node, // named positions in file order (`named_count` of them), then anonymous nodes
	edges:       []Edge, // the sequences of ≥ 2 positions, in file order
	named_count: int,
}

// load_graph is `loadGraph` (src/persistence.cpp:154-169) + `Graph::Graph(pp, ss)` (src/graph.cpp:279-302):
// `parse_db` into a fresh growing arena (strings copied: nothing points into `data`), then `build`. On error the
// arena is destroyed and a zero `Graph` is returned. Scratch goes to `context.temp_allocator` (the caller frees it).
// Free with `graph_destroy`.
load_graph :: proc(data: []byte) -> (g: Graph, err: Error) {
	if arena_err := virtual.arena_init_growing(&g.arena); arena_err != .None {
		return {}, arena_err
	}
	seqs: []Sequence
	seqs, err = parse_db(data, virtual.arena_allocator(&g.arena))
	if err == nil {
		err = build(&g, seqs)
	}
	if err != nil {
		virtual.arena_destroy(&g.arena)
		return {}, err
	}
	return g, nil
}

// graph_destroy releases everything of `g` and leaves it zero.
graph_destroy :: proc(g: ^Graph) {
	virtual.arena_destroy(&g.arena)
	g^ = {}
}

// build is `Graph::Graph(pp, ss)` (src/graph.cpp:279-302) after `loadGraph`'s split (src/persistence.cpp:158-166),
// allocating in `g.arena`; scratch in `context.temp_allocator`. In order:
//  1. the named nodes are the 1-position sequences in file order, wherever they are in the file;
//  2. before each is pushed, its whole description is compared with every node already pushed (non-empty and
//     equal) → `Duplicate_Position_Description` with the later block and the 1-based line of its first
//     description line (src/graph.cpp:283-285). Named positions are never matched with each other;
//  3. the edges are the other sequences in file order: `from = find_or_add(front)`, then `to = find_or_add(back)`
//     (src/graph.cpp:290-296). `from == to` is accepted (§10.3).
// `in`/`out`/`in_out` (src/graph.cpp:298-299) are #173's.
@(private)
build :: proc(g: ^Graph, seqs: []Sequence) -> Error {
	allocator := virtual.arena_allocator(&g.arena)
	nodes := make([dynamic]Node, context.temp_allocator) or_return
	edge_count := 0
	for s, block in seqs {
		assert(len(s.positions) >= 1, "parse_db never yields a sequence without positions")
		if len(s.positions) != 1 {
			edge_count += 1
			continue
		}
		for &x in nodes {
			// The original's `!x.description.empty()`: never false here (all nodes are named so far and parse_db
			// never yields an empty description), kept for fidelity.
			if len(x.description) != 0 && slice.equal(x.description, s.description) {
				return Graph_Error {
					kind = .Duplicate_Position_Description,
					line = s.line_nr - len(s.description) + 1,
					block = block,
				}
			}
		}
		append(
			&nodes,
			Node{position = s.positions[0], description = s.description, line_nr = s.line_nr},
		) or_return
	}
	named_count := len(nodes)
	edges := make([]Edge, edge_count, allocator) or_return
	k := 0
	for s in seqs {
		if len(s.positions) == 1 {
			continue
		}
		from := find_or_add(&nodes, s.positions[0]) or_return
		to := find_or_add(&nodes, s.positions[len(s.positions) - 1]) or_return
		edges[k] = Edge {
			sequence = s,
			from     = from,
			to       = to,
		}
		k += 1
	}
	g.nodes = slice.clone(nodes[:], allocator) or_return
	g.edges = edges
	g.named_count = named_count
	return nil
}

// find_or_add is `Graph::find_or_add` (src/graph.cpp:213-241): the lowest index `n` with
// `is_reoriented(nodes[n].position, p)` (node first, end second), else a new anonymous node with `p` as is and the
// zero `Position_Reorientation`.
@(private)
find_or_add :: proc(nodes: ^[dynamic]Node, p: Position) -> (r: Reoriented_Node, err: Error) {
	for &x, n in nodes {
		if u, ok := is_reoriented(x.position, p); ok {
			return {node = n, reorientation = u}, nil
		}
	}
	append(nodes, Node{position = p, line_nr = NO_LINE}) or_return
	return {node = len(nodes) - 1}, nil
}
