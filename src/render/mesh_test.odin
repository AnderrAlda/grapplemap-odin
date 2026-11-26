package render

import "app:core"
import "core:encoding/json"
import "core:testing"

// Expected values are bit patterns computed outside Odin with the original's operations (Python doubles,
// `struct.pack('f', …)` for the `float` constants and the f32 outputs). No tolerance anywhere (ADR 0003).

bits32 :: proc(x: f32) -> u32 {
	return transmute(u32)x
}

expect_v3 :: proc(t: ^testing.T, got: core.V3, want: [3]f64, loc := #caller_location) {
	for i in 0 ..< 3 {
		testing.expectf(
			t,
			bits(got[i]) == bits(want[i]),
			"[%d]: got %h, want %h",
			i,
			got[i],
			want[i],
			loc = loc,
		)
	}
}

expect_f32 :: proc(t: ^testing.T, got, want: [3]f32, loc := #caller_location) {
	for i in 0 ..< 3 {
		testing.expectf(
			t,
			bits32(got[i]) == bits32(want[i]),
			"[%d]: got %h, want %h",
			i,
			got[i],
			want[i],
			loc = loc,
		)
	}
}

@(test)
test_ico_constants_widened :: proc(t: ^testing.T) {
	testing.expect_value(t, bits(f64(ICO_VERTICES[1].x)), 0x3fe0d2ca00000000)
	testing.expect_value(t, bits(f64(ICO_VERTICES[1].z)), 0x3feb388800000000)
}

@(test)
test_icosphere_levels :: proc(t: ^testing.T) {
	one, err1 := icosphere_make(SPHERE_COARSE)
	defer icosphere_destroy(one)
	testing.expect_value(t, err1, nil)
	testing.expect_value(t, len(one.vertices), 42)
	testing.expect_value(t, len(one.triangles), 80)
	testing.expect_value(t, one.triangles[0], [3]int{0, 12, 14})
	testing.expect_value(t, one.triangles[1], [3]int{4, 13, 12})
	testing.expect_value(t, one.triangles[2], [3]int{1, 14, 13})
	testing.expect_value(t, one.triangles[3], [3]int{12, 13, 14})
	expect_v3(t, one.vertices[12], {0hbfd3c6ef320f88b6, 0h3fe00000023073b8, 0h3fe9e3779b383813})
	expect_v3(t, one.vertices[13], {0h3fd3c6ef320f88b6, 0h3fe00000023073b8, 0h3fe9e3779b383813})
	expect_v3(t, one.vertices[41], {0hbfe9e3779b383813, 0h3fd3c6ef320f88b6, 0hbfe00000023073b8})

	two, err2 := icosphere_make(SPHERE_FINE)
	defer icosphere_destroy(two)
	testing.expect_value(t, err2, nil)
	testing.expect_value(t, len(two.vertices), 162)
	testing.expect_value(t, len(two.triangles), 320)
	testing.expect_value(t, two.triangles[0], [3]int{0, 42, 44})
	testing.expect_value(t, two.triangles[3], [3]int{42, 43, 44})
	expect_v3(t, two.vertices[42], {0hbfdbc4d481537ce2, 0h3fd0a211b773712c, 0h3feb9afaef2e7158})
	expect_v3(t, two.vertices[161], {0hbfe605a90da2ea21, 0hbfe2cf23031c5fcb, 0hbfdb38880b2a3148})
}

@(test)
test_pillar_angles :: proc(t: ^testing.T) {
	a := pillar_angles()
	testing.expect_value(t, bits(a[0][0]), 0)
	testing.expect_value(t, bits(a[0][1]), 0x3ff0000000000000)
	testing.expect_value(t, bits(a[1][0]), 0x3fe2cf23228cdaa5)
	testing.expect_value(t, bits(a[1][1]), 0x3fe9e37785bb08bc)
	testing.expect_value(t, bits(a[5][0]), 0xbe973f48335cb331)
	testing.expect_value(t, bits(a[5][1]), 0xbfeffffffffffde4)
	// The seam stays open: entry 10 is not (0, 1).
	testing.expect_value(t, bits(a[10][0]), 0x3ea73f48335cb1a8)
	testing.expect_value(t, bits(a[10][1]), 0x3feffffffffff78e)
}

@(test)
test_emit_pillar :: proc(t: ^testing.T) {
	b: Mesh_Builder
	testing.expect_value(t, mesh_builder_init(&b), nil)
	defer mesh_builder_destroy(&b)
	m := body_mesh_make()
	defer body_mesh_destroy(&m)

	testing.expect_value(t, emit_pillar(&b, {0, 0, 0}, {0, 1, 0}, 0.05, 0.03, {1, 0, 0}, &m), nil)
	testing.expect_value(t, len(m.positions), 6 * PILLAR_FACES)
	testing.expect_value(t, len(m.normals), 6 * PILLAR_FACES)
	testing.expect_value(t, len(m.colors), 6 * PILLAR_FACES)

	n1 := [3]f32{0hbf3504f3, 0h00000000, 0hbf3504f3}
	n2 := [3]f32{0hbe203057, 0h00000000, 0hbf7cd925}
	want := [6][2][3]f32 {
		{{0hbd10d0c3, 0h00000000, 0hbd10d0c3}, n1},
		{{0hbcadc750, 0h3f800000, 0hbcadc750}, n1},
		{{0hbc0026ac, 0h00000000, 0hbd4a4751}, n2},
		{{0hbc0026ac, 0h00000000, 0hbd4a4751}, n2},
		{{0hbcadc750, 0h3f800000, 0hbcadc750}, n1},
		{{0hbb99c801, 0h3f800000, 0hbcf2bbfa}, n2},
	}
	for w, i in want {
		expect_f32(t, m.positions[i], w[0])
		expect_f32(t, m.normals[i], w[1])
		expect_f32(t, m.colors[i], {1, 0, 0})
	}
}

@(test)
test_pillar_basis :: proc(t: ^testing.T) {
	a, b := pillar_basis({0, 0, 0}, {0, 1, 0})
	expect_v3(t, a, {0h3fe6a09e667f3bcc, 0, 0hbfe6a09e667f3bcc})
	expect_v3(t, b, {0hbfe6a09e667f3bcd, 0, 0hbfe6a09e667f3bcd})
}

@(test)
test_emit_sphere :: proc(t: ^testing.T) {
	b: Mesh_Builder
	testing.expect_value(t, mesh_builder_init(&b), nil)
	defer mesh_builder_destroy(&b)
	m := body_mesh_make()
	defer body_mesh_destroy(&m)
	center := core.V3{0.25, 0.5, -0.75}
	testing.expect_value(t, emit_sphere(&b, center, 0.1, false, {1, 0, 0}, &m), nil)
	testing.expect_value(t, len(m.positions), 3 * 80)
	// Vertices of each triangle reversed: 2, 1, 0.
	tri := b.coarse.triangles[0]
	for k in 0 ..< 3 {
		v := b.coarse.vertices[tri[2 - k]]
		p := center + v * 0.1
		expect_f32(t, m.positions[k], {f32(p.x), f32(p.y), f32(p.z)})
		expect_f32(t, m.normals[k], {f32(v.x), f32(v.y), f32(v.z)})
	}
	body_mesh_clear(&m)
	testing.expect_value(t, len(m.positions), 0)
	testing.expect_value(t, len(m.normals), 0)
	testing.expect_value(t, len(m.colors), 0)
}

BODY_JSON :: #load("../../tests/fixtures/oracle/body.json")

Draw_Json :: struct {
	pi:                         f64,
	pillar_faces:               int,
	pillar_side_reference:      [3]f64,
	sphere_subdivisions_fine:   int,
	sphere_subdivisions_coarse: int,
	fine_sphere_joints:         []int,
	highlight_extra_radius:     f64,
	fat_triangles:              [][3]int,
}

@(test)
test_constants_match_oracle :: proc(t: ^testing.T) {
	body: struct {
		draw: Draw_Json,
	}
	err := json.unmarshal(BODY_JSON, &body, allocator = context.temp_allocator)
	defer free_all(context.temp_allocator)
	testing.expect_value(t, err, nil)
	d := body.draw
	testing.expect_value(t, bits(d.pi), bits(core.PI))
	testing.expect_value(t, d.pillar_faces, PILLAR_FACES)
	expect_v3(t, PILLAR_SIDE_REFERENCE, d.pillar_side_reference)
	testing.expect_value(t, d.sphere_subdivisions_fine, SPHERE_FINE)
	testing.expect_value(t, d.sphere_subdivisions_coarse, SPHERE_COARSE)
	testing.expect_value(t, bits(d.highlight_extra_radius), bits(OVERRIDE_RADIUS_DELTA))
	testing.expect_value(t, len(d.fine_sphere_joints), len(FINE_JOINTS))
	for j, i in d.fine_sphere_joints {
		testing.expect_value(t, core.Joint(j), FINE_JOINTS[i])
	}
	testing.expect_value(t, len(d.fat_triangles), len(FAT_TRIANGLES))
	for tri, i in d.fat_triangles {
		for k in 0 ..< 3 {
			testing.expect_value(t, core.Joint(tri[k]), FAT_TRIANGLES[i][k])
		}
	}
}
