# Plan: #143 feat(core): original lookups (node_by_desc, step_by_desc, named_entity)
Spec: docs/specs/phase-2-core.md (deliverable 7) · docs/original.md §2.8, §10.2 · `src/metadata.cpp:66-124`,
`src/util.hpp:70-86`, `src/metadata.hpp:9-13` (in `reference/GrappleMap`)

## Pasos
1. **`src/core/lookup.odin`** (new), the original's lookups over a built `Graph`, quirks included. Pure: nothing
   allocated (the `\n` → space replacement is done while comparing, never by building a string). Names:
   - `first_line_matches(line, desc: string) -> bool` (`@(private = "file")`): `replace_all(line, "\\n", " ") == desc`
     without allocating: walk `line` left to right; a backslash followed by `n` stands for one `' '` (non-overlapping,
     as boost's `replace_all`); every other byte compares as is. Case-sensitive, no trimming.
   - `node_by_desc(g: ^Graph, desc: string) -> (node: int, ok: bool)` (`src/metadata.cpp:81-94`):
     1. `len(desc) >= 2`, `desc[0] == 'p'` and the rest all ASCII digits `'0'…'9'` → the number, **before and instead
        of** any name lookup. Parsed like `stoul` (decimal, leading zeros allowed: `p007` → 7); a value that does not
        fit a `u64` → `ok = false` (the original throws `out_of_range` and dies: documented divergence). Then wrapped to
        `u16` as the original's `uint16_t(...)` (`p65536` → 0, deterministic, ported). Finally **range-checked**:
        `>= len(g.nodes)` → `ok = false` (the original returns the invalid index and the caller's `g[n]` is UB; the
        port does not hand out invalid indices: documented divergence, the only one besides the `stoul` throw).
     2. Else the first node in index order with a non-empty `description` whose first line matches (anonymous nodes
        skipped; duplicates of the first line: lowest index wins).
     3. Else `ok = false`.
   - `step_by_desc(g: ^Graph, desc: string, from: Maybe(int) = nil) -> (step: Step, ok: bool)`
     (`src/metadata.cpp:66-79`): edges in index order; candidate if the first line of `edge.sequence.description`
     matches **or** `desc == "t" + decimal(index)` (exact text: `t07` never matches edge 7; compare without
     allocating, e.g. parse `desc[1:]` as canonical decimal: digits only, no leading zero unless it is `"0"`). Without
     `from` → first candidate as `{seq, false}`. With `from`: `{seq, false}` if `edge.from.node == from`; else
     `{seq, true}` if `sequence.bidirectional` and `edge.to.node == from`; else **continue** with the next candidate.
     Node equality by index only (reorientation ignored). The parser never yields an empty description (the
     original's UB case, §2.8, cannot happen here; say so in the doc comment).
   - `Named_Entity :: union {Entity_Node, Step}` with `Entity_Node :: struct {node: int}` (the original's
     `variant<NodeNum, Step>`; a bare `int` member would be unreadable at call sites), and
     `named_entity(g: ^Graph, s: string) -> (e: Named_Entity, ok: bool)` (`src/metadata.cpp:107-124`), in this order:
     1. `s == "last-trans"` → `Step{len(g.edges) - 1, false}`; with no edges → `ok = false` (the original wraps to an
        invalid index: same range-check divergence as above).
     2. `l<digits>` (`len >= 2`, `'l'`, rest ASCII digits; `stoul`, overflow → treat as not an `l` name, i.e. fall
        through; truncated to `u32` as `optional<uint32_t>`): the first node with `line_nr == N` (anonymous nodes have
        `NO_LINE`, never equal), then the first edge with `sequence.line_nr == N`. **No early return**: if neither,
        fall through to 3.
     3. `step_by_desc(g, s)` (transitions win over nodes), then 4. `node_by_desc(g, s)` (including `p<N>`), else
        `ok = false`.
   Every proc gets a doc comment citing the original's lines and stating its quirks.
2. Docs: `src/core/CLAUDE.md` gets a `lookup.odin` bullet (one line: lookups of §2.8, quirks kept, the two
   divergences: no invalid index, no throw). `changelog.d/143-lookups.md`. `docs/original.md` is **not** edited.
3. `./build.sh ci`; `fidelity` workflow green on the PR.

## Ficheros a tocar
`src/core/lookup.odin` (new), `src/core/lookup_test.odin` (new), `tests/fidelity/lookup_test.odin` (new),
`src/core/CLAUDE.md` (new bullet only), `changelog.d/143-lookups.md` (+ this plan).
Not touched: `graph.odin`, `parse.odin`, `errors.odin`, `reorient.odin`, `build.sh`, `.github/`, `reference/`.

## Tests a escribir primero
`src/core/lookup_test.odin`, with hand-made graphs through `build` (helpers of `graph_test.odin`: `seq_of`,
`build_seqs`, `load_text`). Red first (procs do not exist → compile error is the first red; then each case):
- `first_line_matches`: `a\nb` (literal backslash-n) vs `a b` → true; vs `a\nb` → false; `a\\nb`-style edge cases:
  `"\\\\n"` (backslash, backslash, n) → backslash + space; trailing lone backslash; empty line vs `""` → true.
- `node_by_desc`: name with `\n` found by its spaced form; case differs → not found; leading/trailing space → not
  found; duplicate first line → lowest index; anonymous node never matched by `""`; a named position with first line
  `""` matched by `""`; `p0`, `p007` → index; `p` alone and `p1x` → name lookup; a node literally named `p1` is
  reachable only as index 1; `p<len(nodes)>` → not found; `p65536` → node 0; `p` + 25 digits → not found.
- `step_by_desc`: first candidate without `from`; `t3` → edge 3, `t03` → no; name shared by two edges with `from` =
  the second's `from` → the second (continue rule); bidirectional entered from `to` → `{seq, true}`; non-bidirectional
  entered from `to` → skipped; a name that also is `t<N>` of another edge → the lower index wins (scan order);
  self-loop with `from` = its node → `{seq, false}`.
- `named_entity`: `last-trans` → last edge; `last-trans` with no edges → not found; `l<N>` hits a node before an edge
  with the same `line_nr` (construct both); `l<N>` with no hit falls through to a transition literally named `l<N>`,
  then to a node so named; a name of both a transition and a node → the transition; `p<N>` reached through step 4.
`tests/fidelity/lookup_test.odin`, on the **shared** DB graph (`shared_graph`, no extra `load_graph`): node 249
(`spiderweb w/o leg over head`) wins over 477; `¼ clinch` → node 200; `...` → the first `...` edge in index order;
`t0` → edge 0; `p124` → 124; `l<line_nr of node 3>` → `Entity_Node{3}`; the 5 isolated named positions (§10.2) found
by name. Values that depend on the DB are computed from the shared graph inside the test where possible, not
hard-coded, except the §10.2 block numbers (named block = node index).
Mutants to try, none committed (the PR lists them): drop the `p<N>` early return; return on the first candidate
ignoring `from`; early-return when `l<N>` finds nothing; overlapping `\n` replacement. Each must turn a test red.

## Riesgos
- **Silent order bugs** (which of two duplicates wins, transition before node): pinned by the tests above.
- **Divergences** (range check, no throw): deliberate and documented in the doc comments and the PR; they only turn
  undefined behaviour of the original into "not found".
- **Size**: ~120 lines of code, ~200 of unit tests, ~60 of fidelity: under 400 hand-written lines.

## Criterio de hecho
- `./build.sh ci` green locally and in CI (linux + macOS); zero leaks; `fidelity` workflow green.
- Mutants documented in the PR.
- `code-reviewer` (opus, `src/core`) without blockers.
- Labels `type:feat`, `area:core`, `phase-2`; milestone «Fase 2: Núcleo de datos»; `Closes #143`.
- Worker model: sonnet (no numeric fidelity involved).
