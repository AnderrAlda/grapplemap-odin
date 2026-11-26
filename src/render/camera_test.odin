package render

import "app:core"
import "core:testing"

// Expected values are f64 bit patterns computed outside Odin with the original's operations (Python, glibc sin/cos
// are correctly rounded on these arguments, so they equal core.cr_sin/cr_cos). Compared with transmute, never with
// a tolerance (ADR 0003).

bits :: proc(x: f64) -> u64 {
	return transmute(u64)x
}

expect_m :: proc(t: ^testing.T, got: M, want: [16]f64, loc := #caller_location) {
	for i in 0 ..< 16 {
		testing.expectf(
			t,
			bits(got[i]) == bits(want[i]),
			"entry %d: got %h, want %h",
			i,
			got[i],
			want[i],
			loc = loc,
		)
	}
}

@(test)
test_translate :: proc(t: ^testing.T) {
	expect_m(
		t,
		translate({1.5, -2.25, 0.125}),
		{
			0h3ff0000000000000,
			0h0000000000000000,
			0h0000000000000000,
			0h0000000000000000,
			0h0000000000000000,
			0h3ff0000000000000,
			0h0000000000000000,
			0h0000000000000000,
			0h0000000000000000,
			0h0000000000000000,
			0h3ff0000000000000,
			0h0000000000000000,
			0h3ff8000000000000,
			0hc002000000000000,
			0h3fc0000000000000,
			0h3ff0000000000000,
		},
	)
}

@(test)
test_xrot :: proc(t: ^testing.T) {
	expect_m(
		t,
		xrot(0.3),
		{
			0h3ff0000000000000,
			0h0000000000000000,
			0h0000000000000000,
			0h0000000000000000,
			0h0000000000000000,
			0h3fee921dd42f09ba,
			0hbfd2e9cd95baba33,
			0h0000000000000000,
			0h0000000000000000,
			0h3fd2e9cd95baba33,
			0h3fee921dd42f09ba,
			0h0000000000000000,
			0h0000000000000000,
			0h0000000000000000,
			0h0000000000000000,
			0h3ff0000000000000,
		},
	)
}

@(test)
test_yrot :: proc(t: ^testing.T) {
	// −sin at index 2, +sin at index 8.
	expect_m(
		t,
		yrot(0.3),
		{
			0h3fee921dd42f09ba,
			0h0000000000000000,
			0hbfd2e9cd95baba33,
			0h0000000000000000,
			0h0000000000000000,
			0h3ff0000000000000,
			0h0000000000000000,
			0h0000000000000000,
			0h3fd2e9cd95baba33,
			0h0000000000000000,
			0h3fee921dd42f09ba,
			0h0000000000000000,
			0h0000000000000000,
			0h0000000000000000,
			0h0000000000000000,
			0h3ff0000000000000,
		},
	)
}

@(test)
test_mat_mul_non_commuting :: proc(t: ^testing.T) {
	x := xrot(0.3)
	tr := translate({1.5, -2.25, 0.125})
	expect_m(
		t,
		mat_mul(x, tr),
		{
			0h3ff0000000000000,
			0h0000000000000000,
			0h0000000000000000,
			0h0000000000000000,
			0h0000000000000000,
			0h3fee921dd42f09ba,
			0hbfd2e9cd95baba33,
			0h0000000000000000,
			0h0000000000000000,
			0h3fd2e9cd95baba33,
			0h3fee921dd42f09ba,
			0h0000000000000000,
			0h3ff8000000000000,
			0hc000e68991038a90,
			0h3fe9194b02f7f2b0,
			0h3ff0000000000000,
		},
	)
	expect_m(
		t,
		mat_mul(tr, x),
		{
			0h3ff0000000000000,
			0h0000000000000000,
			0h0000000000000000,
			0h0000000000000000,
			0h0000000000000000,
			0h3fee921dd42f09ba,
			0hbfd2e9cd95baba33,
			0h0000000000000000,
			0h0000000000000000,
			0h3fd2e9cd95baba33,
			0h3fee921dd42f09ba,
			0h0000000000000000,
			0h3ff8000000000000,
			0hc002000000000000,
			0h3fc0000000000000,
			0h3ff0000000000000,
		},
	)
}

@(test)
test_perspective :: proc(t: ^testing.T) {
	expect_m(
		t,
		perspective(45, 480.0 / 360, 0.01, 15),
		{
			0h3ffcf87691583746,
			0h0000000000000000,
			0h0000000000000000,
			0h0000000000000000,
			0h0000000000000000,
			0h4003504f0b9024d9,
			0h0000000000000000,
			0h0000000000000000,
			0h0000000000000000,
			0h0000000000000000,
			0hbff0057708b5b5e1,
			0hbff0000000000000,
			0h0000000000000000,
			0h0000000000000000,
			0hbf947e60a96a0e01,
			0h0000000000000000,
		},
	)
}

@(test)
test_model_view_default :: proc(t: ^testing.T) {
	c := camera_default(90)
	mv := model_view(c)
	expect_m(
		t,
		mv,
		{
			0h3ff0000000000000,
			0h0000000000000000,
			0h0000000000000000,
			0h0000000000000000,
			0h0000000000000000,
			0h3fea69263c485b15,
			0h3fe2118d17a54159,
			0h0000000000000000,
			0h0000000000000000,
			0hbfe2118d17a54159,
			0h3fea69263c485b15,
			0h0000000000000000,
			0h0000000000000000,
			0h0000000000000000,
			0hbffb333333333333,
			0h3ff0000000000000,
		},
	)
	// The origin maps to (0, 0, −1.7) and +x stays +x (yaw 0: +x is screen right, ADR 0004).
	testing.expect_value(t, mv[12], 0)
	testing.expect_value(t, mv[13], 0)
	testing.expect_value(t, mv[14], -1.7)
	testing.expect_value(t, mv[0], 1)
	testing.expect_value(t, mv[1], 0)
	testing.expect_value(t, mv[2], 0)
}

@(test)
test_model_view_order :: proc(t: ^testing.T) {
	// Non-trivial offset, pitch and yaw pin the left-to-right order ((T·X)·Y)·T2.
	c := Camera {
		offset      = {0.4, 0.9, -0.3},
		orientation = {0.7, -0.35, 2.2},
		fov         = 45,
	}
	expect_m(
		t,
		model_view(c),
		{
			0h3fe87996529f9d93,
			0h3fcc467a7d93624a,
			0hbfe35d799669bc02,
			0h0000000000000000,
			0h0000000000000000,
			0h3fee0f575d0de5b7,
			0h3fd5f209a5390a8b,
			0h0000000000000000,
			0h3fe49d6e694619b8,
			0hbfd0c8e9879a6d7b,
			0h3fe6fdb8bda90d25,
			0h0000000000000000,
			0hbfbcd80b3ef020ea,
			0hbff033188d86014d,
			0hc0006873deebf700,
			0h3ff0000000000000,
		},
	)
}

@(test)
test_projection_uses_core_planes :: proc(t: ^testing.T) {
	c := camera_default(45)
	expect_m(
		t,
		projection(c, 480.0 / 360),
		{
			0h3ffcf87691583746,
			0h0000000000000000,
			0h0000000000000000,
			0h0000000000000000,
			0h0000000000000000,
			0h4003504f0b9024d9,
			0h0000000000000000,
			0h0000000000000000,
			0h0000000000000000,
			0h0000000000000000,
			0hbff0057708b5b5e1,
			0hbff0000000000000,
			0h0000000000000000,
			0h0000000000000000,
			0hbf947e60a96a0e01,
			0h0000000000000000,
		},
	)
}

@(test)
test_camera_controls :: proc(t: ^testing.T) {
	c := camera_default(90)
	testing.expect_value(t, c.offset, core.V3{0, 0, 0})
	testing.expect_value(t, c.orientation, core.CAMERA_DEFAULT_ORIENTATION)

	rotate_vertical(&c, 10)
	expect_bits(t, c.orientation.y, 0h3ff921fb82c2bd7f) // PI/2 with PI = 3.141593
	rotate_vertical(&c, -100)
	expect_bits(t, c.orientation.y, 0hbff921fb82c2bd7f)

	rotate_horizontal(&c, 100)
	rotate_horizontal(&c, 100)
	testing.expect_value(t, c.orientation.x, 200)

	zoom(&c, -5)
	testing.expect_value(t, c.orientation.z, 1.7 + -5)
	testing.expect(t, c.orientation.z < 0)

	hard_set_offset(&c, {1, 2, 3})
	testing.expect_value(t, c.offset, core.V3{1, 2, 3})
}

@(test)
test_heading_angle :: proc(t: ^testing.T) {
	expect_bits(t, heading_angle(0), 0)
	expect_bits(t, heading_angle(1), 0h3ff921fb82c2bd7f)
	expect_bits(t, heading_angle(2), 0h400921fb82c2bd7f)
	expect_bits(t, heading_angle(3), 0h4012d97ca2120e1f)
}

@(test)
test_image_camera :: proc(t: ^testing.T) {
	c := image_camera(0.8, 0)
	expect_bits(t, c.offset.x, 0)
	expect_bits(t, c.offset.y, 0h3fcd70a3d70a3d74)
	expect_bits(t, c.offset.z, 0)
	expect_bits(t, c.orientation.x, 0)
	expect_bits(t, c.orientation.y, 0hbfdfffffffffffff)
	expect_bits(t, c.orientation.z, 0h4002000000000000)
	testing.expect_value(t, c.fov, 45)

	c = image_camera(1.27, 3)
	expect_bits(t, c.offset.y, 0h3fe6666666666667)
	expect_bits(t, c.orientation.x, 0h4012d97ca2120e1f)
	expect_bits(t, c.orientation.y, 0hbfd0f5c28f5c28f5)
	expect_bits(t, c.orientation.z, 0h4002000000000000)
}

@(test)
test_camera_offset_for :: proc(t: ^testing.T) {
	p: core.Position
	p[0][.Core] = {0.2, 0.2, 0}
	p[1][.Core] = {0.6, 0.6, 1}
	o := camera_offset_for(p)
	testing.expect_value(t, o.x, 0.4)
	testing.expect_value(t, o.y, 0) // 0.4 − 0.5 < 0 → clamped
	testing.expect_value(t, o.z, 0.5)

	p[0][.Core].y = 1.2
	p[1][.Core].y = 1.2
	o = camera_offset_for(p)
	expect_bits(t, o.y, 0h3fe6666666666666) // 1.2 − 0.5
}

@(test)
test_to_raylib :: proc(t: ^testing.T) {
	m: M
	for i in 0 ..< 16 {
		m[i] = f64(i)
	}
	r := to_raylib(m)
	for c in 0 ..< 4 {
		for row in 0 ..< 4 {
			testing.expect_value(t, r[row, c], f32(4 * c + row))
		}
	}
}

expect_bits :: proc(t: ^testing.T, got, want: f64, loc := #caller_location) {
	testing.expectf(t, bits(got) == bits(want), "got %h, want %h", got, want, loc = loc)
}
