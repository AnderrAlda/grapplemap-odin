# Plan: #204 feat(render): offscreen images, --image, golden Docker image and oracle measurement
Spec: docs/specs/phase-3-viewer.md (deliverable 6; "Golden set", "UX" `--image`, "Edge cases" depth/determinism/grid) ·
ADR 0006 d4, d5 and open points · docs/original.md §7.6, §7.7 · `tools/oracle/images/images.cpp:130-140` ·
`src/images.cpp:63-112,302-316` (in `reference/GrappleMap`) · epic #5 comment points 3 and 10.
Depends on #199 (merged: #212, #213). Model: `opus` (image pipeline, GL readback, measurement).

## Context
The reference path draws the original's bodies on screen (#199). The golden tests (#200) need the same picture as an
image: rendered offscreen at 2×, reduced exactly like the original's `ImageMaker`, and first measured against the 6
oracle PNGs so Ander can set the tolerance (ADR 0006 d5). This issue delivers that pipeline, the CLI to drive it, the
pinned Mesa image it runs in, and the measurement.

## Pasos
Two PRs (spec: "at risk of the 400-line limit"): **PR 1** = steps 1-4, **PR 2** = steps 5-8.

1. **Prototype first** (scratch, not committed): hidden raylib window (`FLAG_WINDOW_HIDDEN`, no MSAA hint), a
   `RenderTexture` at `2w × 2h`, `draw_scene` inside `BeginTextureMode`, readback with `rlgl.ReadTexturePixels`
   (RGBA8, bottom-up). Settle and note for ADR 0006: the render texture's depth format (raylib's default vs a 16-bit
   attachment via `vendor:OpenGL`, spec "Depth precision"), and the **grid** for images: the interactive 0.02 m quads
   vs the original's `GL_LINES` 2 px at 2× (`rlgl` lines + `rlgl.SetLineWidth(2)`, unlit: the lit factor 1.01 clamps,
   so the colour is the same `0.8·bg`; check `GL_ALIASED_LINE_WIDTH_RANGE` ≥ 2 on Mesa). Both variants stay
   selectable (`Grid_Style :: enum {Quads, Lines}`, a `draw_scene` parameter) until step 7 picks by measurement.
   Verify against the pinned vendor sources: `ReadTexturePixels`, `LoadRenderTexture`'s depth, `ExportImage`
   (PNG writer inside `libraylib.a`), `core:image/png` loading.
2. **`src/render/image.odin`**:
   - pure, no GL: `downsample_2x(rgba: []u8, w2, h2: int, out: []u8)` = truncating 2×2 mean per channel
     (`(a+b+c+d)/4`, integer, `src/images.cpp:63-106`), alpha dropped, rows flipped to top-down
     (`src/images.cpp:111-112`), RGB in **our** order (no BGR swap; the comparison swaps the oracle's);
     `image_position(p, mirror, swap) -> Position` = `orient_canonically_with_mirror`, then `mirror`, then
     `swap_players` (`tools/oracle/images/images.cpp:135`, spec "UX"); `image_ymax(p) = max(IMAGE_YMAX_MIN 0.8,
     both heads' y)` (`images.cpp:136`).
   - GL: `render_image(r: ^Reference_Renderer, p: Position, heading: int, w, h: int, grid: Grid_Style,
     out: []u8) -> Image_Error` = render texture `2w × 2h` → `draw_scene(…, image_camera(ymax, heading),
     aspect = w/h, COLOR_BACKGROUND_WHITE)` → readback → `downsample_2x`. Render texture made and freed per call
     (or cached by size: decided in step 1, documented).
3. **`--image`** in a new `src/image_cli.odin` (package `main`, keeps `main.odin`'s diff small for #201):
   `grapplemap --image <entity> <out.png> [--size WxH] [--heading N|E|S|W] [--mirror] [--swap] [--load <file>]`.
   Parse in `parse_args` (`src/main.odin:175`) into an `Image_Args` field of `App_State`; resolution of the DB:
   `--load`, else `DEFAULT_DB_PATH :: "reference/GrappleMap/GrappleMap.txt"` (#201 reuses it for the viewer).
   Rules (spec "UX" + epic point 3): entity via `core.named_entity`; a transition, unknown entity, bad size/heading,
   missing `<out.png>`, or `--image` with `--headless` → exit 6 **before** any window; DB missing/unreadable → 5,
   invalid → 4, both before any window; PNG not written (`rl.ExportImage` false) → 5. Default size 480×360, heading N.
   Window hidden, never shown; no `--frames` loop.
4. **Docs PR 1**: `src/render/CLAUDE.md` (`image.odin`), root `CLAUDE.md` (app usage line gains `--image`, exits),
   fragment `changelog.d/204-render-image.md`. Grid style stays `Quads` by default for `--image` until PR 2 measures.
5. **`tools/golden/Dockerfile`** (PR 2): amd64, base image pinned by digest, Mesa pinned by exact apt version
   (`libgl1-mesa-dri`, `libglx-mesa0`, …), `xvfb`, `LIBGL_ALWAYS_SOFTWARE=1 GALLIUM_DRIVER=softpipe` (like the
   oracle, `tools/oracle/README.md` "Driver"); the pinned Odin of `.odin-version`, installed the way CI installs it
   (check `.github/workflows/ci.yml`; pinned URL + sha256). The repo (with the submodule) is mounted, not copied.
   `tools/golden/README.md`: what it pins, how to rebuild, softpipe vs llvmpipe.
6. **`tools/golden/measure/`** (package `measure`, own tests): `compare.odin` pure: `diff_stats(ours, oracle: []u8,
   w, h, oracle_bgr: bool) -> Diff_Stats{differing, largest_region (4-connected), max_delta}`, size mismatch → error;
   `main.odin`: loads two PNGs (`core:image/png`), prints one line per pair, writes a diff PNG (differing pixels
   marked) to `build/golden-measure/`. `./build.sh golden-measure` (new `cmd_golden_measure`, in usage and root
   `CLAUDE.md`): builds/reuses the image, inside it builds release and, per row of `tools/oracle/images.tsv`,
   `xvfb-run grapplemap --load reference/GrappleMap/GrappleMap.txt --image p<N> build/golden-measure/p<N>-480x360.png`
   then runs `measure` against `tests/fixtures/oracle/images/p<N>-480x360.png`. A `--grid quads|lines` pass-through
   (hidden option of `--image`, or a `-define`) lets step 7 measure both. `tools/golden/measure` added to
   `TEST_PKGS`, `FMT_DIRS` and `cmd_check`.
7. **Measurement** (by hand, local): run `golden-measure` for both grid styles and both depth settings if step 1
   left it open; run it **twice** and check our own outputs are identical (determinism, spec). Pick the grid style
   and depth by the numbers, make it the `--image` default, record the table (per image: differing pixels, largest
   region, max delta) in ADR 0006 "Open points" → resolved, and in PR 2 with side-by-side images (ours / oracle /
   diff) saved to a path for Ander to attach. Document point 10: the interactive grid width on Linux and macOS, and
   what `--image` gives on macOS.
8. **Tolerance**: propose a value with that evidence in PR 2 and in ADR 0006 d5 as "proposed"; **escalate to Ander
   via MAIN** (do not set it, do not change the ADR status to Accepted until he answers). Fragment
   `changelog.d/204-render-image-2.md`.

## Ficheros a tocar
PR 1: `src/render/image.odin`, `src/render/image_test.odin`, `src/render/reference.odin` (`Grid_Style` param),
`src/render/constants.odin` (`IMAGE_YMAX_MIN`, `IMAGE_DEFAULT_W/H`, `GRID_LINE_WIDTH_PX`), `src/image_cli.odin`,
`src/main.odin` (`parse_args`, dispatch), `src/main_test.odin`, `src/render/CLAUDE.md`, `CLAUDE.md`,
`changelog.d/204-render-image.md` (+ this plan).
PR 2: `tools/golden/Dockerfile`, `tools/golden/README.md`, `tools/golden/measure/{compare,main,compare_test}.odin`,
`build.sh` (`golden-measure`, `TEST_PKGS`, `FMT_DIRS`, `cmd_check`), `docs/adr/0006-body-rendering.md`, `CLAUDE.md`
(command, map), `changelog.d/204-render-image-2.md`.
Not touched: `src/core/`, `reference/`, `tests/golden/`, `tests/fixtures/oracle/`, `.github/workflows/`.

## Tests a escribir primero
- `src/render/image_test.odin` (no window): `downsample_2x` on a hand-made 4×4 RGBA buffer: truncation
  (`1+2+3+5 → 2`, `255·4 → 255`), alpha ignored, row flip (top output row = mean of the two **last** input rows),
  output length `3·w·h`; `image_ymax`: heads below 0.8 → 0.8, above → the higher head's y (bits);
  `image_position`: equals `swap_players(mirror(orient_canonically_with_mirror(p)))` for the flags, and the plain
  canonical one with none.
- `src/main_test.odin`: `parse_args` for `--image p96 out.png`, `--size 320x240`, `--heading E`, `--mirror --swap`;
  errors → usage: no entity, no output, `--size 480`, `--size 0x10`, `--heading Q`, `--image` + `--headless`;
  entity resolution: `t<N>` → 6, unknown → 6 (on a small fixture graph); unreadable `--load` → 5.
- `tools/golden/measure/compare_test.odin`: identical → `{0, 0, 0}`; one pixel off by 7 → `{1, 1, 7}`; two separate
  blobs of 3 and 5 → `largest_region = 5`, diagonal neighbours not joined; BGR swap makes a swapped copy identical;
  size mismatch → error.
The GL path is checked by `golden-measure` (step 7) and, later, by the golden runner (#200).

## Riesgos
- **Line width > 1 in a GL 3.3 core context**: allowed by Mesa on Linux unless forward-compatible; check the range at
  runtime and fall back to quads (logged) if it is 1. macOS stays at 1 px for lines: documented (point 10).
- **Readback orientation/format**: `ReadTexturePixels` may already flip or return a different format; pinned by the
  `downsample_2x` contract + the prototype, not assumed.
- **Docker/Mesa pin**: exact apt versions disappear from rolling archives; prefer a base whose archive is frozen or
  snapshot-pinned (as the oracle does with 18.04); amd64 emulated on Apple Silicon (slow, still exact).
- **The numbers may be bad** (e.g. many differing pixels from depth or rasterisation): that is the deliverable, not a
  failure; no tuning of constants to chase the oracle without recording why. Tolerance is Ander's call.
- 400-line limit per PR (split above; the Dockerfile and PNGs do not count).

## Criterio de hecho
`./build.sh ci` verde y CI verde en ambos PR; tests nuevos sin ventana; cero leaks;
`grapplemap --load reference/GrappleMap/GrappleMap.txt --image p96 /tmp/p96.png` (xvfb) escribe 480×360;
`./build.sh golden-measure` imprime la tabla de las 6 imágenes, dos ejecuciones idénticas; tabla y propuesta de
tolerancia en ADR 0006 y en el PR 2, con imágenes lado a lado; Ander contesta la tolerancia (escalación);
`code-reviewer` sin bloqueantes; docs y fragmentos al día.
