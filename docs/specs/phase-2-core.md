# Spec: Phase 2 — data core

Epic: #4 · Milestone: "Fase 2: Núcleo de datos" · Date: 2026-11-22

## Goal
A `core` package that loads the original's `GrappleMap.txt` and computes everything the original computes from it,
**bit for bit** where ADR 0003 says so, verified against the oracle (ADR 0002):

1. Parse `GrappleMap.txt` (`docs/original.md` §1) into positions and sequences, errors as values.
2. Build the graph: named and anonymous nodes, node matching by reorientation, `in`/`out`/`in_out`,
   `bidirectional`/`detailed` (§2).
3. Transforms: `mirror`, `swap_players`, `heading`, `center`, reorientations, `compose`/`inverse`, canonical
   orientation (§4.3, §5).
4. Frame-based playback: `between`, `follow`/`frames`, `smoothen` (§6.1-§6.3).
5. The original's lookups: `node_by_desc`, `step_by_desc`, `named_entity` (§2.8).
6. Export back to `GrappleMap.txt` (§1.5) and our own JSON (ADR 0005), both round-tripping.
7. Fidelity tests over the committed sample (local) and over the full dump (CI), plus unit, property, round-trip
   and robustness tests; zero leaks.

This list refines the epic's acceptance criteria (#4): when this spec is merged, MAIN rewrites the body of #4 with
it (the epic's "búsqueda, vecinos" = item 5 and `in`/`out` of item 2) and links the phase-2 issues. No rendering, no UI.

## Scope, files and interfaces

### Package layout
One Odin package `src/core` (one directory = one package), split by file. Illustrative interfaces, not a
final API; the plan of each issue fixes the names:

| File | Contents |
|---|---|
| `src/core/types.odin` | `V3 :: [3]f64`, `Joint` enum (23, §3.1 order), `Player :: [Joint]V3`, `Position :: [2]Player`, joint/segment tables (§3.1, §3.2), constants copied verbatim (ADR 0003 decision 7, ADR 0004 decision 4) |
| `src/core/errors.odin` | `Error :: union {Parse_Error, Graph_Error, Json_Error, Export_Error, mem.Allocator_Error}`; each own error a struct with a `kind` enum and its location (`line`, 1-based line of the file; `block`, 0-based block index). `or_return` throughout (checked with the pinned toolchain: a union whose `nil` is success works; `Allocator_Error` must be a member for `make(...) or_return`); first error stops |
| `src/core/parse.odin` | `parse_db(data: []byte, allocator) -> ([]Sequence, Error)`: blocks, description lines, base62 decode `f64(62*d0 + d1)/1000` (−2 on `x`/`z`), `line_nr`, `tags`/`properties` (§1.1-§1.4, §1.7). Strict layout per ADR 0005 decision 8 |
| `src/core/transform.odin` | `mirror`, `swap_players`, `heading`, `center`, `between`; `Reorientation`, `Position_Reorientation`, `apply`, `compose`, `inverse`, `normal_rotation`, `orient_canonically_with_mirror/_without_mirror` (§4.3, §5) |
| `src/core/graph.odin` | `Graph` (owns a `core:mem/virtual` arena; indices, no pointers; descriptions are copied into the arena, nothing points into `data`), `load_graph(data: []byte) -> (Graph, Error)`, `graph_destroy(^Graph)`, `basically_same`, `is_reoriented`, `find_or_add`, `compute_in_out` (§2.1-§2.7) |
| `src/core/lookup.odin` | `node_by_desc`, `step_by_desc`, `named_entity`, quirks included (§2.8) |
| `src/core/playback.odin` | `Step {seq, reverse}`, `follow` (direction by node equality, `from == n` tested first, not by `reverse`), `frames(graph, path, frames_per_pos, allocator)` with its captions (first line, literal `\n` → space, `...` → first line of the end node's description if it has one), `smoothen` (§6.2, §6.3) |
| `src/core/export_txt.odin` | `export_txt(graph, allocator) -> ([]byte, Error)`, the writer of §1.5 |
| `src/core/json.odin` | hand-written reader/writer of ADR 0005 over `[]byte`: precise errors (unknown key, out-of-range `q`, duplicate whole description, bad `schema_version`), stable output (fixed key order, one entry per line) |
| `tests/fidelity/` | new test package (`import "app:core"`, reads files with `core:os`, which `core` itself may not): oracle NDJSON reader (test-only), comparisons per dump file, `f64` compared by bits (`transmute(u64)`, so `-0`/`+0` differ; `strconv.parse_f64` rounds correctly). Also the DB-based tests that need the file system (mutation test). Added to `TEST_PKGS` in `build.sh` |
| `bench/` | `./build.sh bench`: time of `load_graph` on the real DB (release) |
| `build.sh` | `TEST_PKGS` += `tests/fidelity`; `fmt`/`fmt-check`/`check` also cover `tests/fidelity/` and `bench/`; `bench` compiled with `$VET` |
| `src/main.odin` | `--load <file>`: reads the file, `load_graph`, prints counts, exit code on error (see "UX") |

`core` keeps its rules (`src/core/CLAUDE.md`): no raylib, no file system, no `render`/`ui`/`editor` imports, TDD.

### Oracle data
- **Local** (`./build.sh test`): the committed sample `tests/fixtures/oracle/` plus the real DB in the submodule
  (`reference/GrappleMap/GrappleMap.txt`, read-only): the graph is always built from the whole DB (matching depends on
  every earlier node), then compared with the sample's lines by `block`/`index`. **The submodule is required**: the
  `test` and `bench` jobs of `ci.yml` check out without submodules today, so deliverable 2 adds `submodules: true` to
  their `actions/checkout` (a CI workflow edit: Ander's OK in that PR). A missing DB makes the fidelity tests **fail**
  with a clear message (`git submodule update --init`), never skip.
- **Full** (CI): the tests read the oracle directory from `GM_ORACLE_DIR` (default: the sample). The full dump is the
  `oracle-full-dump` artifact of the `oracle` workflow (`tools/oracle/README.md`, "CI"). NDJSON files are streamed line
  by line (`playback.ndjson` is 389 MB).
- **Dumper v4** (`tools/oracle/dump/`, one PR: `dumper_version` 4, regenerates the sample, `MANIFEST.sha256`,
  `FULL.sha256` and the hand-reviewed `tools/oracle/dump/testdata/*/` expected outputs; updates the file table and sizes of
  `tools/oracle/README.md`):
  - `save.txt` (full dump only): the bytes of the original's `save(loadGraph(DB))`, ~2.7 MB, closes ADR 0005 "Open
    points", first bullet. It does **not** go into the sample (it alone would break the 2 MB limit, ADR 0002 decision
    5; the sample is ~1.7 MB): the sample's `meta.json` gets `save_sha256` and `save_equals_db` instead, and the local
    test compares `export_txt(load_graph(DB))` with that hash (and with the DB itself if `save_equals_db`);
  - `compose.ndjson`: per transition, `inverse(reorientation_from)`, `inverse(reorientation_to)` and
    `compose(reorientation_from, reorientation_to)` (closes §5.7, second bullet); filtered by the sample's blocks like
    the other files.
  The pairwise "ambiguous matching" pass (§2.10, §10.3) is **not** added unless graph fidelity fails (see "Edge cases").

### Deliverables (one issue/PR each, <400 hand-written lines; generated files do not count)
Every issue and PR: labels `type:`, `area:core` (or `area:infra`), `phase-2`; milestone "Fase 2: Núcleo de datos".
Model per worker (`docs/ai-workflow.md`): `opus` for fidelity in `core` and for the dumper C++, `sonnet` otherwise.

| # | Deliverable | Depends on | Oracle file |
|---|---|---|---|
| 1a | Types and constants (`types.odin`, `errors.odin`), joint/segment tables | — | — |
| 1b | Parser (`parse.odin`), unit + robustness tests | 1a | — |
| 2 | Fidelity harness (`tests/fidelity/`, NDJSON reader, `GM_ORACLE_DIR`, `TEST_PKGS`, `build.sh` fmt/check scope, `submodules: true` in `ci.yml`) + parser fidelity + joint/segment tables vs `body.json` + DB mutation test | 1b | `sequences.ndjson`, `body.json` |
| 3 | Trig-free transforms: `mirror`, `swap_players`, `heading`, `center`, `between` | 2 | `ops.ndjson` (those fields), `between.ndjson` |
| 4 | Reorientations + canonical orientation + **trig measurement** (see "Decisions") | 3 | `ops.ndjson` (`orient_canonically_*`) |
| 5 | Dumper v4 (`save.txt`, `compose.ndjson`), fixtures and hashes regenerated | — | — |
| 6 | Graph: `load_graph`, matching, anonymous nodes, `in`/`out`/`in_out`, flags | 4 | `graph.ndjson`, `meta.json` `counts` |
| 7 | Lookups (§2.8) | 6 | — (unit tests from §2.8 and §10.2 cases) |
| 8 | `compose`/`inverse`, `follow`/`frames`, `smoothen` | 5, 6 | `compose.ndjson`, `playback.ndjson` |
| 9 | Export to `GrappleMap.txt` | 5, 6 | `save.txt` |
| 10 | JSON reader/writer + round trips (`txt → JSON → txt`, `JSON → JSON`) | 9 | — |
| 11 | `fidelity.yml` workflow (full dump in CI) | 2 | all |
| 12 | `main --load` + `bench/` | 6 | — |

Order: 1a → 1b → 2 → 3 → 4 → 6 → {7, 8, 9, 12} → 10. 5 and 11 run in parallel with the core track (5 touches only
`tools/oracle` and fixtures; 11 only `.github/workflows/fidelity.yml`). Deliverables at risk of the 400-line limit are
split by their plan if needed: 8 into `compose`/`inverse` + `follow`/`frames` and `smoothen`; 10 into reader and writer
(+ round trips). Each fidelity issue adds its comparison to
`tests/fidelity/` and, from 11 on, it runs over the full dump too. If the trig measurement (4) fails, a new issue
"port glibc 2.27 `sin`/`cos`/`atan2`" is inserted before 6, with an ADR 0003 amendment (escalation: plan + ADR).

Also in every PR: a fragment in `changelog.d/`, `src/core/CLAUDE.md`/`docs/architecture.md` when the layout or a rule
changes, and the root `CLAUDE.md` if commands or the map change (`--load`, `GM_ORACLE_DIR`, `tests/fidelity/`,
`bench/`).

## Out of scope
- Time-based `Playback::progress` and the chaser (§6.4, §6.5): phase 3, with the viewer (and the frame-rate decision
  of §6.8).
- Modern search (substring, case folding, tag filters): phase 5. Phase 2 has only the original's lookups.
- Editor operations (`spring`, `apply_limits`, `Graph::set/replace/erase`, §2.9, §9): phase 6, though `spring.ndjson`
  exists already.
- The `.index` cache (§2.5): matching is always recomputed (the dump shows both agree, §10.1).
- `readScene` (§2.8), paths/`in_paths`/`out_paths` beyond what `frames` needs, web-tool data (§8).
- wasm: `virtual.Arena` does not reserve memory on `js` targets (`core/mem/virtual/virtual_other.odin`); the graph's
  allocator is revisited in phase 7 (open point, not solved here).
- Persistent IDs for anonymous nodes and re-import matching across DB versions (ADR 0005 open points): phase 6.
- Any change to `reference/GrappleMap` or the golden images.

## UX / behaviour
- `grapplemap --load <file> --headless` (debug and release): loads, prints one line
  `blocks=2086 positions=8323 named=601 transitions=1485 nodes=725 anonymous=124` and exits 0 **without opening a window
  or entering the main loop** (today `--headless` still calls `rl.InitWindow`, `src/main.odin`). On a load error it
  prints `error: <kind> at line <n> (block <b>)` (1-based line) to stderr and exits with `EXIT_LOAD_ERROR`; a file that
  cannot be read exits with `EXIT_IO_ERROR`; both named constants, distinct from `EXIT_MEMORY_ERROR`. `--load` without
  `--headless` loads, prints the same line and then opens the placeholder window as today (the viewer arrives in
  phase 3). File I/O is in `main`; `core` gets the bytes. Without `--load` the app behaves as today.
- `./build.sh bench` prints the median load time of the real DB in release; no threshold (reported in the PR; a
  threshold is proposed only if it is over 1 s).
- `GM_ORACLE_DIR=<dir> ./build.sh test` runs the fidelity tests over another dump (e.g. the downloaded full dump).

## Edge cases
- **Malformed input** (§1.7, ADR 0005 decision 8): position block without a description, block shorter than 296 bytes,
  non-base62 digit, missing final `'\n'`, off-layout position lines, invalid UTF-8, two named positions with the same
  whole description: each is a distinct error value with line and block, never a `panic`, never a leak (a first
  description line `""` is valid, ADR 0005 decision 5). Covered by unit tests, plus a seeded mutation test in
  `tests/fidelity/` (truncations, byte flips and line swaps of the real DB, fixed seed, a bounded number of cases)
  asserting "error or valid graph, no panic, no leak".
- **Arena leaks are invisible** to the tracking allocator and ASan (`virtual.Arena` maps memory from the OS): a test
  checks that `graph_destroy` releases everything (e.g. the arena's `total_reserved` is 0 afterwards).
- **Data the DB has** (§10): 124 anonymous nodes, the self-loop (block 1826), 136 transitions named `...`,
  duplicate names (the lowest index wins; a later duplicate is reachable only as `p<N>`/`t<N>`), `¼`/`¾` UTF-8, literal `\n`, `"` in `ref:` lines, 5 isolated named
  positions: each has at least one unit or fidelity test.
- **Data the DB lacks**: coordinates `0`/`3843` (`edge_coordinate` is empty in the DB): unit tests with hand-written
  blocks, and `tools/oracle/dump/testdata/basic.txt` already has them.
- **Matching near the threshold**: matching must equal `graph.ndjson` exactly (ADR 0003 decision 6). If any endpoint
  matches differently, the issue stops and escalates; only then is the ambiguous-pairs dumper pass added.
- **`compose` angles** are not wrapped (§5.4); `between` is not clamped (§6.1); `detailed` uses `fpp / 2` by integer
  division (§6.2): unit tests pin these.
- **Export errors** (ADR 0005 decision 8): a description line starting with a space or containing `'\n'`, a `q`
  outside `0…3843`.

## Decisions and trade-offs
- **Trig: measure first.** Deliverable 4 implements reorientations with Odin's `math.sin_f64`/`cos_f64` (platform
  libm) and `math.atan2_f64` (Cephes) and compares against the oracle bit for bit, on the sample on **every CI
  target** (linux amd64 and macOS arm64, `ci.yml` runs `./build.sh test` on both) and on the full dump (linux). Result
  written in ADR 0003 (open points closed). If it fails **on any target**: port glibc 2.27's `sin`/`cos`/`atan2` to
  pure Odin (same bits on every target, wasm included), ADR amendment first. A tolerance is the last resort and needs
  Ander's explicit OK with evidence (ADR 0003 decision 5); discrete decisions are never toleranced.
- **Fidelity in CI: a separate workflow** `.github/workflows/fidelity.yml`: on pull requests touching `src/core/**`,
  `tests/fidelity/**`, `tests/fixtures/oracle/**`, `build.sh` or the workflow itself, nightly and by
  `workflow_dispatch`; with `permissions: actions: read`, downloads the latest successful `oracle-full-dump` artifact
  from `main`, checks it against the commit's `tests/fixtures/oracle/FULL.sha256` (a dump of another dumper version
  fails) and runs `GM_ORACLE_DIR=… odin test tests/fidelity`. Apart from `submodules: true` (deliverable 2), `ci.yml`
  is not changed; `./build.sh ci` never needs the full dump. Approved in this spec as a design; the PR that adds it still asks Ander (CI workflow edit).
  The artifact has a 7-day retention: the nightly `oracle` run keeps one fresh; if none exists the job fails with a
  clear message rather than passing.
- **Memory: the `Graph` owns its arena.** `load_graph` creates a `virtual.Arena` inside the `Graph`;
  `graph_destroy` frees it in one go. Temporary parsing data goes to `context.temp_allocator`. Procedures that return
  new data (`frames`, `export_txt`, JSON) take an explicit `allocator`.
- **Errors: first error, with location.** No error accumulation (the viewer does not need it; the editor in phase 6
  can revisit).
- **JSON: hand-written**, not `core:encoding/json`: the schema is fixed and small; precise errors and a stable,
  diff-friendly output are needed.
- **Original lookups only**, quirks included (`p<N>` before names, `t<N>`, `last-trans`, `l<N>` fall-through).
- **Dumper v4: `save` and `compose`/`inverse`** only: they close two open points cheaply and test bit-exact
  requirements directly; the ambiguous-pairs pass waits for a reason.
- **Critical pieces** (parser, matching, interpolation): tests by `test-writer` in one session, code in another
  (`docs/ai-workflow.md`), as each plan specifies.

## End-to-end verification
1. `./build.sh ci` green locally and in CI; zero leaks (tracking allocator, ASan on Linux).
2. `./build.sh test` runs the fidelity tests over the sample (linux and macOS): `sequences`, `body`, `ops`, `between`,
   `graph`, `compose`, `playback` and the `save_sha256` of `meta.json` all bit-exact (or with a tolerance approved by Ander, listed in ADR 0003).
3. `gh workflow run fidelity` on `main` passes over the full dump (all 2,086 blocks, 8,323 positions, 1,485
   transitions, 725 nodes).
4. `./build/grapplemap-debug --load reference/GrappleMap/GrappleMap.txt --headless` (debug: tracking allocator and
   ASan) prints the counts of §10.1 and exits 0; on a copy cut in the middle of a position block (not after trailing
   description lines, which the original drops silently, §1.1) it prints an error with a line number and exits
   `EXIT_LOAD_ERROR`; no leaks in either.
5. `export_txt(load_graph(DB))` equals `save.txt` of the full dump byte for byte (locally: its `save_sha256`); `txt → JSON → txt` equals it too; `JSON → JSON` is
   byte-identical.
6. `./build.sh bench` prints the load time; the number is in the PR of deliverable 12.
7. Epic #4: every acceptance box ticked with links to the PRs.
