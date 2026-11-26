# Plan: #199 feat(render): reference path (shader, GL state, grid)
Spec: docs/specs/phase-3-viewer.md (deliverable 5) · ADR 0006 d2/d3, ADR 0004 d2/d3 · docs/original.md §7.2, §7.3, §7.4 ·
`src/rendering.cpp:229-264,339-363` (in `reference/GrappleMap`) · epic #5 comment point 10 (grid line width)
Depends on #197 (camera, merged) and #198 (mesh, merged: #210, #211). Model: `opus` (shader + GL state).

## Pasos
1. **Prototype first (no commit of throwaway code)**: in a scratch file, open a window, upload a `Body_Mesh` through
   rlgl (`rlLoadVertexArray`/`rlLoadVertexBuffer`/`rlSetVertexAttribute`, own VAO with position, normal, colour) and draw
   with a custom `Shader` from `LoadShaderFromMemory`. raylib's default batch has no normal attribute, so the body is
   drawn from our own buffers, flushed with `rlDrawRenderBatchActive` before/after. Settle here, and write into
   ADR 0006 "Open points" (per-frame rebuild vs instancing): per-frame rebuild + `rlUpdateVertexBuffer`
   (default; ≈ 2·(6·320+17·80+…) triangles is small) unless the prototype shows otherwise. Settle how to load
   `vendor:OpenGL` procs for `glDepthFunc` (`gl.load_up_to(3, 3, set_proc_address)` fed by raylib's `rlGetProcAddress`,
   or the loader the pinned `libraylib.a` exposes); verify the symbol names in `vendor/raylib` before coding.
2. **`src/render/shaders/reference.vs` / `reference.fs`** (GLSL 330, `#load`-embedded; ADR 0006 d3): attributes
   `vertexPosition`, `vertexNormal`, `vertexColor`; uniform `mat4 mvp`. Vertex stage:
   `lit = color · clamp(AMBIENT_TOTAL + DIFFUSE·(max(0, n·l0) + max(0, n·l1)), 0, ∞)` then `clamp(…, 0, 1)` per channel,
   `l0 = normalize(1,1,1)`, `l1 = normalize(-1,1,-1)` as uniforms set from named constants (`LIGHT_DIRS`,
   `LIGHT_DIFFUSE 0.65`, `LIGHT_AMBIENT 0.03`, `GLOBAL_AMBIENT 0.2` → 0.26, §7.3). Fragment stage only passes the
   interpolated colour (Gouraud). World-space normals: no normal matrix (model matrix is identity).
3. **`src/render/constants.odin`** (extend, with source lines): light constants above, `COLOR_BACKGROUND_WHITE`,
   `GRID_FACTOR :: 0.8`, `GRID_SIZE :: 2`, `GRID_SPACING :: 0.5`, `GRID_NORMAL :: V3{0,1,0}` (§7.2/§7.4,
   `src/rendering.cpp:249-264`), `GRID_LINE_WIDTH :: 0.02` (m, the original's shader-path quad width, §7.4).
4. **`src/render/reference.odin`**:
   - `light_factor(n: core.V3) -> f64` and `shade(color, n) -> core.V3` in `f64`: CPU mirror of the shader formula,
     used by the grid (so the grid goes through the same arithmetic) and by the tests that pin the shader's constants.
   - `grid_mesh(size, spacing, color, out: ^Body_Mesh)`: lines `x = i/2` and `z = i/2`, `i = −2·size … 2·size`, from
     `−size` to `+size` (`4·size + 1` per direction), each as a **quad of `GRID_LINE_WIDTH` in `y = 0`** (2 triangles,
     normal `(0,1,0)`, colour `shade(0.8·bg, n)`). Decision on epic point 10: quads, not `GL_LINES`, because core-profile
     GL has no guaranteed line width and macOS would give 1 px; the interactive width is therefore 0.02 m in world
     space, not the original's constant 2 px at 2× (≈ 1 px after the 2×2 mean). The difference against the oracle PNGs is
     measured in #204; document it in `src/render/CLAUDE.md` and ADR 0006.
   - `Reference_Renderer :: struct {shader, locs, vao/vbo handles, body: Body_Mesh, grid: Body_Mesh, builder: Mesh_Builder}`;
     `reference_init(^R) -> bool` (shader compile failure = error value, not panic), `reference_destroy`.
   - `draw_scene(r: ^Reference_Renderer, pos: core.Position, cam: Camera, aspect: f64, background: core.V3)`:
     clear, `rlgl.DisableBackfaceCulling()`, depth test on with `GL_LESS` via `vendor:OpenGL` (raylib leaves `GL_LEQUAL`),
     `mvp = to_raylib(mat_mul(projection(cam, aspect), model_view(cam)))` (`f32` conversion only here), grid first then
     body (original order, `src/rendering.cpp:358-363`), restore raylib's state afterwards (culling, depth func) so the
     unlit overlays of #202 still work. Per frame: `body_mesh_clear` + `build_body(overrides = nil)` + upload;
     the grid is built once.
5. **`src/main.odin`**: keep `App_State`; with `--load` and no `--headless`, keep the graph in the arena for the window's
   life (`core.load_graph` + `graph_destroy` at exit), show **node 0** (`core.node_position(g, 0)` or the existing
   accessor: check `core/graph.odin`) with `camera_default`-like view from the spec (`fov 50`, distance 2.9 via
   `VIEWER_ZOOM :: 1.2` added to `CAMERA_DEFAULT_ORIENTATION.z`, pitch −0.6; epic point 7) and
   `camera_offset_for(pos)`. `aspect = f64(GetRenderWidth())/f64(GetRenderHeight())`. Without `--load` the placeholder
   screen stays (the viewer shell is #201). `--headless` unchanged (no raylib call).
6. **Docs**: `src/render/CLAUDE.md` (`reference.odin`, shaders, grid decision), ADR 0006 open points (render path
   prototype outcome; status stays Proposed until #204), root `CLAUDE.md` untouched (no new command), fragment
   `changelog.d/199-render-reference-path.md`, 2 screenshots (node 0 of the real DB, default view) in the PR via
   `xvfb-run` (software GL) and a capture tool available in the image; if no capture tool exists, ask before adding one.
7. `./build.sh ci`; if over 400 hand-written lines: PR 1 = shader + `reference.odin` + grid, PR 2 = `main` wiring (`-2`).

## Ficheros a tocar
`src/render/reference.odin`, `src/render/reference_test.odin`, `src/render/shaders/reference.{vs,fs}`,
`src/render/constants.odin`, `src/render/CLAUDE.md`, `src/main.odin` (+ `main_test.odin` if `parse_args`/state change),
`docs/adr/0006-body-rendering-technique.md` (open points only), `changelog.d/199-render-reference-path.md` (+ this plan).
Not touched: `src/core/`, `camera.odin`, `mesh.odin`, `build.sh`, `.github/`, `reference/`, `tests/golden/`.

## Tests a escribir primero
`src/render/reference_test.odin`, no window (pure logic):
- `shade`/`light_factor`: normal `(0,1,0)` → factor `0.26 + 0.65·2/√3` clamped to 1 (grid shows at its nominal colour);
  normal `(-1,-1,-1)/√3` → `0.26` (both lights ≤ 0, only ambient); a normal along `l0` → hand-computed value; compared by bits
  against values computed outside Odin (Python, same operation order).
- `grid_mesh`: `4·size + 1 = 9` lines per direction → 18 quads → 36 triangles; first/last line positions
  `±size`, spacing 0.5, all `y = 0`, all normals `(0,1,0)`, width `GRID_LINE_WIDTH`.
- Shader constants: the GLSL source (`#load`ed string) contains the same numeric literals as the Odin constants
  (guard against drift: test parses/greps the named literals).
- `VIEWER` camera: `orientation.z == CAMERA_DEFAULT_ORIENTATION.z + VIEWER_ZOOM` (= 2.9 up to `f64` rounding, pinned by bits).
The GL path itself (shader compiles, state restored) is checked by the screenshots here and by golden tests in #200/#204.

## Riesgos
- **GL access from `vendor:OpenGL`** next to raylib's own GLAD: the proc loader must be fed from raylib's context; if
  it fails, fall back to `rlgl` only (`rlEnableDepthTest` + keep `GL_LEQUAL`) and record the deviation in ADR 0006 for Ander.
- **raylib batch interplay**: mixing own VAO draws with raylib draws needs explicit flushes; the HUD (#202) is drawn after.
- **Shader compile on the CI/Mesa image**: GLSL 330 needs a 3.3 core context; the failing path returns an error, no panic.
- **Grid width** differs from the oracle (decision above); measured, not tuned, in #204.
- 400-line limit (step 7 split).

## Criterio de hecho
`./build.sh ci` verde y CI verde; tests nuevos pasan sin ventana; cero leaks (tracking allocator, `--frames N` en una
ventana oculta/xvfb sale con 0); `grapplemap --load reference/GrappleMap/GrappleMap.txt` muestra el nodo 0 con la cuadrícula
(capturas en el PR); culling off y `GL_LESS` documentados; ADR 0006 y `src/render/CLAUDE.md` al día; `code-reviewer` sin bloqueantes.
