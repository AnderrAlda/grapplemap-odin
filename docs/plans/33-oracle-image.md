# Plan: #33 ci: build the original GrappleMap tools in a Docker oracle image
Spec: docs/specs/phase-1-original-research.md (Deliverable 2, L29; determinism L221–227; images L228–238;
modern-toolchain/timebox L242–245, L46–48; ADR 0002 L187)

## Context
Phase 1 needs the original built and runnable as an oracle (deliverables 3–5 build on it: dumper, sample, oracle CI).
This PR only produces the image: a reproducible `linux/amd64` Docker build of the original's tools from the pinned
submodule (`032c8f9`, 2020-03-14), without touching it. Nothing in `tools/` exists yet.

Findings that drive the design:
- `src/SConstruct:4-5` sets the flags (`-std=c++1y -O3 -DNDEBUG -DUSE_FTGL`, no `-march`, no `-ffast-math`) and
  needs `pkg-config libgvc freetype2`. `mkpospages` (L48-50) links `images.o` + `rendering.o` (`rendering.cpp`,
  `playerdrawer.cpp`) with OSMesa, GLU, ftgl, png, boost_{program_options,filesystem,system}, pthread, gvc, cgraph.
  So building the `grapplemap-mkpospages` target already covers the last "Done when" box.
- `src/images.cpp:23-26,111` and `src/mkpospages.cpp:36-39` use the **legacy Boost.GIL IO** (`gil/extension/io/png_io.hpp`,
  `png_write_view`, `int_p_NULL` hack). That header was removed when GIL's io_new replaced it (Boost 1.68).
  → The base must ship Boost < 1.68: **Ubuntu 18.04 (bionic): GCC 7.5, Boost 1.65.1, Mesa 20.0 OSMesa**. Era-consistent
  with the code (no C++17 usage found; GCC 7 accepts `-std=c++1y`). Newer Ubuntu would need a shim header = a workaround
  → timebox, ask first.
- `SConstruct:59-61` has a `dbindex` command that writes `../GrappleMap.txt.index`; it only runs if that target is
  requested. We request the three program targets explicitly, so it never runs (and anyway we build on a copy).
- The host is arm64 (Docker 29.7); `--platform linux/amd64` runs emulated locally (slow, but OK), native in CI.

## Pasos
1. Copy this plan to `docs/plans/33-oracle-image.md` and commit it first.
2. `tools/oracle/Dockerfile` (≈50 lines):
   - `FROM --platform=linux/amd64 ubuntu:18.04@sha256:<digest>` — digest resolved with
     `docker buildx imagetools inspect ubuntu:18.04` (the amd64 manifest), recorded in README.
   - `ENV LC_ALL=C DEBIAN_FRONTEND=noninteractive`; one `apt-get install --no-install-recommends` with **exact versions**
     (`pkg=ver`) for `g++`, `libc6-dev`, `scons`, `pkg-config`, `libboost-{program-options,filesystem,system}-dev`,
     `libosmesa6-dev`, `libglu1-mesa-dev`, `libftgl-dev`, `libfreetype6-dev`, `libpng-dev`, `libgraphviz-dev`.
     Bionic's archive is frozen (EOL), so pinned versions make the compiler/libm reproducible together with the digest;
     no `apt-get upgrade` (libm stays the base image's `libc6`). Versions found once with `apt-cache policy` in the image.
   - Out-of-tree build: `COPY reference/GrappleMap/src /oracle/src` and `COPY reference/GrappleMap/GrappleMap.txt /oracle/`
     (keeps the `../GrappleMap.txt` layout the SConstruct expects); then
     `scons -C /oracle/src -j"$(nproc)" grapplemap-indexer grapplemap-dbtojs grapplemap-mkpospages`
     using the original SConstruct unchanged (its flags are the oracle's flags).
   - Install the binaries to `/usr/local/bin`; keep `/oracle/src` (the `.o` files: deliverable 3 links `common` and
     `images`/`rendering` objects); write `/oracle/VERSIONS` (`gcc --version`, `dpkg-query` of libc6/boost/mesa, submodule
     source hash) so later `meta.json` can record them.
   - Build-time guard: `gcc -Q --help=target | grep -- '-march='` must be `x86-64` (fails the build otherwise).
3. `tools/oracle/Dockerfile.dockerignore` (BuildKit per-Dockerfile ignore; context is the repo root): ignore everything
   except `reference/GrappleMap/src` and `reference/GrappleMap/GrappleMap.txt` (deliverable 3 will add `tools/oracle/dump`).
   No root `.dockerignore`.
4. `tools/oracle/README.md` (English): build command
   `docker build --platform linux/amd64 -f tools/oracle/Dockerfile -t grapplemap-oracle .`, smoke commands, pinned digest
   and package versions, why bionic (GIL finding), emulation note for Apple Silicon, known problems found while building,
   and a **"Notes for ADR 0002"** section (source of truth = original in Docker; base/digest/version pinning; no patches;
   amd64 + no FMA; Mesa version affects PNGs). The ADR itself is written in #43/#44 per the spec ("or notes for it").
5. Docs: root `CLAUDE.md` Mapa adds `tools/oracle` (one line); `CHANGELOG.md` Unreleased → Added (oracle image, #33).
   No `build.sh` target here: `./build.sh oracle` arrives with deliverable 3 (spec L30).
6. If the build fails on bionic for a reason not fixable in the Dockerfile itself (deps/flags/env): **stop and ask Ander**
   (timebox) with the exact error, before any shim header, patch or other base.

## Ficheros a tocar
`tools/oracle/Dockerfile` (new) · `tools/oracle/Dockerfile.dockerignore` (new) · `tools/oracle/README.md` (new) ·
`CLAUDE.md` · `CHANGELOG.md` · `docs/plans/33-oracle-image.md` (new). ≈ 180 lines.

## Tests a escribir primero
No `core` code, so no Odin tests. The checks below are the acceptance tests; written into the README first and run
as evidence (output pasted in the PR):
- `docker build --platform linux/amd64 -f tools/oracle/Dockerfile -t grapplemap-oracle .` succeeds.
- `docker run --rm grapplemap-oracle sh -c 'grapplemap-dbtojs --help; grapplemap-mkpospages --help; grapplemap-indexer --help'`.
- Indexer on a copy: `docker run --rm grapplemap-oracle sh -c 'cp /oracle/GrappleMap.txt /tmp/ && grapplemap-indexer /tmp/GrappleMap.txt && ls -l /tmp/GrappleMap.txt.index'`.
- Objects present: `ls /oracle/src/{images,rendering,playerdrawer}.o` in the container.
- Linkage: `ldd /usr/local/bin/grapplemap-mkpospages | grep -E 'OSMesa|ftgl|gvc|png'`.
- Platform/flags: `docker image inspect -f '{{.Architecture}}'` = `amd64`; the `-march=x86-64` guard passed.
- Submodule untouched: `git -C reference/GrappleMap status --porcelain` empty and `git submodule status` without `+`.
- Rebuild with `--no-cache` gives the same `/oracle/VERSIONS` (versions pinned, not floating).

## Riesgos
- Bionic packages: archive is frozen but could move to old-releases in the future → noted in README; the digest + exact
  versions make a failure loud, not silent.
- Build errors on GCC 7/Boost 1.65 (e.g. missing includes): timebox → ask.
- OSMesa may need runtime env (`LIBGL_ALWAYS_SOFTWARE`), fonts for ftgl: only relevant when rendering (#35); `--help`
  smoke tests don't exercise it. Noted as a known open point in the README.
- amd64 emulation on the Mac: slow `-O3` build (minutes); acceptable, documented.
- Deliverable 3 needs the `common` objects with the same flags: kept in `/oracle/src` for that.

## Criterio de hecho
- Issue boxes: Dockerfile (bionic pinned by digest, amd64, no `-march=native`, versions pinned) builds the three tools out
  of tree plus `images.o`/`rendering.o`/`playerdrawer.o` with OSMesa/ftgl/gvc/png; README; ADR 0002 notes.
- All checks above pass, output in the PR; submodule clean. `./build.sh ci` green locally, CI green (unaffected).
- PR draft, labels `type:ci`, `area:infra`, `phase-1`, milestone "Fase 1: Investigación del original"; `code-reviewer`
  without blockers; CHANGELOG updated. No merge without Ander's OK.
