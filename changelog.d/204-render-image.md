### Added
- `grapplemap --image <entity> <out.png> [--size WxH] [--heading N|E|S|W] [--mirror] [--swap] [--load <file>]`:
  writes the reference-path image of a named position through a hidden window, as the original's `ImageMaker`
  (2× render, truncating 2×2 mean); the database defaults to `reference/GrappleMap/GrappleMap.txt`. New exit code 7
  when the GL context or the renderer fails (#204).
- `render.render_image`, `downsample_2x`, `image_position`, `image_ymax` and the `Grid_Style.Lines` floor grid
  (the original's 2-px `GL_LINES`) for the golden images (#204).
