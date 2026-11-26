# Plan: #198 feat(render): reference mesh builder (icospheres, pillars, fat triangles)
Spec: docs/specs/phase-3-viewer.md (deliverable 4) · ADR 0006 d2, ADR 0003, ADR 0004 d2 · docs/original.md §3.1, §3.2,
§7.1, §7.2 · `src/icosphere.cpp`, `src/playerdrawer.{hpp,cpp}`, `src/positions.cpp:138-140` (in
`reference/GrappleMap`) · `tests/fixtures/oracle/body.json` (`draw` block)

## Pasos
1. **`src/render/constants.odin`** (new), named with their source lines: `ICO_X_F32 :: f32(0.525731112119133606)`,
   `ICO_Z_F32 :: f32(0.850650808352039932)` (the original's `float` constants, `src/icosphere.cpp:16-18`; widened to
   `f64` at run time, never as an `f64` constant expression, `src/core/CLAUDE.md`); `@(rodata) ICO_VERTICES`
   (12, that order) and `ICO_TRIANGLES` (20, that order) (`src/icosphere.cpp:20-29`); `PILLAR_FACES :: 10`
   (`src/playerdrawer.hpp:32`); `SPHERE_FINE :: 2`, `SPHERE_COARSE :: 1` (`src/playerdrawer.cpp:144-147`);
   `@(rodata) FINE_JOINTS` (`Head`, `Core`, both hips, both shoulders, `src/playerdrawer.cpp:269-272`);
   `OVERRIDE_RADIUS_DELTA :: 0.005` (`src/playerdrawer.cpp:262`); `PILLAR_SIDE_REFERENCE :: core.V3{1, 1, 1}`
   (`src/playerdrawer.cpp:197`); `@(rodata) FAT_TRIANGLES` (the five joint triples in `drawPlayers` order,
   `src/playerdrawer.cpp:370-374`). Player colours come from `core.PLAYER_COLORS`, radii from `core.JOINT_DEFS`,
   limbs from `core.SEGMENTS` (not redefined).
2. **`src/render/mesh.odin`** (new). All geometry in `f64` with the original's operation order (ADR 0003 d4: no FMA,
   no reassociation; `V3` arithmetic component-wise as `BasicV3`), converted to `f32` only when written out:
   - `normalize(v)` = `v / sqrt(x·x + y·y + z·z)` (`src/math.hpp:186-193`, division per component); `cross` as
     `src/math.hpp:100-107`.
   - `Icosphere :: struct {vertices: []core.V3, triangles: [][3]int}`; `icosphere_make(subdivisions, allocator)`
     (`src/icosphere.cpp:30-87`): start from the 12/20 tables (widened `f32`), each pass splits every triangle in 4
     with `vertex_for_edge` (key = sorted index pair, new vertex = `normalize(e0 + e1)` appended in first-use order;
     output triangles `{v0, m0, m2}, {v1, m1, m0}, {v2, m2, m1}, {m0, m1, m2}` in that order). A map keyed by the
     pair (`map[[2]int]int` on the given allocator, freed at the end). Levels 1 and 2 built once (`Mesh_Builder`
     owns both; `mesh_builder_init/destroy`).
   - `Body_Mesh :: struct {positions, normals: [dynamic][3]f32, colors: [dynamic][3]f32}` (non-indexed triangle
     list, three vertices per triangle); `body_mesh_clear`.
   - `emit_sphere(b, mesh, center, radius, color, out)`: per triangle the vertices `2, 1, 0` (reversed,
     `src/playerdrawer.cpp:149-166`), position `center + v·radius`, normal `v`.
   - `pillar_angles() -> [PILLAR_FACES + 1][2]f64`: `s = 2·core.PI / 10`, `(cr_sin(f64(i)·s), cr_cos(f64(i)·s))`
     (`src/playerdrawer.cpp:178-184`; `core.cr_*`, never libm). Computed once in the builder.
   - `emit_pillar(from, to, r_from, r_to, color, out)` (`src/playerdrawer.cpp:221-241`, the shader version: two
     triangles per face, ADR 0006 d2): `a = normalize(cross(to − from, (1,1,1) − from))`,
     `b = normalize(cross(to − from, a))`; per face `i` the six vertices in the order of that function, each
     position `from + a·r·sinᵢ + b·r·cosᵢ` evaluated as `((from + (a·r)·sinᵢ) + (b·r)·cosᵢ)`, normals
     `a·sinᵢ + b·cosᵢ` (perpendicular to the axis). `assert` no NaN in debug (degenerate basis never occurs on the
     DB, §10.3).
   - `emit_fat_triangle(a, ra, b, rb, c, rc, color, out)` (`src/playerdrawer.cpp:15-100`): `ab, bc, ca, fwd`, the
     twelve points and the 42 vertices (14 triangles) with their normals exactly in the code order.
   - `build_body(builder, pos: core.Position, overrides: ^[core.PLAYER_COUNT][core.Joint]Maybe(core.V3), out)`
     in `drawPlayers` order (`src/playerdrawer.cpp:363-375`): (1) limbs: for each player, each visible segment of
     `core.SEGMENTS` in order, with `mid_radius` → two pillars through `mid = (a + b) / 2`; (2) joints: in
     `playerJoints` order (check `make_playerJoints`, `src/positions.cpp:120-138`, for player-major vs
     joint-major), radius + `OVERRIDE_RADIUS_DELTA` and the override colour when set, fine/coarse by
     `FINE_JOINTS`; (3) the five fat triangles, each for player 0 then 1. No first-person skip (out of scope, spec).
     `overrides = nil` is the normal case.
3. **`src/render/CLAUDE.md`**: `mesh.odin`/`constants.odin` bullets in its `## Ficheros` (added by #197).
   `changelog.d/198-render-mesh.md`. `./build.sh ci`.
   If over 400 hand-written lines: PR 1 = constants + icosphere + spheres + pillars; PR 2 = fat triangles +
   `build_body` (`-2` fragment).

## Ficheros a tocar
`src/render/constants.odin`, `src/render/mesh.odin`, `src/render/mesh_test.odin` (new), `src/render/CLAUDE.md`,
`changelog.d/198-render-mesh.md` (+ this plan). Not touched: `src/core/`, `camera.odin`, `build.sh` (already runs
`src/render` tests since #206), `src/main.odin`, `.github/`, `reference/`.

## Tests a escribir primero
`src/render/mesh_test.odin`; expected `f64` values computed outside Odin (Python with the same operations,
`struct.pack('f', …)` for the `float` constants), compared by bits; `f32` outputs compared by bits too:
- `ICO_X_F32`/`ICO_Z_F32` widened: bits of `(double)0.525731112119133606f` / `…932f`.
- `icosphere_make(1)`: 42 vertices, 80 triangles; `(2)`: 162 / 320; first new vertex and the first four output
  triangles of level 1 by index; 2-3 vertices of each level by bits against Python (no tolerance anywhere).
- `pillar_angles`: entries 0, 1, 5 and 10 by bits (10 is not `(0, 1)`: `sin(10·s) ≈ 7e-7`, the open seam).
- `emit_pillar` on a hand case (`from = (0, 0, 0)`, `to = (0, 1, 0)`, radii 0.05/0.03): 60 vertices; `a`, `b`, the
  first face's six positions and normals by bits against Python.
- `emit_fat_triangle` on a hand triangle: 42 vertices, `fwd`, `aleft`, `cdown` and the normal of each of the 12
  points by bits; the order of the first and the back triangle.
- `build_body` on a real position (block 96 is not available without the file system: a hand position with the 23
  joints of the oracle sample copied as literals, or `gap_position`-like data): total vertex count =
  3·(Σ pillars·20 + 2·(6·320 + 17·80) + 2·5·14); first vertex is the first visible segment's first pillar vertex;
  an override grows that joint's sphere by 0.005 and recolours only it.
- The `draw` block of `tests/fixtures/oracle/body.json` (`#load` + `core:encoding/json` in the test):
  `pi`, `pillar_faces`, `pillar_side_reference`, subdivisions, `fine_sphere_joints`, `highlight_extra_radius`,
  `fat_triangles` equal the constants (joint indices map to `core.Joint`).

## Riesgos
- Operation order is the whole point: every expression mirrors the C++ (`a * r * s` is `(a·r)·s`; `x - y * z`).
  The reviewer checks each against `src/playerdrawer.cpp`.
- The `vertex_for_edge` new-vertex order depends on visiting edges in triangle order and the `insert` semantics of
  `std::map` (the first insertion wins): port it literally.
- `playerJoints` order decides the draw order of spheres, which matters for equal-depth pixels under `GL_LESS`:
  verify in the source, do not assume.
- Allocation: `Body_Mesh` grows on the caller's allocator (per frame: `context.temp_allocator`); the builder's
  icospheres on the long-lived one; tests run under the tracking allocator (zero leaks).

## Criterio de hecho
`./build.sh ci` and CI green with the mesh tests run; tests red first; zero leaks; `code-reviewer` (opus, `render`)
without blockers; `src/render/CLAUDE.md` and changelog fragment updated.
