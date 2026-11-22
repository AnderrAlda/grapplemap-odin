package core

import "core:testing"

// Expected values below are written from docs/original.md §3.1-§3.3 and checked by hand against
// reference/GrappleMap/src/players.hpp:8-167 and src/positions.cpp:7-31,140.

@(test)
test_joint_count_and_order :: proc(t: ^testing.T) {
	testing.expect_value(t, len(Joint), 23)
	testing.expect_value(t, JOINT_COUNT, 23)
	// Anchors of the enum order (§3.1); the full comparison against body.json is #138.
	testing.expect_value(t, int(Joint.LeftToe), 0)
	testing.expect_value(t, int(Joint.RightToe), 1)
	testing.expect_value(t, int(Joint.LeftShoulder), 10)
	testing.expect_value(t, int(Joint.RightFingers), 19)
	testing.expect_value(t, int(Joint.Core), 20)
	testing.expect_value(t, int(Joint.Neck), 21)
	testing.expect_value(t, int(Joint.Head), 22)
}

@(test)
test_joint_defs :: proc(t: ^testing.T) {
	Row :: struct {
		radius:    f64,
		draggable: bool,
	}
	expected := [Joint]Row {
		.LeftToe       = {0.025, false},
		.RightToe      = {0.025, false},
		.LeftHeel      = {0.03, false},
		.RightHeel     = {0.03, false},
		.LeftAnkle     = {0.03, true},
		.RightAnkle    = {0.03, true},
		.LeftKnee      = {0.05, true},
		.RightKnee     = {0.05, true},
		.LeftHip       = {0.09, true},
		.RightHip      = {0.09, true},
		.LeftShoulder  = {0.08, true},
		.RightShoulder = {0.08, true},
		.LeftElbow     = {0.045, true},
		.RightElbow    = {0.045, true},
		.LeftWrist     = {0.02, false},
		.RightWrist    = {0.02, false},
		.LeftHand      = {0.02, true},
		.RightHand     = {0.02, true},
		.LeftFingers   = {0.02, false},
		.RightFingers  = {0.02, false},
		.Core          = {0.1, true},
		.Neck          = {0.05, false},
		.Head          = {0.11, true},
	}
	for row, j in expected {
		def := JOINT_DEFS[j]
		testing.expectf(
			t,
			def.radius == row.radius,
			"%v radius %v, want %v",
			j,
			def.radius,
			row.radius,
		)
		testing.expectf(t, def.draggable == row.draggable, "%v draggable %v", j, def.draggable)
	}
}

@(test)
test_mirror_joint :: proc(t: ^testing.T) {
	for j in Joint {
		i := int(j)
		want := j
		if i < 20 {
			want = Joint(i ~ 1) // 2k <-> 2k+1
		}
		testing.expect_value(t, mirror_joint(j), want)
		testing.expect_value(t, JOINT_DEFS[j].mirror, want)
		testing.expect_value(t, mirror_joint(mirror_joint(j)), j)
	}
	testing.expect_value(t, mirror_joint(.LeftToe), Joint.RightToe)
	testing.expect_value(t, mirror_joint(.RightFingers), Joint.LeftFingers)
	testing.expect_value(t, mirror_joint(.Core), Joint.Core)
	testing.expect_value(t, mirror_joint(.Neck), Joint.Neck)
	testing.expect_value(t, mirror_joint(.Head), Joint.Head)
}

@(test)
test_segments :: proc(t: ^testing.T) {
	Row :: struct {
		a, b:       Joint,
		length:     f64,
		mid_radius: f64, // 0 = none
		visible:    bool,
	}
	expected := [28]Row {
		{.LeftToe, .LeftHeel, 0.23, 0, true},
		{.LeftToe, .LeftAnkle, 0.18, 0, false},
		{.LeftHeel, .LeftAnkle, 0.09, 0, false},
		{.LeftAnkle, .LeftKnee, 0.43, 0.055, true},
		{.LeftKnee, .LeftHip, 0.43, 0.085, true},
		{.LeftHip, .Core, 0.27, 0, false},
		{.Core, .LeftShoulder, 0.37, 0, false},
		{.LeftShoulder, .LeftElbow, 0.29, 0, true},
		{.LeftElbow, .LeftWrist, 0.26, 0.03, true},
		{.LeftWrist, .LeftHand, 0.08, 0, true},
		{.LeftHand, .LeftFingers, 0.08, 0, true},
		{.LeftWrist, .LeftFingers, 0.14, 0, false},
		{.RightToe, .RightHeel, 0.23, 0, true},
		{.RightToe, .RightAnkle, 0.18, 0, false},
		{.RightHeel, .RightAnkle, 0.09, 0, false},
		{.RightAnkle, .RightKnee, 0.43, 0.055, true},
		{.RightKnee, .RightHip, 0.43, 0.085, true},
		{.RightHip, .Core, 0.27, 0, false},
		{.Core, .RightShoulder, 0.37, 0, false},
		{.RightShoulder, .RightElbow, 0.29, 0, true},
		{.RightElbow, .RightWrist, 0.27, 0.03, true},
		{.RightWrist, .RightHand, 0.08, 0, true},
		{.RightHand, .RightFingers, 0.08, 0, true},
		{.RightWrist, .RightFingers, 0.14, 0, false},
		{.LeftHip, .RightHip, 0.23, 0, false},
		{.LeftShoulder, .Neck, 0.175, 0, false},
		{.RightShoulder, .Neck, 0.175, 0, false},
		{.Neck, .Head, 0.165, 0.05, true},
	}
	testing.expect_value(t, len(SEGMENTS), 28)
	visible, with_mid := 0, 0
	for row, i in expected {
		s := SEGMENTS[i]
		testing.expectf(t, s.ends == [2]Joint{row.a, row.b}, "segment %d ends %v", i, s.ends)
		testing.expectf(
			t,
			s.length == row.length,
			"segment %d length %v, want %v",
			i,
			s.length,
			row.length,
		)
		testing.expectf(t, s.visible == row.visible, "segment %d visible %v", i, s.visible)
		mid, has_mid := s.mid_radius.?
		testing.expectf(
			t,
			has_mid == (row.mid_radius != 0),
			"segment %d has mid radius %v",
			i,
			has_mid,
		)
		if has_mid {
			testing.expectf(
				t,
				mid == row.mid_radius,
				"segment %d mid radius %v, want %v",
				i,
				mid,
				row.mid_radius,
			)
			with_mid += 1
		}
		if s.visible {
			visible += 1
		}
	}
	testing.expect_value(t, visible, 15)
	testing.expect_value(t, with_mid, 7)
	// The forearm asymmetry is in the original (src/players.hpp:137,150): keep it.
	testing.expect_value(t, SEGMENTS[8].length, 0.26)
	testing.expect_value(t, SEGMENTS[20].length, 0.27)
}

@(test)
test_players :: proc(t: ^testing.T) {
	testing.expect_value(t, PLAYER_COUNT, 2)
	testing.expect_value(t, opponent(0), 1)
	testing.expect_value(t, opponent(1), 0)
	testing.expect_value(t, PLAYER_COLORS[0], V3{1, 0, 0})
	testing.expect_value(t, PLAYER_COLORS[1], V3{0.15, 0.15, 1})
	testing.expect_value(t, size_of(Position), 2 * 23 * 3 * size_of(f64))

	// Position iterates player 0 then player 1, joints in enum order (playerJoints, §3.3).
	p: Position
	n := 0
	for player in 0 ..< PLAYER_COUNT {
		for j in Joint {
			p[player][j] = V3{f64(n), 0, 0}
			n += 1
		}
	}
	flat := transmute([2 * 23]V3)p
	for v, i in flat {
		testing.expect_value(t, v.x, f64(i))
	}
	pj := Player_Joint{1, .Head}
	testing.expect_value(t, p[pj.player][pj.joint].x, 45)
}

@(test)
test_constants :: proc(t: ^testing.T) {
	testing.expect_value(t, PI, 3.141593)
	testing.expect_value(t, ENCODING_OFFSET_XZ, 2)
	testing.expect_value(t, QUANT_SCALE, 1000)
	testing.expect_value(t, Q_MAX, 62 * 62 - 1)
	testing.expect_value(t, BASICALLY_SAME_SQ, 0.0016)
	testing.expect_value(t, HEAD_PREFILTER_SQ, 0.05)
	testing.expect_value(t, LIMIT_XZ, 2)
	testing.expect_value(t, CAMERA_NEAR, 0.01)
	testing.expect_value(t, CAMERA_FAR, 15)
	testing.expect_value(t, CAMERA_DEFAULT_ORIENTATION, V3{0, -0.6, 1.7})
	testing.expect_value(t, CAMERA_OFFSET_Y_DROP, 0.5)
	testing.expect_value(t, EDITOR_CAMERA_Y_SCALE, 0.7)
	testing.expect_value(t, IMAGE_CAMERA_Y_DROP, 0.57)
	testing.expect_value(t, IMAGE_CAMERA_ZOOM, 0.55)
	testing.expect_value(t, IMAGE_CAMERA_PITCH_Y_DROP, 0.6)
	testing.expect_value(t, IMAGE_CAMERA_PITCH_DIVISOR, 2)
}
