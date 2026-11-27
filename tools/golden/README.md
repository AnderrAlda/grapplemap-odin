# tools/golden

Pinned image for rendering **our** images reproducibly. It is used by `./build.sh golden-measure` (comparison with
the oracle PNGs, #204) and later by `./build.sh test-golden` (#200). The repo is mounted at `/repo` and never
copied, which means the `reference/GrappleMap` submodule has to be initialised.

## What it pins
- **Base:** `ubuntu:24.04`, amd64 manifest pinned by digest.
- **Packages:** Ubuntu's snapshot service, frozen at `SNAPSHOT` (an `ARG`, `20261120T000000Z`). Every package that
  affects the pixels or the build has an exact version:
  - Mesa `25.2.8-0ubuntu0.24.04.5`;
  - Xvfb;
  - clang 18 (Odin's linker);
  - the X11/GL headers raylib links against.
- **TLS certificates:** `ca-certificates` comes first from the image's own archive. It only provides TLS trust for
  the https snapshot; apt still checks the archive signatures.
- **Odin:** the release in `.odin-version` (`ODIN_RELEASE`). It is the same archive CI installs, checked by
  `ODIN_SHA256`.
- **Driver:** `LIBGL_ALWAYS_SOFTWARE=1 GALLIUM_DRIVER=softpipe`, as the oracle (`tools/oracle/README.md`, "Driver").
  llvmpipe's bytes depend on its thread count and on the host's SIMD width.
- `/opt/VERSIONS` records what got installed, and `golden-measure` prints it.

## Rebuilding and bumping
`./build.sh golden-measure` builds the image (`grapplemap-golden`) when it is missing or the Dockerfile changed.

To bump Mesa or Odin:
1. Change `SNAPSHOT` and the versions together. Check them with
   `apt-cache policy <pkg>` in a container that uses the new snapshot.
2. Re-measure (`golden-measure`).
3. Regenerate the golden images, but only with Ander's OK.

On Apple Silicon the image runs as emulated amd64: slower, same bytes.

## golden-measure
`./build.sh golden-measure [lines|quads] [16|raylib]`. The default is `lines 16`, the same as
`render.IMAGE_OPTIONS_DEFAULT`.

For each `tests/fixtures/oracle/images/p<N>-480x360.png`:
1. It renders `grapplemap --image p<N>` twice, with the hidden options `--grid` and `--depth`.
2. It checks that both runs give identical bytes.
3. It runs `tools/golden/measure` against the oracle PNG, swapping the oracle's BGR back.

It prints one line per image:

    p96-480x360	differing=… largest_region=… max_delta=… body=… body_delta=… body_ok	runs=identical

- `differing`: pixels where any channel differs.
- `largest_region`: the largest 4-connected blob of differing pixels.
- `max_delta`: the largest channel difference.
- `body` / `body_delta`: the same two counts, but only for pixels that are not grey (`r = g = b`) in at least one
  image. Pixels grey in both are grid or background.
- `body_ok` / `BODY_OVER`: whether the body is within the tolerance of ADR 0006 d5, which Ander decided: at most 50
  pixels and Δ ≤ 32. Grid shifts are not limited.

In `build/golden-measure/<grid>-<depth>/` it leaves:
- `-run1.png` / `-run2.png`: our two renders;
- `-diff.png`: the differing pixels in magenta over a faded copy of ours;
- `-side.png`: ours | oracle | diff.

The numbers are recorded in ADR 0006 ("Measurement").
