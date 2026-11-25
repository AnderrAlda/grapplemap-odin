# Plan: #181 feat(core): follow/frames and smoothen
Spec: docs/specs/phase-2-core.md (deliverable 8, second part; split from #144) · docs/original.md §6.1-§6.3, §5.4 ·
`src/graph_util.cpp:60-110`, `src/paths.cpp:8-52` (in `reference/GrappleMap`) · oracle `playback.ndjson`
(`tools/oracle/README.md`, "Playback")

## Pasos
1. **`src/core/playback.odin`** (new), bit-exact with the original (ADR 0003 d4: same operation order, no FMA, no
   reassociation), reusing `between` (transform.odin) and `reorient`/`compose`/`inverse` (reorient.odin):
   - `Frame_Step :: struct { caption: string, frames: []Position }`: one entry of the original's `Frames`
     (`vector<pair<string, vector<Position>>>`, `src/paths.hpp:9`).
   - `follow(g: ^Graph, n: Reoriented_Node, seq: int, fpp: int, allocator) -> (frames: []Position, next:
     Reoriented_Node, err: Error)` (`src/graph_util.cpp:60-108`):
     - direction by **node equality, `from` tested first**: `g.edges[seq].from.node == n.node` → forwards, else
       `to.node == n.node` → backwards, else `Graph_Error{.Step_Not_Connected, line = 0, block = seq}` (the
       original throws). `seq` out of range → same kind (the original indexes out of bounds; we never do).
     - `r := compose(inverse(E), n.reorientation)`, `E` the entry end's reorientation (`from` forwards, `to`
       backwards).
     - per consecutive pair `A`, `B` in walking order, `k = 0 … fpp`: `between(reorient(r, A), reorient(r, B),
       f64(k) / f64(fpp))` — keyframes reoriented **first**, then interpolated; `f64(k) / f64(fpp)` at runtime (with
       `fpp = 0` it is `0/0 = NaN`, as the original; never folded as a constant).
     - `next = {exit end's node, compose(X, r)}`, `X` = `Et` forwards, `Ef` backwards (`src/graph_util.cpp:80-81,98-99`).
     - Allocates exactly `segments · (fpp + 1)` positions on `allocator`. The `basicallySame` asserts are not ported
       (compiled out in the original, §1.7).
   - `frames(g: ^Graph, path: []Step, fpp: int, allocator) -> (out: []Frame_Step, err: Error)` (`src/paths.cpp:23-52`):
     - empty path → `nil, nil` (the original returns an empty `Frames`).
     - start node `from(path[0])`: the edge's **own** endpoint, `to` if `reverse` else `from`, with its stored
       reorientation (`src/locations.hpp:166-172`). Then per step `follow(g, n, step.seq, fpp / (detailed ? 2 : 1))`
       (**integer** division; `step.reverse` is not used to pick the direction, only for the start node), drop the
       **last** frame of each step (`pop_back`), `n = next`.
     - caption: `description[0]` of the edge; if it is exactly `"..."` and the stored `to` node (regardless of
       direction) has a non-empty description, that node's `description[0]`; then every literal `\n` (backslash,
       `n`) → one space (`replace_all`, left to right, non-overlapping). Always a fresh string on `allocator` (also
       when nothing changes), so `frames_destroy` frees uniformly.
     - On error everything allocated so far is freed (zero leaks); `frames_destroy(steps, allocator)` frees a result.
     - Negative `fpp`: `assert` (an API misuse, not input data; the original's is `unsigned`).
   - `smoothen(steps: []Frame_Step)` (`src/paths.cpp:8-21`), **in place** (the original takes a copy; callers keep the
     raw frames by cloning if they need them), one pass over all frames of all steps, state crossing step boundaries:
     `last := first frame of the first step`; per frame, per player, per joint: `lag := 0.6 + p.y` if `0.6 + p.y <
     0.83` else `0.83` (`std::min(0.83, x)` returns `x` only if `x < 0.83`; written explicitly, not Odin's `min`, so a
     NaN gives `0.83` as in C++); `one_minus := 1 - lag` once per joint; `p = last = last * lag + p * one_minus`
     per component (V3 ops, `(last·lag) + (raw·(1 − lag))`). The first frame is computed, not copied (1-ulp
     differences, §6.3). If `steps` is empty or `steps[0].frames` is empty, do nothing (the original reads
     `f[0].second[0]`, UB there; divergence documented in the doc comment). Later empty steps are simply skipped.
2. **`src/core/errors.odin`**: `Graph_Error_Kind.Step_Not_Connected` (the only change to that file).
3. **Fidelity** `tests/fidelity/playback_test.odin` (new), shared graph, streaming `playback.ndjson` with
   `ndjson_each` (389 MB in the full dump: one line at a time, `keep_negative_zero` as `between_test.odin`):
   - `transition` lines: `frames(g, {Step{seq, false}}, 11)`; check `block` against `edge.sequence` as the other
     tests do, `segment_frames_per_pos`, `caption` (string equality), `raw` bit for bit (`expect_bits`, per
     frame/player/joint/axis, plus the frame count), then `smoothen` and `smooth` bit for bit.
   - the `chain` line: `frames(g, {Step{a, false}, Step{b, false}}, 11)`, `captions` and `segment_frames_per_pos` per
     step, `raw` per step, then **one** `smoothen` over both steps and `smooth` per step (this is what proves the
     state crosses the boundary).
   - Counts: transition lines compared == lines read and > 0; exactly one `chain` line (the sample and the full dump
     both have one); in the full dump (`oracle_dir() != DEFAULT_ORACLE_DIR`) transition lines == the graph's edge count.
4. Docs: `src/core/CLAUDE.md`, new `playback.odin` bullet only (direction by node equality, `from` first; keyframes
   reoriented then interpolated; integer `fpp / 2`; last frame per step dropped; `smoothen` in place, one pass, state
   across steps, explicit `min`; the two UB divergences). `changelog.d/181-follow-frames-smoothen.md`.
5. `./build.sh ci`; `fidelity` workflow green on the PR (full dump, linux + macOS: every transition plus the chain).

## Ficheros a tocar
`src/core/playback.odin` (new), `src/core/playback_test.odin` (new), `src/core/errors.odin` (one enum value),
`tests/fidelity/playback_test.odin` (new), `src/core/CLAUDE.md` (new bullet only),
`changelog.d/181-follow-frames-smoothen.md` (+ this plan).
Not touched: `graph.odin`, `reorient.odin`, `transform.odin`, `json*.odin`, `tests/fixtures/oracle/`, `build.sh`,
`.github/`, `reference/`.

## Tests a escribir primero
`src/core/playback_test.odin` (red first). Hand-made graphs via the existing test helpers (`load_text`/`build_seqs`);
expected `f64`s as literals computed outside Odin (Python doubles reproducing the formula; snippet quoted in a
comment; `src/core/CLAUDE.md`: Odin folds constant expressions with extra precision):
- Frame counts: a 3-position transition, `fpp = 11` → `2·12 − 1 = 23` frames; `detailed` → `fpp′ = 5`, `2·6 − 1 = 11`;
  `fpp = 1` + `detailed` → `fpp′ = 0`: 1 frame per segment, NaN (`k/0` at runtime), pinned as NaN.
- Boundaries: in a 2-step path the dropped last frame of step 1 is not in the output; within a step, the segment
  boundary repeats (`between(…, 1)` then `between(…, 0)`, not bit-equal in a chosen case: literal bits).
- Direction by node equality: a step with `reverse = true` whose `from` node equals the current node is walked
  **forwards**; the self-loop (`from == to`) is walked forwards; a step not touching the node → `Step_Not_Connected`
  with `block = seq`; `seq` out of range → same; zero leaks on both errors (tracking allocator).
- Reorientation carried: a 2-step chain where the second edge's stored frame differs from the first's end
  (hand-made reorientation by rotating/translating/mirroring the second edge's positions): the first frame of step 2
  is `basically_same` as the dropped last frame of step 1 (semantic, no bits), and `next` of `follow` equals
  `compose(X, r)` (bits of a literal case).
- Keyframes reoriented before interpolation: a mutant that interpolates then reorients changes bits in a chosen case
  (literal).
- Captions: plain; `...` with a named `to` (replaced); `...` with an anonymous `to` (kept `...`); literal `\n` → space,
  also inside the replaced name; `...` reached **backwards** still uses the stored `to`.
- `smoothen`: one frame → `p·lag + p·(1 − lag)` with literal bits (a coordinate that changes by 1 ulp, e.g. `0.789`);
  `lag = 0.83` for `y ≥ 0.23` and `0.6 + y` below (both branches, plus the boundary `0.6 + y == 0.83` → `0.83`); NaN
  `y` → `lag = 0.83`; state crosses steps (smoothing two steps at once ≠ each alone); empty input / empty first step
  → unchanged, no panic.
- Empty path → `nil`, no allocation.
Fidelity: `tests/fidelity/playback_test.odin` as in step 3 (red until the procs exist).
Mutants to try, none committed (the PR lists them): test `to` before `from`; use `step.reverse` for the direction;
`fpp / 2` as float; keep the last frame; `a·(1 − s) + b·s` in `follow`; Odin `min` for `lag`; `1 - lag` recomputed per
component (should still pass: same bits, say so); reset `last` per step. Each mutant that changes behaviour must
turn a test red.

## Riesgos
- **Fidelity of `compose(inverse(E), N)` on the start node**: ≈ identity, not bit-identity; the oracle decides and the
  first transition is compared bit for bit, so any slip shows.
- **Big lines**: a `playback.ndjson` line holds hundreds of frames; `json.unmarshal` per line into a test-local struct
  freed per line (temp allocator + `free_all` per line, as other streamed tests) keeps memory bounded.
- **macOS**: same `cr_sin`/`cr_cos` path as the rest of `core` (through `reorient`); the full dump on both targets
  confirms it.
- **Size**: ~130 lines of code, ~180 of unit tests, ~110 of fidelity: around 400. If it goes over, `smoothen` (+ its
  tests and the `smooth` comparisons) goes as a second PR on the same issue; escalate only if the plan must change.

## Criterio de hecho
- `./build.sh ci` green locally and in CI (linux + macOS); zero leaks; `fidelity` workflow green on the PR.
- Mutants documented in the PR.
- `code-reviewer` (opus, `src/core`) without blockers.
- Labels `type:feat`, `area:core`, `phase-2`; milestone «Fase 2: Núcleo de datos»; `Closes #181`.
- Worker model: opus (bit fidelity in `core`).
