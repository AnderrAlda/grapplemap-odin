# Plan: #148 feat(app): --load summary and load benchmark
Spec: docs/specs/phase-2-core.md (deliverable 12; "UX / behaviour"; end-to-end verification 4 and 6) ·
docs/original.md §10.1 (counts) · `src/core/graph.odin` (`load_graph`, merged in #174)

## Pasos
1. **`src/main.odin`**:
   - `App_State` gains `load_path: string`; `parse_args` reads `--load <file>` (a missing argument after `--load` is a
     usage error: message to stderr and `EXIT_USAGE_ERROR`, a new named constant; the other flags keep their
     current lenient behaviour).
   - New exit codes as named constants, all distinct: `EXIT_LOAD_ERROR`, `EXIT_IO_ERROR`, `EXIT_USAGE_ERROR`
     (`EXIT_MEMORY_ERROR :: 3` keeps its value; pick 4, 5, 6 and document them in the doc comment).
   - `load_summary(path) -> (g: core.Graph, ok: exit code)`: reads the file in `main` (`os.read_entire_file`; `core`
     gets the bytes), `core.load_graph`, frees the file bytes, prints one line to stdout:
     `blocks=<B> positions=<P> named=<N> transitions=<T> nodes=<V> anonymous=<A>` with `B = named_count + len(edges)`,
     `P = named_count + Σ len(edge.sequence.positions)`, `N = named_count`, `T = len(edges)`, `V = len(nodes)`,
     `A = V − N`. For the DB at the pin: `blocks=2086 positions=8323 named=601 transitions=1485 nodes=725 anonymous=124`
     (§10.1; the PR checks it against `tests/fixtures/oracle/meta.json` `counts`). The formatting is a pure
     `summary_line(^core.Graph, allocator) -> string` so it is unit-testable.
   - Errors: `format_load_error(core.Error, allocator) -> string`, a pure procedure: for `Parse_Error`/`Graph_Error`
     `error: <kind> at line <n> (block <b>)` (1-based line as stored; `kind` printed with `%v`); `block` omitted when
     it is `core.NO_BLOCK`; `line` omitted when 0; for `mem.Allocator_Error` `error: out of memory (<v>)`. Printed to
     stderr; exit `EXIT_LOAD_ERROR` (`EXIT_MEMORY_ERROR` is only for the leak tracker). An unreadable file prints
     `error: cannot read <path>: <os error>` and exits `EXIT_IO_ERROR`.
   - Flow: with `--load` and `--headless`, load, print, `graph_destroy` and return **before** any `rl.*` call (no
     `InitWindow`, no main loop). With `--load` alone: load, print, destroy, then open the placeholder window as today
     (the viewer comes in phase 3; the graph is not kept). Without `--load`: unchanged (the CI smoke test
     `--headless --frames 30` keeps opening the hidden window).
   - Exit codes go through one place so the leak report still runs before exiting: `main` computes the code, runs
     `report_leaks`, then `os.exit(code)` (a leak overrides with `EXIT_MEMORY_ERROR`). No `os.exit` inside `run`.
2. **`bench/`** (new package `bench`, `bench/load.odin`): reads `reference/GrappleMap/GrappleMap.txt` (path relative to
   `#directory`; a missing submodule prints `run git submodule update --init` and exits non-zero), one warm-up, then
   `N = 9` timed `load_graph` + `graph_destroy` with `core:time` (`time.tick_now`/`tick_since`), prints the median,
   min and max in ms and the counts line (so the number is tied to the data). No threshold (spec "UX").
3. **`build.sh`**: `cmd_bench` compiles with `$VET` (`odin run bench $COLLECTION $VET -o:speed ...`); `cmd_check` adds
   `odin check bench $COLLECTION $VET` when `bench/` exists. `FMT_DIRS` already includes `bench`. No CI workflow
   change: the `bench` job already runs `./build.sh bench` with `submodules: true`.
4. Docs: root `CLAUDE.md` (Comandos: `--load <file> [--headless]`; Mapa: `bench/`), `docs/architecture.md` if it lists
   the app's flags or packages (check), `changelog.d/148-load-summary-bench.md`.
5. `./build.sh ci`; the spec's end-to-end check 4 by hand, outputs pasted in the PR:
   `./build/grapplemap-debug --load reference/GrappleMap/GrappleMap.txt --headless` (debug + ASan: counts, exit 0, no
   leaks; note the time, ~67 s with ASan per #174), the same on a copy cut in the middle of a position block (error
   with line, `EXIT_LOAD_ERROR`, no leaks), and on a missing file (`EXIT_IO_ERROR`); `./build.sh bench` output.

## Ficheros a tocar
`src/main.odin`, `src/main_test.odin`, `bench/load.odin`, `build.sh` (`cmd_bench`, `cmd_check` only), `CLAUDE.md`,
`docs/architecture.md` (only if it lists flags/packages), `changelog.d/148-load-summary-bench.md` (+ this plan).
Not touched: `src/core/**`, `tests/fidelity/**`, `.github/`, `reference/`.

## Tests a escribir primero
`src/main_test.odin` (red first):
- `parse_args`: `--load f` sets `load_path`; `--load` last → usage error; `--load f --headless` and the reverse order.
- `summary_line` on a graph from `core.load_graph` of a tiny text (two named positions, one transition, one
  anonymous end; built with a small inline text constant in the test) → the exact line.
- `format_load_error`: a `Parse_Error` with line and block, a `Graph_Error` (`Duplicate_Position_Description`), one with
  `NO_BLOCK`, an `Allocator_Error` → the exact strings.
- The headless-load path does not touch raylib: test the procedure that implements it (`load_summary` with an
  injected path to a temp file is not possible without the file system in a unit test — `main` may use it; write the
  temp file under `os.temp_dir()` or skip this one and cover it with the manual check in step 5; the PR says which).
- Exit codes are distinct (a compile-time `#assert` is enough).

## Riesgos
- **Debug load time**: ~67 s with ASan for the full DB; acceptable for the manual check, but do not add a CI step
  that loads the full DB in debug (none is planned).
- **`os.exit` skipping cleanup**: all exits go through `main` after `report_leaks` (step 1).
- **`Error` printing**: `%v` of a union prints its variant; the format must match the spec's text exactly, hence the
  pure formatter and its tests.
- **Size**: ~90 lines of `main.odin`, ~60 of tests, ~50 of bench, ~5 of `build.sh`: ~210.

## Criterio de hecho
- `./build.sh ci` green locally and in CI; zero leaks.
- Manual outputs of step 5 in the PR (counts equal `meta.json` `counts`; both error exits; bench median).
- `code-reviewer` (sonnet) without blockers.
- Labels `type:feat`, `area:infra`, `phase-2`; milestone «Fase 2: Núcleo de datos»; `Closes #148`.
- Worker model: sonnet.
