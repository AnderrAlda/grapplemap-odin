# Plan: #168 test(core): literal-bit unit case for canonical orientation
Spec: docs/specs/phase-2-core.md (deliverable 4, follow-up of the #167 review) · docs/original.md §4.3, §4.5, §5.5 ·
ADR 0003 (amendment #161)

## Pasos
1. **Reference values outside Odin.** A small generator `tools/canonical_ref.py` (Python standard library only, like
   `tools/cr_trig_ref.py`; it imports that file's correctly rounded `sin`/`cos`/`atan2` helpers if they are reusable,
   otherwise it uses `decimal` the same way and says why). It takes one fixed, asymmetric position (written in the
   script as decimals that are exact `f64` grid values `q/1000 − 2`), computes in `f64` with the **same operation
   order** as `src/core/reorient.odin` (`normal_rotation`, `rotate_v3` with its `0 *`/`+ 0` terms, `center`,
   `normal_translation`, the mirror test `head.x >= 0`), with only `sin`/`cos`/`atan2` correctly rounded, and prints
   both `orient_canonically_without_mirror(p)` and `orient_canonically_with_mirror(p)` as hex bit patterns, ready
   to paste as `0h…` literals.
   - Python `float` arithmetic is IEEE `f64` with round-to-nearest and no FMA, so the only non-trivial parts are
     the three trig functions, which come from the correctly rounded reference.
   - Choose the position so that the mirror test gives `true` (so the `with_mirror` case differs from `without`) and
     the angle is non-trivial (not a multiple of π/2).
2. **`src/core/reorient_test.odin`:** one test `test_orient_canonically_literal_bits` that builds that position and
   compares both results bit for bit with the literals (one `0h…` per coordinate: 2 × 23 × 3 per case; a compact
   table `@(rodata)` of `[PLAYER_COUNT][JOINT_COUNT][3]u64`, or generated as a fixture `tests/fixtures/canonical.txt`
   loaded with `#load` like `cr_sin_cos.txt`, whichever is shorter; the worker picks and says so in the PR). The input
   angle comes from data, never a constant, so no constant folding.
3. **`docs/original.md` §4.5:** the open point "`normalRotation` with both cores at the same `xz` and `−0` inputs"
   gets a cross-reference to `test_normal_rotation_signed_zeros` (pinned against the semantics of `atan2`, not the
   oracle: say exactly that, and keep it listed as open for the oracle). Only that line changes.
4. `changelog.d/168-canonical-literal-bits.md` (`./build.sh check` validates it); `./build.sh ci`.

## Ficheros a tocar
`tools/canonical_ref.py`, `src/core/reorient_test.odin`, optionally `tests/fixtures/canonical.txt`,
`docs/original.md` (§4.5, one line), `changelog.d/168-canonical-literal-bits.md` (+ this plan).
Not touched: `src/core/reorient.odin` or any other non-test file of `core`, `src/core/CLAUDE.md` (#169 edits it), `tests/fidelity/`, `reference/`.

## Tests a escribir primero
The test of step 2 is the deliverable. It must pass against the current `reorient.odin` (the oracle already shows it
is bit-exact), so "red first" is shown by mutants instead (none committed):
- dropping a `+ 0` in `rotate_v3`, or computing `normal_translation` before rotating, turns it red;
- replacing `cr_atan2` with `math.atan2` in a local copy turns it red if that angle differs in the last bit; if it
  does not, the PR says so (the first two mutants are enough).

## Riesgos
- **A wrong reference:** if Python's order differs from `reorient.odin` the test fails for the wrong reason. The
  script mirrors the Odin expressions one to one, with comments citing the Odin lines; a mismatch is investigated,
  never "fixed" by editing the literals by hand.
- **Size:** about 60 lines of Python, 40 of test plus the literals (a generated table does not count as hand-written).

## Criterio de hecho
- `./build.sh ci` green locally and in CI (linux + macOS).
- Mutants of "Tests a escribir primero" documented in the PR.
- `code-reviewer` (opus, `src/core`) without blockers.
- Labels `type:test`, `area:core`, `phase-2`, `tech-debt`; milestone: the issue's (`Backlog`); `Closes #168`.
- Worker model: sonnet.
