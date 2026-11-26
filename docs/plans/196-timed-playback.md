# Plan: #196 feat(core): timed playback, chaser and public caption
Spec: docs/specs/phase-3-viewer.md (deliverable 2) · ADR 0007 (#195; decisions fixed in the spec) ·
docs/original.md §6.4, §6.5, §6.6 · `src/playback.{hpp,cpp}`, `src/graph_util.{hpp,cpp}` (`first_segment`,
`last_segment`, `at(Reoriented<Location>)`, `gp_connect`), in `reference/GrappleMap` · review points 5, 6, 12 of
https://github.com/AnderrAlda/grapplemap-odin/issues/5#issuecomment-7193375287

## Pasos
1. **`src/core/timed.odin`** (new). Constants with their source lines: `PAUSE_BEFORE :: 0.8`, `PAUSE_AFTER :: 0.8`
   (`src/playback.hpp:27-29`), `SEGMENTS_PER_SECOND :: 5`, `SEGMENTS_PER_SECOND_DETAILED :: 10`
   (`src/playback.cpp:129-131`). Types and procs:
   - `Reoriented_Step :: struct {step: Step, reorientation: Position_Reorientation}` (`Reoriented<Reversible<SeqNum>>`).
   - `connect(g: ^Graph, n: Reoriented_Node, s: Step) -> (r: Reoriented_Step, err: Error)` = `gp_connect`
     (`src/graph_util.cpp:232-245`): the step's own start end (`edge.to` if `s.reverse`, else `edge.from`) tested
     first, then its exit end; on the first whose `node == n.node`, `r.reorientation = compose(inverse(E),
     n.reorientation)` with `E` that end's stored reorientation. Neither matches, or `seq` out of range →
     `Graph_Error{.Step_Not_Connected, block = s.seq}` (the original asserts; review point 5).
   - `step_exit(g: ^Graph, r: Reoriented_Step) -> Reoriented_Node`: the exit end's node with `compose(X,
     r.reorientation)` (as `follow`'s `next`, `src/core/playback.odin:72`); what "arrive" uses.
   - `Timed_Playback :: struct {path: []Reoriented_Step (borrowed, caller owns it), i, segment: int, how_far, wait:
     f64, at_end, loop: bool}`.
   - `timed_init(g, path, loop := true) -> (p: Timed_Playback, err: Error)`: empty path →
     `Graph_Error{.Empty_Path}` (new kind in `errors.odin`; the original asserts); calls `timed_reset`.
   - `timed_reset(p, g)` (`src/playback.cpp:102-112`): `i = 0`; reversed first step → `segment` = its last segment
     (`len(positions) − 2`), `how_far = 1`; else `0`, `0`; `wait = 0`, `at_end = false`.
   - `timed_progress(p, g, seconds)` (`src/playback.cpp:114-176`), written as a loop with the same semantics as the
     recursion: pause first (`wait > seconds` → `wait -= seconds`, return; else `seconds -= wait`, `wait = 0`); if
     `at_end`: with `loop` → `timed_reset`, `wait = PAUSE_BEFORE`, return (rest discarded); without `loop` → return
     (holds the end). Speed by `sequence.detailed`. Forwards `hf += seconds·speed; if hf < 1 return;
     seconds = (hf − 1)/speed`; next segment with `hf = 0`, or on the last `hf = 1` and finished. Reverse mirrored
     (`hf -= …; if hf > 0 return; seconds = (−hf)/speed`; `segment − 1` with `hf = 1`, or on 0 `hf = 0`). Finished:
     last step → `at_end = true`, `wait = PAUSE_AFTER`, return; else `i += 1`, start at its first segment
     (reversed: last / 1; else 0 / 0) and continue with the leftover. Same operation order as the original
     (ADR 0003 d4), so the state is the original's.
   - `timed_at(p, g) -> Position` = `reorient(path[i].reorientation, between(positions[segment],
     positions[segment + 1], how_far))` (`src/graph_util.hpp:260-268`: interpolate **then** reorient).
   - `timed_duration(path, g) -> f64` = Σ `segments / speed` per step; `timed_elapsed(p, g) -> f64` (inverse of
     seek, for the slider); `timed_seek(p, g, t)`: `t` clamped to `[0, duration]`, find the step, `local = (t −
     start)·speed`, `k = min(floor(local), segments − 1)`, `f = local − k`; forwards `segment = k`, `how_far = f`;
     reversed `segment = segments − 1 − k`, `how_far = 1 − f`; `t = duration` → the end (`how_far` 1 / 0);
     `wait = 0`, `at_end = false`.
2. **`src/core/chaser.odin`** (new): `CHASER_FACTOR :: 0.2` (`src/playback.cpp:180`), `CHASER_REFERENCE_HZ :: 60`,
   `CHASER_MAX_DT :: 0.1`; `per_second_factor(per_frame: f64, dt: f64) -> f64` = `1 − (1 − per_frame)^(HZ·dt)` with
   `math.pow_f64` (ADR 0007 d5/d6: libm, not oracle-checked), `dt` clamped to `[0, CHASER_MAX_DT]`;
   `chase(chaser, target: Position, dt: f64) -> Position` = `between(chaser, target, per_second_factor(
   CHASER_FACTOR, dt))`. The camera smoothing of #201 reuses `per_second_factor(0.03, dt)`.
3. **`src/core/playback.odin`**: `caption` loses `@(private = "file")` (doc comment unchanged + "public for the HUD").
4. **`src/core/errors.odin`**: `Graph_Error_Kind.Empty_Path`.
5. Docs: `src/core/CLAUDE.md` bullets for `timed.odin`, `chaser.odin` and `caption` public;
   `changelog.d/196-timed-playback.md`. `./build.sh ci`; `fidelity` workflow green.
   If the diff passes 400 hand-written lines: PR 1 = `timed.odin` + `Empty_Path`; PR 2 = `chaser.odin` + `caption`
   (`-2` changelog fragment).

## Ficheros a tocar
`src/core/timed.odin`, `src/core/timed_test.odin`, `src/core/chaser.odin`, `src/core/chaser_test.odin` (new);
`src/core/playback.odin` (visibility of `caption`), `src/core/playback_test.odin` (a `caption` test, if not
covered), `src/core/errors.odin` (one kind), `src/core/CLAUDE.md`, `changelog.d/196-timed-playback.md`
(+ this plan). Not touched: `graph.odin`, `reorient.odin`, `transform.odin`, `build.sh`, `.github/`, `render`/`ui`.

## Tests a escribir primero
`src/core/timed_test.odin`, hand-made graphs with the helpers of `graph_test.odin` (`seq_of`, `build_seqs`,
`load_text`, `gap_position`/`translated`), expected floats as literals computed outside Odin (`src/core/CLAUDE.md`):
- `connect`: forward step from its `from` node → `compose(inverse(Ef), N)`; reversed bidirectional step from its
  `to` node → uses `Et`; incoming step (`to == n`, not reversed) → uses `Et` (second branch); self-loop forwards →
  `Ef` (first branch wins); not touching → `Step_Not_Connected` with `block = seq`; `seq` −1 and `len(edges)` → same.
  `step_exit` of an incoming step lands on `n.node`.
- `timed_reset`: forwards 0/0; reversed first step: last segment, `how_far = 1`.
- `timed_progress` (§6.4 cases): a 3-segment non-detailed step: `progress(0.1)` → `how_far = 0.5`;
  `progress(0.25)` from 0 → segment 1, `how_far` = the original's `(1.25 − 1)/5·5` bits; exact crossing (`how_far`
  reaching 1) moves on; detailed step at 10 seg/s; leftover from a detailed step consumed at the next step's 5 seg/s
  (two-step path); reverse step mirrors; end: `at_end`, `wait = 0.8`, leftover discarded; next call with
  `seconds < wait` only decrements `wait`; after the pause `reset` + `wait = PAUSE_BEFORE` and the rest discarded;
  `loop = false` stays at the end forever; `seconds = 0` changes nothing; a huge `seconds` (100) never leaves
  `how_far ∉ [0, 1]` and ends in the at-end state.
- `timed_at`: at `how_far = 0`/`1` equals `reorient(r, keyframe)` bit for bit; at 0.5 equals `reorient(r,
  between(A, B, 0.5))` (not `between` of reoriented keyframes: a test where the two orders differ in bits, if one
  can be found by hand; otherwise just the formula).
- `timed_duration`/`timed_seek`/`timed_elapsed`: 2 steps (5 and 10 seg/s); seek 0 → start; seek duration → end of
  last step; seek in the middle of the second (reversed) step; `elapsed(seek(t)) == t` for a few exact binary `t`;
  `t` < 0 and > duration clamped.
- `timed_init` with an empty path → `Empty_Path`.
`src/core/chaser_test.odin` (inputs where `pow` is exact on every libm, review point 6): `dt = 0` → `s = 0` and
`chase` returns `chaser` bit for bit; `60·dt == 1` (`dt = 1.0/60`, check that `60·dt` is exactly 1 at run time) →
`s = 1 − 0.8` bits (`0.19999999999999996`); `dt` above `CHASER_MAX_DT` gives the same as `CHASER_MAX_DT`;
negative `dt` → 0; monotone for a few `dt` (comparisons only, no bit values, so no tolerance).

## Riesgos
- Bits of `timed_progress`: the expected `how_far` values must be computed with the original's exact operations
  (`hf += s·v`, `(hf − 1)/v`), in Python `float`, not by hand algebra.
- `seek`/`elapsed` round-trip is not exact for arbitrary `t`: test only exact binary values; the slider does not
  need more.
- `pow` from libm: no bit test outside the exact cases (ADR 0007 d5). No tolerance anywhere without Ander's OK.
- Size: see step 5's split.

## Criterio de hecho
`./build.sh ci` and CI (incl. `fidelity`) green; new tests red first, then green; zero leaks; `code-reviewer`
(opus) without blockers; `src/core/CLAUDE.md` and changelog fragment updated.
