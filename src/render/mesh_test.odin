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

@(test)
test_emit_fat_triangle :: proc(t: ^testing.T) {
	a, ar := core.V3{0.1, 0.9, 0.2}, 0.09
	b, br := core.V3{0.3, 1.1, 0.25}, 0.1
	c, cr := core.V3{0.5, 0.95, 0.15}, 0.09
	f := fat_triangle_points(a, ar, b, br, c, cr)
	expect_v3(t, f.fwd, {0hbfc4bb4c56139de2, 0h3fd8e0c200e4570c, 0hbfed0637abb5103f})
	expect_v3(t, f.ab, {0h3fe6482d37a5a3d0, 0h3fe6482d37a5a3d3, 0h3fc6482d37a5a3cf})
	expect_v3(t, f.bc, {0h3fe7c4dd663ebb86, 0hbfe1d3a60caf0ca9, 0hbfd7c4dd663ebb86})
	expect_v3(t, f.ca, {0hbfef82ec882c0f9a, 0hbfbf82ec882c0f8e, 0h3fbf82ec882c0f9c})
	expect_v3(t, f.aleft, {0h3f874b516a875440, 0h3fec720c0f1baa11, 0h3fcb049c905e248b})
	expect_v3(t, f.cdown, {0h3fe223a34933b9d6, 0h3feccbabef7f9b05, 0h3fbdd7d941977f0d})
	expect_v3(t, f.afwd, {0h3fb5de494caa8c8b, 0h3fedeb64e3e150b8, 0h3fbe4d71845eea11})
	expect_v3(t, f.bback, {0h3fd43c909de7617e, 0h3ff0fa618cc7176d, 0h3fd5ce0b225769a6})

	m := body_mesh_make()
	defer body_mesh_destroy(&m)
	testing.expect_value(t, emit_fat_triangle(a, ar, b, br, c, cr, {0, 0, 1}, &m), nil)
	testing.expect_value(t, len(m.positions), 42)
	to_f :: proc(v: core.V3) -> [3]f32 {return {f32(v.x), f32(v.y), f32(v.z)}}
	// Front: afwd, bfwd, cfwd with normal fwd.
	expect_f32(t, m.positions[0], to_f(f.afwd))
	expect_f32(t, m.positions[1], to_f(f.bfwd))
	expect_f32(t, m.positions[2], to_f(f.cfwd))
	expect_f32(t, m.normals[0], to_f(f.fwd))
	// Front left, first triangle: aleft has normal ca, bleft has −bc.
	expect_f32(t, m.positions[4], to_f(f.aleft))
	expect_f32(t, m.normals[4], to_f(f.ca))
	expect_f32(t, m.normals[5], to_f(-f.bc))
	// Back: cback, bback, aback with normal −fwd.
	expect_f32(t, m.positions[21], to_f(f.cback))
	expect_f32(t, m.positions[22], to_f(f.bback))
	expect_f32(t, m.positions[23], to_f(f.aback))
	expect_f32(t, m.normals[21], to_f(-f.fwd))
	// Last vertex: cdown with normal bc.
	expect_f32(t, m.positions[41], to_f(f.cdown))
	expect_f32(t, m.normals[41], to_f(f.bc))
}

// A non-degenerate position: no three joints of a fat triangle collinear, no limb through (1, 1, 1).
@(private = "file")
curved_position :: proc() -> (p: core.Position) {
	for j in core.Joint {
		k := f64(j)
		p[0][j] = {0.01 * k, 0.1 + 0.05 * k, 0.002 * k * k}
		p[1][j] = {1 + 0.03 * k, 0.1 + 0.04 * k, -0.003 * k * k}
	}
	return
}

@(test)
test_build_body :: proc(t: ^testing.T) {
	b: Mesh_Builder
	testing.expect_value(t, mesh_builder_init(&b), nil)
	defer mesh_builder_destroy(&b)
	pos := curved_position()

	pillars := 0
	for s in core.SEGMENTS {
		if s.visible {
			_, has_mid := s.mid_radius.?
			pillars += 2 if has_mid else 1
		}
	}
	fine_triangles := 20 * 4 * 4
	coarse_triangles := 20 * 4
	want :=
		3 *
		(2 * pillars * 2 * PILLAR_FACES +
				2 * (6 * fine_triangles + 17 * coarse_triangles) +
				2 * 5 * 14)

	m := body_mesh_make()
	defer body_mesh_destroy(&m)
	testing.expect_value(t, build_body(&b, pos, nil, &m), nil)
	testing.expect_value(t, len(m.positions), want)
	testing.expect_value(t, len(m.normals), want)
	testing.expect_value(t, len(m.colors), want)

	// First: the first visible segment (LeftToe–LeftHeel, no midpoint) of player 0.
	first := body_mesh_make()
	defer body_mesh_destroy(&first)
	testing.expect_value(
		t,
		emit_pillar(
			&b,
			pos[0][.LeftToe],
			pos[0][.LeftHeel],
			0.025,
			0.03,
			core.PLAYER_COLORS[0],
			&first,
		),
		nil,
	)
	for i in 0 ..< len(first.positions) {
		expect_f32(t, m.positions[i], first.positions[i])
		expect_f32(t, m.normals[i], first.normals[i])
	}

	// An override grows that joint's sphere by 0.005 and recolours only it: player 1's Head (the last sphere).
	overrides: [core.PLAYER_COUNT][core.Joint]Maybe(core.V3)
	overrides[1][.Head] = core.V3{0, 1, 0}
	o := body_mesh_make()
	defer body_mesh_destroy(&o)
	testing.expect_value(t, build_body(&b, pos, &overrides, &o), nil)
	testing.expect_value(t, len(o.positions), want)
	limbs := 3 * 2 * pillars * 2 * PILLAR_FACES
	head_start := limbs + 3 * (2 * (6 * fine_triangles + 17 * coarse_triangles) - fine_triangles)
	head_end := head_start + 3 * fine_triangles
	sphere := body_mesh_make()
	defer body_mesh_destroy(&sphere)
	r := core.JOINT_DEFS[.Head].radius + OVERRIDE_RADIUS_DELTA
	testing.expect_value(t, emit_sphere(&b, pos[1][.Head], r, true, {0, 1, 0}, &sphere), nil)
	for i in 0 ..< len(o.positions) {
		if i >= head_start && i < head_end {
			expect_f32(t, o.positions[i], sphere.positions[i - head_start])
			expect_f32(t, o.colors[i], {0, 1, 0})
		} else {
			expect_f32(t, o.positions[i], m.positions[i])
			expect_f32(t, o.colors[i], m.colors[i])
		}
	}
}

@(test)
test_build_body_clear :: proc(t: ^testing.T) {
	b: Mesh_Builder
	testing.expect_value(t, mesh_builder_init(&b), nil)
	defer mesh_builder_destroy(&b)
	m := body_mesh_make()
	defer body_mesh_destroy(&m)
	testing.expect_value(t, build_body(&b, curved_position(), nil, &m), nil)
	n := len(m.positions)
	body_mesh_clear(&m)
	testing.expect_value(t, len(m.positions), 0)
	testing.expect_value(t, build_body(&b, curved_position(), nil, &m), nil)
	testing.expect_value(t, len(m.positions), n)
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
