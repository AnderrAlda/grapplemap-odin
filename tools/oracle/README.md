# Oracle image

Docker image that builds the **original GrappleMap** tools (`reference/GrappleMap`, read-only submodule, pinned
at `032c8f9`) out of tree, using the original `SConstruct` and its flags unchanged. It is the oracle that later
phase-1 deliverables (dumper, sample, oracle CI) build on. Issues: #33 (image), #34 (dumper).

## Build

From the repository root:

```sh
docker build --platform linux/amd64 -f tools/oracle/Dockerfile -t grapplemap-oracle .
```

`Dockerfile.dockerignore` limits the build context to `reference/GrappleMap/src`, `GrappleMap.txt` and
`tools/oracle/dump` (without its `testdata/`). Stages: `original` (the original tools) and `dumper` (the final image).
On Apple Silicon the image runs emulated (slow `-O3` build, a few minutes); on amd64 CI it is native.

## What it contains

- `/usr/local/bin/grapplemap-{indexer,dbtojs,mkpospages}`
- `/oracle/src`: source copy plus all `.o` files (including `images.o`, `rendering.o`, `playerdrawer.o`, which
  need OSMesa/ftgl/gvc/png and are required by `--images` in #35)
- `/oracle/GrappleMap.txt`: the original database
- `/oracle/VERSIONS`: compiler and library versions, for recording in `meta.json`
- `/usr/local/bin/grapplemap-dump` and `grapplemap-oracle-dump` (the dumper, see below)

## Dumper (#34)

`tools/oracle/dump/dump.cpp` (+ `json.hpp`, no extra dependencies) is linked against the original's `common` objects
(`SConstruct:33`) and `boost_program_options`, built with `-std=c++1y -O3 -DNDEBUG -ffp-contract=off` and `-Werror`.
`grapplemap-oracle-dump DB OUT [--versions FILE] [--commit SHA]` (`dump/run.sh`) runs `grapplemap-indexer` on a
**copy** of `DB`, then the dumper, which always loads `DB` with `loadGraph(std::istream&)` (no `.index`; one code
path) and only reads the copy's `.index` to dump it and check it.

```sh
./build.sh oracle --full   # whole DB -> build/oracle/full/ (git-ignored; wiped first; prints sha256 of each file)
./build.sh oracle --test   # tools/oracle/dump/testdata/*.txt -> build/oracle/test/<name>/, diff -r with testdata/<name>/
```

Both build the image first (`docker build`, cached) and fail with a clear message when Docker or its daemon is
missing. They are not part of `./build.sh ci`. `--sample`, `--images` and `--update-full-hashes` arrive with #35.

Output (format of `docs/specs/phase-1-original-research.md`, "Dump format"; one JSON value per line, fixed order, no
timestamps, doubles as `%.17g`, strings as UTF-8 with JSON escapes):

| File | Content |
|---|---|
| `meta.json` | `dumper_version`, `submodule_commit`, `db_md5`, `index_md5`, `index_matches_db`, `index_consistent` (the `.index` pairs equal the `from`/`to` of `loadGraph(istream)`), `versions` (lines of `/oracle/VERSIONS`), `counts` (`blocks`, `positions`, `named_positions`, `transitions`, `nodes`, `anonymous_nodes`), `errors`: the original's exception message verbatim when `loadGraph` fails, or a message starting with `dumper: ` (the dumper is strict: invalid UTF-8, a coordinate off the base62 grid, an unreadable `.index`). On an error during loading or dumping only `meta.json` is written; on an `.index` mismatch all files are written. In every case with errors the exit status is 1 |
| `sequences.ndjson` | one line per block in file order: `index`, `kind` (`position`/`transition`), `line_nr` (the original's value), `description`, `tags`, `properties` (sorted, as the original's `set`s), `refs` (lines starting `ref:`), `notes` (lines starting `note:`/`todo:`), `detailed`, `bidirectional`, `positions_q` |
| `graph.ndjson` | nodes (`index`, `block` or `null` for anonymous nodes, `description`, `tags`, `position_q`), then transitions (`index`, `block`, `from`, `to`, `reorientation_from`/`_to` = `{translation, angle, swap, mirror}`), then one `{"type":"index", md5, pairs}` line with the `.index` |
| `ops.ndjson` | one line per position, blocks in file order (`pos` 0 for a named position, the index in the sequence for a transition): `block`, `pos`, `mirror`, `swap_players` (on a copy: the original swaps in place), `orient_canonically_with_mirror`, `orient_canonically_without_mirror` (positions as doubles `[player][joint] = [x, y, z]`), `heading` (`[x, z]`), `center` (`[x, y, z]`) (`src/positions.hpp:37,68,132-184`) |
| `between.ndjson` | for every consecutive pair of every transition and `s` = `0.25`, `0.5`, `0.75` (in that order): `block`, `seq`, `pos` (index of the pair's first position), `s`, `position` = `between(a, b, s)` (`src/positions.hpp:42`) |
| `playback.ndjson` | one `{"type":"transition"}` line per transition, then at most one `{"type":"chain"}` line (see "Playback" below) |
| `body.json` | `joints` (`jointDefs`: name, radius, draggable, mirror joint), `segments` (`limbs()`: ends, length, `mid_radius` or `null`, visible), `players` (code, color), `draw` (constants of `playerdrawer.{hpp,cpp}` with their source lines; `rendering.cpp` has none that affect body geometry) |
| `spring.ndjson` | one line per named position in block order: `block`, `node`, `position` = `spring(p)` on a copy (`src/positions.cpp:183-194`: `apply_limits`, then `spring` per player with no fixed joint) |

Playback (`src/paths.cpp:8-54`, `src/graph_util.cpp:60`): `frames(g, path, 11)`, the default frames-per-pos of
`src/makevideo.cpp:34`. A `detailed` transition uses `11 / 2` by **integer** division, i.e. 5 (6 frames per segment,
not 5.5; `src/paths.cpp:42`); `segment_frames_per_pos` records the value used. `follow()` emits frames-per-pos + 1
frames per segment (segment boundaries repeat) and `frames()` drops the last frame of each transition
(`src/paths.cpp:44`): the dump stores exactly what it returns. A `transition` line has `block`, `seq`,
`frames_per_pos`, `segment_frames_per_pos`, `caption` (as `frames()` builds it: first description line, literal `\n`
→ space, a caption that is exactly `...` → first line of the end node's description, if it has one), `raw` (the frames) and `smooth` (`smoothen()` of that transition alone). Each
transition is played forwards from its `from` node (`Step{seq, reverse = false}`). **Smoothing per transition is a
dumper choice**: every caller in the original smooths a whole script in one call (`src/makevideo.cpp:93,105`,
`src/playback.cpp:77,89`, `src/paths.cpp:261`), so the filter state carries across chained transitions. For that
case the `chain` line holds the first pair `a → b` in index order such that `b` starts at `a`'s end node, played as
one path through `frames(g, script, 11)` (`src/paths.cpp:54`) and smoothed in one call: `seqs`, `frames_per_pos`,
`segment_frames_per_pos` and `captions` (one per step), `raw` and `smooth` (one frame list per step). The time-based `Playback::progress` is not dumped.

Output files are streamed record by record to `<name>.tmp` in `OUT` and renamed once all of them are complete
(`meta.json` last), so the ~0.5 GB dump is never held in memory and a failure leaves only `meta.json`.

Positions are quantized: `positions_q[k][player][joint] = [qx, qy, qz]`, integers `0…3843`, with
`x = qx/1000 − 2`, `y = qy/1000`, `z = qz/1000 − 2` (exact: the dumper checks each value decodes back bit for bit).
`refs`/`notes` are derived by the dumper (the original has no parser for them, `docs/original.md` §1.2).
`line_nr` is the 0-based line of the block's first **position** line: the original evaluates `desc.size()` after
`move(desc)` (`src/persistence.cpp:80-85`), which confirms the open point of `docs/original.md` §1.4.

Full dump (pin `032c8f9`, dumper version 2): 2,086 blocks, 8,323 positions, 601 named positions, 1,485 transitions,
725 nodes (124 anonymous); `.index` consistent. 544,312,243 bytes (`playback` 389 MB, `ops` 93 MB, `between` 52 MB,
`sequences` 6.8 MB, `spring` 1.7 MB, `graph` 1.1 MB); ~17 s on amd64. Two runs give identical bytes.

Test DB: `testdata/basic.txt` is generated by `testdata/make_basic.py` (deterministic): a named position with quotes
and `ref:`, a transition from it translated by +0.5 in x to an anonymous node (literal `\n`, UTF-8, `note:`/`todo:`, a
tab, coordinates `q = 0` and `3843`), a bidirectional transition ending at the mirror of the second named position.
The two transitions form the `chain` of `playback.ndjson` (the first is `detailed`: 2 segments × 6 frames − 1 = 11).
`testdata/bad_digit.txt` has a non-base62 digit: the original rejects it, so its expected directory holds only
`meta.json` with the original's error. A test whose expected directory has no `graph.ndjson` must make the dumper
fail, and any other test must make it succeed. `testdata/<name>/` is the expected output, reviewed by hand: change it
only together with the dumper and say why in the PR.

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
