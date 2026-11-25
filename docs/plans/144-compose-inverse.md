# Plan: #144 feat(core): compose/inverse
Spec: docs/specs/phase-2-core.md (deliverable 8, first part; `follow`/`frames` and `smoothen` split to #181, as the
spec allows) · docs/original.md §5.3, §5.4 · `src/math.hpp:257-265`, `src/positions.cpp:97-128` (in
`reference/GrappleMap`) · oracle `compose.ndjson` (dumper v4, #141)

## Pasos
1. **`src/core/reorient.odin`**, next to `apply`/`reorient`, four pure procs (values in, values out, no allocation),
   bit-exact with the original (ADR 0003 d4: same operation order, no FMA, no reassociation):
   - `reorientation_inverse(x: Reorientation) -> Reorientation` = `{rotate_v3(-x.angle, -x.offset), -x.angle}`
     (`src/math.hpp:257-260`). `-x.offset` is the per-component negation of the `V3` (Odin's unary minus on `[3]f64`,
     same as the original's `operator-`), done **before** rotating.
   - `reorientation_compose(a, b: Reorientation) -> Reorientation` = `{b.offset + rotate_v3(b.angle, a.offset),
     a.angle + b.angle}` (`src/math.hpp:262-265`): "first `a`, then `b`". Angle **not** wrapped.
   - `inverse(u: Position_Reorientation) -> Position_Reorientation` (`src/positions.cpp:97-109`):
     `r := {reorientation_inverse(u.reorientation), u.swap_players, u.mirror}`; if `u.mirror`, negate `r.angle` and
     `r.offset.x` (on the inverse, after computing it).
   - `compose(a, b: Position_Reorientation) -> Position_Reorientation` (`src/positions.cpp:111-128`): `br :=
     b.reorientation`; if **`a.mirror`** (not `b.mirror`), negate `br.angle` and `br.offset.x`; result
     `{reorientation_compose(a.reorientation, br), a.swap_players != b.swap_players, a.mirror != b.mirror}`.
   Naming: `inverse`/`compose` take the type the rest of `core` uses (`Position_Reorientation`), the `reorientation_*`
   forms are the building blocks (as `apply_v3`/`apply`); no proc group (keeps call sites explicit). Doc comments say
   "first `a`, then `b`", that the angle is not wrapped, and that `inverse(inverse(u))` is equal only up to rounding.
2. **Fidelity** `tests/fidelity/compose_test.odin` (new): stream `compose.ndjson` (`ndjson_each`), and for each line
   take `edge = shared_graph.edges[seq]` (assert `edge.sequence.line_nr`/block bookkeeping as the other tests do, e.g.
   check `block` against the edge as `graph_test.odin` maps it), `Ef = edge.from.reorientation`,
   `Et = edge.to.reorientation`, and compare **bit for bit** (`expect_bits`, `-0 ≠ +0`): `inverse_from` =
   `inverse(Ef)`, `inverse_to` = `inverse(Et)`, `compose_from_to` = `compose(Ef, Et)`, `compose_inverse_from_to` =
   `compose(inverse(Ef), Et)`; each field `translation[3]`, `angle`, `swap`, `mirror`. Count the lines compared and
   assert it equals the sample's/dump's transition count from `meta.json` (or the number of `compose.ndjson` lines,
   whichever the other tests use), so an empty file cannot pass. Uses the shared graph: no extra `load_graph`.
3. Docs: `src/core/CLAUDE.md`, bullet `reorient.odin` (add the four procs and "first `a`, then `b`; `a.mirror`
   conjugates `b`; angle not wrapped"). `changelog.d/144-compose-inverse.md`. Comment on #144 that `follow`/`frames`/
   `smoothen` moved to #181 (and retitle #144 to `feat(core): compose/inverse` with `gh issue edit`).
4. `./build.sh ci`; `fidelity` workflow green on the PR (full dump on linux and macOS: every transition of the DB).

## Ficheros a tocar
`src/core/reorient.odin`, `src/core/reorient_test.odin`, `tests/fidelity/compose_test.odin` (new),
`src/core/CLAUDE.md` (bullet `reorient.odin` only), `changelog.d/144-compose-inverse.md` (+ this plan).
Not touched: `graph.odin`, `match.odin`, `transform.odin`, `types.odin`, `tests/fixtures/oracle/`, `build.sh`,
`.github/`, `reference/`.

## Tests a escribir primero
`src/core/reorient_test.odin` (red first: the procs do not exist). Expected `f64`s as literals computed outside Odin
(Python doubles reproducing the formula, `src/core/CLAUDE.md`: Odin folds constant expressions with extra precision),
the generator snippet quoted in a comment:
- `reorientation_inverse` of `{(1, 2, 3), 0.5}`: literal bits; of the identity → `{(-0?, …), -0}`: pin the signs of
  zero the formula gives (`rotate_v3(-0, -(0,0,0))` with its `+ 0` terms), not "zero".
- `reorientation_compose`: literal bits for one non-trivial pair; angle sum not wrapped (`3 + 3` → `6`, not
  `6 − 2π`); order matters (`compose(a, b) ≠ compose(b, a)` for a chosen pair).
- `inverse` with `mirror = true`: angle sign and `offset.x` flipped **after** inverting (pin the bits; a mutant that
  flips before inverting must fail); flags kept.
- `compose`: `a.mirror` conjugates `b.reorientation` (a case with `a.mirror = true, b.mirror = false` and one with
  `false, true`, so using `b.mirror` fails); `swap`/`mirror` combine by XOR (all four combinations).
- Semantic (no bits): `reorient(compose(a, b), p)` is `basically_same` as `reorient(b, reorient(a, p))`, and
  `reorient(inverse(u), reorient(u, p))` as `p`, for a few `u` with every flag combination (property-style over a
  fixed list, deterministic).
Fidelity: `tests/fidelity/compose_test.odin` as in step 2 (red until the procs exist).
Mutants to try, none committed (the PR lists them): `a.angle + b.angle` → `b.angle + a.angle` (must still pass: IEEE
addition commutes; say so); conjugate with `b.mirror`; negate before inverting; `rotate_v3(-angle, offset)` then
negate the result (`-R(v)` vs `R(-v)`: equal bits? check and report; if equal, say so in the PR rather than invent a
test). Each mutant that changes bits must turn a test red.

## Riesgos
- **Sign of zero**: `-x.offset` before the rotation and the `+ 0` terms of `rotate_v3` decide `-0`/`+0`; pinned by the
  identity case and by the oracle (`inverse_from` of the sample is `{(0,0,0), -0}`).
- **Fidelity on macOS**: same `cr_sin`/`cr_cos` as the rest of `core`, so no new libm exposure; the full dump on both
  targets confirms it.
- **Size**: ~45 lines of code, ~150 of unit tests, ~90 of fidelity: under 400.

## Criterio de hecho
- `./build.sh ci` green locally and in CI (linux + macOS); zero leaks; `fidelity` workflow green on the PR.
- Mutants documented in the PR.
- `code-reviewer` (opus, `src/core`) without blockers.
- Labels `type:feat`, `area:core`, `phase-2`; milestone «Fase 2: Núcleo de datos»; `Closes #144`.
- Worker model: opus (bit fidelity in `core`).
