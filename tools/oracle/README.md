# Oracle image

Docker image that builds the **original GrappleMap** tools (`reference/GrappleMap`, read-only submodule, pinned
at `032c8f9`) out of tree, using the original `SConstruct` and its flags unchanged. It is the oracle that later
phase-1 deliverables (dumper, sample, oracle CI) build on. Issues: #33 (image), #34 (dumper), #35 (inventory, sample).

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
`grapplemap-oracle-dump DB OUT [--versions FILE] [--commit SHA] [--sample TSV]` (`dump/run.sh`) runs
`grapplemap-indexer` on a **copy** of `DB`, then the dumper, which always loads `DB` with `loadGraph(std::istream&)`
(no `.index`; one code path) and only reads the copy's `.index` to dump it and check it.

```sh
./build.sh oracle --full                # whole DB -> build/oracle/full/ (git-ignored; wiped first); prints the sha256
                                        # of each file and, if tests/fixtures/oracle/FULL.sha256 exists, fails unless
                                        # the list (file set and hashes) is identical
./build.sh oracle --update-full-hashes  # same dump, then writes tests/fixtures/oracle/FULL.sha256
./build.sh oracle [--sample]            # the default: blocks of sample.tsv -> tests/fixtures/oracle/ + MANIFEST.sha256
./build.sh oracle --test                # tools/oracle/dump/testdata/*.txt -> build/oracle/test/<name>/, diff -r with testdata/<name>/
```

All build the image first (`docker build`, cached) and fail with a clear message when Docker or its daemon is
missing. They are not part of `./build.sh ci`. `--images` arrives with the last PR of #35.

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
| `inventory.ndjson` | one line per block in file order: `block`, `kind`, `length` (positions), `family`, `length_bucket` (`2`, `3-5`, `6-10`, `>10`; `null` for a named position), `classes` (see "Inventory and sample") |

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

Full dump (pin `032c8f9`, dumper version 3): 2,086 blocks, 8,323 positions, 601 named positions, 1,485 transitions,
725 nodes (124 anonymous); `.index` consistent. 544,626,736 bytes (`playback` 389 MB, `ops` 93 MB, `between` 52 MB,
`sequences` 6.8 MB, `spring` 1.7 MB, `graph` 1.1 MB, `inventory` 0.3 MB); ~15 s on amd64. Two runs give identical
bytes. Version 3 only added `inventory.ndjson`: the other files are byte-identical to version 2 except `meta.json`
(`dumper_version`). `--sample` does not change the full dump.

Test DB: `testdata/basic.txt` is generated by `testdata/make_basic.py` (deterministic): a named position with quotes
and `ref:`, a transition from it translated by +0.5 in x to an anonymous node (literal `\n`, UTF-8, `note:`/`todo:`, a
tab, coordinates `q = 0` and `3843`), a bidirectional transition ending at the mirror of the second named position.
The two transitions form the `chain` of `playback.ndjson` (the first is `detailed`: 2 segments × 6 frames − 1 = 11).
`testdata/sample_*.txt` are symlinks to `basic.txt` run with their `<name>.sample.tsv` (`--sample`): `sample_ok`
(every class listed or `-`; each output line is byte-identical to a line of `basic/`), and `sample_missing_class`,
`sample_wrong_class`, `sample_not_empty`, `sample_unknown_class`, `sample_duplicate_row` and `sample_bad_index` (a
leading zero) where the dumper fails with the reason in `meta.json`.
`testdata/bad_digit.txt` has a non-base62 digit: the original rejects it, so its expected directory holds only
`meta.json` with the original's error. A test whose expected directory has no `graph.ndjson` must make the dumper
fail, and any other test must make it succeed. `testdata/<name>/` is the expected output, reviewed by hand: change it
only together with the dumper and say why in the PR.

## Inventory and sample (#35)

**Classes** (closed list, `CLASSES` in `dump.cpp`, from the spec's "Representative sample"; a block can be in
several). Counts in the full dump at the pin:

| Class | Rule | Full dump |
|---|---|---|
| `normal` | a transition in no **structural** class (`bidirectional`, `detailed`, `long`, `endpoint_*`, `edge_coordinate`, `error_or_unmatched`); the text classes do not exclude it (2,012 of 2,086 blocks have one; only 9 transitions have no class other than `normal`) | 635 |
| `named` | a named position (1-position block) | 601 |
| `bidirectional`, `detailed` | `properties:` of the block | 38, 159 |
| `long` | a transition of ≥ 15 positions | 16 |
| `endpoint_mirror`, `endpoint_swap`, `endpoint_mirror_swap` | `reorientation_from` or `_to` has mirror only, swap only, both | 217, 332, 75 |
| `duplicate_description` | the name the original looks a block up by equals another block's **of the same kind**: the first description line with a literal `\n` replaced by a space, among transitions (`step_by_desc`, `src/metadata.cpp:66-69`) or among named positions (`node_by_desc`, `src/metadata.cpp:81-89`); 136 of them are `...` | 894 |
| `edge_coordinate` | a coordinate with `q = 0` or `3843` | **0** (q spans 20…3791) |
| `description_newline`, `description_utf8`, `description_quote` | a description line with a literal `\n`, a byte ≥ 0x80, a `"` | 1281, 9, 997 |
| `has_ref`, `has_note` | a `ref:` line; a `note:`/`todo:` line | 1058, 304 |
| `error_or_unmatched` | a transition with an endpoint that matches no named position (an anonymous node, `src/graph.cpp:235-240`). A DB the original reports as an error does not load at all (`meta.json` `errors`), so no block of a loaded DB is an error. Named positions are not in it: 5 of them (nodes 111, 250, 292, 306, 546) are the endpoint of no transition, which is not a failed match | 239 |

`family` is the first entry of `FAMILIES` (`leg_locks`, `back`, `mount`, `side_control`, `turtle`, `guard`,
`standing`; fixed tag lists in `dump.cpp`) whose tags the block has, else `other`. A transition's tags are those of
the original's `is_tagged` (`src/metadata.hpp:32-37`): its own plus every tag that both endpoints have (1,159 of 1,485
transitions have no tag of their own).

**`sample.tsv`**: header `index<TAB>class<TAB>reason`, one row per (block, class); `index` is the block index of
`sequences.ndjson`. Selected from the full dump's `inventory.ndjson` (the `reason` says how): 20 `normal` (one per
family × length bucket present, `other` only at `2` and `>10`; fewest text classes, then first in file), 10 `named`
(endpoints of those transitions, round-robin over families), ≤ 3 per anomaly class (shortest first, at most one
named position per class; `duplicate_description`: a same-name pair plus one `...`). 69 rows: 68 over 62 blocks
(32 of them for the anomaly classes) and one `-`. The dumper fails on a row that names a block outside its class, an
unknown class, a duplicate row or a bad index (not decimal, over 9 digits, a leading zero, no such block), and if a
class has no row. **Allowed-empty**: a class with no block in the whole DB is listed with index `-`, and the dumper checks that it
is really empty (at the pin: `edge_coordinate`).

**`--sample`** filters every file by block index, in the same functions as the full dump: `sequences`,
`inventory`, `ops` (the middle position `n / 2` of each transition, every named position), `between` (the middle
pair `(n - 2) / 2` at `s = 0.5`; the first 10 transitions also at 0.25 and 0.75), `playback` (the 2 shortest
non-bidirectional transitions and the shortest bidirectional one, plus a `chain`), `spring` (10 named positions: those
listed under `named` first, then the other listed ones, in block order), `graph` (the listed transitions, the listed
nodes and the endpoints of the listed transitions; the `.index` line complete), `body.json` and `meta.json` complete
(counts of the whole DB). Every sample line is a line of the full dump **except the `chain` line**: the full dump
chains the first pair in index order, the sample the pair of listed transitions with the fewest positions (ties in
index order), so as not to spend the size budget on a long chain (at the pin: seqs 58 → 66).

`./build.sh oracle --sample` dumps to `build/oracle/sample/` and then replaces every file of `tests/fixtures/oracle/`
except `FULL.sha256` (`images/` is never touched) and writes `MANIFEST.sha256`: the `sha256sum` of every fixture but
the two manifests, `images/*.png` included, in C-locale path order.
Two runs give identical bytes. `.gitattributes` marks the fixtures `-diff linguist-generated` (the `.sha256` files
keep their diff).

Size at the pin: 1,540,722 bytes of working copy in 11 files (`ops` 696 KB, `playback` 317 KB, `between` 192 KB,
`sequences` 183 KB, `graph` 109 KB, `spring` 28 KB, `inventory` 9 KB, rest 7 KB); ~369 KB as `tar | gzip -9`. Hard limit 2 MB (spec; `images/` of the last PR of #35 counts too).

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
