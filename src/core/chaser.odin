package core

import "core:math"

// The chaser of `Playback::frame` (src/playback.cpp:178-184, docs/original.md §6.5), made time-based (ADR 0007): the
// original moves the shown position 0.2 of the way to the target every frame (its own todo: "the 0.2 should depend
// on secondsElapsed"); here the per-frame factor at 60 Hz becomes `1 − (1 − 0.2)^(60·dt)`, equal to 0.2 at
// `dt = 1/60`. `pow` is the libm's (`math.pow_f64`): not oracle-checked (ADR 0007 d5/d6).

// CHASER_FACTOR is the original's per-frame `0.2` (src/playback.cpp:180).
CHASER_FACTOR :: 0.2
// CHASER_REFERENCE_HZ is the frame rate the per-frame factors are tuned for (ADR 0007).
CHASER_REFERENCE_HZ :: 60
// CHASER_MAX_DT clamps `dt` (seconds): a stalled frame does not snap the chaser onto the target.
CHASER_MAX_DT :: 0.1

// per_second_factor turns a per-frame interpolation factor at `CHASER_REFERENCE_HZ` into the factor for `dt` seconds:
// `1 − (1 − per_frame)^(CHASER_REFERENCE_HZ·dt)`, `dt` clamped to [0, CHASER_MAX_DT] (`dt = 0` gives 0).
per_second_factor :: proc(per_frame: f64, dt: f64) -> f64 {
	d := clamp(dt, 0, CHASER_MAX_DT)
	return 1 - math.pow_f64(1 - per_frame, CHASER_REFERENCE_HZ * d)
}

// chase is the chaser step: `between(chaser, target, per_second_factor(CHASER_FACTOR, dt))`. As in the original, the
// target is sampled before `timed_progress`.
chase :: proc(chaser, target: Position, dt: f64) -> Position {
	return between(chaser, target, per_second_factor(CHASER_FACTOR, dt))
}
