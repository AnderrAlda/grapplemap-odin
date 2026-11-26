package render

import "app:core"
import "core:math"
import "core:mem"

// Reference body mesh of the original (docs/original.md §7.1, §7.2; ADR 0006 d2): icospheres for the joints, ten-face
// pillars for the limbs and "fat triangles" for hips, shoulders and feet, in `drawPlayers` order. All geometry is f64
// with the original's operation order (ADR 0003 d4: no FMA, no reassociation; Odin's array operators act per
// component, like `BasicV3`); each vertex becomes f32 only when written out, as the original's `V3f` conversion.

// normalize is `normalize` (src/math.hpp:186): `v / norm2(v)`, a division per component.
@(private)
normalize :: proc(v: core.V3) -> core.V3 {
	n := math.sqrt(v.x * v.x + v.y * v.y + v.z * v.z)
	return {v.x / n, v.y / n, v.z / n}
}

// cross is `cross` (src/math.hpp:100-106).
@(private)
cross :: proc(a, b: core.V3) -> core.V3 {
	return {a.y * b.z - a.z * b.y, a.z * b.x - a.x * b.z, a.x * b.y - a.y * b.x}
}

// Icosphere is `icosphere::IndexedMesh` (src/icosphere.hpp): unit vertices and index triangles. Dynamic arrays, so
// they are freed with the allocator and capacity they were made with.
Icosphere :: struct {
	vertices:  [dynamic]core.V3,
	triangles: [dynamic][3]int,
}

// icosphere_make is `make_icosphere` (src/icosphere.cpp:76-85): the icosahedron (its `float` tables widened) split
// `subdivisions` times. Each pass visits the triangles in order and their edges 0→1, 1→2, 2→0; the midpoint of an
// edge is `normalize(e0 + e1)`, appended on first use (`vertex_for_edge`, src/icosphere.cpp:33-48). On an allocation
// error nothing leaks and the zero `Icosphere` is returned.
icosphere_make :: proc(
	subdivisions: int,
	allocator := context.allocator,
) -> (
	ico: Icosphere,
	err: mem.Allocator_Error,
) {
	// Locals, assigned to `ico` only on success: a `defer` cannot change a result after `return` has captured it.
	vertices := make([dynamic]core.V3, 0, len(ICO_VERTICES), allocator) or_return
	defer if err != nil {delete(vertices)}
	triangles := make([dynamic][3]int, 0, len(ICO_TRIANGLES), allocator) or_return
	defer if err != nil {delete(triangles)}
	for v in ICO_VERTICES {
		append(&vertices, core.V3{f64(v.x), f64(v.y), f64(v.z)}) or_return
	}
	append(&triangles, ..ICO_TRIANGLES[:]) or_return

	for _ in 0 ..< subdivisions {
		triangles = subdivide(&vertices, triangles, allocator) or_return
	}
	return {vertices, triangles}, nil
}

// subdivide is `subdivide` (src/icosphere.cpp:50-72): one pass, appending the new vertices to `vertices`. Consumes
// `triangles` on success; on error `triangles` is kept for the caller to free and nil is returned.
@(private = "file")
subdivide :: proc(
	vertices: ^[dynamic]core.V3,
	triangles: [dynamic][3]int,
	allocator: mem.Allocator,
) -> (
	result: [dynamic][3]int,
	err: mem.Allocator_Error,
) {
	lookup := make(map[[2]int]int, allocator)
	defer delete(lookup)
	out := make([dynamic][3]int, 0, 4 * len(triangles), allocator) or_return
	defer if err != nil {delete(out)}
	for tri in triangles {
		mid: [3]int
		for edge in 0 ..< 3 {
			first, second := tri[edge], tri[(edge + 1) % 3]
			key := [2]int{min(first, second), max(first, second)}
			if index, found := lookup[key]; found {
				mid[edge] = index
			} else {
				mid[edge] = len(vertices)
				map_insert(&lookup, key, mid[edge]) or_return
				append(vertices, normalize(vertices[first] + vertices[second])) or_return
			}
		}
		append(
			&out,
			[3]int{tri[0], mid[0], mid[2]},
			[3]int{tri[1], mid[1], mid[0]},
			[3]int{tri[2], mid[2], mid[1]},
			[3]int{mid[0], mid[1], mid[2]},
		) or_return
	}
	delete(triangles)
	return out, nil
}

// icosphere_destroy frees both arrays.
icosphere_destroy :: proc(ico: Icosphere) {
	delete(ico.vertices)
	delete(ico.triangles)
}

// pillar_angles is the `angles` table of `PlayerDrawer()` (src/playerdrawer.cpp:178-184): `(sin(i·s), cos(i·s))`
// with `s = 2·pi() / faces`, i = 0…faces. Entry `faces` is not (0, 1): the seam is left as in the original.
@(private)
pillar_angles :: proc() -> (angles: [PILLAR_FACES + 1][2]f64) {
	pi: f64 = core.PI // a run-time value: `2 * core.PI / 10` would fold with more precision than f64
	s := 2 * pi / f64(PILLAR_FACES)
	for i in 0 ..= PILLAR_FACES {
		angles[i] = {core.cr_sin(f64(i) * s), core.cr_cos(f64(i) * s)}
	}
	return
}

// Mesh_Builder is the state of `PlayerDrawer`/`SphereDrawer` (src/playerdrawer.hpp): both icospheres and the
// pillar angles, built once.
Mesh_Builder :: struct {
	fine, coarse: Icosphere,
	angles:       [PILLAR_FACES + 1][2]f64,
}

// mesh_builder_init builds both icospheres on `allocator` and the pillar angles. On error nothing is kept.
mesh_builder_init :: proc(
	b: ^Mesh_Builder,
	allocator := context.allocator,
) -> (
	err: mem.Allocator_Error,
) {
	fine := icosphere_make(SPHERE_FINE, allocator) or_return
	coarse, coarse_err := icosphere_make(SPHERE_COARSE, allocator)
	if coarse_err != nil {
		icosphere_destroy(fine)
		return coarse_err
	}
	b.fine, b.coarse = fine, coarse
	b.angles = pillar_angles()
	return
}

// mesh_builder_destroy frees the icospheres and zeroes the builder.
mesh_builder_destroy :: proc(b: ^Mesh_Builder) {
	icosphere_destroy(b.fine)
	icosphere_destroy(b.coarse)
	b^ = {}
}

// Body_Mesh is the original's `vector<BasicVertex>` (src/playerdrawer.hpp:9-13) as parallel arrays: a non-indexed
// triangle list, three vertices per triangle, alpha always 1.
Body_Mesh :: struct {
	positions, normals, colors: [dynamic][3]f32,
}

// body_mesh_make makes an empty mesh whose arrays grow on `allocator` (per frame: `context.temp_allocator`).
body_mesh_make :: proc(allocator := context.allocator) -> Body_Mesh {
	return {
		positions = make([dynamic][3]f32, allocator),
		normals = make([dynamic][3]f32, allocator),
		colors = make([dynamic][3]f32, allocator),
	}
}

// body_mesh_clear empties the mesh, keeping its capacity.
body_mesh_clear :: proc(m: ^Body_Mesh) {
	clear(&m.positions)
	clear(&m.normals)
	clear(&m.colors)
}

// body_mesh_destroy frees the three arrays.
body_mesh_destroy :: proc(m: ^Body_Mesh) {
	delete(m.positions)
	delete(m.normals)
	delete(m.colors)
}

// to_f is the `V3` → `V3f` conversion (src/math.hpp:26-29, 38): one f32 rounding per component.
@(private = "file")
to_f :: proc(v: core.V3) -> [3]f32 {
	return {f32(v.x), f32(v.y), f32(v.z)}
}

@(private = "file")
emit :: proc(out: ^Body_Mesh, pos, norm, color: core.V3) -> mem.Allocator_Error {
	append(&out.positions, to_f(pos)) or_return
	append(&out.normals, to_f(norm)) or_return
	append(&out.colors, to_f(color)) or_return
	return nil
}

// emit_sphere is `SphereDrawer::draw` (src/playerdrawer.cpp:149-166): per triangle the vertices 2, 1, 0; position
// `center + v·radius`, normal `v`.
emit_sphere :: proc(
	b: ^Mesh_Builder,
	center: core.V3,
	radius: f64,
	fine: bool,
	color: core.V3,
	out: ^Body_Mesh,
) -> mem.Allocator_Error {
	mesh := &b.fine if fine else &b.coarse
	for t in mesh.triangles {
		for k in 0 ..< 3 {
			v := mesh.vertices[t[2 - k]]
			emit(out, center + v * radius, v, color) or_return
		}
	}
	return nil
}

// pillar_basis is the `a`, `b` of `drawPillar` (src/playerdrawer.cpp:225-226). Degenerate (NaN) when `to = from` or
// (1, 1, 1) lies on the axis; never on the database (docs/original.md §10.3).
@(private)
pillar_basis :: proc(from, to: core.V3) -> (a, b: core.V3) {
	a = normalize(cross(to - from, PILLAR_SIDE_REFERENCE - from))
	b = normalize(cross(to - from, a))
	return
}

// emit_pillar is the shader `drawPillar` (src/playerdrawer.cpp:222-242): two triangles per face. A position is
// `from + a·r·sinᵢ + b·r·cosᵢ` = `(from + (a·r)·sinᵢ) + (b·r)·cosᵢ`; a normal `a·sinᵢ + b·cosᵢ`.
emit_pillar :: proc(
	builder: ^Mesh_Builder,
	from, to: core.V3,
	from_radius, to_radius: f64,
	color: core.V3,
	out: ^Body_Mesh,
) -> mem.Allocator_Error {
	a, b := pillar_basis(from, to)
	when ODIN_DEBUG {
		assert(!math.is_nan(a.x + a.y + a.z + b.x + b.y + b.z), "degenerate pillar basis")
	}
	at :: proc(base, a, b: core.V3, r: f64, angle: [2]f64) -> core.V3 {
		return base + a * r * angle[0] + b * r * angle[1]
	}
	angles := &builder.angles
	for i in 0 ..< PILLAR_FACES {
		normal := a * angles[i][0] + b * angles[i][1]
		normal2 := a * angles[i + 1][0] + b * angles[i + 1][1]
		emit(out, at(from, a, b, from_radius, angles[i]), normal, color) or_return
		emit(out, at(to, a, b, to_radius, angles[i]), normal, color) or_return
		emit(out, at(from, a, b, from_radius, angles[i + 1]), normal2, color) or_return
		emit(out, at(from, a, b, from_radius, angles[i + 1]), normal2, color) or_return
		emit(out, at(to, a, b, to_radius, angles[i]), normal, color) or_return
		emit(out, at(to, a, b, to_radius, angles[i + 1]), normal2, color) or_return
	}
	return nil
}

// Fat_Triangle_Points are the four directions and twelve points of `fatTriangle` (src/playerdrawer.cpp:17-38).
Fat_Triangle_Points :: struct {
	ab, bc, ca, fwd:                                                                   core.V3,
	aleft, adown, cright, cdown, bleft, bright, afwd, aback, bfwd, bback, cfwd, cback: core.V3,
}

fat_triangle_points :: proc(
	a: core.V3,
	arad: f64,
	b: core.V3,
	brad: f64,
	c: core.V3,
	crad: f64,
) -> (
	f: Fat_Triangle_Points,
) {
	f.ab = normalize(b - a)
	f.bc = normalize(c - b)
	f.ca = normalize(a - c)
	f.fwd = normalize(cross(b - a, c - a))
	f.aleft = a + f.ca * arad
	f.adown = a - f.ab * arad
	f.cright = c - f.ca * crad
	f.cdown = c + f.bc * crad
	f.bleft = b - f.bc * brad
	f.bright = b + f.ab * brad
	f.afwd = a + f.fwd * arad
	f.aback = a - f.fwd * arad
	f.bfwd = b + f.fwd * brad
	f.bback = b - f.fwd * brad
	f.cfwd = c + f.fwd * crad
	f.cback = c - f.fwd * crad
	return
}

// emit_fat_triangle is `fatTriangle` (src/playerdrawer.cpp:14-100): 14 triangles, 42 vertices, in the code order.
emit_fat_triangle :: proc(
	a: core.V3,
	arad: f64,
	b: core.V3,
	brad: f64,
	c: core.V3,
	crad: f64,
	color: core.V3,
	out: ^Body_Mesh,
) -> mem.Allocator_Error {
	f := fat_triangle_points(a, arad, b, brad, c, crad)
	vertices := [42][2]core.V3 {
		// front
		{f.afwd, f.fwd},
		{f.bfwd, f.fwd},
		{f.cfwd, f.fwd},
		// front left
		{f.afwd, f.fwd},
		{f.aleft, f.ca},
		{f.bleft, -f.bc},
		{f.afwd, f.fwd},
		{f.bleft, -f.bc},
		{f.bfwd, f.fwd},
		// front right
		{f.bfwd, f.fwd},
		{f.bright, f.ab},
		{f.cright, -f.ca},
		{f.bfwd, f.fwd},
		{f.cright, -f.ca},
		{f.cfwd, f.fwd},
		// front bottom
		{f.cfwd, f.fwd},
		{f.cdown, f.bc},
		{f.adown, -f.ab},
		{f.cfwd, f.fwd},
		{f.adown, -f.ab},
		{f.afwd, f.fwd},
		// back
		{f.cback, -f.fwd},
		{f.bback, -f.fwd},
		{f.aback, -f.fwd},
		// back left
		{f.aback, -f.fwd},
		{f.bback, -f.fwd},
		{f.bleft, -f.bc},
		{f.aback, -f.fwd},
		{f.bleft, -f.bc},
		{f.aleft, f.ca},
		// back right
		{f.bback, -f.fwd},
		{f.cback, -f.fwd},
		{f.cright, -f.ca},
		{f.bback, -f.fwd},
		{f.cright, -f.ca},
		{f.bright, f.ab},
		// back bottom
		{f.cback, -f.fwd},
		{f.aback, -f.fwd},
		{f.adown, -f.ab},
		{f.cback, -f.fwd},
		{f.adown, -f.ab},
		{f.cdown, f.bc},
	}
	for v in vertices {
		emit(out, v[0], v[1], color) or_return
	}
	return nil
}

@(private = "file")
is_fine :: proc(j: core.Joint) -> bool {
	for f in FINE_JOINTS {
		if f == j {return true}
	}
	return false
}

// build_body is the shader `drawPlayers` (src/playerdrawer.cpp:380-390) without the first-person skip: limbs (per
// player, each visible segment; with a midpoint radius, two pillars through `(a + b) / 2`), joints (in
// `playerJoints` order, player-major, src/positions.cpp:65-73; an override colour adds 0.005 to the radius), then
// the five fat triangles, each for player 0 then 1. `overrides = nil` is the normal case. Appends to `out`; after an error
// `out` is partial (its arrays may differ in length): clear it with `body_mesh_clear` before reusing it.
build_body :: proc(
	b: ^Mesh_Builder,
	pos: core.Position,
	overrides: ^[core.PLAYER_COUNT][core.Joint]Maybe(core.V3),
	out: ^Body_Mesh,
) -> mem.Allocator_Error {
	for p in 0 ..< core.PLAYER_COUNT {
		color := core.PLAYER_COLORS[p]
		player := pos[p]
		for l in core.SEGMENTS {
			if !l.visible {continue}
			ja, jb := l.ends[0], l.ends[1]
			ra, rb := core.JOINT_DEFS[ja].radius, core.JOINT_DEFS[jb].radius
			if mid_radius, has_mid := l.mid_radius.?; has_mid {
				mid := (player[ja] + player[jb]) / 2
				emit_pillar(b, player[ja], mid, ra, mid_radius, color, out) or_return
				emit_pillar(b, mid, player[jb], mid_radius, rb, color, out) or_return
			} else {
				emit_pillar(b, player[ja], player[jb], ra, rb, color, out) or_return
			}
		}
	}
	for p in 0 ..< core.PLAYER_COUNT {
		for j in core.Joint {
			extra_big := 0.0
			cc := core.PLAYER_COLORS[p]
			if overrides != nil {
				if override, ok := overrides[p][j].?; ok {
					extra_big = OVERRIDE_RADIUS_DELTA
					cc = override
				}
			}
			emit_sphere(
				b,
				pos[p][j],
				core.JOINT_DEFS[j].radius + extra_big,
				is_fine(j),
				cc,
				out,
			) or_return
		}
	}
	for tri in FAT_TRIANGLES {
		for p in 0 ..< core.PLAYER_COUNT {
			x, y, z := tri[0], tri[1], tri[2]
			emit_fat_triangle(
				pos[p][x],
				core.JOINT_DEFS[x].radius,
				pos[p][y],
				core.JOINT_DEFS[y].radius,
				pos[p][z],
				core.JOINT_DEFS[z].radius,
				core.PLAYER_COLORS[p],
				out,
			) or_return
		}
	}
	return nil
}
