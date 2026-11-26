# Plan: #197 feat(render): original f64 camera
Spec: docs/specs/phase-3-viewer.md (deliverable 3) · ADR 0004 (d3, d4, d5), ADR 0003 · docs/original.md §4.2, §4.3,
§7.5, §7.6 · `src/camera.hpp`, `src/math.hpp:73-125,211-232`, `src/positions.hpp:182-187`, `src/images.cpp:302-316`,
`src/headings.hpp:65-68` (in `reference/GrappleMap`) · review point 8 of
https://github.com/AnderrAlda/grapplemap-odin/issues/5#issuecomment-7193375287

## Pasos
1. **`src/render/camera.odin`** (new, `package render`, `import "app:core"`, `import rl "vendor:raylib"`). All
   `f64`, the original's formulas and operation order (ADR 0003 d4); trig with `core.cr_sin`/`core.cr_cos` (same
   bits on every target; never `math.sin/cos/tan`):
   - `M :: [16]f64`, column-major like the original (`m[4·c + r]`).
   - `mat_mul(a, b: M) -> M`: the original's `operator*` (`src/math.hpp:211-232`), each entry as
     `a[r]·b[4c] + a[4+r]·b[4c+1] + a[8+r]·b[4c+2] + a[12+r]·b[4c+3]`, left to right, no FMA.
   - `yrot(a)`, `xrot(a)`, `translate(v: core.V3)`: entries exactly as `src/math.hpp:73-100` (note `yrot`'s `−sin`
     at index 2 and `sin` at 8).
   - `perspective(fovy, aspect, near, far)`: `f = 1 / tan(fovy·PI/360)` with `tan(x) = cr_sin(x) / cr_cos(x)` (what
     Odin's `math.tan_f64` does with libm; record the choice: glibc's `tan` is not ported, nothing compares the
     camera with the oracle bit for bit), then the entries of `src/math.hpp:116-125`. `PI` = `core.PI`.
   - `Camera :: struct {offset: core.V3, orientation: core.V3 (x yaw, y pitch, z distance), fov: f64}`;
     `camera_default(fov)` with `orientation = core.CAMERA_DEFAULT_ORIENTATION`, `offset = 0`.
     `rotate_horizontal(c, r)` (`x += r`, unbounded), `rotate_vertical(c, r)` (`y += r`, then
     `max(−PI/2, ·)`, `min(PI/2, ·)` in that order), `zoom(c, z)` (`z += z`, unclamped: the viewer's minimum is
     #201's), `hard_set_offset(c, o)`. The per-frame `setOffset` smoothing is not here (time-based, #201).
   - `model_view(c) -> M` = `translate({0, 0, −z}) · xrot(y) · yrot(x) · translate(−offset)`, multiplied left to
     right as the C++ expression parses (`((T·X)·Y)·T2`). `projection(c, aspect) -> M` =
     `perspective(c.fov, aspect, core.CAMERA_NEAR, core.CAMERA_FAR)`.
   - `camera_offset_for(p: core.Position) -> core.V3` (`src/positions.hpp:182-187`): `between` of the two `Core`
     joints as `(a + b) / 2`, then `y = max(0, y − core.CAMERA_OFFSET_Y_DROP)`.
   - `heading_angle(h: int) -> f64` = `PI · 0.5 · f64(h)` (`src/headings.hpp:65-68`, that order);
     `image_camera(ymax: f64, heading: int) -> Camera` (`src/images.cpp:302-316`): default camera with
     `IMAGE_FOV :: 45` (named here, `src/images.cpp:316`), `hard_set_offset({0, ymax − IMAGE_CAMERA_Y_DROP, 0})`,
     `zoom(IMAGE_CAMERA_ZOOM)`, `rotate_horizontal(heading_angle(h))`,
     `rotate_vertical((ymax − IMAGE_CAMERA_PITCH_Y_DROP) / IMAGE_CAMERA_PITCH_DIVISOR)`, in that order (constants
     already in `core/types.odin:177-180`).
   - `to_raylib(m: M) -> rl.Matrix`: element `(r, c) = f32(m[4·c + r])` (ADR 0004 d3; `rl.Matrix` is
     `#row_major matrix[4, 4]f32`), one conversion per element.
2. **`build.sh`**: `TEST_PKGS` += `src/render`; `cmd_check` += `odin check src/render $COLLECTION $VET
   -no-entry-point` (`odin check src` does not reach it while `main` does not import it). `FMT_DIRS` already covers
   `src/`.
3. **`src/render/CLAUDE.md`**: a `## Ficheros` section with the `camera.odin` bullet (column-major `M`, original
   order, `cr_*` trig, `to_raylib` mapping). `changelog.d/197-render-camera.md`. `./build.sh ci`.

## Ficheros a tocar
`src/render/camera.odin`, `src/render/camera_test.odin` (new), `build.sh` (`TEST_PKGS`, `cmd_check`),
`src/render/CLAUDE.md`, `changelog.d/197-render-camera.md` (+ this plan). Not touched: `src/core/`, `src/main.odin`,
`.github/`, `reference/`.

## Tests a escribir primero
`src/render/camera_test.odin`; expected values as `f64` literals computed outside Odin (Python with the same
operations; Python's `math.sin`/`cos` are glibc's, correctly rounded on these arguments, so they equal `cr_*`;
compare bits with `transmute(u64)`):
- `translate`, `xrot(0.3)`, `yrot(0.3)`: every entry, including the signs of `yrot`'s off-diagonal terms.
- `mat_mul`: a non-commuting pair (`xrot·translate` ≠ `translate·xrot`), entries by bits.
- `perspective(45, 480.0/360, 0.01, 15)`: `f`, `f/aspect`, `(far+near)/(near−far)`, `2·far·near/(near−far)`, `−1`.
- `model_view(camera_default)`: equals `translate({0,0,−1.7})·xrot(−0.6)·yrot(0)·translate(0)` and, checked by hand,
  maps the origin to `(0, 0, −1.7)` and `+x` to `+x` (ADR 0004: yaw 0 → `+x` screen right).
- `rotate_vertical` clamps at `±PI/2` (`PI = 3.141593`, so the clamp is `1.5707965`); `rotate_horizontal`
  unbounded; `zoom` to negative allowed.
- `image_camera(0.8, 0)` and `(1.27, 3)`: `offset`, `orientation` bits against Python; `heading_angle(1..3)` bits.
- `camera_offset_for`: a hand position with `Core` y 0.4 → `y = 0`; y 1.2 → `0.7` bits.
- `to_raylib`: an `M` with entries `0..15` gives `rl.Matrix[r, c] == f32(4c + r)`.

## Riesgos
- `odin test src/render` links raylib (no window is opened; only `rl.Matrix` is used): if linking fails in the
  test job on macOS/Linux, keep `to_raylib` in a file the tests do not need, or escalate. Check in the local and
  CI runs.
- Operation order in `model_view`: the C++ `a * b * c * d` is left-associative; a test with non-trivial `offset`,
  pitch and yaw pins it.
- `tan` as `sin/cos`: documented, not toleranced (no oracle comparison).

## Criterio de hecho
`./build.sh ci` and CI green with the `src/render` tests actually run (seen in the output); new tests red first;
zero leaks; `code-reviewer` (opus: `src/render`) without blockers; `src/render/CLAUDE.md` and changelog fragment.
