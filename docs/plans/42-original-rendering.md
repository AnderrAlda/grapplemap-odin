# Plan: #42 docs(original): rendering and camera (section 7)
Spec: docs/specs/phase-1-original-research.md (section 7 of `docs/original.md`; input for ADR 0006 and phase 3)
## Pasos
1. Read sections 3-6 of `docs/original.md` (style: `file:line` citations of the pinned submodule, `[unverified]` for anything not checked; link earlier sections, do not repeat them, especially §3 joints/radii and §4 axes/`cameraOffsetFor`).
2. Read in `reference/GrappleMap/src/`: `playerdrawer.{hpp,cpp}`, `icosphere.{hpp,cpp}`, `rendering.{hpp,cpp}`, `camera.hpp`, `triangle.{vertex,fragment}shader`, and the callers that set up the view (`glfw_playback.cpp`, `glfw_editor.cpp`, `images.cpp`; `vr_*` only to say what is VR-only).
3. Write `## 7. Rendering and camera`:
   - Body geometry: which joints are spheres and which segments are cylinders/cones, their radii (per joint, per segment; where they come from), icosphere subdivision level and how the mesh is built, cylinder faces, any per-player differences, how normals are computed.
   - Shaders: inputs, uniforms, the lighting model (as written in the GLSL), fog or other effects.
   - Colors (players, highlighted joints/segments, floor, background) as the exact values in code.
   - Lights: positions/directions, ambient/diffuse/specular terms.
   - Floor: geometry, size, grid/texture.
   - Camera: `camera.hpp` state (angles, distance, fov, near/far), projection, how it follows the players (`cameraOffsetFor`, link §4), controls per program (mouse/keys in playback vs editor) and the defaults used by `images.cpp`/mkpospages for the reference PNGs (link `tools/oracle/README.md`).
   - A short "what phase 3 must reproduce exactly vs. what is free" list, as input for ADR 0006 (no decision here).
4. Update Contents. Changelog fragment `changelog.d/42-original-rendering.md` (format in `changelog.d/README.md`); do not edit `CHANGELOG.md`.
## Ficheros a tocar
`docs/original.md` (§7 and one Contents line), `changelog.d/42-original-rendering.md` (new). Nothing under `reference/`.
## Tests a escribir primero
n/a (docs). Check every `file:line` citation against the pinned submodule before the PR (grep/sed of each one).
## Riesgos
- Section length: the PR limit is <400 hand-written lines; if it does not fit, split controls/VR into a follow-up phase-1 docs issue and say so in the PR.
- GL fixed-function state set outside `playerdrawer` (e.g. in `rendering.cpp`) is easy to miss: trace every GL call on the draw path.
- Do not decide the render technique (that is ADR 0006, #44).
## Criterio de hecho
Done-when of #42 met, citations verified, `./build.sh ci` green, reviewer (opus: fidelity content) without blockers.
