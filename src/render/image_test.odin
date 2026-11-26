package render

import "app:core"
import "core:testing"

@(test)
test_downsample_2x :: proc(t: ^testing.T) {
	// 4×4 RGBA, bottom-up as GL reads it back; output 2×2 RGB, top-down.
	W2 :: 4
	H2 :: 4
	rgba: [4 * W2 * H2]u8
	set :: proc(buf: []u8, x, y: int, rgba: [4]u8) {
		i := 4 * (y * W2 + x)
		buf[i], buf[i + 1], buf[i + 2], buf[i + 3] = rgba[0], rgba[1], rgba[2], rgba[3]
	}
	// Bottom-left block (input rows 0-1): R truncates (1+2+3+5)/4 = 2, G saturated stays 255, B mixed; alpha differs
	// per pixel and must not leak into the result.
	set(rgba[:], 0, 0, {1, 255, 10, 0})
	set(rgba[:], 1, 0, {2, 255, 20, 255})
	set(rgba[:], 0, 1, {3, 255, 30, 7})
	set(rgba[:], 1, 1, {5, 255, 43, 99})
	// Top-right block (input rows 2-3): all 9 → 9.
	for y in 2 ..< 4 {
		for x in 2 ..< 4 {
			set(rgba[:], x, y, {9, 9, 9, 200})
		}
	}
	out: [3 * 2 * 2]u8
	downsample_2x(rgba[:], W2, H2, out[:])
	// Output row 0 (top) is the mean of the two last input rows: left block zero, right block 9.
	testing.expect_value(t, out, [12]u8{0, 0, 0, 9, 9, 9, 2, 255, 25, 0, 0, 0})
}

@(test)
test_image_ymax :: proc(t: ^testing.T) {
	p: core.Position
	p[0][.Head].y = 0.5
	p[1][.Head].y = 0.79
	testing.expect(
		t,
		bits(image_ymax(p)) == bits(IMAGE_YMAX_MIN),
		"heads below the floor value: IMAGE_YMAX_MIN",
	)
	p[1][.Head].y = 1.2345678901234567
	testing.expect(
		t,
		bits(image_ymax(p)) == bits(f64(1.2345678901234567)),
		"player 1's head is the higher",
	)
	p[0][.Head].y = 1.5
	testing.expect(t, bits(image_ymax(p)) == bits(f64(1.5)), "player 0's head is the higher")
}

@(test)
test_image_position :: proc(t: ^testing.T) {
	p: core.Position
	for pl in 0 ..< core.PLAYER_COUNT {
		for j in core.Joint {
			// Distinct, asymmetric coordinates so mirror and swap both change something.
			k := f64(pl * 100 + int(j))
			p[pl][j] = {0.01 * k + 0.3, 0.02 * k, -0.015 * k + 0.1}
		}
	}
	c := core.orient_canonically_with_mirror(p)
	testing.expect(t, image_position(p, false, false) == c)
	testing.expect(t, image_position(p, true, false) == core.mirror(c))
	testing.expect(t, image_position(p, false, true) == core.swap_players(c))
	testing.expect(t, image_position(p, true, true) == core.swap_players(core.mirror(c)))
}
