# 0005. Own JSON format
Status: Proposed
Date: 2026-11-21

## Context
Paths `src/…` are in `reference/GrappleMap`.

Phase 2 reads the original's `GrappleMap.txt`; phase 6 edits our own graph, which needs a file format of its own
(`src/editor/CLAUDE.md`, `docs/architecture.md`). The original's format (`docs/original.md` §1) has no identities:
a named position is "the `i`-th 1-position block", a transition "the `i`-th block with ≥ 2 positions"
(`src/graph.cpp:281-296`, §2.1), lookups go by first description line, by index (`p<N>`, `t<N>`) or by `line_nr`
(§2.8), and anonymous nodes are re-derived on every load by matching (§2.2, §2.3). Any insertion or deletion
renumbers everything after it, so an editor, a history or a link from outside cannot hold on to a node or a
transition.

What a block carries (§1.1-§1.4): description lines (the first is the name; `tags:` and `properties:` are parsed,
`ref:`, `note:`, `todo:` are plain lines; a literal backslash-`n` is a display break, §1.2), one or more positions of
2 × 23 joints × `x, y, z`, each an integer `0…3843` in the file (§1.3), and a `line_nr` computed by the loader (§1.4).
The original's writer (`src/persistence.cpp:118-151,241-251`, §1.5) emits named positions first, then transitions,
each in graph order, description lines verbatim, positions as `int(round(d·1000))` (with `+2` on `x`/`z`). At the pin
the DB is already in that order: the 601 named positions come before the first transition (`awk` over runs of
position lines, as in §2.1). The DB is valid UTF-8 (`iconv -f UTF-8 -t UTF-8`) and has literal `\n` in 1282 lines and
`"` in 1142 (§1.8, `grep -c`).

## Decision
1. **One UTF-8 JSON object per graph**, `.json`, read and written by `core` from/to `[]byte` (no file system in
   `core`). Shape (illustrative, not a parser design):
   ```json
   {
     "schema_version": 1,
     "next_id": 2087,
     "positions":   [{"id": 1,   "description": ["name", "tags: a b"], "position": [[[1998, 104, 2311], …23], …2]}],
     "transitions": [{"id": 602, "description": ["name", "properties: detailed"], "positions": [[[[…]]], …]}]
   }
   ```
   `positions` are the named positions (graph nodes with a description), `transitions` the blocks with ≥ 2
   positions. Unknown top-level keys are an error, not ignored.
2. **`schema_version`** is an integer, `1` for this ADR. A reader rejects a version it does not know; a change to the
   schema bumps it and comes with a migration and its own ADR amendment.
3. **Stable IDs.** Every named position and transition has an `id`: a positive integer, unique across both arrays,
   **never reused**; `next_id` is greater than every `id` ever issued in this file. IDs are opaque: not derived from
   the name (names repeat, §2.1, and get edited), nor from the position (it gets edited), nor from the index
   (it shifts). On import from `GrappleMap.txt` they are assigned deterministically: `id` = 1-based block number in
   the file (so the same file always gives the same IDs), `next_id` = blocks + 1. They survive renames, description
   and position edits, reordering and the deletion of other entries; an entry deleted and recreated gets a new `id`.
   **Anonymous nodes have no `id` and are not stored**: as in the original they are derived from the transitions'
   end positions by the same matching on every load (§2.2, §2.3), and storing them would duplicate state that the
   matching can contradict. Giving one a description promotes it to a named position with a new `id`.
4. **Order is data.** The order of `positions` and of `transitions` is the original's node order and sequence order,
   which node matching depends on (first match wins, §2.3). A reader keeps it; `id`s do not define it.
5. **Description lines verbatim**, as an array of strings, one per line, in order, with JSON escaping only (a literal
   backslash-`n` is the JSON string `"\\n"`). `tags`, `properties`, `ref`, `note`, `todo`, `detailed` and
   `bidirectional` are **not** separate fields: they are derived from the lines with the original's rules (§1.2, §2.7),
   so there is one source of truth and the lines' order and spelling round-trip. An empty `description` array is
   invalid (the first line is the name; a first line `""` is valid). **Two named positions with the same whole
   `description`** (all lines equal) are invalid, as the original rejects them on load with `multiple positions
   named` (`src/graph.cpp:283-285`, §2.1): an error on read, on import and on export, so a valid JSON never exports a
   `GrappleMap.txt` the original cannot load. Equal names with different other lines stay valid, as in the original.
6. **Positions in the original's quantization**: each coordinate is the integer `0…3843` exactly as in the file, i.e.
   with the `+2` offset on `x`/`z` (§1.3), nested `[player 0, 1][23 joints in enum order][x, y, z]` (§1.3 order).
   `core` decodes them to `f64` with the original's formula (ADR 0003, decision 1). When phase 6 writes an edited
   position it quantizes with the writer's formula `int(round((x + 2)·1000))` etc. (`src/persistence.cpp:122-136`), so
   an edit rounds to 1 mm exactly as in the original. Values outside `0…3843` are an error on read and on write.
7. **No `line_nr`.** It is a property of one particular text file (and its exact meaning is [unverified], §1.4), not
   of the graph. When a `GrappleMap.txt` is exported, `l<N>` refers to that export, recomputed by the loader. Inside
   our app references use `id`s.
8. **Round trip.** "Byte-exact" means: for every `GrappleMap.txt` the original loads without error and that is not
   rejected below, `export(import(txt))` equals, byte for byte, what the original's `save(loadGraph(txt))`
   writes (§1.5). For the DB at the pin that is expected to be the file itself, since it is already in writer order
   (Context); this is checked in phase 2. What `export(import(txt))` does not give back as the input bytes:
   - changed by the original's writer too, so still equal to `save(loadGraph(txt))`: interleaved named positions after
     transitions (moved first), description lines at the end with no position (dropped, §1.1). Import follows the
     writer;
   - undefined or fatal in the original (§1.7): a position block with no description lines before it, a block shorter
     than 296 bytes, a non-base62 digit, a file without its final `'\n'`; and rejected by the original's `Graph`: two
     named positions with the same whole description (decision 5): **import error** (an error value, never `panic`),
     not a guess;
   - accepted by the original but rejected here, stricter on purpose: a position block not on the 4 × 69 layout
     (other indentation, tabs, digits split differently). The original decodes it silently or misreads it (§1.7) and
     `save` would normalise it; import reports an error instead of guessing which case applies;
   - not representable in JSON strings: bytes that are not valid UTF-8 in a description line: import error;
   - not writable back to `GrappleMap.txt`: a description line that starts with a space (it would be read as a
     position, §1.7) or contains `'\n'`, and a coordinate outside `0…3843`: **export error**. `'\r'` is kept verbatim
     both ways (JSON `"\r"`), as the original does.
9. **`GrappleMap.txt` stays readable and writable**: import and export are both in `core`; the JSON is our working
   format, not a replacement for compatibility with the original.

## Alternatives
- **Keep only `GrappleMap.txt`.** Zero new format, but no stable identities (renumbering on every insert), and
  `line_nr`/index references break on every edit. The editor would have to invent IDs in memory and lose them on save.
- **JSON with doubles** (`f64` in meters). Readable, but a decimal round trip of `f64` is exact only with care
  (shortest round-trip printing), it would admit values off the 1 mm grid that the original cannot store, and the
  `GrappleMap.txt` export would depend on rounding the doubles back. Integers make the round trip exact by
  construction.
- **Store parsed fields** (`tags`, `properties`, `refs`, `notes`) next to or instead of the lines. Handier for the UI,
  but two sources of truth that can disagree, and line order and spelling would not round-trip.
- **Store the derived graph** (anonymous nodes, `from`/`to` with reorientations). Faster loading, but a cache that
  can contradict the matching; the original caches only node numbers, keyed by the md5 of the file (§2.5).
- **A binary format.** Smaller and faster, but not diffable in git, not editable by hand, and the DB is only ~2.7 MB of
  text (`wc -c`); speed is not a problem at this size.

## Consequences
- Phase 2: `core` gets a JSON reader/writer and a `GrappleMap.txt` exporter, with round-trip tests: `txt → JSON →
  txt` byte-exact against the original's DB and against the oracle sample's blocks (ADR 0002), plus robustness tests
  for every import/export error above.
- Phase 6: the editor addresses entries by `id`; undo/redo and history store `id`s, never indices.
- The order of entries matters and must be kept by every tool that rewrites the file (sorting it would change the
  graph).
- The JSON is about as big as the text DB times 2-3 (integers with separators instead of 2 base62 digits); not
  compressed.

### Open points
- ~~Whether `save(loadGraph(DB))` is byte-identical to the DB at the pin~~: closed by dumper v4 (#141): it is
  (`save_equals_db` true, `save_md5` = `db_md5` in the oracle's `meta.json`; the bytes are `save.txt` of the full dump).
- Persistent identities for anonymous nodes, if phase 6 needs them (e.g. to attach notes to one without naming it):
  not decided here.
- Re-importing an updated upstream `GrappleMap.txt` assigns IDs by block number again, so identities are not carried
  over to a JSON that was already edited; matching entries across versions (by name, content or both) is a phase-6
  question.
- ~~Pretty-printing and key order of the written JSON~~: closed by the writer (`src/core/json.odin`, #146). Fixed key
  order `schema_version`, `next_id`, `positions`, `transitions`; inside an entry `id`, `description`, then `position` /
  `positions`; compact (no spaces) with one entry per line, entries separated by `,\n`, an empty array on one line
  (`"positions":[]`), one final `\n`. Strings are escaped per RFC 8259 (`\u00xx` lowercase for other control bytes).
  Changing this layout is an amendment.
- Anonymous nodes carry `NO_ID` (0) in `Node.id`; real ids start at 1.
  The reader (`src/core/json_read.odin`, #182) accepts any RFC 8259 whitespace and key order: the layout binds the writer only.
