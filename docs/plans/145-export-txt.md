# Plan: #145 feat(core): export to GrappleMap.txt
Spec: docs/specs/phase-2-core.md (deliverable 9; edge case "Export errors"; end-to-end verification 5) ·
docs/original.md §1.3, §1.5, §1.7 · ADR 0005 decisions 5, 6, 8 · ADR 0003 · `src/persistence.cpp:118-151`, `:241-251`

## Pasos
1. **`src/core/export_txt.odin`** (new): `export_txt(g: ^Graph, allocator := context.allocator) -> ([]byte, Error)`,
   the original's `save(g, ostream)` (`src/persistence.cpp:241-251`). Builds into a `strings.Builder` (or
   `[dynamic]byte`) on `allocator`; on error frees it and returns `nil` + the error (no leak). In order:
   1. every node that has a description, in node order (`src/persistence.cpp:243-247`): its description lines, each
      followed by `'\n'`, then its position. Anonymous nodes (`index >= named_count`) have none and are skipped, as in
      the original;
   2. every edge in order: its sequence's description lines + `'\n'`, then every position (`:146-151`).
   Position writer (`:118-144`): per joint in `Joint` order and per player, `g(x + 2)`, `g(y)`, `g(z + 2)` with
   `g(d) = i := int(round(d * 1000))`, two digits `BASE62[i / 62]`, `BASE62[i % 62]`; the 276 digits cut in 4 pieces of
   `276 / 4 = 69`, each `"    " + piece + '\n'`. Same operation order as the original (`(x + 2) * 1000`, not
   `x * 1000 + 2000`; ADR 0003 d4). `round` = `math.round_f64` (Go's `math.Round`: half away from zero, like
   `std::round`; the worker checks it in the pinned toolchain's source and says so in the doc comment). The base62
   alphabet: reuse the one of `parse.odin` (make it package-level if it is not; a move, not a change).
   Player/joint loop order: check `playerJoints` in the original (`src/positions.hpp`) against `parse.odin`'s decoder
   and use exactly the inverse of the decoder.
2. **Export errors** (ADR 0005 d5, d8; `Export_Error_Kind` already exists in `errors.odin`), first error stops,
   `line = 0` (no input file), `block` = 0-based index of the block **in the output** (named nodes first, then edges):
   - a description line that starts with `' '` → `Description_Starts_With_Space`; contains `'\n'` →
     `Description_Has_Newline`;
   - a named node (`index < named_count`) or an edge with an empty description → `Empty_Description` (the original
     would drop the node silently or write a position block with no description, which it cannot load back, §1.7);
   - two named nodes with the same whole description → `Duplicate_Description` (block of the later one; ADR 0005 d5);
   - a coordinate whose `round(d * 1000)` (with the offset) is outside `0…3843`, or NaN → `Coordinate_Out_Of_Range`,
     checked on the `f64` **before** converting to `int` (the original's asserts allow up to 3999 and are compiled out,
     §1.5: stricter on purpose, ADR 0005 d8).
   A graph returned by `load_graph` never triggers any of them; they guard graphs built by JSON import (#146) and the
   editor (phase 6). `'\r'` is written verbatim.
3. **Shared DB graph for the fidelity package** (`tests/fidelity/oracle.odin`): one full-DB `load_graph` costs 67 s
   under test flags (#174), so a second load in this PR would add another minute. Add `shared_graph(t) -> (^core.Graph,
   bool)`: loads the DB once per test binary (`sync.once_do`), DB bytes and graph on `runtime.heap_allocator()` /
   the graph's arena (so the per-test tracking allocator does not see them as leaks), never destroyed (reachable from a
   package global until exit: ASan's leak checker does not report reachable memory; say so in a comment). A load error
   is cached and reported by every caller. Move `test_graph_matches_oracle` (`tests/fidelity/graph_test.odin`) to it:
   its `load_graph`/`graph_destroy` become `shared_graph` (a mechanical change; its checks are not touched).
4. **Fidelity, `tests/fidelity/export_test.odin`** (new), on the shared graph:
   - `md5(export_txt(g))` (`core:crypto/legacy/md5`, test package only) equals `meta.json` `save_md5`;
   - if `meta.json` `save_equals_db`: the bytes equal the DB byte for byte (on the first difference, report the offset
     and the line, not the whole buffer);
   - if `<oracle_dir>/save.txt` exists (full dump only, `tools/oracle/README.md`): equal to it byte for byte;
   - round trip: `load_graph(export_txt(g))` succeeds and exporting it again gives the same bytes. Only if the extra
     load fits the budget (it is a second full load: skip it here if it costs > 10 s with ASan and cover the round trip
     in the unit tests and in #146 instead; the PR says which).
5. Docs: `src/core/CLAUDE.md` — **new bullet after `match.odin`**, before `graph.odin` (to avoid a conflict with #173,
   which edits the `graph.odin` bullet): `export_txt.odin` and its rules (writer order, `(x + 2) * 1000` + `round`,
   errors checked before writing). `changelog.d/145-export-txt.md`.
6. `./build.sh ci`; full dump by hand (`GM_ORACLE_DIR=<full dump>`) green, `fidelity` workflow green on the PR, both in
   the PR.

## Ficheros a tocar
`src/core/export_txt.odin`, `src/core/export_txt_test.odin`, `src/core/parse.odin` (base62 alphabet made package-level
only, if needed), `tests/fidelity/oracle.odin`, `tests/fidelity/graph_test.odin` (load → `shared_graph` only),
`tests/fidelity/export_test.odin`, `src/core/CLAUDE.md` (one new bullet), `changelog.d/145-export-txt.md` (+ this plan).
Not touched: `graph.odin`, `graph_test.odin` of `core`, `tests/fidelity/mutation_test.odin` (#173), `errors.odin`,
`docs/`, `build.sh`, `.github/`, `reference/`.

## Tests a escribir primero
`src/core/export_txt_test.odin` (TDD: red with a stub that returns `nil, nil`). Inputs through `load_graph` on small
texts written with the encoders of `parse_test.odin` (`encode_position_q`, `pos_text`), and hand-built `Graph`s
(arena + slices) for the error cases.
- **Empty graph** → empty output, `nil`.
- **Round trip on text**: a file with two named positions and a transition (with `tags:`/`properties:`/`ref:` lines,
  `¼` UTF-8, a literal `\n`, a `'\r'` in a line, a first description line `""`) exports to the same bytes.
- **Writer order**: a transition **before** a named position in the input → the named position comes first in the
  output (§1.5); trailing description lines without positions are dropped.
- **Anonymous nodes skipped**: a transition whose ends match nothing → the output has only the transition block.
- **Coordinates 0 and 3843** (`edge_coordinate`, absent from the DB) on x, y, z round-trip; the 69-digit layout.
- **Rounding**: hand-made positions with `d * 1000` at `.5` boundaries (e.g. `y = 0.0005`, `x = -1.9995`) give the
  digits of `std::round` (half away from zero); expected digits computed outside Odin and written as literals.
- **Each export error** with its `block`: line starting with `' '`, line with `'\n'`, empty description on a named
  node and on an edge, duplicate whole description, coordinate `3843.5 / 1000` beyond the range, a negative one, NaN;
  no leak in any (the builder is freed).
- **Allocator**: the result is on the given allocator (tracking allocator in the test).
Then step 4. Mutants to try, none committed (PR lists them): `x * 1000 + 2000` instead of `(x + 2) * 1000`; truncation
instead of `round`; edges before nodes; not skipping anonymous nodes. Each must turn a test red (the DB checks catch
at least the order and anonymous ones).

## Riesgos
- **Rounding of re-encoded doubles**: values read from the file are `f64(62*d0 + d1)/1000 − 2`; `(v + 2) * 1000` must
  round back to the same integer. Expected for every grid value, but the DB check (all 8,323 positions) and an
  exhaustive unit test over the 3,844 grid values per axis (cheap) prove it.
- **Shared graph in tests**: tests run in parallel threads; `sync.once_do` makes the load single. If the tracking
  allocator still flags it, the worker escalates rather than disabling `ODIN_TEST_FAIL_ON_BAD_MEMORY`.
- **Conflict with #173**: only `src/core/CLAUDE.md`, in different bullets; whichever merges second runs
  `git merge origin/main` (orchestrate §4).
- **Size**: ~110 lines of `export_txt.odin`, ~170 of unit tests, ~70 of fidelity and shared graph: ~350.

## Criterio de hecho
- `./build.sh ci` green locally and in CI (linux + macOS); zero leaks; `./build.sh test` time not higher than before
  this PR (the shared graph pays for the new test), measured in the PR.
- Full dump by hand: `export_txt(load_graph(DB)) == save.txt` byte for byte; `fidelity` workflow green on the PR.
- Mutants documented in the PR.
- `code-reviewer` (opus, `src/core`) without blockers.
- Labels `type:feat`, `area:core`, `phase-2`; milestone «Fase 2: Núcleo de datos»; `Closes #145`.
- Worker model: opus (byte-exact fidelity in `core`).
