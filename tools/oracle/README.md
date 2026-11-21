# Oracle image

Docker image that builds the **original GrappleMap** tools (`reference/GrappleMap`, read-only submodule, pinned
at `032c8f9`) out of tree, using the original `SConstruct` and its flags unchanged. It is the oracle that later
phase-1 deliverables (dumper, sample, oracle CI) build on. Issue: #33.

## Build

From the repository root:

```sh
docker build --platform linux/amd64 -f tools/oracle/Dockerfile -t grapplemap-oracle .
```

`Dockerfile.dockerignore` limits the build context to `reference/GrappleMap/src` and `GrappleMap.txt`.
On Apple Silicon the image runs emulated (slow `-O3` build, a few minutes); on amd64 CI it is native.

## What it contains

- `/usr/local/bin/grapplemap-{indexer,dbtojs,mkpospages}`
- `/oracle/src`: source copy plus all `.o` files (including `images.o`, `rendering.o`, `playerdrawer.o`, which
  need OSMesa/ftgl/gvc/png and are required by `--images` in #35)
- `/oracle/GrappleMap.txt`: the original database
- `/oracle/VERSIONS`: compiler and library versions, for recording in `meta.json`

## Smoke checks

```sh
docker run --rm grapplemap-oracle sh -c 'grapplemap-dbtojs --help; grapplemap-mkpospages --help'
docker run --rm grapplemap-oracle sh -c 'cp /oracle/GrappleMap.txt /tmp/ && grapplemap-indexer /tmp/GrappleMap.txt && ls -l /tmp/GrappleMap.txt.index'
docker run --rm grapplemap-oracle sh -c 'ls /oracle/src/images.o /oracle/src/rendering.o /oracle/src/playerdrawer.o; ldd /usr/local/bin/grapplemap-mkpospages | grep -E "OSMesa|ftgl|gvc|png"'
docker image inspect -f '{{.Architecture}}' grapplemap-oracle   # amd64
git -C reference/GrappleMap status --porcelain                  # empty
```

## Versions and pinning

- Base: `ubuntu:18.04` (bionic), amd64 manifest `sha256:dca176c9663a7ba4c1f0e710986f5a25e672842963d95b960191e2d9f7185ebe`
  (index digest `sha256:152dc042452c496007f07ca9127571cb9c29697f42acbfad72324b2bb2e43c98`).
- Packages pinned to exact versions in the `Dockerfile`: GCC 7.5.0 (`gcc-7`/`g++-7`/`libstdc++-7-dev` 7.5.0-3ubuntu1~18.04), libc6 2.27-3ubuntu1.6,
  Boost 1.65.1, Mesa/OSMesa 20.0.8, ftgl 2.1.3~rc5, libpng 1.6.34, graphviz 2.40.1, scons 3.0.1. No `apt-get upgrade`.
- Determinism: amd64 only, no `-march=native` (the build fails unless GCC's default is `-march=x86-64`), no
  `-ffast-math` (the original flags are `-std=c++1y -O3 -DNDEBUG -DUSE_FTGL`), libm fixed by the base image and libc6.

## Why Ubuntu 18.04

The original uses the legacy Boost.GIL IO (`gil/extension/io/png_io.hpp`, `png_write_view`) in `src/images.cpp` and
`src/mkpospages.cpp`. That header was removed in Boost 1.68. Bionic ships Boost 1.65, so the original builds
unmodified. A newer base would need a shim header, i.e. a workaround (ask first).

## Known problems

- Bionic is EOL; its archive may move to `old-releases` someday. The digest plus exact versions make that fail loudly.
- `grapplemap-indexer` has no `--help`: it treats any argument as the database path.
- Rendering (`mkpospages --images`) is not exercised here. It may need `LIBGL_ALWAYS_SOFTWARE` and fonts for ftgl;
  to be checked in #35. Mesa's version affects the PNG output.

## Notes for ADR 0002 (oracle)

- Source of truth for the data format and rendering is the original, run in Docker; the Odin code is verified
  against it, not the other way round.
- The base is pinned by digest and packages by exact version; the image is `linux/amd64` with generic x86-64 codegen
  (no FMA) so floating-point output is reproducible across machines.
- No patches to the original: the submodule is never modified; the build works on a copy.
- Mesa version influences rendered PNGs, so image comparisons must be tolerance-aware or pinned to this image.
