# 0006. Body rendering technique
Status: Proposed (the final choice needs the phase-3 prototype against the oracle PNGs)
Date: 2026-11-21

## Context
Paths `src/…` are in `reference/GrappleMap`; paths `vendor/…` are in the pinned Odin distribution (raylib 6.2,
ADR 0004).

The oracle images are made by the original's **fixed-function** renderer through OSMesa (`ImageMaker`,
`docs/original.md` §7, §7.6). What they show, and therefore what a pixel comparison depends on (§7.7):
- **Geometry** (§7.1, `src/playerdrawer.cpp`): per joint an icosphere of level 2 (Head, Core, hips, shoulders) or 1
  (the rest), built from `float` icosahedron constants (`src/icosphere.cpp:16-29`), vertex `center + v·radius`,
  normal `v`; per visible limb a 10-face truncated cone whose basis comes from the fixed world point `(1, 1, 1)`, with
  normals perpendicular to the axis, split at the midpoint when it has a mid radius; five "fat triangles" per player
  (pelvis, two torso slabs, feet) of 14 triangles each with per-vertex normals. No caps, no other mesh. Vertices and
  normals go to GL as `double` (`src/playerdrawer.cpp:9-10`).
- **Lighting** (§7.3, `src/rendering.cpp:229-247,339`): two directional lights toward `(1, 1, 1)/√3` and
  `(−1, 1, −1)/√3` in world space, diffuse 0.65, ambient 0.03 each, global ambient 0.2, `GL_COLOR_MATERIAL`, no
  specular, per-vertex (Gouraud): `color · (0.26 + 0.65·(max(0, n·l₀) + max(0, n·l₁)))`, clamped. No culling, depth
  test `GL_LESS` with a 16-bit depth buffer (`src/images.cpp:525`), near 0.01 / far 15.
- **Image pipeline** (§7.6): 2× supersampling with a truncating 2×2 box filter, vertical flip, channel swap, grid of
  2-px aliased lines at 2×.

What raylib 6.2 gives, as checked in the pinned `libraylib.a`: the OpenGL 3.3 backend (default shaders are
`#version 330`, `rcore.o`), whose default shader is **unlit** (`finalColor = texelColor*colDiffuse*fragColor`); `rlglInit`
calls `glCullFace(GL_BACK)`, `glFrontFace(GL_CCW)`, `glEnable(GL_CULL_FACE)` (disassembly of `rlglInit`: constants
`0x405`, `0x901`, `0xb44` = `GL_BACK`, `GL_CCW`, `GL_CULL_FACE`), so **back-face culling is on by default**,
whereas the original never culls and emits the sphere triangles in reversed order (`src/playerdrawer.cpp:149-166`).
Culling can be turned off with `rlgl.DisableBackfaceCulling` (`vendor/raylib/rlgl/rlgl.odin:468`). `rlglInit` also
sets `glDepthFunc(GL_LEQUAL)` (`0x203`), not the original's default `GL_LESS`; the `rlgl` binding has no setter for
it (only enable/disable of depth test and mask), so changing it needs `vendor:OpenGL`. raylib's shape helpers take
rings/slices or a side count (`DrawSphereEx`, `DrawCylinderEx`, `DrawCapsule`,
`vendor/raylib/raylib.odin:1618,1621,1624`): ring/slice spheres, not the original's icospheres.

## Decision
1. **Two render paths over the same `core` data**, chosen per view:
   - **Reference path** (phase 3): reproduces the original's image for the golden tests. Fidelity over looks.
   - **Modern path** (phase 4): free look (per-pixel lighting, shadows, AA, other materials). Never compared with the
     oracle; it may share the reference path's meshes.
2. **Reference path geometry: the original's meshes rebuilt on the CPU**, vertex for vertex, in `f64` with the
   original's formulas (icosphere subdivision with the `float` constants widened to `f64`; the pillar basis from
   `(1, 1, 1)`; the fat-triangle points and normals; `pi()` = `3.141593` in the pillar angles), converted to `f32` once
   when uploaded (ADR 0004, decision 2). Positions and normals as in §7.1; no shortcuts of raylib's shape helpers.
   "Vertex for vertex" means the same surface: the pillar is drawn as its 20 triangles (10 quads), not as the
   original's 60-vertex strip with degenerate and duplicate triangles (§7.1). Per frame the joint positions change,
   so the body mesh is regenerated per frame (per player 6·320 + 17·80 sphere triangles, 20 per pillar and 5·14 slab
   triangles: small) or the spheres are drawn as two unit meshes transformed per joint (same vertices up to the `f32`
   rounding of the transform); the prototype picks one.
3. **Reference path lighting: the fixed-function model reproduced in a shader** (raylib's GL 3.3 has no
   fixed-function lighting), evaluated **per vertex** with the constants above, colors from §7.2, output clamped. The
   light directions are world-space constants (ADR 0004: no axis change). Back-face culling **off**, depth test on
   with `GL_LESS` as in the original (set through `vendor:OpenGL`, since raylib leaves `GL_LEQUAL`).
4. **Camera and image pipeline**: the original's matrices (ADR 0004, decision 3), render at 2× into a render texture,
   downsample with a truncating 2×2 mean, the grid as the original draws it (§7.4). Depth precision: 16-bit, like
   the original's OSMesa context; the grid: 2-px `GL_LINES`. Both were chosen by the measurement against the oracle
   PNGs ("Measurement", #204). The oracle's channel order is BGR.
5. **The pixel tolerance is not set here.** It is an **open question for Ander** (`CLAUDE.md`: tolerances only with
   his OK): the prototype measures, per test image, the differences against the oracle PNGs (count and size of
   differing pixels, max channel delta), recorded under "Measurement" (#204), and the value is put to Ander with that
   evidence (escalated in #204; pending).
   Until then the comparison reports differences and does not pass by tolerance. This measurement against the oracle
   PNGs is local and by hand, like their regeneration (ADR 0002, "Consequences": they depend on the Mesa version and
   CI does not compare them pixel by pixel). Once accepted, our own reference-path images become the golden images
   in `tests/golden/` (`./build.sh test-golden`, `docs/architecture.md`), and CI compares against those.

## Alternatives
For the reference path:
- **Instanced sphere + cylinder** (one unit icosphere per level and one unit 10-face pillar, transformed per joint
  and limb). Fewer vertices to upload; but a truncated cone with another ratio of end radii is not an affine image
  of a unit mesh (and its axis-perpendicular normals would need per-instance fixing), the pillar's basis depends on
  where the limb is (`(1, 1, 1)` is a point, §7.1), and the fat triangles are not instances: exact only with
  per-instance geometry, i.e. most of the CPU work anyway. Acceptable for the spheres (decision 2).
- **raylib shape helpers / capsules** (`DrawSphere`, `DrawCylinderEx`, `DrawCapsule`). Least code, but different
  meshes (UV spheres, other segment counts, caps), unlit by default, and no fat triangles: visibly different from the
  oracle images.
- **SDF raymarching** (spheres, cones and slabs as distance functions). Smooth and resolution-independent, good for
  the modern path, but it renders the ideal shapes, not the original's faceted meshes and Gouraud shading: it cannot
  match the PNGs.
- **Per-pixel lighting in the reference path.** Better looking, but different from the original's per-vertex
  interpolation on coarse meshes (visible on the level-1 spheres): it belongs to the modern path.
- **Port the shader renderer of the web editor** (point lights, `src/triangle.vertexshader`). It is not what the
  oracle images use, and it looks different (§7.3).

## Consequences
- `render` gets a mesh builder that mirrors `src/playerdrawer.cpp` and `src/icosphere.cpp` and is unit-tested on
  vertex counts and on values computed by hand from the formulas; ideally `body.json` of the oracle sample also
  carries the mesh constants (ADR 0002).
- A small custom shader (per-vertex lighting) is part of the reference path; the default raylib shader is used only
  for unlit overlays.
- Culling and depth state are set explicitly by `render`, never left to raylib's defaults.
- The modern path (phase 4) can change looks freely without touching the golden tests.

### Open points (need the phase-3 prototype or the oracle images, #35)
- **Resolved, #204 ("Measurement" below):**
  - Per-vertex lighting in GLSL with `f32` vertices reproduces OSMesa's pixels on the bodies to within a few edge
    pixels, provided the depth buffer is 16-bit like the original's.
  - OSMesa's channel order is BGR, as §7.6 says.
  - The lighting defaults hold: body pixels away from the edges are equal.
- **Pending: the pixel tolerance (decision 5).** It is Ander's call, with the measurement below. Not set here.
- Whether a pillar basis ever degenerates on the DB (`docs/original.md` §7.1, section 10).
- Per-frame mesh rebuild vs instanced spheres (decision 2): by measurement, if either matters at all. **#199
  prototype:** per-frame rebuild with `rlUpdateVertexBuffer` into our own VAO (one VBO per attribute) is what
  `src/render/reference.odin` does. Measured on the real DB's node 0 (`-o:speed`, Mesa llvmpipe under Xvfb, 300
  frames, two runs): `build_body` 0.28–0.43 ms per frame (22 740 vertices) against 15–18 ms for the whole frame at 1280×720, so
  instancing is not pursued unless a later measurement says otherwise.
- `GL_LESS` (decision 3) is set with `vendor:OpenGL` loaded through `rlgl.GetProcAddress` (raylib's own GLFW
  context); `draw_scene` saves and restores raylib's depth function, depth test and culling around the 3D pass.
- Grid of the interactive path (#199, epic #5 point 10): drawn as the original's shader-path quads, 0.02 m wide in
  world space (`src/rendering.cpp:267-289`), not `GL_LINES`, because a core-profile context only guarantees 1-px
  lines. The oracle images use 2-px aliased `GL_LINES` at 2× (≈ 1 px after the 2×2 mean); the difference is measured
  in #204, not tuned here.
  - **#204, interactive path:** it keeps the quads on Linux and macOS alike, so its grid looks the same everywhere.
  - **#204, images (`--image`, golden):** they draw `GL_LINES` 2 px wide (`Grid_Style.Lines`), lit by the reference
    shader like the original's lit lines (normal `(0, 1, 0)` gives a light factor of 1.0106, so `0.8·bg` becomes
    0.808, not 0.8).
  - **macOS:** a forward-compatible context (`GL_CONTEXT_FLAGS`) or an aliased line range below 2 px makes
    `effective_grid_style` fall back to quads with a warning. `--image` on macOS is therefore not the golden image;
    the golden images are rendered on Linux in `tools/golden/Dockerfile`.

### Measurement (#204)
**Method:** `./build.sh golden-measure <grid> <depth>` in `tools/golden/Dockerfile` (Mesa 25.2.8, softpipe), against
the 6 oracle PNGs (OSMesa 20.0.8, softpipe), with the oracle's BGR swapped back. Images are 480×360 (172 800 px),
heading N, white background.

**Columns:** `differing` = pixels with any channel different; `region` = the largest 4-connected blob of differing
pixels; `Δ` = the largest channel difference.

**Options compared:**
- `quads` = the 0.02 m quads of the interactive grid; `lines` = `GL_LINES` 2 px wide.
- `raylib` = raylib's unsized depth renderbuffer (24 bits on Mesa); `16` = `GL_DEPTH_COMPONENT16`, like
  `OSMesaCreateContextExt(OSMESA_RGB, 16, 0, 16)`.

| image | quads, raylib | quads, 16 | lines, raylib | **lines, 16** |
|---|---|---|---|---|
| p96  | 7785 / 3948 / 149 | 5966 / 3948 / 49 | 5978 / 957 / 149 | **4159 / 957 / 25** |
| p165 | 9566 / 3230 / 123 | 7879 / 3226 / 49 | 2625 / 325 / 123 | **936 / 324 / 25** |
| p223 | 9788 / 6171 / 240 | 7592 / 6159 / 49 | 2967 / 239 / 240 | **768 / 239 / 25** |
| p267 | 9415 / 3908 / 141 | 7312 / 3866 / 49 | 2946 / 251 / 141 | **839 / 251 / 25** |
| p288 | 9408 / 3226 / 200 | 8163 / 3224 / 49 | 2116 / 315 / 200 | **869 / 313 / 25** |
| p304 | 9555 / 3244 / 180 | 7192 / 3240 / 49 | 3104 / 284 / 180 | **736 / 284 / 25** |

Each cell is differing / region / Δ.

- **Choice:** `lines` + `16` is what `--image` and the golden images use (`render.IMAGE_OPTIONS_DEFAULT`).
- **The 16-bit depth** removes the large Δ: 123–240 with raylib's depth, 49 (quads) or 25 (lines) with 16 bits.
  With the deeper buffer, surfaces that touch resolve differently from the original [unverified: inferred from where
  the differences lie].
- **`lines`** removes the large regions of the quads, whose grid is a different shape.
- **What remains with `lines` + `16`**, split by whether the pixel is grey (`r = g = b`) in both images (grid or
  background) or not (body). This split was computed with a one-off script over the `-run1.png` files; it is not part
  of `measure`:

  | image | grid/background | body | body Δ |
  |---|---|---|---|
  | p96  | 4129 | 30 | 25 |
  | p165 | 918  | 18 | 15 |
  | p223 | 742  | 26 | 25 |
  | p267 | 800  | 39 | 25 |
  | p288 | 855  | 14 | 18 |
  | p304 | 717  | 19 | 25 |

  - **Grid:** the difference is whole grid lines rasterised one pixel row apart, mostly near-horizontal ones. In p96
    four lines differ, hence its larger count and its region of 957. The cause, wide-line rasterisation in Mesa 20
    vs Mesa 25 or `f32` vs `double` in the vertex transform, is [unverified] and was not tuned.
  - **Bodies:** they differ in at most 39 edge pixels per image.
- **Determinism:** with `lines` + `16`, two invocations of `golden-measure`, each rendering every image twice, gave
  identical bytes for all 6 images. The other three settings were also identical across their two runs.
