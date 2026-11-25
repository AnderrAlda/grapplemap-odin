# Plan: #146 feat(core): JSON writer and stable ids
Spec: docs/specs/phase-2-core.md (deliverable 10, first part; reader and round trips split to #182, as the spec
allows) · ADR 0005 (decisions 1-6, open point "pretty-printing and key order") · docs/original.md §1.3, §1.5

## Pasos
1. **Stable ids in the data model** (ADR 0005 d3), minimal:
   - `Sequence.id: int` (`parse.odin`): `parse_db` sets `id = block + 1` (1-based block number in the file).
   - `Node.id: int` (`graph.odin`): copied from the sequence for named nodes; `NO_ID :: 0` for anonymous nodes
     (they have no id, d3). Edges use `edge.sequence.id`.
   - `Graph.next_id: int`: `build` sets it to `len(seqs) + 1` (blocks + 1), i.e. greater than every id.
   No other behaviour changes; existing tests stay green untouched.
2. **`src/core/json.odin`** (new): `export_json(g: ^Graph, allocator := context.allocator) -> (out: []byte, err:
   Error)`, the hand-written writer of ADR 0005 (not `core:encoding/json`). Output, byte for byte (this closes the ADR's
   open point on key order and pretty-printing; the ADR gets the layout):
   ```
   {
   "schema_version":1,
   "next_id":2087,
   "positions":[
   {"id":1,"description":["…","…"],"position":[[[x,y,z],…23],[…]]},
   …
   ],
   "transitions":[
   {"id":602,"description":["…"],"positions":[[[[x,y,z],…],[…]],…]},
   …
   ]
   }
   ```
   followed by one `'\n'`. Compact inside an entry (no spaces), one entry per line, entries separated by `",\n"`; an
   empty array is `"positions":[]` on one line. Fixed key order as above. `positions` = nodes with a non-empty
   description in node order (as `export_txt`); `transitions` = edges in order. Coordinates are the original's
   quantization `round((x + 2)·1000)`, `round(y·1000)`, `round((z + 2)·1000)`, reusing `export_txt.odin`'s `quantize`
   (made package-private: `@(private)` instead of `@(private = "file")`; the only change to that file), so JSON and
   txt can never disagree. Integers in plain decimal.
   String escaping (JSON, RFC 8259): `"` → `\"`, `\` → `\\`, `\b \f \n \r \t` short forms, other bytes `< 0x20` →
   `\u00XX` (lowercase hex), everything else (including UTF-8 multibyte and `0x7f`) verbatim. A literal backslash-`n` in a
   line is therefore `"\\n"` (ADR 0005 d5).
   Errors (`Json_Error`, `line = 0`, `block` = 0-based index of the entry in the output: positions first, then
   transitions), checked **before** allocating (as `export_txt`: a failed export allocates nothing): empty description
   → `Empty_Description`; two written nodes with the same whole description → `Duplicate_Description`; coordinate out
   of `0…Q_MAX` or NaN → `Coordinate_Out_Of_Range`; an id `<= 0`, `>= next_id`, or repeated → `Duplicate_Id` (a new
   kind only if the reviewer prefers `Bad_Id`; keep to the existing enum otherwise); a description line that is not
   valid UTF-8 → a new `Json_Error_Kind.Invalid_Utf8` (JSON strings must be UTF-8; the parser never yields one, an
   editor could). A graph from `load_graph` never triggers any.
   Size: compute the exact size in the check pass and fill one buffer (as `export_txt`), or a `strings.Builder` freed on
   error; the worker picks, the tests check for zero leaks either way.
3. Docs: ADR 0005, "Open points": close the pretty-printing/key-order bullet pointing to `json.odin` (the layout
   above), and note `NO_ID` for anonymous nodes; `src/core/CLAUDE.md`: new `json.odin` bullet, `parse.odin`/`graph.odin`
   bullets mention `id`/`next_id`; `changelog.d/146-json-writer.md`. Retitle #146 to
   `feat(core): JSON writer and stable ids` (`gh issue edit`) and comment that the reader moved to #182.
4. `./build.sh ci`; `fidelity` workflow green on the PR.

## Ficheros a tocar
`src/core/json.odin` (new), `src/core/json_test.odin` (new), `src/core/parse.odin` (`id` field and its assignment),
`src/core/graph.odin` (`Node.id`, `NO_ID`, `Graph.next_id`), `src/core/export_txt.odin` (`quantize` visibility only),
`src/core/errors.odin` (`Invalid_Utf8` in `Json_Error_Kind`), `src/core/parse_test.odin` and `src/core/graph_test.odin`
(id tests only), `tests/fidelity/json_test.odin` (new), `docs/adr/0005-*.md`, `src/core/CLAUDE.md`,
`changelog.d/146-json-writer.md` (+ this plan).
Not touched: `reorient.odin`, `match.odin`, `lookup.odin`, `build.sh`, `.github/`, `reference/`.

## Tests a escribir primero
Red first:
- `parse_test.odin`: ids are `1, 2, 3` for three blocks, in file order, including interleaved named/transition blocks.
- `graph_test.odin`: named node keeps its sequence's id; anonymous node has `NO_ID`; edge id = its block's; `next_id`
  = blocks + 1; empty DB → `next_id = 1`.
- `json_test.odin` (hand-made graphs via `load_text`/`build_seqs`):
  - **Golden bytes**: a tiny DB (one named position, one 2-position transition) → the exact expected JSON string,
    written in the test (the layout of step 2, including the final `'\n'`).
  - Empty graph → `positions":[]`, `"transitions":[]`, `next_id` 1.
  - Escaping: a line with `"`, `\`, literal backslash-`n`, `'\r'`, `'\t'`, `0x01`, `¼` → expected escaped bytes.
  - Quantization: coordinates at the grid edges (`q = 0` and `3843` on every axis) written as `0`/`3843`; matches
    `export_txt`'s digits for the same graph (decode both, same integers).
  - Anonymous nodes are not written; the order is node order then edge order; ids are the stored ones (not indices).
  - Each error kind with its `block`, and no allocation on error (tracking allocator: zero allocations after a failed
    export).
- `tests/fidelity/json_test.odin` (shared graph, no extra load): `export_json` of the DB succeeds; the output has
  601 + 1485 entries (counts from `meta.json`, not literals), ids `1…` in writer order equal to block + 1 (the DB is in
  writer order, ADR 0005), `next_id` = 2087 via `meta.json` blocks + 1; output is valid JSON per `core:encoding/json`
  (`json.parse` in the test package only, as a syntax check; `core` itself never uses it). Time of the export reported
  in the PR.
Mutants to try, none committed: drop the `+ 2` on `x`; escape `/`; forget the comma between entries; write
anonymous nodes. Each must turn a test red.

## Riesgos
- **Data model change** (`id`, `next_id`) touches `parse.odin`/`graph.odin`: additive fields only; #143 and #144 of
  this batch do not touch those files.
- **Layout is a format commitment**: once #182 reads it and files exist, changing it needs an ADR amendment; that is
  why the golden-bytes test exists and the ADR records it.
- **Size**: ~25 lines of id plumbing, ~170 of writer, ~200 of tests: near but under 400; if it goes over, the id
  plumbing goes first as its own PR on the same branch flow (escalate only if the plan must change).

## Criterio de hecho
- `./build.sh ci` green locally and in CI (linux + macOS); zero leaks; `fidelity` workflow green.
- ADR 0005 updated (open point closed); mutants documented in the PR.
- `code-reviewer` (opus, `src/core`) without blockers.
- Labels `type:feat`, `area:core`, `phase-2`; milestone «Fase 2: Núcleo de datos»; `Closes #146`.
- Worker model: sonnet (format work; the quantization is reused, not reimplemented).
