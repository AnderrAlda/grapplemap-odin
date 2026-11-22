package core

// Player model of the original (docs/original.md §3). All geometry is f64 (ADR 0003 decision 1).

V3 :: [3]f64

// Joint lists the 23 joints in the original's enum order (`JOINTS`, src/players.hpp:8-21).
Joint :: enum u8 {
	LeftToe,
	RightToe,
	LeftHeel,
	RightHeel,
	LeftAnkle,
	RightAnkle,
	LeftKnee,
	RightKnee,
	LeftHip,
	RightHip,
	LeftShoulder,
	RightShoulder,
	LeftElbow,
	RightElbow,
	LeftWrist,
	RightWrist,
	LeftHand,
	RightHand,
	LeftFingers,
	RightFingers,
	Core,
	Neck,
	Head,
}

JOINT_COUNT :: len(Joint) // joint_count, src/players.hpp:29
PLAYER_COUNT :: 2 // PerPlayer = array<T, 2>, src/players.hpp:52-59

// Player is one player's joints (src/players.hpp:169); Position is player 0 then player 1
// (src/positions.hpp:9), so its memory order is `playerJoints` (§3.3).
Player :: [Joint]V3
Position :: [PLAYER_COUNT]Player

// Player_Joint addresses one joint of one player (src/players.hpp:40).
Player_Joint :: struct {
	player: int,
	joint:  Joint,
}

// opponent(p) = 1 − p (src/players.hpp:38).
opponent :: proc(player: int) -> int {
	assert(player == 0 || player == 1)
	return 1 - player
}

// Joint_Def is `JointDef` (src/players.hpp:69) plus the mirror joint of `mirror(Joint)` (src/players.hpp:73-101).
// `draggable` is kept verbatim although the original reads it nowhere (§3.1).
Joint_Def :: struct {
	radius:    f64,
	draggable: bool,
	mirror:    Joint,
}

// JOINT_DEFS is `jointDefs` (src/positions.cpp:7-31), values verbatim. Read-only data, not an Odin constant, so
// it can be indexed with a variable.
@(rodata)
JOINT_DEFS := [Joint]Joint_Def {
	.LeftToe       = {0.025, false, .RightToe}, // src/positions.cpp:8
	.RightToe      = {0.025, false, .LeftToe}, // :9
	.LeftHeel      = {0.03, false, .RightHeel}, // :10
	.RightHeel     = {0.03, false, .LeftHeel}, // :11
	.LeftAnkle     = {0.03, true, .RightAnkle}, // :12
	.RightAnkle    = {0.03, true, .LeftAnkle}, // :13
	.LeftKnee      = {0.05, true, .RightKnee}, // :14
	.RightKnee     = {0.05, true, .LeftKnee}, // :15
	.LeftHip       = {0.09, true, .RightHip}, // :16
	.RightHip      = {0.09, true, .LeftHip}, // :17
	.LeftShoulder  = {0.08, true, .RightShoulder}, // :18
	.RightShoulder = {0.08, true, .LeftShoulder}, // :19
	.LeftElbow     = {0.045, true, .RightElbow}, // :20
	.RightElbow    = {0.045, true, .LeftElbow}, // :21
	.LeftWrist     = {0.02, false, .RightWrist}, // :22
	.RightWrist    = {0.02, false, .LeftWrist}, // :23
	.LeftHand      = {0.02, true, .RightHand}, // :24
	.RightHand     = {0.02, true, .LeftHand}, // :25
	.LeftFingers   = {0.02, false, .RightFingers}, // :26
	.RightFingers  = {0.02, false, .LeftFingers}, // :27
	.Core          = {0.1, true, .Core}, // :28
	.Neck          = {0.05, false, .Neck}, // :29
	.Head          = {0.11, true, .Head}, // :30
}

// mirror_joint is `mirror(Joint)` (src/players.hpp:73-101): left ↔ right, Core/Neck/Head fixed.
mirror_joint :: proc(j: Joint) -> Joint {
	return JOINT_DEFS[j].mirror
}

// Segment is `Limb` (src/players.hpp:118-124); `mid_radius` is the optional `midpointRadius`.
Segment :: struct {
	ends:       [2]Joint,
	length:     f64,
	mid_radius: Maybe(f64),
	visible:    bool,
}

// SEGMENTS is the table of `limbs()` (src/players.hpp:126-167), 28 entries in order, values verbatim
// (the forearm is 0.26 on the left and 0.27 on the right in the original; kept).
@(rodata)
SEGMENTS := [28]Segment {
	{{.LeftToe, .LeftHeel}, 0.23, nil, true}, // src/players.hpp:129
	{{.LeftToe, .LeftAnkle}, 0.18, nil, false}, // :130
	{{.LeftHeel, .LeftAnkle}, 0.09, nil, false}, // :131
	{{.LeftAnkle, .LeftKnee}, 0.43, 0.055, true}, // :132
	{{.LeftKnee, .LeftHip}, 0.43, 0.085, true}, // :133
	{{.LeftHip, .Core}, 0.27, nil, false}, // :134
	{{.Core, .LeftShoulder}, 0.37, nil, false}, // :135
	{{.LeftShoulder, .LeftElbow}, 0.29, nil, true}, // :136
	{{.LeftElbow, .LeftWrist}, 0.26, 0.03, true}, // :137
	{{.LeftWrist, .LeftHand}, 0.08, nil, true}, // :138
	{{.LeftHand, .LeftFingers}, 0.08, nil, true}, // :139
	{{.LeftWrist, .LeftFingers}, 0.14, nil, false}, // :140
	{{.RightToe, .RightHeel}, 0.23, nil, true}, // :142
	{{.RightToe, .RightAnkle}, 0.18, nil, false}, // :143
	{{.RightHeel, .RightAnkle}, 0.09, nil, false}, // :144
	{{.RightAnkle, .RightKnee}, 0.43, 0.055, true}, // :145
	{{.RightKnee, .RightHip}, 0.43, 0.085, true}, // :146
	{{.RightHip, .Core}, 0.27, nil, false}, // :147
	{{.Core, .RightShoulder}, 0.37, nil, false}, // :148
	{{.RightShoulder, .RightElbow}, 0.29, nil, true}, // :149
	{{.RightElbow, .RightWrist}, 0.27, 0.03, true}, // :150
	{{.RightWrist, .RightHand}, 0.08, nil, true}, // :151
	{{.RightHand, .RightFingers}, 0.08, nil, true}, // :152
	{{.RightWrist, .RightFingers}, 0.14, nil, false}, // :153
	{{.LeftHip, .RightHip}, 0.23, nil, false}, // :156
	{{.LeftShoulder, .Neck}, 0.175, nil, false}, // :158
	{{.RightShoulder, .Neck}, 0.175, nil, false}, // :159
	{{.Neck, .Head}, 0.165, 0.05, true}, // :160
}

// PLAYER_COLORS is `playerDefs` (src/positions.cpp:140): player 0 `red` = {1, 0, 0} (src/math.hpp:62), player 1
// {0.15, 0.15, 1}.
@(rodata)
PLAYER_COLORS := [PLAYER_COUNT]V3{{1, 0, 0}, {0.15, 0.15, 1}}

// Constants copied verbatim from the original (ADR 0003 decision 7, ADR 0004 decision 4). Not improved.

PI :: 3.141593 // pi(), src/math.hpp:12

ENCODING_OFFSET_XZ :: 2 // `g() - 2` on x and z, src/persistence.cpp:53
QUANT_SCALE :: 1000 // coordinate = (62·d0 + d1) / 1000, src/persistence.cpp:43-48 (§1.3)
Q_MAX :: 62 * 62 - 1 // 3843, largest two-digit base62 value (§1.3); range 0…3843, ADR 0005 decision 6

BASICALLY_SAME_SQ :: 0.0016 // m², basicallySame, src/positions.hpp:52
HEAD_PREFILTER_SQ :: 0.05 // m², is_reoriented pre-filter, src/positions.cpp:238

LIMIT_XZ :: 2 // apply_limits box x, z ∈ [−2, 2] (y ≥ radius), src/positions.cpp:318-320

CAMERA_NEAR :: 0.01 // perspective near plane, src/camera.hpp:34
CAMERA_FAR :: 15 // perspective far plane, src/camera.hpp:34
CAMERA_DEFAULT_ORIENTATION :: V3{0, -0.6, 1.7} // Camera::orientation, src/camera.hpp:12
CAMERA_OFFSET_Y_DROP :: 0.5 // cameraOffsetFor: y = max(0, y − 0.5), src/positions.hpp:182-187
EDITOR_CAMERA_Y_SCALE :: 0.7 // editor camera target c.y *= 0.7, src/editor_canvas.cpp:539-544
IMAGE_CAMERA_Y_DROP :: 0.57 // ImageMaker offset y = ymax − 0.57, src/images.cpp:310
IMAGE_CAMERA_ZOOM :: 0.55 // ImageMaker camera.zoom(0.55), src/images.cpp:311
IMAGE_CAMERA_PITCH_Y_DROP :: 0.6 // rotateVertical((ymax − 0.6)/2), src/images.cpp:313
IMAGE_CAMERA_PITCH_DIVISOR :: 2 // rotateVertical((ymax − 0.6)/2), src/images.cpp:313
