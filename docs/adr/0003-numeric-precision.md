# 0003. Numeric precision
Status: Proposed
Date: 2026-11-21

## Context
Paths `src/…` are in `reference/GrappleMap`; paths `core/…` and `base/…` are in the pinned Odin distribution.

The original computes everything in `double`: `V3 = BasicV3<double>` (`reference/GrappleMap/src/math.hpp:34`),
`V4` (`src/math.hpp:59`), matrices `M = std::array<double, 16>` (`src/math.hpp:71`); `docs/original.md` §2.3
*Precision*, §4.1, §5. Inputs are quantized: each coordinate is an integer `0…3843` divided by `1000` as a
`double` division, with an offset of −2 on `x` and `z` (`src/persistence.cpp:45-46,53`; `docs/original.md` §1.3).
Node matching compares squared distances against thresholds (`0.0016` m² in `basicallySame`, `0.05` in the
head-to-head pre-filter; `docs/original.md` §2.3): a result one ulp away can flip a match near a threshold, so the
graph itself depends on reproducing the arithmetic.

The oracle (ADR 0002) records the original's results as `%.17g` doubles, built with GCC 7.5 `-O3` for generic
x86-64 (no FMA in the ISA) and `-ffp-contract=off` for the dumper's own code; trigonometry comes from glibc 2.27's
libm (`tools/oracle/README.md`; `docs/original.md` §5.7). raylib works in `f32`.

What Odin does was checked, not assumed, with the pinned toolchain (`.odin-version` = `dev-2026-11a`,
`odin version` = `dev-2026-11-nightly:9a69916`), on `a*b + c` and `ca*x + sa*z` in `f64`:
- The LLVM IR (`-build-mode:llvm-ir`, `-o:speed`, targets `linux_amd64` and `darwin_arm64`) has plain `fmul` /
  `fadd`, with no `contract` (or any other fast-math) flag and no `llvm.fmuladd`.
- The assembly has separate multiply and add (`mulsd`+`addsd`; `fmul`+`fadd` on arm64) for `linux_amd64 -o:speed`,
  `linux_amd64 -o:aggressive -microarch:native` on a CPU with FMA, `linux_amd64 -debug -microarch:native` (i.e.
  `-o:none`), and `darwin_arm64 -o:speed`. So Odin does
  **not** contract to FMA implicitly at the levels we build with (`-debug`/`-o:none` for tests, `-o:speed` for
  release, `build.sh`). Fusion only happens on request: `math.fmuladd_f64` (`core/math/math_basic.odin:92`, the
  `llvm.fmuladd` intrinsic) and `intrinsics.fused_mul_add` (`base/intrinsics/intrinsics.odin:70`).
- `math.sin_f64`/`cos_f64` are the `llvm.sin`/`llvm.cos` intrinsics (`core/math/math_basic.odin:12,53`), which
  compile to a call to the platform libm (`jmp sin` on linux, `b _sin` on darwin); `math.sqrt_f64` is
  `intrinsics.sqrt` (`core/math/math_basic.odin:119`), correctly rounded by IEEE 754. `math.atan2_f64` is a pure
  Odin port of Cephes (`core/math/math.odin:1693`), **not** libm. On `js` targets `sin`/`cos` come from the host
  (`core/math/math_basic_js.odin:9-12`).

## Decision
1. **`f64` in `core`** for positions, vectors, matrices, reorientations, interpolation and playback: the same type
   as the original. Decoding is `f64(62*d0 + d1) / 1000` (then `− 2` on `x`/`z`), the same operations in the same
   order as `src/persistence.cpp:45-53`, which gives the same bits.
2. **Same operation order.** Formulas in `core` follow the original term by term (`docs/original.md` §5.6): no
   algebraic rewrites, no reassociation, no hand-written FMA (`fmuladd`, `fused_mul_add`) in any code that must
   match the oracle, and no `-ffast-math`-like option. `core` is tested at `-o:none` and shipped at `-o:speed`;
   both are free of implicit contraction today (Context). If a future Odin version changes that, the fidelity
   tests catch it and this ADR is revised.
3. **`f32` only at the render boundary.** `render` converts to `f32` when uploading to raylib. `core` never stores
   or computes in `f32`, and no `f32` value flows back into `core`.
4. **What is compared bit for bit** (equality of `f64`): every result built only from `+ − × ÷`, `min`/`max` and
   `sqrt`: decoding (`sequences.ndjson`); the fields `mirror`, `swap_players`, `heading` and `center` of
   `ops.ndjson` (`src/positions.cpp:130-136`, `src/positions.hpp:68,132-135,142-145`); `between`
   (`between.ndjson`, `src/positions.hpp:42`) and `spring` (`spring.ndjson`, `src/positions.cpp:142-194`). "Same
   formula" is literal: `center` uses `between(V3, V3) = (a + b) / 2` (`src/math.hpp:193`), not
   `between(a, b, 0.5) = a + (b − a)·0.5` (`src/positions.hpp:42`); the two do not give the same bits.
5. **What may need a tolerance**: results that go through `sin`, `cos` or `atan2`: the reorientation found by
   matching (`angleOff` from `angle` = `atan2`, then `yrot`; `src/positions.cpp:198-210`), so the edges'
   `reorientation_from`/`_to` in `graph.ndjson`; `apply(Reorientation)`; `normalRotation`
   (`src/positions.hpp:137-140`) and both canonical orientations (`src/positions.cpp:261-291`); and playback
   frames, a single transition included, whenever the reorientation of its `from` node has a non-zero angle
   (`follow()` applies `compose(inverse(from.reorientation), …)` to every frame, `src/graph_util.cpp:60-77`).
   They are compared bit for bit first; a tolerance is used only where that fails, and only with the explicit
   value, the affected fields and the evidence written in the PR, **approved by Ander** (`CLAUDE.md`,
   "Prohibiciones": no raising tolerances or thresholds without asking).
6. **Discrete decisions are exact, never toleranced**: which node every endpoint matches, and with which `swap`/
   `mirror` flags, must equal `graph.ndjson`; the `mirror` flag of `canonical_reorientation_with_mirror`
   (`apply(reo, p)[player1][Head].x >= 0`, `src/positions.cpp:266`) must equal the oracle's. A different result is
   a bug, or (if caused by a last-bit trig difference near a threshold) an open question for Ander, not a
   tolerance.
7. **Constants are copied, not improved**: e.g. `pi()` is `3.141593` (`src/math.hpp:12`, `docs/original.md` §4.1),
   used wherever the original uses `pi()`.

## Alternatives
- **`f32` throughout** (raylib's type). Simpler upload, but it cannot reproduce the original's doubles, and
  matching near the `0.0016` m² threshold would differ from the original.
- **Fixed point on the quantization grid** (integers in thousandths). Exact for decoding, but every transform and
  interpolation leaves the grid; it would be a different arithmetic from the original's.
- **Compare everything with a tolerance.** Easy to pass, but it hides operation-order bugs, and a tolerance on
  matching changes the graph.

## Consequences
- `core` works in `f64` and its tests assert exact equality unless an approved tolerance applies.
- Phase 2 must check, with the oracle, whether `sin`/`cos`/`atan2` give the original's bits (open points below)
  before the fidelity tests for rotations are written.
- The render boundary does one `f64 → f32` conversion per joint per frame.

### Open points (not verifiable now)
- **`sin`/`cos` bits.** The original uses glibc 2.27; the port calls the libm of the machine it runs on (a newer
  glibc on Linux, Apple's libm on macOS, the browser on wasm). None of them is required to be correctly rounded, so
  equality over every angle in the DB is **unverified** (phase 2, with the full dump). Options if it fails: port
  glibc 2.27's `sin`/`cos`/`atan2` (or a correctly rounded library), verified against the full dump, for every
  target; or a tolerance (Ander decides).
- **`atan2` bits.** Odin's `atan2` is Cephes, not glibc's: likely to differ in the last bit for some inputs
  (**unverified**). The same options apply; it feeds node matching (`angleOff`), `normalRotation` and canonical
  orientation.
- **Constant folding.** LLVM may evaluate `llvm.sin`/`llvm.cos` with constant arguments at compile time with its own
  implementation; whether that can differ from the runtime call is **unverified**. It matters only for
  compile-time constant angles.
- **wasm** (phase 7): `sin`/`cos` from the JS host; to be checked against the same fixtures when the target exists.
