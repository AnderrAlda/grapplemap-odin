package measure

import "core:fmt"
import "core:image"
import "core:image/png"
import "core:os"

// `measure <ours.png> <oracle.png> <out-prefix>`: compares our image with the oracle's (BGR, swapped back) and prints
// one line `differing=… largest_region=… max_delta=…`; writes `<out-prefix>-diff.png` (differing pixels in
// DIFF_MARK over a faded copy of ours) and `<out-prefix>-side.png` (ours | oracle in RGB | diff).
// Exit codes: 0 compared (whatever the numbers), 1 an image could not be read or written, 2 sizes differ, 3 usage.

DIFF_MARK :: [3]u8{255, 0, 255}
FADE_BASE :: 192 // faded pixel = FADE_BASE + mean(r, g, b) / FADE_DIVISOR: light grey, so the marks stand out
FADE_DIVISOR :: 4
#assert(FADE_BASE + 255 / FADE_DIVISOR <= 255)

main :: proc() {
	if len(os.args) != 4 {
		fmt.eprintln("usage: measure <ours.png> <oracle.png> <out-prefix>")
		os.exit(3)
	}
	os.exit(run(os.args[1], os.args[2], os.args[3]))
}

@(private = "file")
run :: proc(ours_path, oracle_path, prefix: string) -> int {
	ours, ok := load_rgb(ours_path)
	if !ok {
		return 1
	}
	defer png.destroy(ours)
	oracle: ^image.Image
	oracle, ok = load_rgb(oracle_path)
	if !ok {
		return 1
	}
	defer png.destroy(oracle)
	w, h := ours.width, ours.height
	if oracle.width != w || oracle.height != h {
		fmt.eprintfln("error: sizes differ: %dx%d vs %dx%d", w, h, oracle.width, oracle.height)
		return 2
	}

	mask := make([]bool, w * h)
	defer delete(mask)
	s, err := diff_stats(ours.pixels[:], oracle.pixels[:], w, h, true, mask)
	if err != .None {
		fmt.eprintfln("error: %v", err)
		return 2
	}
	fmt.printfln(
		"differing=%d largest_region=%d max_delta=%d",
		s.differing,
		s.largest_region,
		s.max_delta,
	)

	// [dynamic] with its length set: png.save_to_file takes an image.Image, whose pixels are a [dynamic]byte.
	diff := make([dynamic]u8, 3 * w * h)
	defer delete(diff)
	for marked, i in mask {
		px := ours.pixels[3 * i:][:3]
		v := u8(FADE_BASE + (int(px[0]) + int(px[1]) + int(px[2])) / 3 / FADE_DIVISOR)
		c := DIFF_MARK if marked else [3]u8{v, v, v}
		diff[3 * i], diff[3 * i + 1], diff[3 * i + 2] = c[0], c[1], c[2]
	}
	side := make([dynamic]u8, 3 * 3 * w * h)
	defer delete(side)
	for y in 0 ..< h {
		row := side[3 * 3 * w * y:][:3 * 3 * w]
		src := 3 * w * y
		copy(row[:3 * w], ours.pixels[src:][:3 * w])
		for x in 0 ..< w {
			o := oracle.pixels[src + 3 * x:][:3]
			r := row[3 * (w + x):][:3]
			r[0], r[1], r[2] = o[2], o[1], o[0]
		}
		copy(row[3 * 2 * w:], diff[src:][:3 * w])
	}
	if !save_rgb(fmt.tprintf("%s-diff.png", prefix), diff, w, h) ||
	   !save_rgb(fmt.tprintf("%s-side.png", prefix), side, 3 * w, h) {
		return 1
	}
	return 0
}

// load_rgb loads an 8-bit PNG as RGB (alpha dropped).
@(private = "file")
load_rgb :: proc(path: string) -> (img: ^image.Image, ok: bool) {
	err: image.Error
	img, err = png.load_from_file(path, {.alpha_drop_if_present})
	if err != nil {
		fmt.eprintfln("error: cannot read %s: %v", path, err)
		return nil, false
	}
	if img.channels != 3 || img.depth != 8 {
		fmt.eprintfln(
			"error: %s is not 8-bit RGB (%d channels, %d bits)",
			path,
			img.channels,
			img.depth,
		)
		png.destroy(img)
		return nil, false
	}
	return img, true
}

@(private = "file")
save_rgb :: proc(path: string, pixels: [dynamic]u8, w, h: int) -> bool {
	img := image.Image {
		width    = w,
		height   = h,
		channels = 3,
		depth    = 8,
		pixels   = pixels,
	}
	if err := png.save_to_file(path, &img); err != nil {
		fmt.eprintfln("error: cannot write %s: %v", path, err)
		return false
	}
	return true
}
