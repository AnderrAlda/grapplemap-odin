package render

import "app:core"
import "core:strings"
import "core:testing"

// Expected values are bit patterns computed outside Odin with the same operation order (Python doubles):
// `l = 1/sqrt(1+1+1)`, `0.26 + 0.65*(max(0, n·l0) + max(0, n·l1))`.

@(test)
test_light_factor_up :: proc(t: ^testing.T) {
	// Floor normal: both lights at 1/√3; the factor is above 1, so white saturates (docs/original.md §7.3).
	f := light_factor({0, 1, 0})
	testing.expectf(t, bits(f) == 0x3ff02b3c162d16fc, "got %h", f)
	expect_v3(t, shade({1, 1, 1}, {0, 1, 0}), {1, 1, 1})
	g := shade({GRID_FACTOR, GRID_FACTOR, GRID_FACTOR}, {0, 1, 0})
	testing.expectf(t, bits(g.x) == 0x3fe9dec689e1be60, "got %h", g.x)
}

@(test)
test_light_factor_ambient_only :: proc(t: ^testing.T) {
	// Facing down: n·l ≤ 0 for both lights, only the ambient terms (0.2 + 2·0.03) remain.
	f := light_factor({0, -1, 0})
	testing.expectf(t, bits(f) == bits(0.26), "got %h", f)
	expect_v3(t, shade({1, 0, 0.5}, {0, -1, 0}), {0.26, 0, 0.13})
}

@(test)
test_light_factor_along_light0 :: proc(t: ^testing.T) {
	// n = l0: n·l0 = 3·l² = 1.0000000000000002, n·l1 = −l² (clamped away).
	f := light_factor(normalize({1, 1, 1}))
	testing.expectf(t, bits(f) == 0x3fed1eb851eb8520, "got %h", f)
}

@(test)
test_grid_mesh :: proc(t: ^testing.T) {
	m := body_mesh_make()
	defer body_mesh_destroy(&m)
	color := core.V3{0.8, 0.8, 0.8}
	testing.expect(t, grid_mesh(GRID_SIZE, color, &m) == nil)

	lines := 4 * GRID_SIZE + 1
	testing.expect_value(t, lines, 9)
	// Each line is a quad (two triangles) in each direction.
	testing.expect_value(t, len(m.positions), 2 * lines * 6)
	testing.expect_value(t, len(m.normals), len(m.positions))
	testing.expect_value(t, len(m.colors), len(m.positions))
	for i in 0 ..< len(m.positions) {
		testing.expect_value(t, m.positions[i].y, 0)
		testing.expect_value(t, m.normals[i], [3]f32{0, 1, 0})
		testing.expect_value(t, m.colors[i], [3]f32{0.8, 0.8, 0.8})
	}

	half := GRID_LINE_WIDTH / 2
	// First line (i = −4): x = −2 ± half, z from −2 to 2, vertex order of src/rendering.cpp:273-279.
	expect_f32(t, m.positions[0], {f32(-2 + half), 0, -2})
	expect_f32(t, m.positions[1], {f32(-2 - half), 0, -2})
	expect_f32(t, m.positions[2], {f32(-2 + half), 0, 2})
	expect_f32(t, m.positions[4], {f32(-2 - half), 0, 2})
	// Its z twin: z = −2 ± half, x from −2 to 2 (src/rendering.cpp:281-287).
	expect_f32(t, m.positions[6], {-2, 0, f32(-2 + half)})
	expect_f32(t, m.positions[8], {-2, 0, f32(-2 - half)})
	// Second line is GRID_SPACING further.
	expect_f32(t, m.positions[12], {f32(-2 + GRID_SPACING + half), 0, -2})
	// Last line (i = 4): x = 2 ± half.
	last := len(m.positions) - 12
	expect_f32(t, m.positions[last], {f32(2 + half), 0, -2})
	expect_f32(t, m.positions[last + 1], {f32(2 - half), 0, -2})
	// Width of every quad: GRID_LINE_WIDTH.
	testing.expect_value(t, m.positions[0].x - m.positions[1].x, f32(-2 + half) - f32(-2 - half))
}

@(test)
test_shader_names_match :: proc(t: ^testing.T) {
	// The names `reference.odin` binds must be the ones the GLSL declares (guard against drift).
	vs := string(REFERENCE_VS)
	for name in ([]string{ATTRIB_POSITION, ATTRIB_NORMAL, ATTRIB_COLOR, UNIFORM_MVP, UNIFORM_LIGHT_DIR_0, UNIFORM_LIGHT_DIR_1, UNIFORM_LIGHT_DIFFUSE, UNIFORM_LIGHT_AMBIENT}) {
		testing.expectf(t, strings.contains(vs, string(name)), "vertex shader lacks %s", name)
	}
	testing.expect(t, strings.has_prefix(vs, "#version 330"))
	testing.expect(t, strings.has_prefix(string(REFERENCE_FS), "#version 330"))
	// No numeric light constant in the GLSL: they all come from the Odin constants as uniforms.
	for lit in ([]string{"0.65", "0.03", "0.26", "0.2"}) {
		testing.expectf(t, !strings.contains(vs, lit), "vertex shader hard-codes %s", lit)
	}
}

@(test)
test_viewer_camera :: proc(t: ^testing.T) {
	pos: core.Position
	c := viewer_camera(pos)
	testing.expect_value(t, c.fov, VIEWER_FOV)
	want := core.CAMERA_DEFAULT_ORIENTATION.z + VIEWER_ZOOM
	testing.expectf(t, bits(c.orientation.z) == bits(want), "got %h", c.orientation.z)
	// 1.7 + 1.2 in doubles (Python: 1.7 + 1.2 = 2.9).
	testing.expectf(t, bits(c.orientation.z) == bits(2.9), "got %h", c.orientation.z)
	testing.expect_value(t, c.orientation.y, core.CAMERA_DEFAULT_ORIENTATION.y)
	testing.expect_value(t, c.offset, camera_offset_for(pos))
}
