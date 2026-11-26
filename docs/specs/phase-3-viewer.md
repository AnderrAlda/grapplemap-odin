# Spec: Phase 3 — basic 3D viewer

Epic: #5 · Milestone: "Fase 3: Visor 3D básico" · Date: 2026-11-26

## Goal
A native viewer that draws the original's two players **exactly as the original draws them** and plays transitions,
over the `core` of phase 2:

1. **Reference render path** (ADR 0006): the original's meshes (icospheres, 10-face pillars, fat triangles) rebuilt on
   the CPU in `f64`, its fixed-function lighting reproduced per vertex in a shader, culling off, depth `GL_LESS`, the
   original's grid and colors. It is both the interactive view and the golden-image renderer (one renderer).
2. **Camera** from the original's formulas in `f64` (ADR 0004 decision 3), interactive (orbit, zoom, reset) and for
   images (the `ImageMaker` heading view).
3. **Time-based playback** ported from `Playback::progress` (§6.4) with a time-based chaser (§6.5, new ADR):
   play/pause, scrub, speed 0.25×–2×, loop toggle.
4. **Mirror and swap** view toggles.
5. **Golden images**: offscreen 2× render + truncating 2×2 downsample (§7.6), measured by hand against the oracle
   PNGs (tolerance: Ander's call), our accepted images committed to `tests/golden/` and compared **exactly** in CI
   inside a pinned Mesa Docker image. Smoke test of the real app.

This list refines the epic's acceptance criteria (#5): when this spec is merged, MAIN rewrites the body of #5 with it
and links the phase-3 issues. #14 (run golden/bench jobs only when their runners exist) is folded into deliverable 7;
`bench/` exists already, so only its golden half remains.

## Scope, files and interfaces

### Package layout
Illustrative interfaces, not a final API; the plan of each issue fixes the names. `core` rules unchanged
(`src/core/CLAUDE.md`); `render` only reads `core` (`src/render/CLAUDE.md`); `ui` logic is separate from drawing and
unit-tested without a window (`src/ui/CLAUDE.md`).

| File | Contents |
|---|---|
| `src/core/timed.odin` | `Timed_Playback` = the original's `Playback` (§6.4): `Oriented_Path` (`[]Reoriented_Step`: a `Step` + its `Position_Reorientation`), `segment`, `how_far`, `wait`, `at_end`; direction by `Step.reverse` (`src/playback.cpp:102-155`), each step's reorientation from `connect(g, n: Reoriented_Node, s: Step)` = the original's `gp_connect` (`src/graph_util.cpp:231-245`: the step's own start end `from(s)`, i.e. the edge's `to` when `reverse`, tested first, then `to(s)`; `r = compose(inverse(E), n.reorientation)`); the node reached is `compose(X, r)`, `X` the exit end's stored reorientation (as `follow`'s `next`, §6.2); `timed_reset`, `timed_progress(^Timed_Playback, g, seconds)` (recursive semantics of §6.4: 5 / 10 segments/s by `detailed`, leftover carried at the new step's speed, 0.8 s `PAUSE_BEFORE`/`PAUSE_AFTER`, leftover discarded at the end), `timed_at(g, location) = reorient(u, between(A, B, how_far))` (interpolate **then** reorient, §6.4), `timed_duration`/`timed_seek(t)` for the scrub bar (total time without pauses, `f64`, not the original's truncating integer `duration`, §6.6). `loop: bool` (default true = original: hold end 0.8 s, `reset`, hold start 0.8 s, play again; false = stop holding the end) |
| `src/core/chaser.odin` | `chase(chaser, target: Position, dt: f64) -> Position` = `between(chaser, target, 1 − 0.8^(60·dt))` (ADR 0007); `CHASER_FACTOR :: 0.2`, `CHASER_REFERENCE_HZ :: 60`. Order as the original: target sampled **before** `progress` |
| `src/core/types.odin` | playback constants (`PAUSE_BEFORE`, `PAUSE_AFTER`, `SEGMENTS_PER_SECOND`, `_DETAILED`) and the axis-dependent ones (light directions of §7.3, ADR 0004 d4), each with its `src/…:line` comment. Render-only constants (mesh: `ICO_X`, `ICO_Z`, `PILLAR_FACES`, `FINE`/`COARSE`, `OVERRIDE_RADIUS_DELTA`; light diffuse/ambient; colors of §7.2; grid of §7.4/§7.6) live in `src/render/constants.odin`. `ICO_X`/`ICO_Z` are the original's `float` values widened: a test pins `transmute(u64)f64(ICO_X)` to the bits of `(double)0.525731112119133606f` (Odin folds constants with more than `f64` precision, `src/core/CLAUDE.md`) |
| `src/core/playback.odin` | `caption` made public (today `@(private = "file")`), with its tests, for the HUD (deliverable 2) |
| `src/render/camera.odin` | `Camera {offset: V3, yaw, pitch, distance, fov_deg: f64}` mirroring `src/camera.hpp`: `rotate_horizontal`, `rotate_vertical` (clamped `±PI/2`), `zoom`, `model_view` (`translate(0,0,−d)·xrot(pitch)·yrot(yaw)·translate(−offset)`), `perspective(fov, aspect, CAMERA_NEAR, CAMERA_FAR)` with `pi()`, `camera_offset_for(p)`, `image_camera(ymax, heading)` (§7.6); `to_raylib(M) -> rl.Matrix` (element `(r, c) = f32(M[4c + r])`). All `f64`, unit-tested against hand-computed values of the original's formulas |
| `src/render/mesh.odin` | CPU mesh builder (ADR 0006 decision 2): `icosphere(level)` (unit, `f64`, `normalize(e0 + e1)` per edge), `pillar(from, to, r_from, r_to)` (basis from the world point `(1,1,1)`, normals ⟂ axis, 20 triangles), `fat_triangle(a, b, c, ra, rb, rc)` (14 triangles, §7.1 vertices and normals), `build_body(pos: Position, colors, out: ^Body_Mesh)` in `drawPlayers` order (pillars, 46 spheres, 5 fat triangles per player). Pillar angles use `core`'s correctly rounded `sin`/`cos` (same bits on every target). Output: `f32` position/normal/color arrays, converted once |
| `src/render/reference.odin` | the reference path: GLSL 330 shader (embedded with `#load`, `src/render/shaders/reference.{vs,fs}`) evaluating `color · (0.26 + 0.65·Σ max(0, n·lᵢ))` **per vertex**, clamped; `rlgl.DisableBackfaceCulling`, depth `GL_LESS` via `vendor:OpenGL` (raylib leaves `GL_LEQUAL`, ADR 0006); grid lines on `y = 0` (§7.4, lit like the original: factor ≈ 1.01, clamped); `draw_scene(view: Scene_View, pos: Position, cam: Camera)`. Per-frame mesh rebuild vs instanced spheres: chosen by the prototype (ADR 0006 open point), recorded in ADR 0006 |
| `src/render/image.odin` | offscreen: render at `2w × 2h` into a `RenderTexture`, read back, truncating 2×2 mean, flip to top-down, `[]u8` RGB (our order; the oracle's BGR is swapped only by the comparison). Used by the golden runner and `--image` |
| `src/ui/viewer.odin` | `Viewer` logic (no drawing): current `Reoriented_Node`, the node's transition list (see "Selection" below), `Timed_Playback`, play/pause, speed in `@(rodata) SPEEDS := []f64{0.25, 0.5, 1, 1.5, 2}`, loop, mirror, swap, scrub; `viewer_apply(^Viewer, Action)`, `viewer_update(^Viewer, dt) -> Position` (chaser → mirror → swap). Arriving at a transition's end moves the current node to `compose(X, r)` (`connect` above) |
| `src/ui/input.odin` | key/mouse bindings **as data** (`@(rodata) BINDINGS := []Binding{{.SPACE, .Toggle_Play}, …}`) mapped to `Action`; camera controls (below); `SetExitKey(.KEY_NULL)` so `Esc` is a binding, not raylib's default exit key |
| `src/ui/widgets.odin` + `src/ui/hud.odin` | hand-drawn widgets with raylib primitives (no raygui: the pinned Odin ships no `libraygui` for Linux, `vendor/raylib/raygui.odin:12-14`): button, toggle, slider; their hit-testing/drag logic is pure and unit-tested. The HUD: bottom bar (play/pause, scrub slider, speed, loop, mirror, swap), top caption (node description first line / `core.caption` of the step), list of the current node's transitions with the selected one highlighted. Layout constants named, scaled by DPI |
| `src/ui/font.odin` + `assets/fonts/` | one bundled TTF (permissive licence, chosen in its plan, registered in `docs/ASSETS.md`), embedded with `#load`, loaded with `LoadFontFromMemory` for ASCII + the non-ASCII codepoints present in the loaded DB's descriptions (`¼`, `¾`, …); long captions are ellipsised |
| `src/main.odin` | `App_State` (graph, viewer, camera, window flags), window `1280×720` with `FLAG_WINDOW_RESIZABLE | WINDOW_HIGHDPI | VSYNC_HINT | MSAA_4X_HINT`, projection from the real render size, per-frame `free_all(context.temp_allocator)`; new options `--show <entity>` and `--image <entity> <out.png> [--size WxH] [--heading N|E|S|W] [--mirror] [--swap]` (rules in "UX") |
| `tests/golden_runner/` | package run by `./build.sh test-golden` (`build.sh:139-142`, which deliverable 7 changes so that `--update` becomes `-define:GOLDEN_UPDATE=true`): renders the golden set (below) with `render/image.odin` in **one** test that owns the GL context (`odin test` runs tests on worker threads), compares the **decoded RGB pixels** exactly with `tests/golden/*.png` (not the file bytes, which depend on the PNG encoder), writes `tests/golden/_actual/` and a diff image on failure; `--update` rewrites them, **only with Ander's explicit OK** |
| `tools/golden/Dockerfile` + `./build.sh golden-measure` | pinned image (base tag and Mesa version fixed) with the pinned Odin toolchain, Xvfb (GLFW needs a display) and `LIBGL_ALWAYS_SOFTWARE=1`; the repo, including the `reference/GrappleMap` submodule, is mounted. Driver: softpipe by default, like the oracle (`tools/oracle/README.md`, "Driver": llvmpipe's bytes change with threads and the host's SIMD width); llvmpipe only with `LP_NUM_THREADS=0` and a pinned `LP_NATIVE_VECTOR_WIDTH`, if the prototype needs it. `test-golden` runs in it locally and in CI. `golden-measure` renders the 6 oracle images and prints, per image, the count of differing pixels, the size of the largest differing region and the max channel delta against `tests/fixtures/oracle/images/` (R/B swapped back) |
| `build.sh` | `TEST_PKGS` += `src/render` (deliverable 3; otherwise its tests never run, `build.sh:10`); `test-golden --update`; `golden-measure` |
| `.github/workflows/ci.yml` | the `golden` job checks out with `submodules: true` and runs `./build.sh test-golden` in the pinned image instead of bare `xvfb-run`, skipping while `tests/golden_runner/` is missing (#14); `build` smoke test with `submodules: true` and `--show`. **CI workflow edit: Ander's OK in that PR** |
| `docs/adr/0007-timed-playback.md` | new ADR (below) |

### Golden set (deliverables 6, 7)
- **Oracle-measured**: the 6 positions of `tools/oracle/images.tsv` at 480×360, `WhiteBg`, heading N, no mirror, the
  `ImageMaker` camera (`ymax = max(0.8, heads' y)` of `orient_canonically_with_mirror`), exactly like
  `tools/oracle/images/images.cpp`.
- **Ours only** (regression, never compared with the oracle), all with the same heading-N camera rule:
  block 96 canonically oriented, then mirrored (`ymax` from the result); the same, swapped instead (the bodies change
  colours, see "UX"); one mid-transition frame: `timed_at` of a fixed transition (chosen in deliverable 7's plan),
  forwards from its `from` node in that node's stored orientation, at its middle segment with `how_far = 0.5`, then
  canonically oriented.
- The oracle set (`tools/oracle/images.tsv`) is **not** extended in this phase.

### Deliverables (one issue/PR each, <400 hand-written lines; generated files and PNGs do not count)
Every issue and PR: labels `type:`, `area:core|render|ui|infra`, `phase-3`; milestone "Fase 3: Visor 3D básico".
Model per worker (`docs/ai-workflow.md`): `opus` for the mesh builder, the shader/GL state, the image pipeline and
`timed_progress`; `sonnet` otherwise.

| # | Deliverable | Depends on | Area |
|---|---|---|---|
| 1 | ADR 0007 (timed playback, chaser, speed, interactive camera = original matrices; closes ADR 0004's `Camera3D` open point and §6.8's first bullet) | — | docs |
| 2 | `core`: `Timed_Playback` (`connect`, `reset`, `progress`, `at`, `duration`, `seek`, `loop`) + `chase` + public `caption`, TDD with the §6.4/§6.5 cases | 1 | core |
| 3 | `render/camera.odin` + `to_raylib`, unit tests against the original's formulas; `src/render` added to `TEST_PKGS` | — | render |
| 4 | `render/mesh.odin` + `render/constants.odin`: icosphere, pillar, fat triangles, `build_body`; tests on vertex/triangle counts and hand-computed vertices and normals, the `ICO_X`/`ICO_Z` bits; `body.json` constants checked if present | — | render |
| 5 | `render/reference.odin`: shader, GL state (culling off, `GL_LESS`), grid, `draw_scene`; `main --load <file>` shows node 0 with the default camera (first visual PR, screenshots) | 3, 4 | render |
| 6 | `render/image.odin` + `--image` + `tools/golden/Dockerfile` + `./build.sh golden-measure`; **prototype measurement** of the 6 oracle images, recorded in ADR 0006 (status → Accepted or amended) and in the PR; tolerance proposed to Ander with that evidence | 5 | render, infra |
| 7 | `tests/golden_runner/`, `tests/golden/*.png` (after Ander's OK on 6), `build.sh test-golden --update`, `ci.yml` golden job in the pinned image + #14 | 2, 6 | infra |
| 8 | `ui`: `Viewer` logic + bindings as data + camera controls; `--show`, default DB, `App_State`, resizable/HiDPI/MSAA window; unit tests of `viewer_apply`/`viewer_update` without a window | 2, 5 | ui |
| 9 | `ui/widgets.odin` + `ui/hud.odin` + font asset: hand-drawn bar, caption, transition list | 8 | ui |
| 10 | Smoke test (`--show` + `--frames`, real DB) in `ci.yml` `build` job, docs (`architecture.md`, `CLAUDE.md` commands/map, nested `CLAUDE.md`s), screenshots | 7, 9 | infra |

Order: {1, 3, 4} → {2, 5} → 6 → {7, 8} → 9 → 10. 2 is independent of the render track. At risk of the 400-line
limit: 4 (split into icosphere+pillar / fat triangles + `build_body`), 6 (split into `image.odin` + `--image` /
Docker image + `golden-measure` + measurement), 8 (split into `Viewer` logic / app shell) and 9 (widgets / HUD +
font).

Also in every PR: a fragment in `changelog.d/`, `src/*/CLAUDE.md`/`docs/architecture.md` when the layout or a rule
changes, the root `CLAUDE.md` when commands or the map change (`--show`, `--image`, `golden-measure`,
`tools/golden`, `assets/`), screenshots for every visual change.

## Out of scope
- The modern render path (per-pixel lighting, shadows, materials, post-processing): phase 4.
- Search, full graph navigation, history, filters, tag lists, camera presets beyond reset: phase 5. Phase 3 only has
  `--show` and stepping through the current node's transitions.
- First-person and split views (§7.5), auto-orbit, jiggle, the editor's colors and overlays (§7.2): not in phase 3.
- Editing anything (phase 6); ping-pong playback; multi-step paths chosen by the user (the `Oriented_Path` supports
  them, the UI plays one step at a time).
- Clips/MP4s and the 320×240 / other headings of `mkpospages`; extending `tools/oracle/images.tsv` (a regeneration
  of the oracle, by hand, if ever needed).
- wasm (phase 7): the GLSL is 330 only; the ES variant is checked then (`src/render/CLAUDE.md`).
- Any change to `reference/GrappleMap`, or to `tests/golden/` without Ander's explicit OK.

## UX / behaviour
- **Start**: `grapplemap` loads `--load <file>` or, without it, `reference/GrappleMap/GrappleMap.txt` relative to the
  working directory. Neither readable → the window shows "no database: use --load <file>" and closes with exit 0;
  `--load` errors keep phase 2's exits (4 invalid DB, 5 I/O). `--show <entity>` (`core.named_entity`: `p<N>`,
  `t<N>`, a description) selects the initial node or transition; unknown → usage error (exit 6) before opening the
  window. Default: node 0, still. `--headless` keeps phase 2's behaviour (no window).
- **Window**: 1280×720, resizable, HiDPI-aware (projection from `GetRenderWidth/Height`), vsync, MSAA 4× when the
  driver offers it (interactive only: the golden path renders without MSAA, 2× supersampled). White background,
  grid `0.8·bg` over ±2 m, as the images (§7.2, §7.6).
- **Camera**: the original's matrices (ADR 0004), `glfw_playback`'s view: fov 50, distance 2.9 (`1.7 + zoom(1.2)`),
  pitch −0.6, yaw 0 (§7.5; named `VIEWER_FOV`, `VIEWER_DISTANCE`). Left- or middle-drag: yaw/pitch at 0.002 rad per
  pixel (`glfw_editor`'s rate; pitch clamped `±pi()/2`); wheel: distance, clamped to a minimum
  (`CAMERA_MIN_DISTANCE`, named; the original's zoom is unclamped, §7.5); ←/→ yaw, ↑/↓ pitch, Home/End distance, as
  `glfw_playback` but per second (rates named in `ui`); `R` resets yaw/pitch/distance to that view. The target follows `camera_offset_for(shown position)` with a
  time-based smoothing equivalent to `setOffset`'s 3 % per frame at 60 Hz (ADR 0007). No auto-orbit.
- **Selection**: at a node, `Tab`/`Shift+Tab` (or the list in the HUD) cycles the node's transitions: first
  `outgoing` (where it can go: forward steps and the reverse steps of bidirectional transitions, §2.6), then the
  `incoming` steps with `reverse = false` that are not already listed (how it is reached; dedupes the self-loop).
  Not `in_out`: it holds `{s, true}` for every transition ending at the node, bidirectional or not
  (`src/core/graph.odin:163-166`), and would play non-bidirectional transitions backwards. Every entry is played in
  its own direction, never reversed by the UI. `Enter` plays the selected step placed by `connect` from the current
  node in its current orientation: an outgoing step starts at the node, an incoming one ends at it. When a
  transition is shown, `N` ("arrive") moves to its end node (`compose(X, r)`; for an incoming step that is the
  current node again); `Esc` returns to the node shown before `Enter`.
- **Playback**: `Space` play/pause; speed `[`/`]` over `SPEEDS` (scales every `seconds` passed to `progress`,
  pauses included); `L` loop on/off (on = the original's hold-reset-hold loop; off = stops at the end, `Space`
  restarts); the scrub slider sets `seek(t)` over the step's duration (pauses excluded), pausing playback while
  dragged; while paused or scrubbing the chaser is bypassed (the exact frame is shown).
- **Mirror / swap** (`M` / `S`, and HUD toggles): applied to the shown position after the chaser (`mirror`,
  `swap_players` of `core`). The graph, the path and the playback use the untransformed positions; only the drawing
  and the camera target (`camera_offset_for` of the shown position) use the transformed one, so the view stays
  centred. Colours stay by player index (§3.3), so with swap on the bodies change colour.
- **HUD**: top caption (node description first line, or `core.caption` of the step; an anonymous node at rest shows
  `p<N>`); bottom bar with the controls above; key hints as a tooltip line. All shortcuts live in `BINDINGS`.
- `grapplemap --image <entity> out.png [--size 480x360]` writes the reference-path image, no window shown (hidden
  window/offscreen context, as the platform allows), exactly as `tools/oracle/images/images.cpp`: a node is
  `orient_canonically_with_mirror`ed, then `--mirror`/`--swap` applied, then `ymax = max(0.8, both heads' y)` and the
  heading camera of §7.6 (`--heading`, default N). A transition (`t<N>`) is a usage error in phase 3. Exits: 0, 4/5
  as `--load`, 5 if the PNG cannot be written, 6 on bad arguments.

## Edge cases
- **Self-loop** (block 1826, not bidirectional) and a **reversed bidirectional** step: direction by `Step.reverse`,
  reorientation by `connect` (`gp_connect`, the step's own start end tested first), as the original's `Playback`, so
  a step always starts at the end it is played from. The UI's list never offers a reversed non-bidirectional step,
  so §6.8's reversed self-loop cannot be selected; `connect` still has unit tests for it and for a reversed
  bidirectional step in deliverable 2.
- **`detailed` → normal step** boundaries timed at the new speed (§6.4 point 5); `seconds = 0` and huge `dt`
  (a stalled frame, e.g. 5 s) give `how_far ∈ [0, 1]` and never extrapolate; `dt` is clamped for the chaser only
  (`CHASER_MAX_DT`, named) so a stall does not snap differently from the original at 60 Hz.
- **Isolated node** (5 in the DB): nothing to cycle. Anonymous nodes (no description): `p<N>` at rest, the step's
  `core.caption` while playing.
- **`Esc`** is raylib's default exit key (`SetExitKey`, `vendor/raylib/raylib.odin:1189`): disabled at start-up, so
  `Esc` only does what `BINDINGS` says; closing is the window's close button.
- **Grid line width on macOS**: the core GL 3.3 context rejects line widths > 1, so the interactive grid is 1 px
  there; the golden and `--image` renders run on Linux (Mesa accepts 2 px, as the original's 2 px at 2×).
- **Speed and pauses**: at 0.25× the 0.8 s pauses last 3.2 s (scaled, by design).
- **Zero-size window** (minimised): skip drawing, keep the clock; resize changes only the aspect.
- **HiDPI** where `GetRenderWidth ≠ GetScreenWidth` (macOS Retina, Wayland scaling): HUD and mouse use screen
  coordinates, projection the render size; checked by hand (CI is headless).
- **Degenerate pillar basis**: never happens on the DB (§10.3); the mesh builder asserts no NaN in debug.
- **Font glyphs** missing from the TTF: replaced by `?`, never a crash; the codepoint set comes from the DB.
- **Depth precision**: 16-bit in the oracle vs the render texture's depth (24-bit in raylib): measured in 6; if it
  matters, the render texture gets a 16-bit depth attachment via `vendor:OpenGL`.
- **Determinism of the golden images**: two runs in the pinned image give identical pixels, and so do a local run
  and the CI runner (checked in 6 and 7; on Apple Silicon the image runs as amd64 emulated). Otherwise the
  driver/threads/SIMD setting changes, never a tolerance between our own images.

## Decisions and trade-offs
- **One renderer**: the interactive view is the reference path, so what the user sees is what the golden images
  test. MSAA 4× is the only interactive-only difference. Phase 4 adds the modern path beside it.
- **Golden images: ours, exact, in pinned Mesa.** The oracle PNGs (OSMesa softpipe, Mesa 20.0.8) are the
  measurement, done locally by `golden-measure`; the tolerance against them is Ander's call with that evidence
  (ADR 0006 decision 5; this spec moves the proposal to deliverable 6, which amends ADR 0006 accordingly). CI
  compares our committed images pixel for pixel, rendered in `tools/golden/Dockerfile`, so a runner's Mesa update
  cannot flake the job. Cost: one more Docker image; regenerating goldens needs Docker.
- **Camera: original matrices everywhere** (settles what ADR 0004 decision 3 left to phase 3; the ADR 0007 PR edits
  ADR 0004 to say so): no `Camera3D`/`BeginMode3D`; any raylib
  helper that depends on a `Camera3D` (picking, `GetWorldToScreen`) is not used, or is given the same matrices.
- **Time-based playback + time-based chaser** (ADR 0007): faithful in semantics (§6.7 "match semantically"), equal to
  the original at 60 Hz, independent of frame rate. The frame-based `frames()`/`smoothen` of phase 2 stay for
  fidelity tests and images, not the interactive view.
- **Mirror/swap as view transforms**, not path reorientations: same picture, no interaction with the chained
  reorientation of the navigation.
- **Minimal navigation** (`--show` + in/out cycling): enough to reach every transition, without building phase 5's UI
  twice.
- **Hand-drawn widgets, not raygui**: raygui needs a `libraygui` the pinned Odin does not ship for Linux
  (`vendor/raylib/raygui.odin:12-14`: `system:raygui`), i.e. building it from a pinned `raygui.h` with a C compiler
  in setup, CI and the Docker image. The bar needs three widget kinds; drawing them with raylib primitives (~150
  lines) keeps the build pure Odin on every target, wasm included.
- **One bundled font** (new asset, registered with licence): the DB has non-ASCII descriptions.
- **Constants by owner**: playback and axis-dependent constants in `core` (ADR 0004 d4); mesh counts, colours and
  light strengths in `render`, the only user.
- **Escalations in this phase**: ADR 0007 and ADR 0006 updates (plans), the tolerance (6), the golden images (7), CI
  workflow edits (7, 10), the font asset (9).

## End-to-end verification
1. `./build.sh ci` green locally and in CI; zero leaks (tracking allocator, ASan on Linux), including a run of the
   app with `--show t<N> --frames 600` under the tracking allocator.
2. `./build.sh test` covers `Timed_Playback`/`chase` (core, TDD), `camera`/`mesh` (render, no window) and `Viewer`
   (ui, no window).
3. `./build.sh golden-measure` prints the per-image difference against the 6 oracle PNGs; the numbers and the
   approved tolerance are in deliverable 6's PR and ADR 0006; side-by-side screenshots (ours / oracle) attached.
4. `./build.sh test-golden` passes in the pinned image locally and in CI; twice in a row gives identical pixels;
   a deliberate change (one pixel of an expected image, or a shader constant) makes it fail and uploads `_actual/`
   and the diff.
5. `./build/grapplemap-debug` with the real DB: orbit, zoom, reset; `--show` a transition, play/pause, scrub,
   0.25×/2×, loop off; mirror and swap; `Tab`/`Enter`/`N` walk from a node through two transitions; window
   resized and on a HiDPI screen. Screenshots/GIF in deliverable 10's PR.
6. Epic #5: every acceptance box ticked with links to the PRs.
