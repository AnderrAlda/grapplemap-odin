# Plan: #142 feat(core): graph construction and node matching
Spec: docs/specs/phase-2-core.md (deliverable 6, second half; matching: #169, merged in #172; in/out: #173) ·
docs/original.md §2.1, §2.2, §2.4, §2.6, §2.7, §10.1, §10.3 · ADR 0003 (decision 6)

## Pasos
1. **`src/core/graph.odin`** (new). Types (names may be adjusted by the worker; the plan fixes their content):
   - `Step :: struct {seq: int, reverse: bool}`: the original's `Reversible<SeqNum>` (`src/graph.hpp:44-47`). #144
     reuses it for `follow`.
   - `Reoriented_Node :: struct {node: int, reorientation: Position_Reorientation}`: `Reoriented<NodeNum>`, with
     `reorientation(nodes[node].position) ≈ endpoint` (`src/graph.hpp:56-58`).
   - `Node :: struct {position: Position, description: []string, line_nr: int, in, out, in_out: []Step}`.
     `NO_LINE :: -1` is the `line_nr` of an anonymous node (the original's empty optional, `src/graph.cpp:222-233`);
     #143 (`l<N>`) depends on it.
   - `Edge :: struct {sequence: Sequence, from, to: Reoriented_Node}` (`src/graph.hpp:54-66`): the sequence's own
     positions untouched, `detailed`/`bidirectional` as the parser set them (§2.7).
   - `Graph :: struct {arena: virtual.Arena, nodes: []Node, edges: []Edge, named_count: int}`. **Only slices**, no
     `[dynamic]` and no stored `mem.Allocator`: `load_graph` returns the `Graph` by value, so anything holding
     `arena_allocator(&arena)` would point at the old copy of the arena.
2. **Procedures** (operation order and source line in each doc comment):
   - `load_graph(data: []byte) -> (g: Graph, err: Error)`: `arena_init_growing`; `parse_db(data, arena allocator)`
     (strings already copied, nothing points into `data`); then `build`. On any error the arena is destroyed and a
     zero `Graph` is returned (nothing leaks). Scratch in `context.temp_allocator`.
   - `@(private) build(g: ^Graph, seqs: []Sequence) -> Error` (`src/graph.cpp:279-302`), allocating in `g`'s arena.
     Package-private so that `graph_test.odin` can feed sequences with arbitrary (non-grid, rotated) positions:
     1. named nodes = the 1-position sequences, in file order, wherever they appear in the file (`loadGraph` splits
        them first, `src/persistence.cpp:154-169`);
     2. before pushing each, compare its **whole** description with every node already pushed (non-empty and equal,
        all lines) → `Graph_Error{.Duplicate_Position_Description, line, block}`: `block` = the later block, `line` =
        1-based line of its first description line;
     3. edges = the other sequences in file order: `from = find_or_add(front)`, **then** `to = find_or_add(back)`;
     4. `in`/`out`/`in_out` are **not** computed here: #173 (split for size). `Node` has the three fields, left
        `nil`, so #173 only fills them.
     No match between named positions; no check of `from != to` (the self-loop of block 1826 loads, §10.3).
   - `find_or_add(nodes: ^[dynamic]Node, p: Position) -> Reoriented_Node` (`src/graph.cpp:213-241`): the lowest
     index `n` with `is_reoriented(nodes[n].position, p)` (node first, endpoint second); else append an anonymous
     node (`position = p` as is, `description = nil`, `line_nr = NO_LINE`) and return it with the zero
     `Position_Reorientation`. The `[dynamic]` lives only inside `build`; the `Graph` keeps its slice.
   - `graph_destroy(g: ^Graph)`: `virtual.arena_destroy`, then `g^ = {}`.
   - Node/sequence counts beyond 65535 do **not** wrap (the original's `uint16_t` would, §2.1): indices are `int`.
     Documented in the doc comment; the DB is far from it.
3. **Fidelity, `tests/fidelity/graph_test.odin`** (new): `load_graph(DB)` once, then:
   - `meta.json` `counts`: `len(nodes) == nodes`, `named_count == named_positions`,
     `len(nodes) − named_count == anonymous_nodes`, `len(edges) == transitions`;
   - the `index` line of `graph.ndjson`: its `pairs` are **all** 1,485 transitions even in the sample (checked), so
     `edges[i].from.node, edges[i].to.node == pairs[i]` for every `i` checks the whole numbering (lowest index wins,
     anonymous order, front before back) locally, not only in CI; `len(pairs) == len(edges)`;
   - node lines: `block == null` ⟺ `index >= named_count`; the description lines equal; the position equals
     `position_q` decoded bit for bit (for an anonymous node: the endpoint that created it);
   - transition lines: `from`, `to` and both reorientations bit for bit. Reuse the decoding and comparison of
     `match_test.odin` by making its `Oracle_Reorientation`/comparison helper package-level (a move, not a change;
     `keep_negative_zero` on transition lines only, as there);
   - the self-loop: on the full dump, `edges[1225].from.node == edges[1225].to.node == 506` comes out of the pairs
     check; a unit test covers self-loops on the sample (block 1826 is not in it).
   - **Mutation test** (`mutation_test.odin`, spec "Edge cases"): also run `load_graph` on the mutated DBs that
     `parse_db` accepts, asserting "error or valid graph, no panic, no leak". Bound the extra time (e.g. every k-th
     case) so `./build.sh test` grows by < 30 s in debug; the PR states the time and k.
4. Docs: `src/core/CLAUDE.md` ("Ficheros": `graph.odin`; rule "`Graph` holds only slices: it is returned by value")
   and `changelog.d/142-graph-construction.md`. `docs/original.md` is not edited.
5. `./build.sh ci`; full dump by hand and the `fidelity` workflow green on the PR, both in the PR.

## Ficheros a tocar
`src/core/graph.odin`, `src/core/graph_test.odin`, `tests/fidelity/graph_test.odin`, `tests/fidelity/match_test.odin`
(helpers made package-level only), `tests/fidelity/mutation_test.odin`, `src/core/CLAUDE.md`,
`changelog.d/142-graph-construction.md` (+ this plan).
Not touched: `match.odin`, `parse.odin`, `errors.odin` (`Duplicate_Position_Description` exists), `reorient*`,
`docs/`, `build.sh`, `.github/`, `reference/`, `tests/fixtures/`.

## Tests a escribir primero
`src/core/graph_test.odin` (TDD: red first with a stub `build` that returns `nil` and no nodes). Text inputs use the
encoders of `parse_test.odin` (`encode_position_q`, `pos_text`); rotated or near-threshold cases go through `build`
with hand-made `Sequence`s in an arena.
- **Empty DB** → 0 nodes, 0 edges, `nil`.
- **Order:** a file with a transition **before** a named position still numbers the named node 0 and the edge 0.
- **Duplicates:** two named blocks with the same whole description → `Duplicate_Position_Description` with the second
  block and the 1-based line of its first description line, and no leak; same first line but a different second line
  → accepted (the DB's blocks 249/477 case is the lookup-name one, not this).
- **Named never merged:** two named positions that are exact reorientations of each other → 2 nodes.
- **Anonymous numbering:** two transitions whose ends match nothing → nodes `N, N+1, N+2…` in order front, back,
  next front…; the anonymous node keeps the endpoint bits as is (including a `-0`) and the edge carries the zero
  reorientation (all-zero bits, no swap, no mirror); a later end matching it gets `is_reoriented`'s result.
- **Lowest index wins:** an end within the threshold of two nodes picks the lower one, even when the higher one is
  closer.
- **`to` matches the node just created for `from`** → a self-loop, accepted.
- **Flags:** `detailed`/`bidirectional` of each edge equal the sequence's.
- **Errors propagate:** a parse error from `load_graph` is returned unchanged and nothing leaks.
- **Arena released:** `arena_destroy` sets `total_reserved = 0` unconditionally, so checking it afterwards is
  vacuous. Instead: before `graph_destroy`, `g.arena.total_reserved > 0` and `g.arena.curr_block != nil`; after it,
  `g^` is zero. The PR says that the OS-level release itself is the stdlib's (`arena_growing_free_last_memory_block`).

Then step 3. Check that it can fail (none committed): scanning nodes from the highest index, or calling
`find_or_add(back)` before `front`, turns the pairs check red on the sample.

## Riesgos
- **Numbering mismatch** (ADR 0003 d6): an end matching a different node is a discrete decision, never a tolerance.
  The test reports the transition, the end, the expected and the obtained node, and whether the expected node is
  also a match (`is_reoriented`) for diagnosis. The spec says: stop and escalate; only then is the ambiguous-pairs
  dumper pass added.
- **Graph copied by value:** the arena struct is copied on return; safe only because nothing keeps a pointer to it
  (step 1). The doc comment says "do not copy a `Graph` after `load_graph` and destroy both".
- **Load time in debug:** O(transitions × nodes) `is_reoriented` with the pre-filter; measured in the PR (the bench
  is #148).
- **Size:** with `in`/`out` in #173, about 120 lines of `graph.odin`, 150 of unit tests, 110 of fidelity and 20 of
  mutation, about 400. If it goes over, the mutation-test extension moves to #173, said in the PR.

## Criterio de hecho
- `./build.sh ci` green locally and in CI (linux + macOS); zero leaks.
- `fidelity` workflow green on the PR, and the full dump by hand green (725 nodes, 124 anonymous, 1,485 edges,
  pairs equal, self-loop 1225 → 506), with the oracle run in the PR.
- Mutants documented in the PR.
- `code-reviewer` (opus, `src/core`) without blockers.
- Labels `type:feat`, `area:core`, `phase-2`; milestone «Fase 2: Núcleo de datos»; `Closes #142`.
- Worker model: opus (fidelity in `core`).
