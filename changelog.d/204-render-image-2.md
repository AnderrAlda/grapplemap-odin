### Added
- `tools/golden/Dockerfile`: pinned image (Ubuntu 24.04 by digest, packages frozen by the Ubuntu snapshot service,
  Mesa 25.2.8 softpipe, the pinned Odin), used to render our images reproducibly (#204).
- `./build.sh golden-measure [lines|quads] [16|raylib]`: renders the 6 oracle images twice inside that image and
  prints, per image, the pixels that differ from the oracle PNG, the largest differing region, the largest channel
  difference and whether both runs are identical. The comparison tool is the new `tools/golden/measure` package
  (#204).
- `render.Image_Options` (grid style, 16-bit depth), set from the hidden `--image` options `--grid` and `--depth`
  (#204).
- By default `--image` draws the grid as 2-px lines and uses a 16-bit depth buffer: of the combinations measured, it
  is the closest to the oracle images (ADR 0006, "Measurement"). If the GL context cannot draw 2-px lines, it warns
  (#204).
