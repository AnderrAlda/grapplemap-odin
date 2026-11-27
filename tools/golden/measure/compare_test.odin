package measure

import "core:testing"

W :: 6
H :: 4

@(private = "file")
white :: proc() -> [3 * W * H]u8 {
	b: [3 * W * H]u8
	for &v in b {
		v = 255
	}
	return b
}

@(private = "file")
set :: proc(b: []u8, x, y: int, rgb: [3]u8) {
	i := 3 * (y * W + x)
	b[i], b[i + 1], b[i + 2] = rgb[0], rgb[1], rgb[2]
}

@(test)
test_identical :: proc(t: ^testing.T) {
	a, b := white(), white()
	mask: [W * H]bool
	s, err := diff_stats(a[:], b[:], W, H, false, mask[:])
	testing.expect_value(t, err, Compare_Error.None)
	testing.expect_value(t, s, Diff_Stats{})
}

@(test)
test_one_pixel :: proc(t: ^testing.T) {
	a, b := white(), white()
	set(b[:], 2, 1, {255, 248, 255})
	mask: [W * H]bool
	s, _ := diff_stats(a[:], b[:], W, H, false, mask[:])
	testing.expect_value(
		t,
		s,
		Diff_Stats {
			differing = 1,
			largest_region = 1,
			max_delta = 7,
			body_differing = 1,
			body_max_delta = 7,
		},
	)
	testing.expect(t, mask[1 * W + 2])
}

@(test)
test_regions_four_connected :: proc(t: ^testing.T) {
	a, b := white(), white()
	// Blob of 3: an L at the top left.
	set(b[:], 0, 0, {0, 0, 0})
	set(b[:], 1, 0, {0, 0, 0})
	set(b[:], 0, 1, {0, 0, 0})
	// Blob of 5 on the right: a plus sign.
	set(b[:], 4, 1, {0, 0, 0})
	set(b[:], 3, 2, {0, 0, 0})
	set(b[:], 4, 2, {0, 0, 0})
	set(b[:], 5, 2, {0, 0, 0})
	set(b[:], 4, 3, {0, 0, 0})
	// A diagonal neighbour of the L, not 4-connected to it: its own region of 1.
	set(b[:], 1, 2, {0, 0, 0})
	mask: [W * H]bool
	s, _ := diff_stats(a[:], b[:], W, H, false, mask[:])
	testing.expect_value(t, s, Diff_Stats{differing = 9, largest_region = 5, max_delta = 255})
}

@(test)
test_diagonal_not_joined :: proc(t: ^testing.T) {
	// A diagonal staircase of 4 pixels: 8-connectivity would make one region of 4, 4-connectivity four of 1.
	a, b := white(), white()
	for k in 0 ..< 4 {
		set(b[:], k, k, {0, 0, 0})
	}
	mask: [W * H]bool
	s, _ := diff_stats(a[:], b[:], W, H, false, mask[:])
	testing.expect_value(t, s, Diff_Stats{differing = 4, largest_region = 1, max_delta = 255})
}

@(test)
test_bgr_swap :: proc(t: ^testing.T) {
	a, b := white(), white()
	set(a[:], 3, 3, {10, 20, 30})
	set(b[:], 3, 3, {30, 20, 10})
	mask: [W * H]bool
	s, _ := diff_stats(a[:], b[:], W, H, true, mask[:])
	testing.expect_value(t, s, Diff_Stats{})
	s, _ = diff_stats(a[:], b[:], W, H, false, mask[:])
	testing.expect_value(
		t,
		s,
		Diff_Stats {
			differing = 1,
			largest_region = 1,
			max_delta = 20,
			body_differing = 1,
			body_max_delta = 20,
		},
	)
}

@(test)
test_size_mismatch :: proc(t: ^testing.T) {
	a, b := white(), white()
	mask: [W * H]bool
	_, err := diff_stats(a[:], b[:3 * W * (H - 1)], W, H, false, mask[:])
	testing.expect_value(t, err, Compare_Error.Size_Mismatch)
	_, err = diff_stats(a[:], b[:], W, H, false, mask[:W])
	testing.expect_value(t, err, Compare_Error.Size_Mismatch)
}

@(test)
test_body_and_grid_split :: proc(t: ^testing.T) {
	a, b := white(), white()
	// Grid/background: grey in both images (a grid line moved), whatever the delta.
	set(a[:], 0, 0, {206, 206, 206})
	set(b[:], 1, 0, {206, 206, 206})
	// Body: coloured in either image.
	set(a[:], 3, 3, {20, 20, 230})
	set(b[:], 3, 3, {20, 20, 200})
	set(a[:], 5, 3, {230, 20, 20}) // body edge over the white background
	mask: [W * H]bool
	s, _ := diff_stats(a[:], b[:], W, H, false, mask[:])
	testing.expect_value(t, s.differing, 4)
	testing.expect_value(t, s.body_differing, 2)
	testing.expect_value(t, s.body_max_delta, 235)
	testing.expect(t, !body_within_tolerance(s), "Δ 235 is over BODY_MAX_DELTA")
}

@(test)
test_body_within_tolerance :: proc(t: ^testing.T) {
	testing.expect(t, body_within_tolerance({}))
	testing.expect(
		t,
		body_within_tolerance(
			{body_differing = BODY_MAX_DIFFERING, body_max_delta = BODY_MAX_DELTA},
		),
	)
	testing.expect(t, !body_within_tolerance({body_differing = BODY_MAX_DIFFERING + 1}))
	testing.expect(t, !body_within_tolerance({body_max_delta = BODY_MAX_DELTA + 1}))
	// Grid and background differences never count (ADR 0006 d5).
	testing.expect(
		t,
		body_within_tolerance({differing = 10_000, largest_region = 5000, max_delta = 255}),
	)
}
