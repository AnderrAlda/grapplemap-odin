# Plan: #195 docs(adr): 0007 timed playback, chaser and interactive camera
Spec: docs/specs/phase-3-viewer.md (deliverable 1) · docs/original.md §6.4, §6.5, §6.8, §7.5 · ADR 0003, 0004 ·
`src/playback.{hpp,cpp}`, `src/camera.hpp:38-50` (in `reference/GrappleMap`)

## Pasos
1. **`docs/adr/0007-timed-playback.md`** (new, from `docs/adr/TEMPLATE.md`, in English like 0004-0006; status
   "Accepted" since the decisions were approved in the spec, PR #194; date of the PR). Sections:
   - **Context**: the original's time-based `Playback` (§6.4: 5 / 10 segments/s, 0.8 s pauses, leftover carried at
     the new step's speed, leftover discarded at the end, endless hold-reset-hold loop, interpolate then reorient) and
     its chaser `between(chaser, target, 0.2)` per frame, target sampled before `progress` (§6.5); `setOffset`'s
     `0.97·offset + 0.03·o` per frame (`src/camera.hpp:38-50`); both frame-rate dependent (§6.8 first bullet, the
     source's own `todo`). The frame-based `frames()`/`smoothen` of phase 2 are oracle-checked but sample at a fixed
     frame count. raylib's `Camera3D` (ADR 0004 d3 left the interactive camera to phase 3).
   - **Decision** (numbered):
     1. Interactive playback = a port of `Playback` into `core` (`Timed_Playback`, `src/core/timed.odin`),
        semantics of §6.4 exactly: direction by `Step.reverse`, reorientation per step by `connect` (=
        `gp_connect`, `src/graph_util.cpp:232-245`), `seconds ≥ 0` keeps `how_far ∈ [0, 1]`. Not bit-checked
        (no dump: §6.7 "match semantically"); unit-tested.
     2. **Loop toggle**: `loop = true` is the original; `loop = false` stops at the end (holds the last keyframe,
        `at_end` stays set, no `reset`) until restarted. No ping-pong.
     3. **Speed** ∈ {0.25, 0.5, 1, 1.5, 2}: the viewer multiplies every `seconds` given to `progress` by it, pauses
        included (at 0.25× a 0.8 s pause lasts 3.2 s).
     4. **Scrub**: `duration` (Σ segments / speed per step, `f64`, pauses excluded; not the original's truncating
        integer `duration`, §6.6) and `seek(t)` place `segment`/`how_far` directly; while paused or scrubbing the
        chaser is bypassed (the exact target is shown).
     5. **Chaser, time-based**: `s = 1 − (1 − 0.2)^(60·dt)` per frame (`CHASER_FACTOR = 0.2`,
        `CHASER_REFERENCE_HZ = 60`): at 60 Hz the same filter as the original up to the rounding of `s`
        (`1 − 0.8` is `0.19999999999999996`, not `0.2`); at other rates the same decay per second. Target sampled
        before `progress`, as the original. `dt` clamped to `CHASER_MAX_DT` (named, e.g. 0.1 s) for the chaser only,
        so a stalled frame does not snap. `pow` is the platform libm (`math.pow_f64` → `llvm.pow`): its bits may
        differ between targets, accepted because nothing compares the chaser with the oracle (ADR 0003 d3's bit
        rules apply to oracle-checked values; this is not one). Tests use inputs where `pow` is exact.
     6. **Camera target smoothing, time-based**: `offset = between(offset, target, 1 − 0.97^(60·dt))`, the same
        construction as 5 for `setOffset`.
     7. **Interactive camera = the original's `f64` matrices** (ADR 0004 d3), never `Camera3D`/`BeginMode3D`: one
        camera module (`src/render/camera.odin`) for the interactive view and the images. Any raylib helper bound to
        `Camera3D` (picking, `GetWorldToScreen`) is not used or is fed the same matrices.
   - **Alternatives**: faithful 0.2 per frame (fps-dependent: 144 Hz converges 2.4× faster); no chaser (visible jump
     at the loop restart and at junctions, §6.6); frame-based playback with `frames()` (speed tied to fps or
     resampling; no scrub between frames); `Camera3D` for the interactive view (two code paths, true π, near/far
     0.05/4000, `f32`).
   - **Consequences**: `core` gets `timed.odin`, `chaser.odin`; the frame-based playback stays for fidelity and
     images; viewer behaviour at 60 Hz equals the original's; closes §6.8 first bullet.
2. **`docs/adr/0004-axes-and-units.md`**: in decision 3, replace "Whether the interactive UX camera (phase 3) may
   use `Camera3D` instead is left to phase 3: it is not compared with the oracle." with "The interactive camera uses
   the same matrices ([ADR 0007](0007-timed-playback.md) decision 7)." Nothing else.
3. **`docs/original.md`** is not edited (it describes the original). **`docs/architecture.md`**: ADR list +
   `- [0007](adr/0007-timed-playback.md) Timed playback, chaser and interactive camera.`
4. `changelog.d/195-adr-timed-playback.md` (`### Added`). `./build.sh ci`.

## Ficheros a tocar
`docs/adr/0007-timed-playback.md` (new), `docs/adr/0004-axes-and-units.md` (one sentence),
`docs/architecture.md` (ADR list), `changelog.d/195-adr-timed-playback.md` (+ this plan).
Not touched: `src/`, `docs/original.md`, `docs/specs/`, `reference/`.

## Tests a escribir primero
n/a (docs only). Check: `./build.sh ci` (changelog-check) green.

## Riesgos
- Contradicting the spec: every number (5/10, 0.8, 0.2, 0.97, speeds) must equal `docs/specs/phase-3-viewer.md` and
  `docs/original.md` §6.4/§6.5/§7.5; the reviewer checks them against `reference/GrappleMap/src/`.
- The libm `pow` point: it must not read as an exception to ADR 0003 for oracle-checked values.

## Criterio de hecho
ADR 0007 merged with decisions 1-7; ADR 0004 d3 points to it; architecture ADR list updated; `./build.sh ci` and
CI green; `code-reviewer` (opus) without blockers.
