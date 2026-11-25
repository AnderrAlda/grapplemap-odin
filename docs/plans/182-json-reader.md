# Plan: #182 feat(core): JSON reader and round trips
Spec: docs/specs/phase-2-core.md (deliverable 10, second part; split from #146) · ADR 0005 (decisions 1-8, layout in
"Open points") · `src/core/json.odin` (writer, #146) · docs/original.md §1.2, §2.1

## Pasos
1. **`src/core/json_read.odin`** (new; `json.odin` keeps the writer): `load_graph_json(data: []byte) -> (g: Graph,
   err: Error)`, the counterpart of `load_graph`: same arena ownership (`virtual.arena_init_growing` in `g.arena`,
   destroyed on error, zero `Graph` returned), freed with `graph_destroy`. Hand-written, not `core:encoding/json`.
   - **Syntax**: any RFC 8259 JSON (whitespace anywhere, keys in any order), not only the writer's layout, so a
     hand-edited file loads; a schema-driven recursive-descent reader (no generic tree, bounded depth by the schema).
     Integers only where the schema has numbers (`-`? digits, no fraction/exponent, no leading zeros, fits in `int`).
     Strings: all RFC 8259 escapes, `\uXXXX` with surrogate pairs → UTF-8 (lone surrogate → `Syntax`); raw bytes
     `< 0x20` → `Syntax`; raw bytes not valid UTF-8 → `Invalid_Utf8`. Unescaped lines are copied into the arena
     (nothing points into `data`). Leading UTF-8 BOM → `Syntax` (RFC 8259 §8.1 lets us reject it). Trailing
     non-whitespace after the object → `Syntax`.
   - **Schema** (ADR 0005 d1-d6): top level exactly `schema_version`, `next_id`, `positions`, `transitions`;
     a position entry exactly `id`, `description`, `position`; a transition entry exactly `id`, `description`,
     `positions`. Extra key → `Unknown_Key`; absent → `Missing_Key`; repeated key → `Syntax`; wrong JSON type or
     shape (string for an array, `position` not `2 × 23 × 3`, a transition with `< 2` positions, a position entry
     shaped as a transition) → `Syntax`. `schema_version != 1` → `Bad_Schema_Version`. Coordinate outside
     `0…Q_MAX` → `Coordinate_Out_Of_Range`. Empty `description` → `Empty_Description`. Two positions with the same
     whole description → `Duplicate_Description` (checked here, so it never surfaces as `Graph_Error`). An id `<= 0`,
     `>= next_id` or repeated across both arrays → `Duplicate_Id` (the writer's convention, #146). Only the existing
     `Json_Error_Kind` values: **`errors.odin` is not touched**.
   - **Error location**: `line` = 1-based line of the input where the offending token starts (the writer puts one
     entry per line, so it points at the entry); `block` = 0-based entry index (positions, then transitions, the
     writer's numbering) or `NO_BLOCK` outside entries. First error stops.
   - **To `Graph`**: each entry becomes a `Sequence` in the arena: `id` from the file; positions decoded with the
     parser's formula (`f64(q)/1000`, `− 2` on `x`/`z`; reuse/expose the decode step of `parse.odin` as
     `@(private)` if it is a separate proc, else a shared `dequantize` helper used by both — the only change allowed
     there); `detailed`/`bidirectional` with `properties_in_desc` exactly as `parse.odin` does; `line_nr = NO_LINE`
     (ADR 0005 d7: no line numbers; `l<N>` lookups never match). Sequences = positions then transitions, in file
     order (ADR 0005 d4), then the private `build` (graph.odin) as `load_graph` does, then `g.next_id` = the file's
     `next_id` (not recomputed: ids are never reused, d3). Scratch on `context.temp_allocator`.
2. **Round trips** (ADR 0005 d8, spec "End-to-end" 5):
   - `tests/fidelity/json_test.odin` (extend): from the shared graph, `j1 = export_json(g)`, `h = load_graph_json(j1)`,
     then `export_txt(&h)` has `meta.json`'s `save_md5` (and equals the DB bytes when `save_equals_db`; `save.txt` byte
     for byte when the oracle dir has it, as `export_test.odin` does: reuse its helpers), and `export_json(&h) == j1`
     byte for byte. Also `h` has the same counts as `g` (nodes, `named_count`, edges, anonymous nodes = matching
     recomputed identically) and equal `from`/`to` node indices per edge. Time of `load_graph_json` reported in the PR.
3. Docs: `src/core/CLAUDE.md`, `json.odin` bullet → "writer" + new `json_read.odin` bullet (general JSON syntax,
   strict schema, error kinds, `line_nr = NO_LINE`, `next_id` from the file); ADR 0005: one line under the layout
   point saying the reader accepts any RFC 8259 whitespace/key order (the layout binds the writer only).
   `changelog.d/182-json-reader.md`. Root `CLAUDE.md`: nothing (no new command).
4. `./build.sh ci`; `fidelity` workflow green on the PR.

## Ficheros a tocar
`src/core/json_read.odin` (new), `src/core/json_read_test.odin` (new), `src/core/parse.odin` (only if the decode
helper must become package-visible), `tests/fidelity/json_test.odin`, `src/core/CLAUDE.md` (json bullets only),
`docs/adr/0005-json-format.md` (one line), `changelog.d/182-json-reader.md` (+ this plan).
Not touched: `errors.odin`, `graph.odin`, `json.odin` (writer), `playback*.odin` (#181, same batch), `build.sh`,
`.github/`, `reference/`.

## Tests a escribir primero
`src/core/json_read_test.odin` (red first), table-driven where possible to keep it compact:
- **Round trip unit**: the tiny DB of the writer's golden test → `export_json` → `load_graph_json` → `export_json`
  identical bytes; → `export_txt` equals `export_txt` of the original graph; empty graph (`"positions":[]`) loads.
- **General syntax**: the golden document re-spaced (pretty-printed, CRLF, tabs) and with keys reordered loads to the
  same graph (same `export_json` bytes).
- **Strings**: every escape (`\" \\ \/ \b \f \n \r \t é`, a surrogate pair → 4-byte UTF-8) decodes to the
  expected bytes; a literal backslash-`n` (`"\\n"`) stays two bytes; lone surrogate, raw `0x01`, unterminated string
  → `Syntax`; raw invalid UTF-8 → `Invalid_Utf8`.
- **Each error kind** with its `line` and `block` (table: input snippet built from the golden doc by one substitution
  → kind, line, block): unknown top-level key, unknown entry key, missing `next_id`, missing `position`, repeated key,
  `schema_version` 2, `q` = −1 and 3844, fraction `1.5`, exponent `1e3`, leading zero, empty description, duplicate
  whole description (equal name + different other line is **valid**), id 0, id = `next_id`, id repeated across arrays,
  transition with 1 position, position with 22 joints, trailing garbage, truncated input at every byte of the golden
  doc (loop: error, never panic).
- **Data**: `detailed`/`bidirectional` derived from `properties:` lines; `line_nr == NO_LINE`; `next_id` kept from the
  file (a file with `next_id` far above the max id keeps it); ids kept (not renumbered); anonymous nodes recomputed.
- **Zero leaks** on every error (tracking allocator; the arena destroyed) and `graph_destroy` leaves `total_reserved`
  0 (as the graph tests do).
Fidelity: step 2 (red until the reader exists).
Mutants to try, none committed: accept unknown keys; skip the duplicate-description check (would surface as
`Graph_Error`); recompute `next_id`; forget `− 2` on `z`; take `line` from the entry start instead of the token. Each
must turn a test red.

## Riesgos
- **Size**: ~230 lines of reader, ~170 of table-driven tests, ~40 of fidelity: around 400-440. If it goes clearly
  over, the round-trip fidelity (step 2) goes as a second PR on the same issue (the second one `Closes #182`);
  escalate only if the plan must change.
- **Robustness**: a schema-driven reader bounds the depth; the truncation loop and the fidelity mutation style catch
  panics; integers parsed with overflow checks (no `strconv` silent saturation: check its behaviour or hand-roll).
- **Overlap with #181** (same batch): only `src/core/CLAUDE.md` (different bullets); whichever merges second runs
  `git merge origin/main` per `/orchestrate` §4.

## Criterio de hecho
- `./build.sh ci` green locally and in CI (linux + macOS); zero leaks; `fidelity` workflow green (full dump: the
  round trips over the whole DB).
- ADR 0005 line added; mutants documented in the PR; epic #4 boxes "Export … JSON propio con round trip exacto"
  ticked in the PR description (MAIN ticks the epic after merge).
- `code-reviewer` (opus, `src/core`) without blockers.
- Labels `type:feat`, `area:core`, `phase-2`; milestone «Fase 2: Núcleo de datos»; `Closes #182`.
- Worker model: sonnet (format work; the decode and the graph build are reused, not reimplemented).
