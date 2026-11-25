# Plan: #173 feat(core): node in/out/in_out lists
Spec: docs/specs/phase-2-core.md (deliverable 6, second part; split from #142, merged in #174) · docs/original.md §2.6,
§2.7, §10.3 · `src/graph.cpp:243-277` and `:298-299` · issue comment (mutation-test extension inherited from #142, M1)

## Pasos
1. **`src/core/graph.odin`**: `@(private) compute_in_out(g: ^Graph, n: int) -> Error`, the original's
   `Graph::compute_in_out` (`src/graph.cpp:243-277`), allocating the three slices in `g.arena`. For node `n`, every
   edge `s` in ascending order, and for each `s` in this exact order (§2.6 table):
   1. `edges[s].to.node == n` → `incoming += {s, false}`; `in_out += {s, true}`;
   2. `edges[s].from.node == n` → `outgoing += {s, false}`; `in_out += {s, false}`;
   3. `sequence.bidirectional` and `from.node == n` → `incoming += {s, true}`;
   4. `sequence.bidirectional` and `to.node == n` → `outgoing += {s, true}`.
   Compared by node index only (the reorientation is ignored). A node with no incident edge keeps `nil` slices (not
   empty allocations), so "isolated" is `len(...) == 0` either way.
   Called from `build` for every node after all edges exist (`src/graph.cpp:298-299`). The calls the original makes
   inside `find_or_add` (`:230`) are overwritten by this final pass and are not reproduced (say so in the doc comment).
   Efficiency: one pass over the edges per node is O(nodes × edges) ≈ 1.1 M cheap checks, negligible next to matching;
   if the worker prefers a single pass over the edges appending to per-node scratch lists, the order must be the same
   (by `s`, then the four rules), and the unit tests below pin it.
2. Doc comments: `Node` and `build` stop saying "filled by #173"; `build` gains step 4.
3. **Mutation test extension** (`tests/fidelity/mutation_test.odin`, M1 of #174 / issue comment): measured in #174, a
   full-DB `load_graph` takes 67 s under test flags. **Decisión de Ander tras la escalación** (el prefijo no sirve: los
   bloques 0-600 son las ~600 posiciones con nombre, así que un prefijo con transiciones tarda ≥ 3 s por `load_graph` y
   sigue sin nodos anónimos): mutar una **muestra** de bloques del DB, los bloques 0-39 (posiciones con nombre) + las
   transiciones a partir del bloque 601, cortados por bloque y concatenados en ese orden. El test asegura que la muestra
   tiene ≥ 1 arista y ≥ 1 nodo anónimo. Se mide un `load_graph` de la muestra con ASan y se elige el nº de transiciones
   y de casos para que `./build.sh test` crezca < 30 s (con ~150 transiciones un `load_graph` tarda 17 s, así que se
   reducen hasta ≲ 0.5 s por carga). Same seeded mutations as today (truncations, byte flips, line swaps) on the sample;
   for every mutant that `parse_db` accepts, also `load_graph`, asserting "error or a graph whose every edge's
   `from.node`/`to.node` and every `Step.seq` is in range, no panic, no leak" and `graph_destroy`. The existing full-DB
   `parse_db` mutations stay as they are. The PR states the time, the sample size and the number of cases.
4. Docs: `src/core/CLAUDE.md`, bullet `graph.odin` only (replace "y los rellena #173" with the §2.6 rule in one line:
   order by edge, then `to` before `from`, reverse steps of bidirectional edges only in `incoming`/`outgoing`).
   `changelog.d/173-node-in-out.md`.
5. `./build.sh ci`; `fidelity` workflow green on the PR (graph fidelity must stay green: `in`/`out` are not in the dump).

## Ficheros a tocar
`src/core/graph.odin`, `src/core/graph_test.odin`, `tests/fidelity/mutation_test.odin`, `src/core/CLAUDE.md` (bullet
`graph.odin` only), `changelog.d/173-node-in-out.md` (+ this plan).
Not touched: `match.odin`, `parse.odin`, `errors.odin`, `tests/fidelity/graph_test.odin`, `docs/`, `build.sh`,
`.github/`, `reference/`.

## Tests a escribir primero
`src/core/graph_test.odin`, through `build` with hand-made `Sequence`s (as the #142 tests do). Red first: `build` does
not call `compute_in_out` yet.
- **Plain edge** `A → B`: `A.outgoing = A.in_out = [{0,false}]`, `A.incoming = nil`; `B.incoming = [{0,false}]`,
  `B.in_out = [{0,true}]`, `B.outgoing = nil`.
- **Bidirectional** `A ↔ B`: `A.incoming = [{0,true}]`, `B.outgoing = [{0,true}]`; the reverse step is **not** in
  `in_out` (`A.in_out = [{0,false}]`, `B.in_out = [{0,true}]`).
- **Order by edge**: three edges touching one node in file order 0, 1, 2 with mixed directions → lists sorted by `seq`.
- **Same edge, rule order**: a self-loop `A → A` → `incoming = [{0,false}]`, `outgoing = [{0,false}]`,
  `in_out = [{0,true}, {0,false}]` (to-rule before from-rule).
- **Bidirectional self-loop** → `incoming = [{0,false},{0,true}]`, `outgoing = [{0,false},{0,true}]`,
  `in_out = [{0,true},{0,false}]`.
- **Reorientation ignored**: an edge whose end matched a node through a non-zero reorientation still counts.
- **Isolated named node** (the DB has 5, §10.2) → three `nil` slices.
- **Anonymous nodes** get their lists too.
- **No leak / arena**: lists live in the arena (the `graph_destroy` test of #142 still passes).
Optional fidelity smoke check (no oracle data needed, in an existing test that already loads the DB, without a second
load): `sum(len(in_out)) == 2 × len(edges)` and the self-loop node 506 (full dump) / the 5 isolated named nodes have
empty lists. Only if it costs no extra `load_graph`.
Mutants to try, none committed (PR lists them): swap rules 1 and 2; put the reverse step in `in_out`; iterate edges
backwards. Each must turn a unit test red.

## Riesgos
- **Order**: the lists feed `follow`/`connector` (#144) and the lookups (#143); a wrong order is silent. Mitigated by the
  explicit order tests above.
- **Mutation-test time**: a prefix that is too large brings back the 67 s problem; too small and it has no anonymous
  node. Assert both properties of the prefix; state the time.
- **Size**: ~40 lines of `graph.odin`, ~130 of unit tests, ~40 of mutation test: well under 400.
- `in_out` naming: kept as `in_out` (not a keyword); `incoming`/`outgoing` as merged in #174.

## Criterio de hecho
- `./build.sh ci` green locally and in CI (linux + macOS); zero leaks.
- `fidelity` workflow green on the PR.
- Mutants documented in the PR; mutation-test time, `K` and case count in the PR.
- `code-reviewer` (opus, `src/core`) without blockers.
- Labels `type:feat`, `area:core`, `phase-2`; milestone «Fase 2: Núcleo de datos»; `Closes #173`.
- Worker model: opus (graph semantics in `core`).
