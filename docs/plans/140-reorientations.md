# Plan: #140 feat(core): reorientations, canonical orientation and trig measurement
Spec: docs/specs/phase-2-core.md (deliverable 4; "Decisions and trade-offs", *Trig: measure first*) ·
docs/original.md §4.3, §5.3, §5.5, §5.7 · ADR 0003 (decisions 4-6, "Open points")

## Pasos
1. **`src/core/types.odin`**: two types, with the original's field names and defaults (zero value = identity):
   - `Reorientation :: struct {offset: V3, angle: f64}` (`src/math.hpp:235-243`);
   - `Position_Reorientation :: struct {reorientation: Reorientation, swap_players: bool, mirror: bool}`
     (`src/positions.hpp:73-96`).
2. **`src/core/reorient.odin`** (new). Pure procedures with no allocation. The operation order is the original's
   (ADR 0003 decision 4: no FMA, no reassociation), and each procedure's doc comment cites its source line.
   - `rotate_v3(a: f64, v: V3) -> V3`: `yrot(a) * v` evaluated as the original does (`src/math.hpp:73-80,197-209`).
     Each of `c := math.cos(a)` and `s := math.sin(a)` is computed once; the original calls them twice, but the
     result is deterministic and has the same bits. Each component is written literally, with `0`/`1` as `f64`:
     - `x = ((c*v.x + 0*v.y) + s*v.z) + 0`;
     - `y = ((0*v.x + 1*v.y) + 0*v.z) + 0`;
     - `z = ((-s*v.x + 0*v.y) + c*v.z) + 0`.

     `-s` is the negated result of `sin`, as in `m[2] = -sin(a)`. The `0*` and `+ 0` terms are kept: they decide the
     sign of zero. A comment warns that they must not be "simplified".
   - `rotate(a: f64, p: Position) -> Position`: `rotate_v3` per joint (`src/positions.hpp:160-163`).
   - `apply_v3(r: Reorientation, v: V3) -> V3`: `rotate_v3(r.angle, v) + r.offset` (`src/math.hpp:252-255`).
   - `apply(r: Reorientation, p: Position) -> Position`: per joint (`src/positions.hpp:62-66`).
   - `reorient(u: Position_Reorientation, p: Position) -> Position`: `apply`, then `mirror` if `u.mirror`, then
     `swap_players` if `u.swap_players` (`src/positions.hpp:82-88`). `reorient_v3` does `apply_v3`, then `mirror_v3`
     if `u.mirror`; the swap is ignored (`:90-95`). Joint indices (`apply(u, PlayerJoint)`) are not in scope: they
     go to #142, which uses them.
   - `normal_rotation(p) -> f64`: `-math.atan2(h.x, h.y)` with `h := heading(p)` (`angle(V2) = atan2(v.x, v.y)`,
     `src/math.hpp:267`; `src/positions.hpp:137-140`).
   - `normal_translation(p) -> V3`: `{-c.x, 0, -c.z}` with `c := center(p)`, i.e. `y0(-xz(center(p)))`
     (`src/math.hpp:40,110,137`; `src/positions.hpp:169`). `y` is the literal `+0`.
   - `canonical_reorientation_without_mirror(p)`: `angle = normal_rotation(p)`,
     `offset = normal_translation(rotate(angle, p))` (centre taken **after** rotating); swap and mirror are `false`
     (`src/positions.cpp:272-281`).
   - `canonical_reorientation_with_mirror(p)`: the same `r`, plus
     `mirror = apply(r, p)[1][.Head].x >= 0` (`src/positions.cpp:261-270`).
   - `orient_canonically_without_mirror(p)` / `orient_canonically_with_mirror(p)`: `reorient(canonical_…(p), p)`
     (`src/positions.cpp:283-291`).
   - Trig: `math.sin`/`math.cos` (the `llvm.sin/cos.f64` intrinsics → platform libm) and `math.atan2` (Odin's Cephes),
     as the spec says. They are reached only through this file, so a later port changes one place.
3. **Fidelity, `tests/fidelity/ops_test.odin`**: compare `orient_canonically_with_mirror` and `…_without_mirror` of
   each record bit for bit with `expect_position` (it already exists), in the same pass and with the same rules
   (it stops at the first mismatch, `compared == lines > 0`, and the total equals 8,323 on the full dump). The header
   comment "decoded but not compared (#140)" goes away.
   - On a mismatch, the failure message gives block, pos, player, joint and axis, as now. It also prints the
     `normal_rotation` it computed, with its bits, so the trig function at fault can be told apart.
4. **Trig measurement** (the spec's "measure first"): the fidelity test from step 3 **is** the measurement.
   - Every `orient_canonically_*` goes through `atan2` (angle), `sin` and `cos` (rotation) of a non-trivial angle,
     for each of the 8,323 positions.
   - Where it runs:
     - sample: `./build.sh test` (`ci.yml`, linux + macOS);
     - full dump: the `fidelity` workflow (#158), which this PR triggers itself because it touches `src/core/**`,
       linux + macOS;
     - once by hand on the local full dump (`gh run download <run> -n oracle-full-dump`).
   - **Green on all four**: record the result in ADR 0003. "Open points" closes `sin`/`cos` bits and `atan2` bits,
     with platforms, Odin version, oracle run and number of positions. `docs/original.md` §5.7 and §4.5 point to the
     ADR. Constant folding and wasm stay open.
   - **Red on any target**: no tolerance, no workaround, and the PR stays draft.
     - The worker measures where it fails (function, angles, ULPs). It can try `core:c/libc`'s `atan2`/`sin`/`cos`
       as a **diagnostic only**, not committed.
     - It opens the issue "port glibc 2.27 `sin`/`cos`/`atan2`", with labels, phase-2 milestone and the data.
     - It escalates: the spec puts that port, with an ADR 0003 amendment, before #142, and the decision is Ander's.
5. Docs: `src/core/CLAUDE.md` ("Ficheros": `reorient.odin`; the rule "the `0*`/`+0` terms of `rotate_v3` are not
   simplified") and `changelog.d/140-reorientations.md`.
6. `./build.sh ci`; the full dump by hand, and the `fidelity` workflow green on the PR, both with the result in the PR.

## Ficheros a tocar
`src/core/types.odin` (the two types), `src/core/reorient.odin`, `src/core/reorient_test.odin`,
`tests/fidelity/ops_test.odin`, `docs/adr/0003-numeric-precision.md` ("Open points" → result),
`docs/original.md` (§4.5 and §5.7: one line each pointing to the ADR), `src/core/CLAUDE.md`,
`changelog.d/140-reorientations.md` (+ this plan).
Not touched: `transform.odin` (only called), `tests/fidelity/{oracle,ndjson}.odin`, `build.sh`, `.github/`, `reference/`.

## Tests a escribir primero
`src/core/reorient_test.odin` (TDD: red first, with stubs that return `{}`). Expected values are `f64` literals
computed outside Odin (`src/core/CLAUDE.md`), and angles come in as runtime variables, not constants, so LLVM's
constant folding (ADR 0003 open point) doesn't get in.
- **`rotate_v3` term order:**
  - with `a = 0` and `v = (-0, -0, -0)` it gives `(+0, +0, +0)`, the original's `+ 0`;
  - `rotate_v3(-0.0, v)` keeps the `-sin(-0) = +0` term (sign of zero pinned);
  - with `a = π/2`, using the literal `math.PI/2` at runtime, its known result is bit-exact for `v = (1, 2, 3)`.
- **Identity:** `apply({}, p)` equals `p` except that `-0` becomes `+0` (§5.3).
- **`reorient` order** (rotate → translate → mirror → swap):
  - with `mirror` and `offset.x ≠ 0`, the mirror happens **after** translating (it is not equal to translate-then-
    unmirror);
  - with `swap_players`, the players are swapped at the end;
  - `reorient_v3` ignores the swap.
- **`normal_rotation`:**
  - with cores at the same bit-identical `xz`: `heading = (+0, +0)` → `-atan2(+0, +0) = -0`;
  - with `heading = (-0, -0)`: `-atan2(-0, -0) = π` (§5.5);
  - player 1 on `+x`: `-π/2`.
- **Canonical:**
  - `heading(orient_canonically_without_mirror(p))` has `|x| ≤ 1e-15` and `z > 0`;
  - `xz(center)` is about 0 (`|·| ≤ 1e-15`, a property of the result, not a fidelity tolerance);
  - `y` of the centre is unchanged;
  - it never swaps players.
- **Mirror test:**
  - player 1's head at `x > 0` after reorienting → `mirror = true` and `x < 0` in the result;
  - `x < 0` → `false`;
  - `x == 0` exactly, built with cores on the `z` axis and the head at `x = 0` → `true` (`≥ 0`).

Then step 3 in `ops_test.odin`. Check that it can fail: these changes turn it red, and none of them is committed:
- dropping the `+ 0` from `rotate_v3`, or swapping the order of a sum (if neither changes any sample bit, the PR
  says so and shows a mutant that does fail, e.g. `math.atan2(h.y, h.x)`);
- changing a bit of `orient_canonically_*` in a copy of the sample (`GM_ORACLE_DIR=<copy>`).

## Riesgos
- **Trig in the last bit** (the main risk). glibc 2.27 has correctly rounded `sin`/`cos`/`atan2` (IBM libm, with its
  slow paths). Odin's `atan2` is Cephes, and macOS's libm is not glibc. A mismatch is plausible, above all in `atan2`.
  It is handled as step 4 says: measure, open an issue, escalate. Never a tolerance (ADR 0003 decisions 5-6).
- **The discrete mirror flag:** a head at `x ≈ 0` with a different last bit changes the decision. ADR 0003 d6 says
  this is a bug or a question for Ander, never a tolerance.
- **Constant folding:** if an angle were a compile-time constant, LLVM could fold `sin`/`cos` with its own
  implementation. In `core` the angles always come from data. In the tests, they come from variables.
- **`-0` in the dump:** `keep_negative_zero` already covers it (#139). `orient_canonically_with_mirror` produces `-0`
  legitimately.
- **Size:** about 120 lines of `reorient.odin`, about 200 of tests and about 30 in `ops_test.odin`, so about 350.
  If it goes over 400, `reorient`/`reorient_v3` and their tests go to a stacked PR, keeping rotate/apply/canonical in
  the first.

## Criterio de hecho
- `./build.sh ci` green locally and in CI (linux + macOS).
- `fidelity` workflow green on the PR (full dump, linux + macOS), with its duration and the oracle run in the PR.
- The full dump by hand is green.
- Or, if any target is red: issue opened, escalation done, and the PR in draft with the data.
- ADR 0003 updated with the measured result.
- No vacuous test: the mutants are documented in the PR.
- `code-reviewer` (opus, `src/core`) without blockers.
- Labels `type:feat`, `area:core`, `phase-2`; milestone «Fase 2: Núcleo de datos»; `Closes #140`.
- Worker model: opus (fidelity in `core`).
