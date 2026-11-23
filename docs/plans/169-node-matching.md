# Plan: #169 feat(core): node matching (basically_same, is_reoriented)
Spec: docs/specs/phase-2-core.md (deliverable 6, first half; split from #142 so that both PRs stay under 400 lines) ·
docs/original.md §2.3 · ADR 0003 (decisions 2, 4, 6; amendment #161)

## Pasos
1. **`src/core/match.odin`** (new). Pure procedures, nothing allocated, operation order of the original (ADR 0003 d2),
   each with a doc comment citing its source line. Trig only through `cr_atan2` (and `cr_sin`/`cr_cos` via
   `rotate_v3`/`apply`).
   - `distance_squared(from, to: V3) -> f64`: `inner_prod(to − from, to − from)` (`src/math.hpp:190`); the worker
     reads `inner_prod(BasicV3)` (`src/math.hpp:68`) and copies its summation order literally.
   - `basically_same(a, b: Position) -> bool` (`src/positions.hpp:49-54`): player 0's 23 joints, then player 1's, in
     `Joint` order; returns false at the first joint with `distance_squared(a[j], b[j]) > BASICALLY_SAME_SQ` (strict
     `>`, so exactly at the threshold passes).
   - `head2head(p) -> f64`: `distance_squared(p[0][.Head], p[1][.Head])` (`src/positions.cpp:235-236`).
   - `angle_v2(v: V2) -> f64`: `cr_atan2(v.x, v.y)` (`src/math.hpp:267`). If `normal_rotation` in `reorient.odin`
     can use it unchanged (same bits by construction), leave `reorient.odin` alone anyway: no refactor in this PR.
   - `@(private = "file") is_reoriented_without_mirror_and_swap(a, b) -> (Reorientation, bool)`
     (`src/positions.cpp:198-211`): `angle_off = angle_v2(xz(b1h − b0h)) − angle_v2(xz(a1h − a0h))`, **not wrapped**;
     `r = {offset = b0h − rotate_v3(angle_off, a0h), angle = angle_off}` (`xyz(yrot · V4(a0h, 1))` is exactly
     `rotate_v3`, whose `+ 0` terms are the `m[12..14] · 1` column); accept iff `basically_same(apply(r, a), b)`.
   - `@(private = "file") is_reoriented_without_swap(a, b) -> (Position_Reorientation, bool)`
     (`src/positions.cpp:213-230`): first `(a, b)` → `mirror = false`; else `(a, mirror(b))` → `mirror = true`.
   - `is_reoriented(a, b: Position) -> (u: Position_Reorientation, ok: bool)` (`src/positions.cpp:233-259`): `a` is
     the node's position, `b` the endpoint (argument order of the original). Pre-filter
     `abs(head2head(a) − head2head(b)) > HEAD_PREFILTER_SQ` → no match; then without swap; else with
     `b' = swap_players(b)` (a local copy, the mirror of the second pass is of `b'`) and `swap_players = true`. The
     first of the four attempts that passes wins; the rest are never evaluated. The debug asserts of the original
     are compiled out (`-DNDEBUG`): not ported.
2. **Fidelity, `tests/fidelity/match_test.odin`** (new): over `graph.ndjson` (sample: 87 nodes, 49 transitions; the
   full dump with `GM_ORACLE_DIR`).
   - Node lines: decode `position_q` with the parser's formula (`f64(q) / QUANT_SCALE`, `− ENCODING_OFFSET_XZ` on
     `x`/`z`; the same expression `parse.odin` uses, so the same bits) into a map `index → Position`. For a named node
     (`block != null`), its position equals `seqs[block].positions[0]` bit for bit (`expect_position`).
   - Transition lines: `seq := seqs[block]`; `is_reoriented(nodes[from], seq.positions[0])` must match and equal
     `reorientation_from` (`translation` ↔ `offset`, `angle`, `swap`, `mirror`) bit for bit; the same for `to` with
     the last position. Every endpoint node is in the sample (checked: 0 missing); a missing one fails the test.
   - Anonymous nodes: the endpoint that created one has the identity in the dump; `is_reoriented(p, p)` gives
     `angle = +0` and `offset = +0` exactly (`rotate_v3(0, v)` returns `v` up to `-0 → +0`, `x − x = +0`), so the same
     comparison holds. If it ever did not, the test reports the case; never special-cased silently.
   - Transition lines contain no strings: they go through `keep_negative_zero` (`ops_test.odin`) before decoding, so a
     `-0` in a translation keeps its sign. Node lines are not rewritten (they contain strings and only integer
     coordinates). The `index` line is ignored here (#142 uses it).
   - Counters: compared transitions == transition lines > 0 (as `ops_test.odin` does; on the full dump that is
     1,485, recorded in the PR from the manual run, not hard-coded). The first mismatch stops, with block, end
     (`from`/`to`) and field.
   - What this does **not** check (goes to #142): that the matched node is the lowest-index one, anonymous numbering,
     `in`/`out`.
3. Docs: `src/core/CLAUDE.md` ("Ficheros": `match.odin`) and `changelog.d/169-node-matching.md`.
4. `./build.sh ci`; the full dump by hand (`gh run download <run> -n oracle-full-dump` + `GM_ORACLE_DIR`) and the
   `fidelity` workflow green on the PR, both with their result in the PR.

## Ficheros a tocar
`src/core/match.odin`, `src/core/match_test.odin`, `tests/fidelity/match_test.odin`, `src/core/CLAUDE.md`,
`changelog.d/169-node-matching.md` (+ this plan).
Not touched: `reorient.odin`, `reorient_test.odin`, `transform.odin`, `types.odin` (the constants already exist),
`errors.odin`, `docs/original.md`, `build.sh`, `.github/`, `reference/`, `tests/fixtures/`.

## Tests a escribir primero
`src/core/match_test.odin` (TDD: red first, with stubs returning `false`/`{}`). Floats as `f64` literals computed
outside Odin, angles as runtime variables (`src/core/CLAUDE.md`).
- **`basically_same`:**
  - equal positions → true; one joint of player 1 moved by more than 4 cm → false; the same joint moved by less → true;
  - **the boundary:** a displacement whose `distance_squared` is exactly the `f64` of `0.0016` passes (strict `>`).
    The worker finds such a displacement outside Odin (Python `float`, the same summation order) and writes it as a
    literal; if none with a single non-zero axis exists, use two axes and say so in the test comment;
  - one bit above the threshold → false.
- **Pre-filter:** two positions that are reorientations of each other except for the head-to-head distance
  (`|Δhead2head| > 0.05`) → no match, even if `basically_same` would otherwise pass for the other joints.
- **`is_reoriented`:**
  - `is_reoriented(p, p)` → `ok`, all-zero bits (`+0` offset and angle), no swap, no mirror;
  - `b = apply(r, a)` with a known `r` (angle, offset) → `ok`, no swap, no mirror, and `apply(u.reorientation, a)`
    is `basically_same` as `b`;
  - `b = mirror(apply(r, a))` for an asymmetric `a` → `mirror = true`, `swap_players = false`;
  - `b = swap_players(apply(r, a))` → `swap_players = true`, `mirror = false`;
  - `b = swap_players(mirror(apply(r, a)))` → both true (the mirror of the **swapped** copy);
  - **attempt order:** a left/right-symmetric `a` that matches both with and without mirror → `mirror = false`; a
    position that matches both with and without swap → `swap_players = false`;
  - **angle not wrapped:** heads such that the difference of the two `atan2` is below `−π` → `u.reorientation.angle`
    is that raw value (literal bits), not `+ 2π`;
  - no match: an unrelated position → `ok = false`.

Then step 2. Check that it can fail (none of these committed): swapping the argument order of `is_reoriented` in the
fidelity test, trying mirror before no-mirror, or wrapping the angle into `(−π, π]` turns it red (if one does not
change any sample bit, the PR says so and shows a mutant that does).

## Riesgos
- **Discrete decisions near the threshold:** a different last bit in `distance_squared` could flip a match. ADR 0003
  d6: that is a bug or a question for Ander, never a tolerance. The fidelity test reports block, end and joint.
- **`-0` in the translations:** handled by `keep_negative_zero` on transition lines only (step 2).
- **Size:** about 90 lines of `match.odin`, 180 of unit tests and 110 of fidelity, about 380. If it goes over 400,
  the unit tests of the attempt order stay and the "not wrapped" case moves to #142's PR, said in the PR.

## Criterio de hecho
- `./build.sh ci` green locally and in CI (linux + macOS); zero leaks.
- `fidelity` workflow green on the PR and the full dump by hand green (1,485 transitions, 2,970 ends), with the oracle
  run in the PR.
- No vacuous test: the mutants are documented in the PR.
- `code-reviewer` (opus, `src/core`) without blockers.
- Labels `type:feat`, `area:core`, `phase-2`; milestone «Fase 2: Núcleo de datos»; `Closes #169`, `Refs #142`.
- Worker model: opus (fidelity in `core`).
