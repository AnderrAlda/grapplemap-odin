# 0004. Axes and units
Status: Proposed
Date: 2026-11-21

## Context
Paths `src/…` are in `reference/GrappleMap`; paths `vendor/…` and `core/…` are in the pinned Odin distribution
(`.odin-version` = `dev-2026-11a`), whose `vendor:raylib` is raylib **6.2** (`vendor/raylib/raylib.odin:154`).

**The original** (`docs/original.md` §4): lengths in **meters** with no scale factor between file and world
(`src/persistence.cpp:53`), angles in radians except `perspective`'s `fovy` in degrees (`src/math.hpp:116-118`),
`pi()` = `3.141593` (`src/math.hpp:12`). `y` is up and the floor is `y = 0`; the horizontal plane is `xz`; mirror is
`x ↦ −x`. The world is **right-handed**: matrices are column-major `double[16]` loaded unchanged with
`glLoadMatrixd` (`src/rendering.cpp:341-354`), `perspective` is the `gluPerspective` matrix (`m[11] = −1`,
`src/math.hpp:116-125`), so the eye looks down `−z`, and the model-view is only rotations and translations
(`src/camera.hpp:18`). Rotations about `y` have the sign of `yrot`/`angle` (§4.2).

**raylib 6.2, as checked** (not assumed):
- `Matrix` is documented "right handed" (`vendor/raylib/raylib.odin:201`); upstream raylib 6.2 `raymath.h` and
  `raylib.h` say "OpenGL style 4x4 - right handed, column major". In Odin it is `#row_major matrix[4, 4]f32`
  (`vendor/raylib/raylib.odin:202`): the memory layout differs from the original's `M`, the maths does not.
  Vectors are `f32` (`vendor/raylib/raylib.odin:192,194`).
- `MatrixLookAt` and `MatrixPerspective` in the Odin binding are `linalg.matrix4_look_at` and
  `linalg.matrix4_perspective` (`vendor/raylib/raymath.odin:670-677`): the eye looks down `−f` (third row `−f`,
  `core/math/linalg/specific.odin:2157-2170`) and the projection uses the OpenGL convention by default
  (`flip_z_axis := true`, `core/math/linalg/specific.odin:2261-2274`). `fovY` is in **radians** there
  (`vendor/raylib/raymath.odin:668`). Upstream 6.2 `MatrixPerspective` sets `m11 = −1.0f`, like `gluPerspective`.
- `Camera3D` has `position`, `target`, `up` and `fovy` in **degrees** (`vendor/raylib/raylib.odin:282-288`).
  `BeginMode3D` (compiled C, `rcore.c`) builds the projection with `rlFrustum` from
  `top = near·tan(fovy·0.5·DEG2RAD)` with `DEG2RAD = PI/180` and `PI` = the true π
  (`vendor/raylib/raylib.odin:156-157`), and the view with the C `MatrixLookAt` (upstream 6.2 `src/rcore.c`; the
  pinned toolchain ships only `libraylib.a`, so this was read in the upstream 6.2 source).
- **Clip planes**: `BeginMode3D` uses `rlGetCullDistanceNear/Far`. In the compiled `libraylib.a` they default to
  **0.05** and **4000.0** (the `double`s read by `rlGetCullDistanceNear` in `rcore.o`'s `.data`), not the
  `rlgl.CULL_DISTANCE_NEAR :: 0.01` / `FAR :: 1000.0` constants of the binding (`vendor/raylib/rlgl/rlgl.odin:204-205`,
  which are only constants; its own header comment says 0.05/4000, `vendor/raylib/rlgl/rlgl.odin:56-57`). They can be
  changed with `rlgl.SetClipPlanes` (`vendor/raylib/rlgl/rlgl.odin:403`); the matrices can be replaced outright with
  `rlgl.SetMatrixProjection`/`SetMatrixModelview` (`vendor/raylib/rlgl/rlgl.odin:596-597`).

So raylib's world and eye conventions are the same as the original's: right-handed, `y` up when `up = (0, 1, 0)`,
eye looking down `−z`, OpenGL clip space. raylib has no unit; meters are a choice.

## Decision
1. **The original's coordinates are used as-is**: meters, `y` up, floor `y = 0`, right-handed, mirror `x ↦ −x`. No
   axis swap, flip or scale anywhere, neither in `core` nor at the render boundary. A joint at `(x, y, z)` in a
   `core` position is drawn at `(f32(x), f32(y), f32(z))`.
2. **`f64 → f32` happens only in `render`**, when a value is handed to raylib (ADR 0003, decision 3): joint
   positions and generated vertices per frame (ADR 0006), and camera matrices. Nothing converted to `f32` flows back
   into `core`.
3. **Camera matrices for fidelity are computed with the original's formulas**, in `f64`, and given to rlgl:
   projection = `perspective(fov, aspect, 0.01, 15)` with `pi()` = `3.141593` (`src/math.hpp:116-125`,
   `src/camera.hpp:34`); model-view = `translate(0, 0, −zoom)·xrot(pitch)·yrot(yaw)·translate(−offset)`
   (`src/camera.hpp:18`). They are not rebuilt from a `Camera3D`: `BeginMode3D` would use the true π, raylib's
   near/far (0.05/4000 instead of 0.01/15) and `f32` throughout, which changes the projection, the depth range
   and hence pixels (ADR 0006). Converting the original's column-major `M` (`m[4·c + r]`, `src/math.hpp:91-98,197-204`)
   to raylib's `Matrix` is element `(r, c) = f32(M[4·c + r])`, one conversion per element. Whether the interactive
   UX camera (phase 3) may use `Camera3D` instead is left to phase 3: it is not compared with the oracle. First-person
   views use `gluLookAt(Head, (LeftHand + RightHand)/2, Head − Neck)` (`src/rendering.cpp:346-352`); if a phase needs
   them, that matrix is rebuilt with the `gluLookAt` formula in `f64` too.
4. **Axis-dependent constants are kept verbatim in `core`** (`docs/original.md` §4.4): the `−2` offset on `x` and
   `z` only in the encoding (§1.3, `src/persistence.cpp:53`); the `apply_limits` box `x, z ∈ [−2, 2]`,
   `y ≥ radius` (`src/positions.cpp:318-320`); `cameraOffsetFor`'s `y = max(0, y − 0.5)` (`src/positions.hpp:182-187`);
   the editor's `y · 0.7` target (`src/editor_canvas.cpp:539-544`); the image camera's `ymax − 0.57`, `+0.55` distance
   and `(ymax − 0.6)/2` pitch (`src/images.cpp:302-316`); the default orientation `{0, −0.6, 1.7}`
   (`src/camera.hpp:12`); `pi()` = `3.141593` wherever the original uses `pi()` (ADR 0003, decision 7). They are
   copied with their signs, since the axes are not changed. `core` owns them as named constants; the camera code of
   `render`/`ui` (decision 3) reads them from `core`, it does not redefine them.
5. **Angles in radians** in `core`; degrees only where the original takes degrees (`perspective`'s `fovy`), converted
   with the original's `fovy·pi()/360`, not raylib's `DEG2RAD`.

## Alternatives
- **Use raylib's `Camera3D` and `BeginMode3D` for every view.** Less code, but a different π, different clip planes
  (0.05/4000 vs 0.01/15) and `f32` matrices: the golden images would differ from the oracle's for reasons that are
  not bugs in our geometry.
- **Convert to another convention** (e.g. `z` up, or left-handed for a future backend). No current consumer needs
  it; it would put a flip in every transform and every test, and the oracle's numbers would stop being directly
  comparable.
- **Scale to centimeters** (or another unit) for nicer numbers. Every threshold of the original (`0.0016` m²,
  `0.05`, joint radii, `apply_limits`) would have to be rescaled, with new rounding.

## Consequences
- `core` tests compare against the oracle's numbers with no axis mapping. `render` needs only an element-wise
  `f64 → f32` and a layout change for matrices.
- `render` owns a small `f64` camera module that mirrors `src/camera.hpp` and `src/math.hpp:73-125`, using the
  constants of decision 4 from `core`; it is tested against the original's formulas (phase 3). Which package exposes
  camera presets to the user is `ui`'s concern (`docs/architecture.md`).
- Anything that uses raylib's own camera helpers (`Camera3D`, `UpdateCamera`, `GetWorldToScreen`, picking) must be
  checked against the same matrices, or not used for views compared with the oracle.

### Open points (not verifiable now)
- **On-screen orientation of the default camera** (`docs/original.md` §4.2, §4.5): **settled by the oracle PNGs
  (#35)**: with `yaw = 0` (heading N) world `+x` is screen right and the eye is on the `+z` side, as the algebra
  says (evidence: `tools/oracle/README.md`, "Reference images"). The images also flip vertically and swap channels
  0 and 2 before writing (`src/images.cpp:89,111-112`, §7.6); OSMesa's buffer is RGB, so the PNGs are BGR (player 0
  shows blue). Those belong to the image path, not to the world axes.
- **raylib's C internals** (`BeginMode3D`, `rlFrustum`) were read in the upstream 6.2 source, not in the pinned
  binary (only the clip-plane defaults and `rlglInit` were checked in `libraylib.a`). Decision 3 does not depend on
  them, since the matrices are set explicitly.
- **The JS viewers' handedness** (Babylon.js, `docs/original.md` §3.2): out of scope; the C++ renderer is the
  reference.
