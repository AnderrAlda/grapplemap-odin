package render

import "app:core"

// Body mesh constants of the original, verbatim with their source lines (docs/original.md §7.1, §7.2). Player
// colours are `core.PLAYER_COLORS`, joint radii `core.JOINT_DEFS`, limbs `core.SEGMENTS`.

// The icosahedron's `float` constants (src/icosphere.cpp:16-17). Typed `f32` and only ever widened to `f64` from a
// run-time load (the tables below), never as an `f64` constant expression (Odin folds constants with more precision).
ICO_X_F32 :: f32(0.525731112119133606)
ICO_Z_F32 :: f32(0.850650808352039932)

// ICO_VERTICES is `icosahedron::vertices` (src/icosphere.cpp:20-23), in that order (N = 0).
@(rodata)
ICO_VERTICES := [12][3]f32 {
	{-ICO_X_F32, 0, ICO_Z_F32},
	{ICO_X_F32, 0, ICO_Z_F32},
	{-ICO_X_F32, 0, -ICO_Z_F32},
	{ICO_X_F32, 0, -ICO_Z_F32},
	{0, ICO_Z_F32, ICO_X_F32},
	{0, ICO_Z_F32, -ICO_X_F32},
	{0, -ICO_Z_F32, ICO_X_F32},
	{0, -ICO_Z_F32, -ICO_X_F32},
	{ICO_Z_F32, ICO_X_F32, 0},
	{-ICO_Z_F32, ICO_X_F32, 0},
	{ICO_Z_F32, -ICO_X_F32, 0},
	{-ICO_Z_F32, -ICO_X_F32, 0},
}

// ICO_TRIANGLES is `icosahedron::triangles` (src/icosphere.cpp:25-29), in that order.
@(rodata)
ICO_TRIANGLES := [20][3]int {
	{0, 4, 1},
	{0, 9, 4},
	{9, 5, 4},
	{4, 5, 8},
	{4, 8, 1},
	{8, 10, 1},
	{8, 3, 10},
	{5, 3, 8},
	{5, 2, 3},
	{2, 7, 3},
	{7, 10, 3},
	{7, 6, 10},
	{7, 11, 6},
	{11, 0, 6},
	{0, 1, 6},
	{6, 1, 10},
	{9, 0, 11},
	{9, 11, 2},
	{9, 2, 5},
	{7, 2, 11},
}

PILLAR_FACES :: 10 // PlayerDrawer::faces, src/playerdrawer.hpp:32
SPHERE_FINE :: 2 // fine_icomesh = make_icosphere(2), src/playerdrawer.cpp:145
SPHERE_COARSE :: 1 // course_icomesh = make_icosphere(1), src/playerdrawer.cpp:146
OVERRIDE_RADIUS_DELTA :: 0.005 // extraBig, src/playerdrawer.cpp:294
PILLAR_SIDE_REFERENCE :: core.V3{1, 1, 1} // V3{1,1,1} in drawPillar, src/playerdrawer.cpp:225

// FINE_JOINTS are the joints drawn with the fine sphere, in the order of the test in drawJoints
// (src/playerdrawer.cpp:299-301).
@(rodata)
FINE_JOINTS := [6]core.Joint{.Head, .Core, .RightHip, .LeftHip, .RightShoulder, .LeftShoulder}

// FAT_TRIANGLES are the five joint triples of drawPlayers, in that order (src/playerdrawer.cpp:385-389).
@(rodata)
FAT_TRIANGLES := [5][3]core.Joint {
	{.LeftHip, .Core, .RightHip},
	{.LeftShoulder, .Neck, .RightShoulder},
	{.LeftShoulder, .Core, .RightShoulder},
	{.LeftAnkle, .LeftHeel, .LeftToe},
	{.RightAnkle, .RightHeel, .RightToe},
}

// Lights of `setupLights` (src/rendering.cpp:229-247; docs/original.md §7.3): two directional lights toward
// LIGHT_DIRS (world space, normalised at run time with `normalize`), diffuse and ambient per light, plus OpenGL's
// default global ambient (spec, not code). Per vertex: `color · (LIGHT_AMBIENT_TOTAL + LIGHT_DIFFUSE·Σ max(0, n·l))`.
@(rodata)
LIGHT_DIRS := [2]core.V3{{2, 2, 2}, {-2, 2, -2}} // light_position0/1, src/rendering.cpp:237-238 (GLfloat)
LIGHT_DIFFUSE :: 0.65 // light_diffuse, src/rendering.cpp:235 (GLfloat; the shader gets it as f32)
LIGHT_AMBIENT :: 0.03 // light_ambient, src/rendering.cpp:236 (GLfloat)
GLOBAL_AMBIENT :: 0.2 // GL_LIGHT_MODEL_AMBIENT default (OpenGL 1.x spec)
LIGHT_AMBIENT_TOTAL :: GLOBAL_AMBIENT + 2 * LIGHT_AMBIENT // 0.26

// Floor grid (src/rendering.cpp:249-289; docs/original.md §7.2, §7.4).
COLOR_BACKGROUND_WHITE :: core.V3{1, 1, 1} // WhiteBg, src/images.hpp:182
GRID_FACTOR :: 0.8 // grid colour = 0.8 · background, src/images.cpp:71
GRID_SIZE :: 2 // Style::grid_size, src/rendering.hpp:30
GRID_SPACING :: 0.5 // i/2, src/rendering.cpp:256-261
GRID_NORMAL :: core.V3{0, 1, 0} // glNormal3d(0, 1, 0), src/rendering.cpp:251
GRID_LINE_WIDTH :: 0.02 // ±.01f quads of the shader path, src/rendering.cpp:273-287 (m, world space)

// Interactive viewer camera: as `glfw_playback` (src/glfw_playback.cpp:46,94; docs/original.md §7.5).
VIEWER_FOV :: 50
VIEWER_ZOOM :: 1.2 // camera.zoom(1.2): distance 1.7 → 2.9

// Offscreen images: the `ImageMaker` view of `mkpospages` (src/images.cpp:55-112,302-316; docs/original.md §7.6).
IMAGE_YMAX_MIN :: 0.8 // ymax = max(.8, both heads' y), src/mkpospages.cpp:579
IMAGE_SUPERSAMPLE :: 2 // rendered at width*2 × height*2, then the 2×2 mean, src/images.cpp:63-106
IMAGE_DEFAULT_WIDTH :: 480 // ctx.mkimg.png(…, 480, 360, …), src/mkpospages.cpp:583-584
IMAGE_DEFAULT_HEIGHT :: 360
GRID_LINE_WIDTH_PX :: 2 // Style::grid_line_width, src/rendering.hpp:31 (pixels of the 2× render, `GL_LINES`)
