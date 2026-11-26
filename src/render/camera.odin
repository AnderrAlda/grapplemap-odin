package render

import "app:core"
import rl "vendor:raylib"

IMAGE_FOV :: 45 // ImageMaker::png projection fov (degrees), src/images.cpp:316

// M is a column-major 4×4 matrix of f64, like the original's `M` (src/math.hpp:70): entry (row r, column c) is
// `m[4·c + r]`.
M :: [16]f64

// mat_mul is `operator*(M, M)` (src/math.hpp:211-232): each entry as the original's left-to-right sum of four
// products.
mat_mul :: proc(a, b: M) -> M {
	o: M
	for c in 0 ..< 4 {
		for r in 0 ..< 4 {
			o[4 * c + r] =
				a[r] * b[4 * c] +
				a[4 + r] * b[4 * c + 1] +
				a[8 + r] * b[4 * c + 2] +
				a[12 + r] * b[4 * c + 3]
		}
	}
	return o
}

// yrot is `yrot` (src/math.hpp:73-81).
yrot :: proc(a: f64) -> M {
	c := core.cr_cos(a)
	s := core.cr_sin(a)
	return {c, 0, -s, 0, 0, 1, 0, 0, s, 0, c, 0, 0, 0, 0, 1}
}

// xrot is `xrot` (src/math.hpp:83-91).
xrot :: proc(a: f64) -> M {
	c := core.cr_cos(a)
	s := core.cr_sin(a)
	return {1, 0, 0, 0, 0, c, -s, 0, 0, s, c, 0, 0, 0, 0, 1}
}

// translate is `translate` (src/math.hpp:93-100).
translate :: proc(v: core.V3) -> M {
	return {1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, v.x, v.y, v.z, 1}
}

// perspective is `perspective` (src/math.hpp:116-125). `tan` is `sin/cos` with the `cr_*` functions (what Odin's
// `math.tan_f64` does with libm): glibc's `tan` is not ported, and nothing compares the camera with the oracle bit
// for bit.
perspective :: proc(fovy, aspect, near, far: f64) -> M {
	x := fovy * core.PI / 360
	f := 1 / (core.cr_sin(x) / core.cr_cos(x))
	return {
		f / aspect,
		0,
		0,
		0,
		0,
		f,
		0,
		0,
		0,
		0,
		(far + near) / (near - far),
		-1,
		0,
		0,
		2 * far * near / (near - far),
		0,
	}
}

// Camera is the original's `Camera` (src/camera.hpp:10-14) without the cached matrices. orientation: x yaw (around
// y), y pitch (around x), z distance.
Camera :: struct {
	offset:      core.V3,
	orientation: core.V3,
	fov:         f64,
}

camera_default :: proc(fov: f64) -> Camera {
	return Camera{offset = {}, orientation = core.CAMERA_DEFAULT_ORIENTATION, fov = fov}
}

// rotate_horizontal is `rotateHorizontal`: unbounded.
rotate_horizontal :: proc(c: ^Camera, radians: f64) {
	c.orientation.x += radians
}

// rotate_vertical is `rotateVertical`: clamped to [−PI/2, PI/2], max first, then min.
rotate_vertical :: proc(c: ^Camera, radians: f64) {
	c.orientation.y += radians
	c.orientation.y = max(-core.PI / 2, c.orientation.y)
	c.orientation.y = min(core.PI / 2, c.orientation.y)
}

// zoom is `zoom`: unclamped (the viewer's minimum distance is #201's).
zoom :: proc(c: ^Camera, z: f64) {
	c.orientation.z += z
}

hard_set_offset :: proc(c: ^Camera, o: core.V3) {
	c.offset = o
}

// model_view is `computeMv` (src/camera.hpp:17-21): `translate(0,0,−z) · xrot(pitch) · yrot(yaw) · translate(−offset)`,
// left-associative as C++ parses it.
model_view :: proc(c: Camera) -> M {
	a := mat_mul(translate({0, 0, -c.orientation.z}), xrot(c.orientation.y))
	b := mat_mul(a, yrot(c.orientation.x))
	return mat_mul(b, translate(-c.offset))
}

// projection is `perspective(fov, w/h, 0.01, 15)` (src/camera.hpp:34).
projection :: proc(c: Camera, aspect: f64) -> M {
	return perspective(c.fov, aspect, core.CAMERA_NEAR, core.CAMERA_FAR)
}

// camera_offset_for is `cameraOffsetFor` (src/positions.hpp:182-187): the midpoint of the cores, y lowered.
camera_offset_for :: proc(p: core.Position) -> core.V3 {
	r := core.center(p)
	r.y = max(0, r.y - core.CAMERA_OFFSET_Y_DROP)
	return r
}

// heading_angle is `angle(Heading)` (src/headings.hpp:65-68), in that operation order.
heading_angle :: proc(h: int) -> f64 {
	return core.PI * 0.5 * f64(h)
}

// image_camera is the camera of `ImageMaker::png` (src/images.cpp:302-316).
image_camera :: proc(ymax: f64, heading: int) -> Camera {
	c := camera_default(IMAGE_FOV)
	hard_set_offset(&c, {0, ymax - core.IMAGE_CAMERA_Y_DROP, 0})
	zoom(&c, core.IMAGE_CAMERA_ZOOM)
	rotate_horizontal(&c, heading_angle(heading))
	rotate_vertical(&c, (ymax - core.IMAGE_CAMERA_PITCH_Y_DROP) / core.IMAGE_CAMERA_PITCH_DIVISOR)
	return c
}

// to_raylib converts to `rl.Matrix` (`#row_major matrix[4, 4]f32`): element (r, c) = f32(m[4·c + r]), one
// conversion per element (ADR 0004 d3).
to_raylib :: proc(m: M) -> rl.Matrix {
	r: rl.Matrix
	for c in 0 ..< 4 {
		for row in 0 ..< 4 {
			r[row, c] = f32(m[4 * c + row])
		}
	}
	return r
}
