package measure

// Pixel comparison of our images with the oracle's (tools/golden/README.md). Pure: no GL, no files.

// Body tolerance against the oracle, decided by Ander (ADR 0006 d5, #204): per image at most BODY_MAX_DIFFERING body
// pixels differ, none by more than BODY_MAX_DELTA in a channel. Grid and background pixels have no limit (known 1-px
// shifts of the grid lines).
BODY_MAX_DIFFERING :: 50
BODY_MAX_DELTA :: 32

// Diff_Stats summarises where two RGB8 images differ: `differing` pixels (any channel differs), the pixel count of the
// `largest_region` of differing pixels (4-connected), and the `max_delta` of any channel. The `body_` fields count
// only the differing pixels that are not grey (`r = g = b`) in both images: grey in both is grid or background.
Diff_Stats :: struct {
	differing:      int,
	largest_region: int,
	max_delta:      int,
	body_differing: int,
	body_max_delta: int,
}

// body_within_tolerance is whether the body differences are within the tolerance of ADR 0006 d5.
body_within_tolerance :: proc(s: Diff_Stats) -> bool {
	return s.body_differing <= BODY_MAX_DIFFERING && s.body_max_delta <= BODY_MAX_DELTA
}

Compare_Error :: enum {
	None,
	Size_Mismatch, // a buffer is not `3·w·h` bytes (`w·h` for the mask)
	Out_Of_Memory,
}

// diff_stats compares `ours` with `oracle`, both RGB8 `w × h`, top row first. `oracle_bgr`: the oracle stores B, G, R
// (the original swaps the channels before writing, src/images.cpp:89), so its first and third channels are swapped
// back. `mask[y·w + x]` is set to whether that pixel differs.
diff_stats :: proc(
	ours, oracle: []u8,
	w, h: int,
	oracle_bgr: bool,
	mask: []bool,
	allocator := context.allocator,
) -> (
	s: Diff_Stats,
	err: Compare_Error,
) {
	n := w * h
	if len(ours) != 3 * n || len(oracle) != 3 * n || len(mask) != n {
		return {}, .Size_Mismatch
	}
	for i in 0 ..< n {
		o := oracle[3 * i:][:3]
		theirs := [3]u8{o[0], o[1], o[2]}
		if oracle_bgr {
			theirs = {o[2], o[1], o[0]}
		}
		mine := [3]u8{ours[3 * i], ours[3 * i + 1], ours[3 * i + 2]}
		delta := 0
		for ch in 0 ..< 3 {
			delta = max(delta, abs(int(mine[ch]) - int(theirs[ch])))
		}
		mask[i] = delta > 0
		if !mask[i] {
			continue
		}
		s.differing += 1
		s.max_delta = max(s.max_delta, delta)
		if !(is_grey(mine) && is_grey(theirs)) {
			s.body_differing += 1
			s.body_max_delta = max(s.body_max_delta, delta)
		}
	}
	s.largest_region, err = largest_region(mask, w, h, allocator)
	return
}

@(private = "file")
is_grey :: proc(c: [3]u8) -> bool {
	return c[0] == c[1] && c[1] == c[2]
}

// largest_region is the size of the largest 4-connected set of `true` cells of `mask` (`w × h`), by flood fill with
// an explicit stack.
@(private = "file")
largest_region :: proc(
	mask: []bool,
	w, h: int,
	allocator := context.allocator,
) -> (
	best: int,
	err: Compare_Error,
) {
	seen := make([]bool, len(mask), allocator)
	stack := make([dynamic]int, allocator)
	defer delete(seen, allocator)
	defer delete(stack)
	if seen == nil && len(mask) > 0 {
		return 0, .Out_Of_Memory
	}
	for start in 0 ..< len(mask) {
		if !mask[start] || seen[start] {
			continue
		}
		size := 0
		seen[start] = true
		if _, e := append(&stack, start); e != nil {
			return 0, .Out_Of_Memory
		}
		for len(stack) > 0 {
			i := pop(&stack)
			size += 1
			x, y := i % w, i / w
			neighbours := [4][2]int{{x - 1, y}, {x + 1, y}, {x, y - 1}, {x, y + 1}}
			for nb in neighbours {
				if nb.x < 0 || nb.x >= w || nb.y < 0 || nb.y >= h {
					continue
				}
				j := nb.y * w + nb.x
				if mask[j] && !seen[j] {
					seen[j] = true
					if _, e := append(&stack, j); e != nil {
						return 0, .Out_Of_Memory
					}
				}
			}
		}
		best = max(best, size)
	}
	return best, .None
}
