package render

import "app:core"
import "core:c"
import "core:mem"
import gl "vendor:OpenGL"
import rl "vendor:raylib"
import "vendor:raylib/rlgl"

// Reference render path (ADR 0006 d1-d3; docs/original.md §7.2-§7.4): the original's meshes, lit per vertex by a
// GLSL 330 copy of its fixed-function lights, no culling, depth test `GL_LESS`, the grid drawn first.

REFERENCE_VS :: #load("shaders/reference.vs", cstring)
REFERENCE_FS :: #load("shaders/reference.fs", cstring)

// Names shared with the GLSL (test_shader_names_match keeps them in sync).
ATTRIB_POSITION :: "vertexPosition"
ATTRIB_NORMAL :: "vertexNormal"
ATTRIB_COLOR :: "vertexColor"
UNIFORM_MVP :: "mvp"
UNIFORM_LIGHT_DIR_0 :: "lightDir0"
UNIFORM_LIGHT_DIR_1 :: "lightDir1"
UNIFORM_LIGHT_DIFFUSE :: "lightDiffuse"
UNIFORM_LIGHT_AMBIENT :: "lightAmbient"

// GL_MAJOR/GL_MINOR: the core profile raylib's desktop backend creates (ADR 0006, "Context").
GL_MAJOR :: 3
GL_MINOR :: 3

// dot is `dot` (src/math.hpp): left-to-right sum of the three products.
@(private = "file")
dot :: proc(a, b: core.V3) -> f64 {
	return a.x * b.x + a.y * b.y + a.z * b.z
}

// light_factor is the CPU mirror of reference.vs in f64: `LIGHT_AMBIENT_TOTAL + LIGHT_DIFFUSE·(max(0, n·l0) +
// max(0, n·l1))`, light directions normalised from LIGHT_DIRS. Never below LIGHT_AMBIENT_TOTAL.
light_factor :: proc(n: core.V3) -> f64 {
	l0 := normalize(LIGHT_DIRS[0])
	l1 := normalize(LIGHT_DIRS[1])
	return LIGHT_AMBIENT_TOTAL + LIGHT_DIFFUSE * (max(0, dot(n, l0)) + max(0, dot(n, l1)))
}

// shade is the lit colour of reference.vs: `color · light_factor(n)` clamped to [0, 1] per channel.
shade :: proc(color, n: core.V3) -> core.V3 {
	f := light_factor(n)
	return {clamp(color.x * f, 0, 1), clamp(color.y * f, 0, 1), clamp(color.z * f, 0, 1)}
}

// grid_mesh appends the floor grid of the shader path (src/rendering.cpp:267-289; docs/original.md §7.4) to `out`:
// for `i = −2·size … 2·size` the lines `x = i·GRID_SPACING` and `z = i·GRID_SPACING` from `−size` to `+size`, each a
// quad GRID_LINE_WIDTH wide in `y = 0` (two triangles, in the original's vertex order), normal GRID_NORMAL. `color`
// is unlit: the shader lights it like the original lights its grid. Quads, not `GL_LINES`: core-profile GL has no
// guaranteed line width (ADR 0006, open points).
grid_mesh :: proc(size: int, color: core.V3, out: ^Body_Mesh) -> mem.Allocator_Error {
	s := f64(size)
	h := GRID_LINE_WIDTH / 2.0
	for i := -2 * size; i <= 2 * size; i += 1 {
		v := f64(i) * GRID_SPACING
		quads := [2][6]core.V3 {
			{
				{v + h, 0, -s},
				{v - h, 0, -s},
				{v + h, 0, s},
				{v - h, 0, -s},
				{v - h, 0, s},
				{v + h, 0, s},
			},
			{
				{-s, 0, v + h},
				{s, 0, v + h},
				{-s, 0, v - h},
				{-s, 0, v - h},
				{s, 0, v + h},
				{s, 0, v - h},
			},
		}
		for q in quads {
			for p in q {
				append(&out.positions, [3]f32{f32(p.x), f32(p.y), f32(p.z)}) or_return
				append(
					&out.normals,
					[3]f32{f32(GRID_NORMAL.x), f32(GRID_NORMAL.y), f32(GRID_NORMAL.z)},
				) or_return
				append(&out.colors, [3]f32{f32(color.x), f32(color.y), f32(color.z)}) or_return
			}
		}
	}
	return nil
}

// viewer_camera is the interactive view of `glfw_playback` (docs/original.md §7.5): fov VIEWER_FOV, distance
// zoomed by VIEWER_ZOOM, default pitch, aimed at `camera_offset_for(pos)`.
viewer_camera :: proc(pos: core.Position) -> Camera {
	c := camera_default(VIEWER_FOV)
	zoom(&c, VIEWER_ZOOM)
	hard_set_offset(&c, camera_offset_for(pos))
	return c
}

// Gpu_Mesh is a VAO with one VBO per attribute (position, normal, colour; 3 f32 each). `capacity` is in vertices.
@(private = "file")
Gpu_Mesh :: struct {
	vao:      u32,
	vbos:     [3]u32,
	capacity: int,
	count:    int,
}

// Reference_Renderer owns the shader, the GPU buffers and the CPU meshes of the reference path. Needs a GL context
// (after `rl.InitWindow`).
Reference_Renderer :: struct {
	shader:        rl.Shader,
	attribs:       [3]c.int, // position, normal, colour
	loc_mvp:       c.int,
	loc_light:     [2]c.int,
	loc_diffuse:   c.int,
	loc_ambient:   c.int,
	builder:       Mesh_Builder,
	body, grid:    Body_Mesh,
	gpu_body:      Gpu_Mesh,
	gpu_grid:      Gpu_Mesh,
	grid_built_bg: Maybe(core.V3), // the background the grid was built for
}

Reference_Error :: enum {
	None,
	Shader_Compile, // the GLSL did not compile or link (raylib fell back to its default shader)
	Shader_Interface, // an attribute or uniform of the GLSL is missing
	Out_Of_Memory,
}

@(private = "file")
gl_set_proc_address :: proc(p: rawptr, name: cstring) {
	(^rawptr)(p)^ = rlgl.GetProcAddress(name)
}

// reference_init compiles the shader, loads the `vendor:OpenGL` procs from raylib's context and builds the mesh
// builder. On error everything made so far is released.
reference_init :: proc(r: ^Reference_Renderer, allocator := context.allocator) -> Reference_Error {
	r^ = {}
	gl.load_up_to(GL_MAJOR, GL_MINOR, gl_set_proc_address)
	r.shader = rl.LoadShaderFromMemory(REFERENCE_VS, REFERENCE_FS)
	if r.shader.id == rlgl.GetShaderIdDefault() || !rl.IsShaderValid(r.shader) {
		r.shader = {}
		return .Shader_Compile
	}
	r.attribs = {
		rl.GetShaderLocationAttrib(r.shader, ATTRIB_POSITION),
		rl.GetShaderLocationAttrib(r.shader, ATTRIB_NORMAL),
		rl.GetShaderLocationAttrib(r.shader, ATTRIB_COLOR),
	}
	r.loc_mvp = rl.GetShaderLocation(r.shader, UNIFORM_MVP)
	r.loc_light = {
		rl.GetShaderLocation(r.shader, UNIFORM_LIGHT_DIR_0),
		rl.GetShaderLocation(r.shader, UNIFORM_LIGHT_DIR_1),
	}
	r.loc_diffuse = rl.GetShaderLocation(r.shader, UNIFORM_LIGHT_DIFFUSE)
	r.loc_ambient = rl.GetShaderLocation(r.shader, UNIFORM_LIGHT_AMBIENT)
	locs := [?]c.int {
		r.attribs[0],
		r.attribs[1],
		r.attribs[2],
		r.loc_mvp,
		r.loc_light[0],
		r.loc_light[1],
		r.loc_diffuse,
		r.loc_ambient,
	}
	for l in locs {
		if l < 0 {
			reference_destroy(r)
			return .Shader_Interface
		}
	}
	if mesh_builder_init(&r.builder, allocator) != nil {
		reference_destroy(r)
		return .Out_Of_Memory
	}
	r.body = body_mesh_make(allocator)
	r.grid = body_mesh_make(allocator)
	return .None
}

// reference_destroy releases the GPU objects, the shader and the CPU meshes. Safe on a partly initialised renderer.
reference_destroy :: proc(r: ^Reference_Renderer) {
	gpu_mesh_destroy(&r.gpu_body)
	gpu_mesh_destroy(&r.gpu_grid)
	if r.shader.id != 0 {
		rl.UnloadShader(r.shader)
	}
	mesh_builder_destroy(&r.builder)
	body_mesh_destroy(&r.body)
	body_mesh_destroy(&r.grid)
	r^ = {}
}

@(private = "file")
gpu_mesh_destroy :: proc(g: ^Gpu_Mesh) {
	for v in g.vbos {
		if v != 0 {
			rlgl.UnloadVertexBuffer(v)
		}
	}
	if g.vao != 0 {
		rlgl.UnloadVertexArray(g.vao)
	}
	g^ = {}
}

// gpu_mesh_upload sends `m` to `g`: in place when it fits, otherwise into new, larger buffers.
@(private = "file")
gpu_mesh_upload :: proc(g: ^Gpu_Mesh, m: ^Body_Mesh, attribs: [3]c.int) {
	n := len(m.positions)
	g.count = n
	if n == 0 {
		return
	}
	data := [3]rawptr{raw_data(m.positions), raw_data(m.normals), raw_data(m.colors)}
	size := c.int(n * size_of([3]f32))
	if n <= g.capacity {
		for v, i in g.vbos {
			rlgl.UpdateVertexBuffer(v, data[i], size, 0)
		}
		return
	}
	gpu_mesh_destroy(g)
	g.count = n
	g.capacity = n
	g.vao = rlgl.LoadVertexArray()
	rlgl.EnableVertexArray(g.vao)
	for i in 0 ..< 3 {
		g.vbos[i] = rlgl.LoadVertexBuffer(data[i], size, true)
		rlgl.SetVertexAttribute(u32(attribs[i]), 3, rlgl.FLOAT, false, 0, 0)
		rlgl.EnableVertexAttribute(u32(attribs[i]))
	}
	rlgl.DisableVertexArray()
}

@(private = "file")
gpu_mesh_draw :: proc(g: Gpu_Mesh) {
	if g.count == 0 {
		return
	}
	rlgl.EnableVertexArray(g.vao)
	rlgl.DrawVertexArray(0, c.int(g.count))
	rlgl.DisableVertexArray()
}

@(private = "file")
to_f32 :: proc(v: core.V3) -> [3]f32 {
	return {f32(v.x), f32(v.y), f32(v.z)}
}

// draw_scene draws `pos` as the original's `renderBasic` (src/rendering.cpp:321-363): clear to `background`, grid
// (GRID_FACTOR·background) then bodies, no culling, depth test `GL_LESS`. Call between `BeginDrawing` and
// `EndDrawing`; raylib's batch is flushed before and its state (culling, depth test and function) restored after,
// so 2D overlays drawn later work as usual. The body mesh is rebuilt every call (ADR 0006, open points).
draw_scene :: proc(
	r: ^Reference_Renderer,
	pos: core.Position,
	cam: Camera,
	aspect: f64,
	background: core.V3,
) -> mem.Allocator_Error {
	if bg, ok := r.grid_built_bg.?; !ok || bg != background {
		body_mesh_clear(&r.grid)
		grid_mesh(GRID_SIZE, GRID_FACTOR * background, &r.grid) or_return
		gpu_mesh_upload(&r.gpu_grid, &r.grid, r.attribs)
		r.grid_built_bg = background
	}
	body_mesh_clear(&r.body)
	build_body(&r.builder, pos, nil, &r.body) or_return
	gpu_mesh_upload(&r.gpu_body, &r.body, r.attribs)

	rlgl.DrawRenderBatchActive()
	bg := to_f32(background)
	gl.ClearColor(bg.x, bg.y, bg.z, 0)
	gl.Clear(gl.COLOR_BUFFER_BIT | gl.DEPTH_BUFFER_BIT)

	culling := gl.IsEnabled(gl.CULL_FACE)
	depth_test := gl.IsEnabled(gl.DEPTH_TEST)
	depth_func: i32
	gl.GetIntegerv(gl.DEPTH_FUNC, &depth_func)
	rlgl.DisableBackfaceCulling()
	rlgl.EnableDepthTest()
	gl.DepthFunc(gl.LESS)

	mvp := to_raylib(mat_mul(projection(cam, aspect), model_view(cam)))
	l0 := to_f32(normalize(LIGHT_DIRS[0]))
	l1 := to_f32(normalize(LIGHT_DIRS[1]))
	diffuse := f32(LIGHT_DIFFUSE)
	ambient := f32(LIGHT_AMBIENT_TOTAL)
	rlgl.EnableShader(r.shader.id)
	rlgl.SetUniformMatrix(r.loc_mvp, mvp)
	rlgl.SetUniform(r.loc_light[0], &l0, c.int(rl.ShaderUniformDataType.VEC3), 1)
	rlgl.SetUniform(r.loc_light[1], &l1, c.int(rl.ShaderUniformDataType.VEC3), 1)
	rlgl.SetUniform(r.loc_diffuse, &diffuse, c.int(rl.ShaderUniformDataType.FLOAT), 1)
	rlgl.SetUniform(r.loc_ambient, &ambient, c.int(rl.ShaderUniformDataType.FLOAT), 1)
	gpu_mesh_draw(r.gpu_grid)
	gpu_mesh_draw(r.gpu_body)
	rlgl.DisableShader()

	gl.DepthFunc(u32(depth_func))
	if !depth_test {
		rlgl.DisableDepthTest()
	}
	if culling {
		rlgl.EnableBackfaceCulling()
	}
	return nil
}
