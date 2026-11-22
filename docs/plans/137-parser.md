# Plan: #137 feat(core): GrappleMap.txt parser
Spec: docs/specs/phase-2-core.md (deliverable 1b)

## Pasos
1. **Tests first, by the `test-writer` subagent** (critical piece, `docs/ai-workflow.md`): `src/core/parse_test.odin`
   from this plan and `docs/original.md` §1, without the implementation. A test-only encoder
   (`encode_position_q` in the test file: `[2][23][3]int` → the 4 lines of §1.3) builds inputs. They must fail first.
2. `src/core/parse.odin` (illustrative names; keep them consistent with `types.odin`/`errors.odin`):
   ```odin
   Sequence :: struct {
       description:   []string,   // lines verbatim, first = name; never empty
       positions:     []Position, // ≥ 1; 1 = named position, ≥ 2 = transition (the graph decides, #142)
       line_nr:       int,        // 0-based line of the first position line (confirmed by the dumper)
       detailed:      bool,       // properties_in_desc, §2.7
       bidirectional: bool,
   }
   parse_db :: proc(data: []byte, allocator := context.allocator) -> (seqs: []Sequence, err: Error)
   sequences_destroy :: proc(seqs: []Sequence, allocator := context.allocator)
   tags_in_desc :: proc(desc: []string, allocator := context.allocator) -> ([]string, mem.Allocator_Error)       // sorted, unique
   properties_in_desc :: proc(desc: []string, allocator := context.allocator) -> ([]string, mem.Allocator_Error) // sorted, unique
   ```
   - Line rule (§1.1): first byte `' '` → position line; anything else (including an empty line) → description line.
   - **Strict position layout** (ADR 0005 decision 8): a position is exactly 4 consecutive lines of 4 spaces + 69
     bytes + `'\n'`. A line starting with `' '` that is not 73 bytes + `'\n'`, or fewer than 4 such lines in a row
     (a run not a multiple of 4) → `Bad_Position_Layout`. A byte in the 69 that is not `[a-zA-Z0-9]` →
     `Bad_Base62_Digit` (the original rejects it too). Fewer than 296 bytes left for a block → `Truncated_Block`.
   - Decoding (§1.3, ADR 0003 d1): alphabet `a-z A-Z 0-9` = 0…61; per coordinate `f64(62*d0 + d1) / QUANT_SCALE`,
     then `- ENCODING_OFFSET_XZ` on `x` and `z` (same operations, same order); order player 0 then 1, joints in enum
     order, `x, y, z`.
   - Blocks (§1.1): description lines then one or more positions; consecutive positions with no description in
     between append to the same sequence. A position with no pending description → `Block_Without_Description`.
     Trailing description lines with no position are **dropped** (the writer drops them too, ADR 0005 d8).
   - Whole file: empty input → no sequences, no error; non-empty input whose last byte is not `'\n'` →
     `Missing_Final_Newline`; a description line that is not valid UTF-8 (`core:unicode/utf8.valid_string`) →
     `Invalid_Utf8`. `'\r'` is kept verbatim. A literal backslash-`n` is left untouched (§1.2).
   - `line_nr` = 0-based index of the block's first position line (`tools/oracle/README.md`, "Dumper").
   - `tags:` / `properties:` (§1.2): prefix at column 0 on **every** line (first included), rest split on ASCII
     whitespace, union of all such lines, sorted and unique (the original's `std::set` order: bytewise). `detailed` /
     `bidirectional` = presence in the properties.
   - Errors: first error stops; `Parse_Error{kind, line (1-based line of the offending line), block (0-based index of
     the sequence being built, NO_BLOCK before the first)}`. On error everything allocated so far is freed and `nil`
     is returned (no leak on the error path).
   - Memory: description strings are **copied** (the result does not point into `data`); scratch in
     `context.temp_allocator`. `sequences_destroy` frees one success result.
3. `src/core/CLAUDE.md` (file list: `parse.odin`), `changelog.d/137-parser.md`.
4. `./build.sh ci`.

## Ficheros a tocar
`src/core/parse.odin`, `src/core/parse_test.odin`, `src/core/CLAUDE.md`, `changelog.d/137-parser.md`. If an error kind
is missing, add it to `src/core/errors.odin` (enums "may grow"). Nothing outside `src/core` (the real DB is read by the
fidelity tests of #138, not here: `core` has no file system).

## Tests a escribir primero
- Decoding: digits `aa` → 0, `99` → 3843 (`Q_MAX`), one mixed value per alphabet range; `x`/`z` offset; bit equality
  with `f64(q)/1000 - 2` for every `q` in `0…3843` (property test over the whole grid, all three axes).
- Structure: one named position; a transition of 3; two named positions; consecutive positions merging; `line_nr` of
  several blocks; description with literal `\n`, `"`, `¼`, `'\r'`, empty first line `""`; trailing description lines
  dropped; empty input.
- Tags/properties: several `tags:` lines unioned and sorted; `properties: detailed bidirectional` flags; `tags:` on the
  first line; extra whitespace.
- Errors (one test each, kind + line + block): non-base62 byte, truncated last block, missing final `'\n'`, position
  before any description, wrong indent, 68/70 digits on a line, a run of 3 position lines, CRLF, tab inside digits,
  invalid UTF-8 in a description.
- Robustness: every prefix of a small valid file (truncation at each byte) gives a value or an error, never a panic,
  and the tracking allocator of `core:testing` reports no leak (success and error paths).

## Riesgos
- Being stricter than the original by mistake: every rejection must be one of §1.7 / ADR 0005 d8; the real DB has
  none of them (§1.8), which #138 checks on the whole file.
- Bit-exact decoding: no `* 0.001`, no FMA, no reassociation; the property test over the grid catches it.
- Leaks on the error path with many small allocations: build per-sequence slices with `make`/`append` on the given
  allocator and free them all on error (or build into the temp allocator and copy out only on success).
- `tags_in_desc` split rule: `istringstream >>` splits on C `isspace` (space, `\t\n\v\f\r`); use the same set.

## Criterio de hecho
Tests written first (by `test-writer`) and green under the tracking allocator; `./build.sh ci` green; `code-reviewer`
(opus) without blockers; PR < 400 lines (tests included; if over, justified in the PR as in #150); labels
`type:feat`, `area:core`, `phase-2`, milestone «Fase 2: Núcleo de datos».
