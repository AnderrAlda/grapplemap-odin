# Plan: #40 docs(original): transforms, mirror, swap and reorientation (section 5)
Spec: docs/specs/phase-1-original-research.md (section 5 of `docs/original.md`)
## Pasos
1. Read sections 2-4 of `docs/original.md` (style: `file:line` citations of the pinned submodule, `[unverified]` for anything not checked; §2.3 already covers `is_reoriented` and §4.3 `heading`/`normalRotation`/`center`: link them, do not repeat).
2. Read the original, read-only: `positions.hpp` (`mirror` l.37, `swap_players` l.68, `PositionReorientation` l.74-125, `inverse`/`compose` l.127-128, `orient_canonically_*` l.179-184), `positions.cpp` (their bodies), `math.hpp` (`Reorientation`, `inverse` l.257, `compose` l.262, `apply`/`*` operators, `yrot`), `players.hpp` (`mirror(Joint)`), and the `PositionInSequence`/`graph_util.hpp:148-154` uses.
3. Section 5: `mirror` (axis it negates, how joints swap left/right), `swap_players`, `Reorientation` (translation + angle about the vertical axis, order of operations) and `PositionReorientation` (+ swap, + mirror; the order in which `operator()` applies them), `compose` and `inverse` with formulas checked against the code (including how mirror/swap interact with the angle), canonical orientation with and without mirror (what is fixed: center, heading; tie-breaks).
4. A short "input for phase 2" list: which formulas the Odin port must match bit for bit and which the oracle `ops.ndjson` (#34) checks; open points marked as such.
5. Update Contents; CHANGELOG (Unreleased).
## Ficheros a tocar
`docs/original.md`, `CHANGELOG.md`. Nothing under `reference/`.
## Tests a escribir primero
n/a (docs). The worker re-opens every cited line to verify it; formulas are derived from the code, never assumed.
## Riesgos
- #41 (section 6) edits the same file: it goes in a later batch, not in parallel.
- `CHANGELOG.md` shared with #34 and #21 in this batch: whoever opens second merges `main` (see #98).
- PR <400 lines; if it does not fit, split (`Refs #40`, then `Closes #40`).
## Criterio de hecho
Done-when of #40 met, citations verified, `./build.sh ci` green, reviewer (opus: fidelity content) without blockers.
