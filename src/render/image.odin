package render

import "app:core"
import "core:c"
import gl "vendor:OpenGL"
import rl "vendor:raylib"
import "vendor:raylib/rlgl"

// Offscreen images as `ImageMaker::png` (src/images.cpp:55-112,302-316; docs/original.md §7.6): the scene rendered
// at IMAGE_SUPERSAMPLE× into a render texture, read back and reduced by a truncating 2×2 mean. Used by `--image` and
// the golden images (#200).

// Image_Depth is the render texture's depth buffer: `.Raylib` = raylib's unsized `GL_DEPTH_COMPONENT` renderbuffer
// (24 bits on Mesa); `.Bits16` = `GL_DEPTH_COMPONENT16`, the depth of the original's OSMesa context
// (`OSMesaCreateContextExt(OSMESA_RGB, 16, 0, 16)`, src/images.cpp:525).
Image_Depth :: enum {
	Raylib,
	Bits16,
}

// Image_Options are the render settings an image can vary.
Image_Options :: struct {
	grid:  Grid_Style,
	depth: Image_Depth,
}

// IMAGE_OPTIONS_DEFAULT is what `--image` and the golden images use: of the four combinations measured against the
// oracle PNGs (`./build.sh golden-measure`, ADR 0006 "Measurement"), 2-px lines and a 16-bit depth differ least.
IMAGE_OPTIONS_DEFAULT :: Image_Options {
	grid  = .Lines,
	depth = .Bits16,
}

Image_Error :: enum {
	None,
	Render_Texture, // raylib could not make the render texture, or the 16-bit depth left it incomplete
	Readback, // reading the render texture back failed
	Out_Of_Memory,
}

// image_position is the position an image shows (tools/oracle/images/images.cpp:135, spec "UX"):
// `orient_canonically_with_mirror`, then `mirror` (as `ImageMaker::png` does for a mirrored view,
// src/images.cpp:354), then `swap_players`.
image_position :: proc(p: core.Position, mirror, swap: bool) -> core.Position {
	r := core.orient_canonically_with_mirror(p)
	if mirror {
		r = core.mirror(r)
	}
	if swap {
		r = core.swap_players(r)
	}
	return r
}

// image_ymax is `std::max(.8, std::max(p0 head y, p1 head y))` (src/mkpospages.cpp:579-581).
image_ymax :: proc(p: core.Position) -> f64 {
	return max(IMAGE_YMAX_MIN, max(p[0][.Head].y, p[1][.Head].y))
}

// downsample_2x is the reduction of `ImageMaker::png` (src/images.cpp:93-112): `rgba` is a `w2 × h2` RGBA8 buffer,
// bottom row first (as GL reads back); `out` gets the `w2/2 × h2/2` RGB8 image, top row first, each channel the
// integer mean `(a + b + c + d) / 4` of its 2×2 block (truncating). Alpha is dropped and the channels stay in our
// RGB order (the original swaps to BGR before the mean; the comparison with its PNGs swaps back).
downsample_2x :: proc(rgba: []u8, w2, h2: int, out: []u8) {
	assert(w2 % 2 == 0 && h2 % 2 == 0, "downsample_2x: odd size")
	w, h := w2 / 2, h2 / 2
	assert(len(rgba) == 4 * w2 * h2 && len(out) == 3 * w * h, "downsample_2x: buffer sizes")
	for y in 0 ..< h {
		row := h - 1 - y // flipped_up_down_view, src/images.cpp:111-112
		for x in 0 ..< w {
			a := 4 * ((2 * y) * w2 + 2 * x)
			b := a + 4
			cc := a + 4 * w2
			d := cc + 4
			o := 3 * (row * w + x)
			for ch in 0 ..< 3 {
				sum :=
					int(rgba[a + ch]) + int(rgba[b + ch]) + int(rgba[cc + ch]) + int(rgba[d + ch])
				out[o + ch] = u8(sum / 4)
			}
		}
	}
}

// render_image draws `p` (already through `image_position`) with the `ImageMaker` camera for `heading` (0..3 =
// N, E, S, W) on the white background into a `2w × 2h` render texture, reads it back and writes the `w × h` RGB8
// image to `out` (`3·w·h` bytes, top row first). Needs a GL context and an initialised renderer; call it outside
// `BeginDrawing`/`EndDrawing`. The render texture is made and freed per call (one image per process for `--image`;
// the golden runner renders a handful).
render_image :: proc(
	r: ^Reference_Renderer,
	p: core.Position,
	heading, w, h: int,
	opts: Image_Options,
	out: []u8,
) -> Image_Error {
	assert(w > 0 && h > 0 && len(out) == 3 * w * h, "render_image: size")
	w2, h2 := IMAGE_SUPERSAMPLE * w, IMAGE_SUPERSAMPLE * h
	target := rl.LoadRenderTexture(c.int(w2), c.int(h2))
	if !rl.IsRenderTextureValid(target) {
		return .Render_Texture
	}
	// Unloading deletes whatever depth renderbuffer is attached (rlUnloadFramebuffer), the 16-bit one included.
	defer rl.UnloadRenderTexture(target)
	if opts.depth == .Bits16 && !attach_depth16(&target) {
		return .Render_Texture
	}

	rl.BeginTextureMode(target)
	cam := image_camera(image_ymax(p), heading)
	err := draw_scene(r, p, cam, f64(w2) / f64(h2), COLOR_BACKGROUND_WHITE, opts.grid)
	rl.EndTextureMode()
	if err != nil {
		return .Out_Of_Memory
	}

	pixels := rlgl.ReadTexturePixels(
		target.texture.id,
		c.int(w2),
		c.int(h2),
		c.int(rl.PixelFormat.UNCOMPRESSED_R8G8B8A8),
	)
	if pixels == nil {
		return .Readback
	}
	defer rl.MemFree(pixels)
	downsample_2x(([^]u8)(pixels)[:4 * w2 * h2], w2, h2, out)
	return .None
}

// attach_depth16 replaces the render texture's depth renderbuffer by a `GL_DEPTH_COMPONENT16` one of the same size.
// Returns whether the framebuffer is complete.
@(private = "file")
attach_depth16 :: proc(target: ^rl.RenderTexture2D) -> bool {
	rb: u32
	gl.GenRenderbuffers(1, &rb)
	if rb == 0 {
		return false // attaching 0 would detach the depth buffer and still leave the FBO complete
	}
	gl.BindRenderbuffer(gl.RENDERBUFFER, rb)
	gl.RenderbufferStorage(
		gl.RENDERBUFFER,
		gl.DEPTH_COMPONENT16,
		target.texture.width,
		target.texture.height,
	)
	gl.BindRenderbuffer(gl.RENDERBUFFER, 0)
	rlgl.FramebufferAttach(
		target.id,
		rb,
		c.int(rlgl.FramebufferAttachType.DEPTH),
		c.int(rlgl.FramebufferAttachTextureType.RENDERBUFFER),
		0,
	)
	old := target.depth.id
	gl.DeleteRenderbuffers(1, &old)
	target.depth.id = rb
	return rlgl.FramebufferComplete(target.id)
}
