# Plan: #138 test(core): fidelity harness and parser fidelity
Spec: docs/specs/phase-2-core.md (deliverable 2, "Oracle data")

## Pasos
1. **`tests/fidelity/`** (new package `fidelity`, test-only; `import "app:core"`; may use `core:os`, `core:bufio`,
   `core:encoding/json`: core library, no new dependency; `core:encoding/json` is fine here because the hand-written
   JSON decision is about `core`'s own format, not about reading the oracle):
   - `oracle.odin`: `oracle_dir()` = `os.get_env("GM_ORACLE_DIR")` or `#directory + "/../fixtures/oracle"`;
     `db_path()` = `#directory + "/../../reference/GrappleMap/GrappleMap.txt"`; `load_db()` reads it and **fails the
     test** (not skip) with "missing reference/GrappleMap: run `git submodule update --init`" if absent.
   - `ndjson.odin`: `ndjson_each(path, ctx, proc(line: []byte, ctx) -> bool)` streams line by line with `bufio.Reader`
     (lines can be MBs: `playback.ndjson` is 389 MB in the full dump), each line parsed by the caller with
     `json.unmarshal` into a small struct and freed per line (`context.temp_allocator` + `free_all` per line).
   - `f64` comparisons by bits (`transmute(u64)`), helper `expect_bits(t, got, want, what)`.
2. **Parser fidelity** (`sequences_test.odin`): parse the whole DB once; check `meta.json` `counts.blocks` (2,086) and
   `counts.positions` (8,323) against the parse; then for every line of `sequences.ndjson` (`index` = block): the
   sequence at that index has the same `description` lines (exact strings), `line_nr`, `kind` (`position` iff 1
   position), `tags`, `properties` (`tags_in_desc`/`properties_in_desc`), `detailed`, `bidirectional`, and every
   coordinate's bits equal `f64(q)/1000` (− 2 on `x`/`z`) of `positions_q` (the dumper checked that this is the
   original's double, `tools/oracle/README.md`). `refs`/`notes` are dumper-derived and not compared.
3. **Body tables** (`body_test.odin`): `body.json` `joints` (index, radius bits, draggable, mirror) vs `JOINT_DEFS`;
   `segments` (ends, length bits, `mid_radius` or `null`, visible) vs `SEGMENTS`; `players` colors vs
   `PLAYER_COLORS`. Names: compare with `to_string` only if `core` has one; otherwise not compared (no new API for it).
4. **Mutation test** (`mutation_test.odin`): fixed seed (`ODIN_TEST_RANDOM_SEED`-independent: `rand.create(SEED)`),
   N = 200 cases over the real DB: truncation at a random byte, a random byte flip, a swap of two random lines.
   Each: `parse_db` returns a value or an error, never panics; the value is freed with `sequences_destroy`; no leak.
5. **`build.sh`**:
   - `TEST_PKGS` += `tests/fidelity`;
   - `cmd_check`: also `odin check tests/fidelity $COLLECTION $VET -no-entry-point`;
   - `cmd_fmt` / `cmd_fmt_check`: also `tests/fidelity/` (and `bench/` when it exists, guarded);
   - `cmd_test`: add `-define:ODIN_TEST_FAIL_ON_BAD_MEMORY=true` (#151, point 1: today a leak is only logged;
     verified in the pinned toolchain, `core/testing/runner.odin:40,107`); all current packages must stay green.
6. **`ci.yml`**: `submodules: true` in the `actions/checkout` of the `test` and `bench` jobs (nothing else). This is a
   CI workflow edit: **approved by Ander with this plan**; `Edit(./.github/workflows/**)` is `ask` in
   `.claude/settings.json`, so the worker will get a permission prompt: it stops there and MAIN tells Ander to answer it
   in the worker's space.
7. Docs: root `CLAUDE.md` "Mapa" (`tests/fidelity`, `GM_ORACLE_DIR`), `docs/architecture.md` test table (fidelity row:
   package name and env var), `changelog.d/138-fidelity-harness.md`. Comment on #151 that point 1 is done here.
8. `./build.sh ci` locally, and `GM_ORACLE_DIR=<downloaded full dump> ./build.sh test` once by hand
   (`gh run download <latest oracle run on main> -n oracle-full-dump`), result in the PR.

## Ficheros a tocar
`tests/fidelity/{oracle,ndjson,sequences_test,body_test,mutation_test}.odin`, `build.sh`, `.github/workflows/ci.yml`,
`CLAUDE.md`, `docs/architecture.md`, `changelog.d/138-fidelity-harness.md`. Not `src/core` (if a needed accessor is
missing, stop and escalate rather than widen `core`'s API in this PR) and not `src/core/parse_test.odin` (#151).

## Tests a escribir primero
The fidelity tests are themselves the tests: write `sequences_test.odin` first against the harness stubs and see it
fail (e.g. harness returning no lines must fail the count check, never pass vacuously: assert that at least one line
was compared per file).

## Riesgos
- Vacuous passes (empty file, wrong path, filter that matches nothing): every test asserts a minimum number of
  compared records; a missing file or DB is a failure.
- Memory on the full dump: per-line temp allocator with `free_all`; never hold a whole NDJSON in memory.
- `ODIN_TEST_FAIL_ON_BAD_MEMORY` may turn an existing hidden leak red in another package: fix it only if trivial and in
  test code; otherwise escalate (do not drop the flag).
- `json.unmarshal` of `%.17g` doubles: correct rounding is required for bit comparison (`strconv.parse_f64`, Eisel-Lemire);
  a test on a known value (`0.025000000000000001` → bits of `0.025`) pins it.
- PR size: if over 400 lines, split the mutation test + `body.json` into a second PR (spec: deliverable 2 may split).

## Criterio de hecho
`./build.sh ci` green locally and in CI (linux + macOS) with the submodule; full-dump run by hand green and reported;
no vacuous test; `code-reviewer` (opus) without blockers; labels `type:test`, `area:core`, `area:infra`, `phase-2`,
milestone «Fase 2: Núcleo de datos».
