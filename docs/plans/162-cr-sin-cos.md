# Plan: #162 feat(core): correctly rounded sin/cos (CORE-MATH port)
Spec: docs/specs/phase-2-core.md (*Trig: measure first*, red case) · measurement and decision in #161 (option A,
CORE-MATH, MIT) · sibling: #161 (`atan2` + ADR 0003 amendment, separate worker)

Context: with a correctly rounded `atan2`, 29 DB positions still differ from the oracle. These are the angles
where glibc 2.39's `sin` (19) or `cos` (10) is not correctly rounded. The oracle behaves as correctly rounded.
`core` gets `cr_sin`/`cr_cos`, ported from CORE-MATH and used on every target.

## Pasos
1. **Source.** Check out CORE-MATH (`https://gitlab.inria.fr/core-math/core-math`), files
   `src/binary64/sin/sin.c` and `src/binary64/cos/cos.c`, at a fixed commit. Write the commit hash in the header.
   Read them in full before porting. Check the shared argument reduction (including the Payne-Hanek path for
   large `|x|`), the double-double / `u128` types, `fma` and the rounding-mode branches. Only round-to-nearest is
   needed: drop the other modes and document that with a comment. If `sin` and `cos` share code or tables in
   CORE-MATH, share them in the port too, without duplicating.
2. **Odin APIs**: check in the Odin source/docs (`odin-researcher`), don't assume: `u128`, `transmute(u64)`, and
   that `intrinsics.fused_mul_add` lowers to `llvm.fma` (not `fmuladd`) on x86-64 with no `-mfma` and on arm64.
   No reassociation or contraction (ADR 0003 d4).
3. **TDD.** Write `src/core/cr_sin_cos_test.odin` first, red with stubs. Then port to `src/core/cr_sin_cos.odin`:
   `cr_sin :: proc "contextless" (x: f64) -> f64` and `cr_cos`, with no allocation or global state, `@(rodata)`
   tables, the original's operation order, and doc comments that cite the CORE-MATH line ranges.
4. **Licence.** CORE-MATH's MIT notice goes in the file header, plus an entry in `docs/ASSETS.md`. #161 adds a
   CORE-MATH entry to the same file: if it merges first, extend that entry (`git merge origin/main`) instead of
   adding a second one.
5. **No ADR changes**: #161 does the ADR 0003 amendment. Note `cr_sin`/`cr_cos` in `src/core/CLAUDE.md` only if
   that file has no entry for them yet; if #161 merges first, merge `main` and adjust.
6. **Don't touch `reorient.odin`** (#140, not in `main`).

## Ficheros a tocar
`src/core/cr_sin_cos.odin` (new) · `src/core/cr_sin_cos_test.odin` (new) · `docs/ASSETS.md` · `src/core/CLAUDE.md`
(at most one line) · `changelog.d/162-cr-sin-cos.md`. Not the ADR, `reference/`, golden images or CI.

## Tests a escribir primero
Expected values are `f64` hex literals computed outside Odin (mpmath/`Decimal` with ≥80 digits, correctly
rounded). Commit the script to `tools/` if it is short; otherwise cite the command in the test.
- Special values: `±0` (`sin(-0) = -0`, `cos(±0) = 1`), `±inf` and NaN give NaN, subnormals, and the tiny-`|x|`
  fast path.
- Argument reduction: multiples and near-multiples of `π/2`, `|x|` around `2^20`, `2^100`, `2^1023` and the
  maximum finite value.
- Hard cases: CORE-MATH's worst cases for `sin`/`cos`, if the repo has them (≥20 per function).
- The 29 angles from #161 where glibc 2.39 fails. Recover them with the script or data from #140 (worktree
  `../grapplemap-odin-wt/feat-reorientations`, read only). If you can't, use ≥20 angles from the DB and say so in
  the PR.
- ≥1,000 random values (fixed seed) in `[-4π, 4π]` and ≥200 large ones, against the external reference.
- Mutation: changing one table constant or one reduction step must turn some test red. Check this and don't
  commit it.

## Riesgos
- Size: `sin.c` + `cos.c` with their tables can go over 400 lines. Tables are data. Justify it in the PR, and
  don't split the algorithm.
- Without hardware fma, `llvm.fma` goes to the libm `fma`. That is correct in glibc and Apple, but check it is
  not `fmuladd`.
- `u128` codegen: check results, not just that it compiles.

## Criterio de hecho
`./build.sh ci` green locally and in CI (linux and macOS), new tests green, zero leaks, licence recorded,
`code-reviewer` with no blockers, and the changelog fragment. The full 0-mismatch result is checked in #140 once it
uses `cr_sin`/`cr_cos`.
