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
