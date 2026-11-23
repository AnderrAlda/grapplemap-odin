# Plan: #161 feat(core): correctly rounded atan2 (CORE-MATH port) + ADR 0003 amendment
Spec: docs/specs/phase-2-core.md ("Decisions and trade-offs", *Trig: measure first*, red case) · ADR 0003 ("Open
points") · measurement in #161 (found in #140) · sibling issue: `sin`/`cos` (#162, separate worker)

Decision (Ander delegated it to MAIN, 2026-11-22): option A of #161. `core` gets its own **correctly rounded**
binary64 `atan2`, `sin`, `cos`, ported from CORE-MATH (MIT), used on every target instead of the host libm or
Odin's `math`. The data shows the oracle behaves as correctly rounded on all 8,323 DB angles. This issue covers
`atan2` and the ADR amendment. `sin`/`cos` go to the sibling issue (different files, so they run in parallel).
macOS no longer needs measuring separately: the implementation does not depend on the platform.

## Pasos
1. **Source.** Check out CORE-MATH (`https://gitlab.inria.fr/core-math/core-math`), file
   `src/binary64/atan2/atan2.c`, at a fixed commit. Write the commit hash in the file header. Read it in full
   before porting. Do not assume how it works: check its types (`__int128`/`u128`, double-double), its use of
   `fma` and its `fegetround`/rounding-mode branches. Only round-to-nearest is needed: drop the other modes and
   document that with a comment.
2. **Odin APIs**: check in the Odin source/docs (use `odin-researcher`), don't assume:
   - `u128`/`i128` arithmetic and shifts;
   - `intrinsics.fused_mul_add` for `f64`, and that it lowers to a true fma (`llvm.fma`, not `fmuladd`) on
     x86-64 with no `-mfma` and on arm64;
   - `transmute(u64)` for bit access;
   - that no optimisation level reassociates or contracts (ADR 0003 d4).
3. **TDD.** Write `src/core/cr_atan2_test.odin` first, red with a stub. Then port it to
   `src/core/cr_atan2.odin`: `cr_atan2 :: proc "contextless" (y, x: f64) -> f64`, with no allocation and no
   global state. Constant tables are `@(rodata)` (see `src/core/CLAUDE.md`). Keep the original's operation
   order, and cite the CORE-MATH line ranges in doc comments.
4. **Licence.** Put CORE-MATH's MIT notice in the header of `cr_atan2.odin`, and add an entry to
   `docs/ASSETS.md` (or the third-party section that file uses) with the source, commit and licence.
5. **ADR 0003 amendment.** Add a dated "Amendment (#161)" section. It records that `core` uses its own correctly
   rounded `atan2`/`sin`/`cos` (CORE-MATH, MIT), never `math.atan2`/`math.sin`/`math.cos` or the libm, on every
   target. Give the reasons: the measurement data, being platform independent, the licence, and wasm later. List
   the rejected options (glibc 2.27 IBM libm: LGPL and large; a tolerance: against d5-6). Update "Open points":
   the trig item is resolved, and the constant-folding point no longer applies to these functions, because they
   are ordinary procs and not LLVM intrinsics. Note this in `src/core/CLAUDE.md` too. If `./build.sh check` or
   `vet` allows it, add a check that `math.atan2`/`math.sin`/`math.cos` are not used in `src/core`. If that
   would need a new tool, skip it and only note it.
6. **Don't touch `reorient.odin`**: it is not in `main` (#140). #140 switches to `cr_*` after this merges.

## Ficheros a tocar
`src/core/cr_atan2.odin` (new) · `src/core/cr_atan2_test.odin` (new) · `docs/adr/0003-numeric-precision.md` ·
`src/core/CLAUDE.md` · `docs/ASSETS.md` · `changelog.d/161-cr-atan2.md`. Not `reference/`, golden images or CI.

## Tests a escribir primero
Expected values are `f64` hex literals computed outside Odin (mpmath/`Decimal` with ≥80 digits, then correctly
rounded to binary64). Commit the script to `tools/` if it is short; otherwise cite the exact command in the test.
- Special values: `±0` against `±0`/`±x` in all four sign combinations, `±inf` combinations, NaN propagation,
  `x = 0` with `y ≠ 0`, subnormals, `|y/x|` overflow and underflow.
- Quadrant and sign of zero, as in C99 Annex F.
- Hard cases: CORE-MATH's worst cases for `atan2`, if the repo has them (≥20).
- The angles from #161: block 654 pos 1 (oracle `0x…8de0`) and block 608 pos 2.
- ≥1,000 random pairs (fixed seed) against the external reference.
- Mutation: changing one table constant, or swapping a `fused_mul_add` for `a*b+c`, must turn some test red.
  Check this and say so in the PR; don't commit it.

## Riesgos
- Without hardware fma, `llvm.fma` calls libm `fma`. That is correctly rounded in glibc and Apple, but check it
  is not `fmuladd`.
- The 400-line limit on PR size: ported tables are data. If the PR is still over the limit, justify it in the PR
  body; don't split the algorithm.
- Odin `u128` codegen: check the results, not just that it compiles.

## Criterio de hecho
`./build.sh ci` green locally and in CI (linux and macOS), new tests green, zero leaks, ADR 0003 amended, licence
recorded, `code-reviewer` with no blockers, and the changelog fragment. A complete 0-mismatch run over the full dump
comes in #140, once it uses `cr_atan2` and the `sin`/`cos` port.
