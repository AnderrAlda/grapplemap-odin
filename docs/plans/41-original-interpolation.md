# Plan: #41 docs(original): interpolation and playback (section 6)
Spec: docs/specs/phase-1-original-research.md (section 6 of `docs/original.md`)
## Pasos
1. Read sections 2, 4 and 5 of `docs/original.md` (style: `file:line` citations of the pinned submodule, `[unverified]` for anything not checked; link earlier sections, do not repeat them) and `tools/oracle/README.md` (what `between.ndjson` and `playback.ndjson` hold, merged in #103).
2. Read the original, read-only: `positions.hpp:42` (`between(Position, Position, s)`) and `math.hpp:193-195` (`between` of `V3`/`V2`); `paths.cpp:8-60` (`smoothen`, `frames` for one path and for a script, `frames_per_pos`, `detailed` halving by integer division, dropped last frame); `graph_util.hpp:262` and `graph_util.cpp` (`follow`, `at(location)`); `playback.cpp:90-185` / `playback.hpp` (`Playback::progress`, speed in segments per second, the chaser `between(chaser, target, 0.2)` per frame, ends of a transition and chaining to the next one); `makevideo.cpp:34,93,105` (default frames-per-pos and who smooths what).
3. Section 6: `between` (formula per joint, per player; whether `s` is clamped; what happens for `s` outside [0, 1]); frame-based path (`frames()` / `follow()`: frames per segment, `detailed`, repeated boundaries, last frame dropped); `smoothen` (exact filter, state carried across a whole script); time-based `Playback::progress` (speed, how `howFar` crosses segment and transition ends, reversal for bidirectional, leftover seconds); the chaser (frame-rate dependent, factor 0.2); chained transitions and reorientation between them (link §5).
4. "Input for phase 2/3": which behaviours the Odin port must reproduce bit for bit (`between`, `frames`, `smoothen`, checked by `between.ndjson`/`playback.ndjson`) and which only semantically (`progress`, chaser); open points marked as such.
5. Update Contents; CHANGELOG (Unreleased).
## Ficheros a tocar
`docs/original.md`, `CHANGELOG.md`. Nothing under `reference/`.
## Tests a escribir primero
n/a (docs). The worker re-opens every cited line to verify it; formulas are derived from the code, never assumed. Where useful, cross-check one value against `tools/oracle/dump/testdata/basic/{between,playback}.ndjson`.
## Riesgos
- #35 (section 10) and #42 (section 7) edit the same file: they go in later batches.
- `CHANGELOG.md` shared with the other PRs of the batch (#98 fixes this): whoever opens second merges `main`.
- PR <400 lines; if it does not fit, split (`Refs #41`, then `Closes #41`).
## Criterio de hecho
Done-when of #41 met, citations verified, `./build.sh ci` green, reviewer (opus: fidelity content) without blockers.
