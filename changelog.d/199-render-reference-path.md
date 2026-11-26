### Added
- Reference render path (`src/render/reference.odin`): GLSL 330 per-vertex shader with the original's two
  directional lights, no culling, depth test `GL_LESS`, floor grid as 0.02 m quads; `grapplemap --load <file>` now
  shows node 0 of the graph in the window (#199).
