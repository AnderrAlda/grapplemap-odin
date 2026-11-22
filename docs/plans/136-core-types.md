# Plan: #136 feat(core): types, constants and joint/segment tables
Spec: docs/specs/phase-2-core.md (deliverable 1a)

## Pasos
1. Tests first (`src/core/types_test.odin`, failing): joint count 23 and enum order of §3.1 (`LeftToe` = 0 … `Head` = 22);
   `JOINT_DEFS` radius/mirror per joint (table §3.1, values verbatim); `mirror_joint` swaps `2k ↔ 2k+1` for `k < 10`
   and fixes `Core`, `Neck`, `Head`; `SEGMENTS` has 28 entries in `limbs()` order (§3.2) with length, mid radius
   (`Maybe(f64)`) and visible, including the forearm asymmetry (left 0.26, right 0.27); 15 visible, 7 with mid radius;
   player colors (§3.3); `opponent`.
2. `src/core/types.odin`: `V3 :: [3]f64`, `Joint :: enum u8 {…}`, `Player :: [Joint]V3`, `Position :: [2]Player`,
   `Player_Joint {player: int, joint: Joint}`, `Joint_Def {radius: f64, mirror: Joint}`, `JOINT_DEFS :: [Joint]Joint_Def`,
   `Segment {ends: [2]Joint, length: f64, mid_radius: Maybe(f64), visible: bool}`, `SEGMENTS`, `PLAYER_COLORS`.
   `draggable` is kept as a field (verbatim, read nowhere, §3.1) so the `body.json` comparison in #138 is total.
3. Constants copied verbatim with their source line in a comment (ADR 0003 d7, ADR 0004 d4): `PI :: 3.141593`,
   `ENCODING_OFFSET_XZ :: 2`, `QUANT_SCALE :: 1000`, `Q_MAX :: 3843` (62² − 1), `BASICALLY_SAME_SQ :: 0.0016`,
   `HEAD_PREFILTER_SQ :: 0.05` (§2.3), the `apply_limits` box and the camera constants of ADR 0004 d4. Only names and
   values; no procedure uses them yet except the tests.
4. `src/core/errors.odin`: `Error :: union {Parse_Error, Graph_Error, Json_Error, Export_Error, mem.Allocator_Error}`;
   each own error a struct `{kind: <X>_Error_Kind, line: int, block: int}` with the kinds of §1.7 / ADR 0005 d8 that the
   later deliverables need (enums may grow). Doc comment: never assign an `Allocator_Error` (even `.None`) to `Error`
   without checking it; use `or_return`. Test: `proc() -> Error { return nil }` is `nil`, and an `or_return` through
   `make` compiles (one small test).
5. `src/core/CLAUDE.md`: list of files of the package (one line each). `changelog.d/136-core-types.md`.
6. `./build.sh ci`.

## Ficheros a tocar
`src/core/types.odin`, `src/core/types_test.odin`, `src/core/errors.odin`, `src/core/errors_test.odin`,
`src/core/CLAUDE.md`, `changelog.d/136-core-types.md`. Nothing outside `src/core` (no `build.sh`: `src/core` is already
in `TEST_PKGS`).

## Tests a escribir primero
The table tests of step 1 and the error-union test of step 4, all failing before the types exist (TDD, `core:testing`).
Values are written from `docs/original.md` §3.1-§3.3 and checked once by hand against
`reference/GrappleMap/src/players.hpp:8-167` and `src/positions.cpp:7-31,140`; the automatic comparison with
`body.json` is #138.

## Riesgos
- Typos in the tables: each value cites its source line; the reviewer checks them against `players.hpp`.
- `f64` literals: write them exactly as in the C++ (`0.26`, not `0.260`); Odin parses decimal literals correctly
  rounded, as GCC does, so the bits match.
- `[Joint]V3` vs `[23]V3`: enumerated arrays keep enum order; `Position` must iterate player 0 then player 1, joints
  in enum order (`playerJoints`, §3.3).

## Criterio de hecho
Tests green under the tracking allocator, `./build.sh ci` green, no use of `f32` in `core`, `code-reviewer` (opus)
without blockers, PR < 400 lines, labels `type:feat`, `area:core`, `phase-2`, milestone «Fase 2: Núcleo de datos».
