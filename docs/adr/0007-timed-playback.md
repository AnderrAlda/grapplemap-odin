# 0007. Timed playback, chaser and interactive camera
Status: Accepted (decisions approved in the phase 3 spec, `docs/specs/phase-3-viewer.md`, PR #194)
Date: 2026-11-26

## Context
Paths `src/…` are in `reference/GrappleMap`; `§` refers to `docs/original.md`.

The phase 3 viewer plays transitions interactively: play/pause, scrub, speed, loop (spec deliverable 3). The original
has two ways of playing a path:
- **Frame-based** (`frames()` + `smoothen`, §6.2-§6.3): a fixed number of frames per segment. Ported in phase 2 and
  checked bit for bit by the oracle (`playback.ndjson`), but it samples at a fixed frame count, so its speed is tied
  to the frame rate and it cannot show a time between two frames.
- **Time-based** (`Playback`, `src/playback.{hpp,cpp}`, §6.4), used by the editor: `progress(seconds)` advances at
  5 segments per second (10 if the step is `detailed`); the leftover of a segment is carried into the next one at the
  **new** step's speed; reaching the end of the path holds it for `pause_after = 0.8` s with the leftover discarded,
  then `reset()` jumps to the start, holds it for `pause_before = 0.8` s and plays again, forever. The shown target is
  `at(location)`: interpolate **then** reorient. Each step of the `OrientedPath` carries its own reorientation, which
  `reorient_from` keeps consistent through `gp_connect` (`src/graph_util.cpp:232-245`). Nothing of this is dumped by
  the oracle: §6.7 asks to "match semantically".
- **The chaser** (§6.5, `src/playback.cpp:178-184`): every frame `chaser = between(chaser, at(location()), 0.2)`, the
  target sampled **before** `progress`. The factor is per frame, so the smoothing depends on the frame rate; the
  source says so itself (`// todo: the 0.2 should depend on secondsElapsed`). §6.8, first bullet, leaves the choice
  between faithful and time-based to phase 3.
- **Camera target smoothing** (§7.5, `src/camera.hpp:38-50`): `setOffset(o)` is `offset·0.97 + o·0.03`, called once
  per frame by the players and editors (`src/glfw_playback.cpp:72`, `src/glfw_editor.cpp:530`,
  `src/editor_canvas.cpp:543`): frame-rate dependent in the same way.
- **The camera**: ADR 0004 decision 3 builds the images' camera from the original's `f64` matrices (`pi()` =
  `3.141593`, near/far 0.01/15) and left open whether the interactive camera may use raylib's `Camera3D` instead.

Odin's `math.pow_f64` (`core/math/math_basic.odin:26-27,79` in the pinned distribution, `.odin-version`) is the LLVM
intrinsic `llvm.pow.f64`, i.e. the platform's libm `pow`; on `js`/wasm it is a foreign import
(`core/math/math_basic_js.odin`).

## Decision
1. **Interactive playback is a port of `Playback` into `core`**: `Timed_Playback` in `src/core/timed.odin`, with the
   semantics of §6.4 exactly: 5 / 10 segments per second by `detailed`; `how_far` measured from keyframe `segment`
   towards `segment + 1` in both directions; direction by `Step.reverse`; leftover seconds carried across segments
   and steps at the new step's speed; `PAUSE_BEFORE = PAUSE_AFTER = 0.8` s; leftover discarded at the end and at the
   restart; shown target = interpolate then reorient. Each step's reorientation comes from `connect` (= `gp_connect`:
   `compose(inverse(E), n.reorientation)`, with `E` the stored reorientation of the step's own start end). For
   `seconds ≥ 0`, `how_far ∈ [0, 1]` whenever `progress` returns, so `between` never extrapolates. It is unit-tested
   against the cases of §6.4, not bit-checked (there is no dump).
2. **Loop toggle**: `loop = true` is the original (hold the end 0.8 s, `reset`, hold the start 0.8 s, play again).
   `loop = false` stops at the end: it holds the last keyframe with `at_end` set and does not `reset` until the user
   restarts. No ping-pong (the original has none).
3. **Speed** ∈ {0.25, 0.5, 1, 1.5, 2}: the viewer multiplies every `seconds` it passes to `progress` by the speed,
   pauses included (at 0.25× a 0.8 s pause lasts 3.2 s). `Timed_Playback` itself knows nothing about speed.
4. **Scrub**: `timed_duration` is the sum over the path's steps of `segments / speed` of each step, in `f64`, pauses
   excluded; it is not the original's `duration` (`src/editor.cpp:33-62`), which truncates in integer arithmetic
   (§6.6: 7 segments → 1 s instead of 1.4 s). `timed_seek(t)` places `segment`/`how_far` directly for time `t`. While
   paused or scrubbing the chaser is bypassed: the exact target is shown.
5. **The chaser is time-based**: per frame,
   `chaser = between(chaser, target, 1 − (1 − CHASER_FACTOR)^(CHASER_REFERENCE_HZ·dt))` with
   `CHASER_FACTOR = 0.2` and `CHASER_REFERENCE_HZ = 60`, the target sampled before `progress` as in the original.
   - At 60 Hz this is the original's filter up to the rounding of the factor: `1 − 0.8` is `0.19999999999999996` in
     `f64`, not `0.2`. At any other rate the error decays by the same amount per second (×0.8 per 1/60 s).
   - `dt` is clamped to a named `CHASER_MAX_DT` (of the order of 0.1 s) **for the smoothing filters only**
     (decisions 5 and 6), so a stalled frame does not snap the body to the target; `progress` always receives the
     full scaled `dt` (decision 1 keeps `how_far ∈ [0, 1]` for any `dt`).
   - `pow` is the platform libm (`math.pow_f64` → `llvm.pow.f64`): its last bits may differ between targets (native,
     wasm). This is accepted because nothing compares the chaser with the oracle. It is **not** an exception to
     ADR 0003: its bit-for-bit (decision 4) and tolerance (decision 5) rules apply to oracle-checked values, and the
     chaser is not one. Its unit tests use inputs where `pow` is exact (`dt = 0`, exponent 1, exponent 2).
6. **Camera target smoothing is time-based** in the same way:
   `offset = between(offset, target, 1 − (1 − CAMERA_OFFSET_FACTOR)^(CHASER_REFERENCE_HZ·dt))` with
   `CAMERA_OFFSET_FACTOR = 0.03`, equal to `setOffset` at 60 Hz up to rounding (`between`'s `a + (b − a)·s` instead
   of `a·0.97 + b·0.03`; not oracle-checked either), with the same `dt` clamp.
7. **The interactive camera uses the original's `f64` matrices** (ADR 0004 decision 3), never
   `Camera3D`/`BeginMode3D`: one camera module (`src/render/camera.odin`) serves the interactive view and the
   images. Any raylib helper bound to a `Camera3D` (picking, `GetWorldToScreen`) is either not used or fed the same
   matrices.

## Alternatives considered
- **Faithful chaser, 0.2 per frame.** Equal to the original only at the original's frame rate: at 144 Hz it
  converges 2.4× faster in wall-clock time, at 30 Hz twice as slow. The original's own `todo` asks for the time-based
  version.
- **No chaser.** The exact target jumps visibly at the loop restart (the `reset` jump back to the start, which the
  original smooths with the chaser) and at any residual mismatch between two steps (§6.6).
- **Frame-based playback with `frames()`** for the viewer. Speed would be tied to the frame rate, or need
  resampling, and scrubbing could not land between two frames. It stays for fidelity tests and the images.
- **`Camera3D` for the interactive view.** Two camera code paths, the true π instead of `3.141593`, near/far
  0.05/4000 instead of 0.01/15, and `f32` throughout (ADR 0004): the interactive view would not match the images.

## Consequences
- `core` gets `src/core/timed.odin` (`Timed_Playback`, `connect`, `timed_reset`, `timed_progress`, `timed_at`,
  `timed_duration`, `timed_seek`, `loop`) and `src/core/chaser.odin` (`chase`), both TDD. The frame-based playback
  of phase 2 is unchanged and remains the oracle-checked path for the images.
- At 60 Hz the viewer behaves as the original's editor playback; at other rates it keeps the same timing and the
  same smoothing per second.
- Closes §6.8's first bullet (chaser) and the open point of ADR 0004 decision 3 (interactive camera), which now
  points here.
