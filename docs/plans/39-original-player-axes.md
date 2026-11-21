# Plan: #39 docs(original): player model, units and axes (sections 3-4)
Spec: docs/specs/phase-1-original-research.md (sections 3-4 of `docs/original.md`)
## Pasos
1. Read sections 1-2 of `docs/original.md` (style: `file:line` citations of the pinned submodule, anything unverified marked as such) and the Contents list.
2. Read the original, read-only: `players.hpp` (`PlayerJoint`, 23 joints, `jointDefs` ~l.71, segments and lengths, `mirror(Joint)`), `positions.hpp` (`heading` ~l.132, `center` ~l.142, `swap_players`), `normalRotation`, `camera.hpp` and wherever `cameraOffsetFor` lives, `math.hpp` (V2/V3 conventions).
3. Section 3: table of the 23 joints (index, name, and the fields of `jointDefs`), segments (ends, length, mid radius, visible), players 0/1 (`t`/`b`) and how they are indexed in `Position`.
4. Section 4: units (meters), vertical axis, handedness (derived from the code, not assumed), `heading`, `normalRotation`, `center`, `cameraOffsetFor`; a note "input for ADR 0004" with the raylib mapping left pending.
5. Update Contents; CHANGELOG (Unreleased).
## Ficheros a tocar
`docs/original.md`, `CHANGELOG.md`. Nothing under `reference/`.
## Tests a escribir primero
n/a (docs). The worker re-opens every cited line to verify it.
## Riesgos
- #40/#41 edit the same file: they are chained after this PR, not parallel.
- PR <400 lines; if it does not fit, split section 3 and 4 into two PRs (`Refs #39`, then `Closes #39`).
## Criterio de hecho
Done-when of #39 met, citations verified, `./build.sh ci` green, reviewer (opus: fidelity content) without blockers.
