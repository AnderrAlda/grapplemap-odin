# Spec: Phase 1 — research of the original

Epic: #3 · Milestone: "Fase 1: Investigación del original" · Date: 2026-11-20

## Goal
Study the original (GrappleMap by Eelis), pin it and make it runnable as an **oracle**, so that phase 2 (data
core) and phase 3 (viewer) can write exact-fidelity tests without reading C++ again:

1. `reference/GrappleMap` as a pinned, read-only submodule.
2. A reproducible oracle (Docker, Linux) that builds the original's tools plus our own dumper and produces
   fixtures and reference images.
3. Only a **representative sample** of fixtures is committed (normal cases + anomalies). CI generates the full
   dump with the oracle and checks it against a committed hash manifest. From phase 2 on, CI compares the
   implementation against that full dump.
4. `docs/original.md`: a specification of the original that is enough to reimplement it (data, graph, body,
   rendering, playback, web tools, editor).
5. `docs/architecture.md` and the initial ADRs.

This phase is documentation and tooling only: **no product Odin code** is written.

## Scope, files and interfaces

### Deliverables (one issue/PR per row; <400 hand-written lines each, generated files do not count)
Every issue and PR gets labels (`type:`, `area:`, `phase-1`) and the milestone "Fase 1: Investigación del original".

| # | Deliverable | Files |
|---|---|---|
| 1 | Submodule | `.gitmodules`, `reference/GrappleMap` @ `032c8f91809786b7b784852abd07cf3e10c0ea35` (master, 2020-03-14); `reference/CLAUDE.md` (read-only, how to bump the pin) |
| 2 | Oracle image | `tools/oracle/Dockerfile` (Ubuntu base pinned by digest, a compiler that accepts `-std=c++1y`), `tools/oracle/README.md`. It builds `grapplemap-indexer`, `grapplemap-dbtojs` and `grapplemap-mkpospages` from the submodule **without modifying it** (out-of-tree build: a copy or a SCons `variant_dir`) |
| 3 | Dumper (full dump) | `tools/oracle/dump/*.cpp`, linked against the original's `common` objects; `tools/oracle/dump/testdata/` (a small hand-written `.txt`); `./build.sh oracle [--sample\|--full\|--images\|--update-full-hashes]` (new target; `--images` and `--update-full-hashes` land with deliverable 4). `--full` writes the full dump to `build/oracle/full/` (git-ignored) |
| 4 | Data inventory + sample | `tools/oracle/sample.tsv` (selected sequences and class), `tests/fixtures/oracle/` (sample), `tests/fixtures/oracle/MANIFEST.sha256` (sample), `tests/fixtures/oracle/FULL.sha256` (hashes of the full dump), `tests/fixtures/oracle/images/*.png`, `.gitattributes` (`-diff linguist-generated` for generated files) |
| 5 | Oracle CI | `.github/workflows/oracle.yml`: a **separate workflow** (see "CI"); `ci.yml` is not changed |
| 6.. | `docs/original.md`, by section (see below); one PR per section or small group | `docs/original.md` |
| n | Architecture and ADRs | `docs/architecture.md`, `docs/adr/0002…0006` |

Also in every PR: CHANGELOG (Unreleased), and the root `CLAUDE.md` if commands (`./build.sh oracle`) or the map change.

### Order and priority
- **Two independent tracks after the submodule (1)**: the oracle (2 → 3 → 4 → 5) and `docs/original.md`.
  The original.md sections cite `file:line` of the submodule and **do not depend on the oracle**, so they go
  ahead even if the oracle is blocked.
- **original.md priority**: sections 1–6 first (format, graph, player, axes, transforms, interpolation; this is what
  phase 2 needs), then section 7 (rendering and camera). Sections 8 (web tools) and 9 (editor semantics) are the
  **last issues of the phase**.
- Section 10 (data inventory) and the sample (4) need the dumper (3). If the oracle is blocked, they wait.
- **Oracle timebox**: if the Docker image cannot build the original after a reasonable attempt (an older base image
  included), work on the oracle **stops and Ander is asked** before anything else is tried (patches, another
  approach, dropping deliverables). The docs track keeps going in the meantime.
- Then `architecture.md` and the ADRs (#43, #44). ADR 0002 needs the oracle to be settled; ADR 0003 needs
  sections 1–5; ADRs 0004–0005 need sections 3–5; ADR 0006 needs section 7. Sections 8 and 9 (#45, #46) close the
  phase.

### Database facts (measured on the pinned `GrappleMap.txt`)
- 2,086 blocks, 8,323 positions. A block with a single position is a **named position**; the loader removes it
  from the sequences (`src/persistence.cpp:154-169`, `loadGraph`): 601 named positions and 1,485 transitions with 7,722
  positions.
- Graph nodes are the named positions **plus anonymous nodes** that `Graph::find_or_add` (`src/graph.cpp:235`) creates
  for transition endpoints that match no named position. The total node count is not known yet; the dumper
  records it in `meta.json`.
- Transition length (positions): 2 → 89, 3–5 → 898, 6–10 → 428, 11–14 → 54, ≥15 → 16 (max 22).
  Counted with `awk` over the file; the dumper confirms them.
- `properties:` bidirectional = 38, detailed = 159.

### Dump format
NDJSON (one JSON object per line), in a fixed order (by block index), with no timestamps.
- Positions read from the file are stored **quantized**: for each coordinate, the integer `q` (2 base62 digits,
  `0…3843`). Decoding is documented as `x = q/1000 − 2`, `y = q/1000`, `z = q/1000 − 2`. This is exact and about
  4 times smaller than storing the doubles.
- Computed results (transforms, interpolation, playback) are stored as doubles with `%.17g` (exact round-trip).

Files (the same names in the full dump and in the sample):
- `meta.json`: submodule commit, md5 of `GrappleMap.txt` (the one the `.index` uses), dumper version,
  compiler and Mesa versions, counts, and errors reported by the original.
- `sequences.ndjson`: `{index, line_nr, description[], tags[], properties[], refs[], notes[], detailed, bidirectional, positions_q: [[[x,y,z]×23]×2]…}`.
- `graph.ndjson`: nodes (index, block of origin or `null` for anonymous nodes, description, tags) and, for each transition,
  `{from, to, reorientation_from, reorientation_to}` (translation, angle, swap, mirror) as the original builds
  them, plus the `.index` produced by `grapplemap-indexer`.
- `ops.ndjson`: `mirror`, `swap_players`, `orient_canonically_with_mirror/without_mirror`, `heading`, `center`.
- `between.ndjson`: `between(a, b, s)` for consecutive positions.
- `playback.ndjson`: frames from the frame-based path `frames()` (`src/paths.cpp:23`) / `follow()`
  (`src/graph_util.cpp:60`), with the default `frames-per-pos` of 11 (`src/makevideo.cpp:34`), halved for
  `detailed` transitions (`src/paths.cpp:42`). `follow()` emits `frames-per-pos + 1` positions per segment, so
  segment boundaries repeat; `frames()` drops the last frame of each transition (`src/paths.cpp:44`). Per
  transition the dump stores the **raw** frames and the frames after `smoothen` (`src/paths.cpp:8-21`, applied by
  callers such as `src/makevideo.cpp:93`; it is stateful and starts from that transition's first frame). The
  time-based `Playback::progress`
  (`src/playback.cpp:129-130`) is **not** dumped; it is described in section 6 and the viewer checks it as
  `between` over the oracle positions.
- `body.json`: `jointDefs`, segments (ends, length, mid radius, visible), colors per player and any constant from
  `playerdrawer.cpp`/`rendering.cpp` that affects geometry.
- `spring.ndjson`: `spring(p)` (input for phase 6).

**Full dump** (`--full`, CI only, never committed): every block; `ops` for every position; `between` for every
consecutive pair with `s ∈ {0.25, 0.5, 0.75}`; `playback` for every transition; `spring` for every named
position. Estimated size: about **0.3–0.5 GB** of text, with ~2.6 KB per position in doubles: `playback` ~175–390 MB
(6,237 segments × ~12 frames, ~6 for `detailed`, raw + smoothed), `ops` ~87 MB (8,323 positions × 4 transforms), `between` ~49 MB (6,237 pairs × 3
values of `s`), the rest ~8 MB. That is why only its hashes are committed.

### Representative sample (what is committed)
The sample is chosen by hand from the inventory (section 10 of `original.md`) and listed in
`tools/oracle/sample.tsv` (`index`, `class`, `reason`). `./build.sh oracle --sample` produces it **from the same
code** as the full dump (filter by index). The dumper fails if a class in the list has no example.

| Class | Examples | Criterion |
|---|---|---|
| Normal transitions | 20 | stratified by tag family (guard, side control, mount, back, turtle, standing, leg locks) and by length (2 / 3–5 / 6–10 / >10) |
| Named positions | 10 | the nodes of the sampled transitions first, plus others with different postures |
| Anomalies | ≤ 3 per class, ~25 in total | `bidirectional`; `detailed`; length ≥ 15; endpoint matched with mirror; with swap; with mirror+swap; duplicate descriptions; coordinates at the edges of the range (`q = 0` or `3843`); descriptions with `\n`, UTF-8 or quotes; blocks with `ref:`/`note`/`todo`; any block the original reports as an error or cannot match |

Within the sample, `ops` covers one position per transition plus every named position (~55). `between` covers
one pair per transition with `s = 0.5`, and 10 pairs with `{0.25, 0.75}` as well. `playback` covers 2 short
transitions and 1 bidirectional one. `spring` covers 10 positions. `body.json` is complete.

**Justification of the size** (estimate; PR 4 records the real size):

| File | Estimate |
|---|---|
| `sequences.ndjson` (~45 transitions + 10 nodes ≈ 260 positions × 0.75 KB quantized) | ~200 KB |
| `graph.ndjson` (sampled transitions and nodes) | ~30 KB |
| `ops.ndjson` (~55 positions × 4 transforms × 2.6 KB) | ~570 KB |
| `between.ndjson` (~65 interpolations × 2.6 KB) | ~170 KB |
| `playback.ndjson` (~45 frames, raw + smoothed, × 2.6 KB) | ~235 KB |
| `spring.ndjson` + `body.json` + `meta.json` | ~40 KB |
| `images/` (6 PNGs, 480×360) | ~250 KB |
| **Total** | **~1.5 MB** of working copy (git compresses the text; the pack should be well under 1 MB) |

That is about 0.3–0.5% of the full dump, and it covers every documented class. The size is driven by the transform
results in doubles (2.6 KB per position is a lower bound; ~2.9 KB with brackets and commas still fits), so it is
cut by covering one position per transition, not every position. **Hard limit:
2 MB.** If the real dump is larger, the sample is reduced (fewer normal transitions, never fewer anomaly classes)
before merge, and the PR says so. Lowering the limit or keeping something over it needs Ander's OK.

### CI (`oracle` workflow)
**Where and when it runs**: in its own workflow, `.github/workflows/oracle.yml`, not in `ci.yml`. In GitHub
Actions `paths` filters the whole workflow's `push`/`pull_request` triggers (not a job), and `schedule` takes no
`paths`; putting them in `ci.yml` would skip or duplicate the regular jobs. Triggers of `oracle.yml`:
- `pull_request` and `push` to `main` with `paths: [tools/oracle/**, reference/GrappleMap, tests/fixtures/oracle/**,
  .github/workflows/oracle.yml]` (`reference/GrappleMap` is the submodule pointer; docs in `reference/` do not
  trigger it);
- `workflow_dispatch`;
- a nightly `schedule` (runs on the default branch).

It is **not** a required check (a path-filtered workflow that does not run would leave a required check pending).
Checkout uses `submodules: true`. The regular `ci` jobs do not depend on it.

1. Build the image (with a layer cache) and the dumper.
2. `--sample`: regenerate the sample and fail if `git status --porcelain tests/fixtures/oracle` is not empty
   (provenance and determinism; also catches new untracked files). `--sample` never writes `images/` (only
   `--images` does), so the PNGs are not regenerated here (see edge cases).
3. `--full`: generate the full dump, check it against `FULL.sha256` (the full data matches what was committed
   without storing it), and upload it as an artifact (compressed, short retention).
4. From phase 2 on, the fidelity job downloads the latest full-dump artifact from `main` (nightly or the last run
   that changed the oracle) and runs the Odin fidelity tests over the full DB. Designing that job is phase 2 work.
   Locally, `./build.sh test` only uses the sample and does not need Docker.

### Sections of `docs/original.md`
Every claim cites `file:line` of the pinned submodule. Nothing is assumed: anything not verified is marked as such.
1. **Data format**: the structure of `GrappleMap.txt` (description lines, `tags:`, `properties:`, `ref:`, `note`,
   `todo`; literal `\n` in descriptions; positions are lines that start with a space, 4 lines per position,
   `encoded_pos_size = 2·23·3·2 + 4·5`), base62 (`a-zA-Z0-9`), 2 digits per coordinate, `value/1000`, offset `−2`
   on X and Z, and the resulting range. A grammar (EBNF) and the errors the original parser detects.
2. **Graph model**: named positions (1-position blocks) vs. transitions; how endpoints are matched to nodes by
   reorientation (`is_reoriented`, `basicallySame` with a threshold of `0.0016` m² per joint); the `.index` cache
   keyed by md5; `bidirectional`, `detailed`; looking up nodes by description.
3. **Player model**: 23 joints, `PlayerJoint`, `jointDefs`, segments and their lengths, player 0/1 (`t`/`b`).
4. **Units and axes**: meters, vertical axis, handedness, `heading`, `normalRotation`, `center`, `cameraOffsetFor`.
5. **Transforms**: `mirror`, `swap_players`, `Reorientation`/`PositionReorientation`, `compose`, `inverse`,
   canonical orientation.
6. **Interpolation and playback**: `between`, speed (segments per second: 5, or 10 for `detailed`,
   `src/playback.cpp:129-130`), `frames-per-pos` (halved for `detailed`, `src/paths.cpp:42`),
   `smoothen`, the "chaser" (`between(chaser, target, 0.2)`), behaviour at the ends and across chained transitions.
7. **Rendering and camera**: `playerdrawer` (spheres/cylinders, radii, icosphere subdivision), the
   `triangle.*shader` shaders, colors, lights, floor, camera (`camera.hpp`) and its controls.
8. **Web tools**: search, per-position pages, explorer, composer and the web editor: what they do and their UX
   (input for phase 5).
9. **Editor semantics**: `spring()`, the bone-length constraint, editing/inserting/deleting positions and
   sequences, persistence on save (input for phase 6).
10. **Data inventory**: real counts in the DB, and the anomaly classes with every case found. This is the source
    of `sample.tsv`. Anomalies are documented, **not fixed**.

### `docs/architecture.md`
Packages (`core`, `render`, `ui`, `editor`, `main`) and the direction of their dependencies. Data flow
(bytes → parser → graph in an arena → interpolation → render). Memory strategy. Test strategy: unit, property,
round-trip, fidelity (sample locally, full dump in CI) and golden. Links to the ADRs.

### ADRs (tentative numbering)
- `0002` Oracle: the original built in Docker is the source of truth. Committed sample + full dump in CI checked
  by hashes, with the size limit and the reasons for it.
- `0003` Numeric precision: `f64` in `core` (as in the original; input values quantized to 1/1000), `f32` only in
  `render`. Tolerance policy: exact where the original is deterministic; an explicit, justified tolerance where it
  is not, only with Ander's OK.
- `0004` Axes and units: how the original's coordinate system maps to raylib's (decided after section 4).
- `0005` Own JSON format: a lossless schema for phases 2 and 6 (schema version, stable IDs, positions in the
  original's quantization for an exact round-trip with `GrappleMap.txt`).
- `0006` Body rendering technique: how to reproduce the exact geometry of `playerdrawer` (instanced sphere +
  cylinder, capsules, SDF…). It stays `proposed` if the final decision needs a prototype in phase 3.

## Out of scope
- Any Odin code in `src/` (parser, graph, render): phases 2 and 3.
- Odin fidelity tests that consume the fixtures: phase 2. The CI job that compares against the full dump starts
  in phase 2; phase 1 only leaves the full dump generated, hashed and published as an artifact.
- Golden images of our own viewer in `tests/golden/`: phase 3 (the oracle images go in
  `tests/fixtures/oracle/images/`).
- Committing the full dump, or copying `GrappleMap.txt` into `data/`.
- Modifying the original or its data, or "fixing" anomalies.
- Building the original's GUI/VR tools (`glfw-editor`, `vr-*`) or the emscripten build.
- The open phase 0 issues (#11–#27, #21 included).

## UX / behaviour
- `./build.sh oracle --sample` (the default) and `--full` need Docker. Without Docker, they fail with a clear
  message and a non-zero exit code. Both are idempotent: running twice in a row produces no diff. They print the
  files written and their hashes.
- `./build.sh oracle --update-full-hashes` rewrites `FULL.sha256`. It is only used when the dumper changes, and
  the PR explains why.
- `./build.sh ci` does **not** run the oracle, so it does not need Docker locally. The `oracle` workflow in CI does.
- The fixtures are read-only for tests. Protecting `tests/fixtures/oracle/` against direct edits by the agent
  (hook + `Edit(...)` deny; `./build.sh oracle` still regenerates them) is proposed in PR 4 and not turned on
  without Ander's OK.

## Edge cases
- **Determinism**: fixed output order, `C` locale, the same compiler flags (the SConstruct's `-O3`, without
  `-ffast-math`, no `-march=native`). The image is pinned to `--platform linux/amd64`: an Apple Silicon Mac would
  otherwise build `arm64`, where GCC fuses multiply-adds by default. This matters because the arithmetic
  (`between`, transforms, `spring`) lives in the original's `common` objects, built with the SConstruct's flags.
  Baseline x86-64 emits no FMA; the dumper's own code also uses `-ffp-contract=off`. The compiler and libm come
  from the base image pinned by digest. If two builds give different doubles, `FULL.sha256` catches it; the cause
  is documented and decided in ADR 0003.
- **Reference images**: `grapplemap-mkpospages` renders 480×360 PNGs (`src/mkpospages.cpp:584-585`) but walks
  the whole DB (its help warns the first run takes "many hours"; not measured). `--images` instead calls the
  original's `ImageMaker::png` (`src/images.hpp:198`, `src/images.cpp:340`) for the 6 chosen positions only,
  reproducing what `mkpospages` does before the call (`src/mkpospages.cpp:578-582`: canonical orientation with
  mirror, `ymax`) and choosing an `ImageView`. `ImageMaker` creates its own OSMesa context
  (`src/images.cpp:525`); the dumper provides a `Graph` and an existing `res_dir` and `res_dir/store/`
  (`src/images.cpp:529-532`). `png` writes `store/<hash>…png`, where the hash is `boost::hash_value` and depends on
  the Boost version, and a symlink `res_dir/<base_linkname><view><w>x<h>.png` (`src/images.cpp:329-352`): the
  dumper passes a deterministic `base_linkname` and copies the file the symlink points to. This part links
  `images.o` and `rendering.o` (`rendering.cpp` + `playerdrawer.cpp`) with OSMesa, GLU, ftgl, png,
  boost_filesystem, boost_system, pthread, gvc and cgraph (`src/SConstruct:48-50`). If these cannot be built in the image, the oracle timebox applies.
- **OSMesa**: PNGs can change between Mesa versions. They are regenerated by hand (`./build.sh oracle --images`),
  have their own hash in `MANIFEST.sha256`, and the Mesa version is recorded in `meta.json`. CI does not compare
  them pixel by pixel.
- **Building the original with a modern toolchain**: if it does not build as is, an older base image is pinned.
  If that also fails, the oracle timebox applies (see "Order and priority"): stop and ask.
  The submodule is never patched. If a patch cannot be avoided, it goes in `tools/oracle/patches/`, justified in
  ADR 0002.
- **Errors in the DB**: if the original rejects a block, the dumper records it in `meta.json`, the inventory
  documents it, and it goes into the sample as an anomaly.
- **Descriptions** with literal `\n`, UTF-8 and quotes: correct JSON escaping, with a dumper test over `testdata/`.
- **Pin bump**: changing the submodule commit invalidates the sample, `FULL.sha256` and the inventory. It needs
  its own PR that regenerates all three.
- **CI artifact size**: if the full dump does not fit the artifact limits or the job time, it is split by file.
  The Odin comparison is never moved to a subset without Ander's OK.
- **`between` with `s` outside [0, 1]**, and 2-position transitions: document the behaviour observed.

## Decisions and trade-offs
| Decision | Chosen | Why / cost |
|---|---|---|
| Oracle | Docker, Linux | Reproducible on macOS and in CI. Cost: Docker is needed to regenerate |
| Committed data | Sample of ~1.5 MB (limit 2 MB) + `FULL.sha256` | The repo stays light. The full DB is still checked through its hashes. Cost: local fidelity tests only cover the sample |
| Full coverage | Full dump in CI, published as an artifact | Exact fidelity over the whole DB from phase 2. Cost: Docker CI time, limited to oracle-related changes, manual runs and a nightly run |
| Oracle risk | Timebox: stop and ask if it does not build | Building a 2020 C++ code base can sink time. The docs track does not depend on it |
| Sample format | Input quantized to integers, computed results as `%.17g` doubles | ~4 times smaller with no loss. Doubles only where the original computes them |
| Node matching | Document the algorithm + dump the assignment | Phase 2 reimplements it and must match 100%. The editor (phase 6) needs it to match new nodes |
| Pin | Submodule at `032c8f9` | The latest master. Data is read from the submodule; `data/` is left for our own graph. `loadGraph(filename)` and the SConstruct write `GrappleMap.txt.index` next to the DB, and with an index present the graph is built through another path (`find_or_add_indexed`, `src/graph.cpp:304-348`, chosen when the md5 matches and the index is not empty, `src/persistence.cpp:201-228`). So the dumper always uses `loadGraph(istream)` (`src/persistence.cpp:171`, no index), and `grapplemap-indexer` runs separately on a copy of the DB to produce the `.index` that goes into `graph.ndjson`; the submodule is never dirtied |
| Language | English (this spec, `original.md`, `architecture.md`, new ADRs) | Matches README, CHANGELOG and the code. The new ADRs translate the headings of `docs/adr/TEMPLATE.md` (Status, Context, Decision, Alternatives, Consequences); the template itself is left for #18 |
| Split | One issue per deliverable | Small, reviewable PRs |

## End-to-end verification
In a clean clone, after every PR of the phase is merged:
```sh
git submodule update --init && git -C reference/GrappleMap rev-parse HEAD   # = 032c8f9…
./build.sh setup
./build.sh oracle --sample && git status --porcelain tests/fixtures/oracle    # empty (deterministic)
(cd tests/fixtures/oracle && shasum -a 256 -c MANIFEST.sha256)                # all OK
du -sh tests/fixtures/oracle                                                  # ≤ 2 MB
./build.sh oracle --full && (cd build/oracle/full && shasum -a 256 -c ../../../tests/fixtures/oracle/FULL.sha256)
jq -r .counts tests/fixtures/oracle/meta.json                                 # 2,086 blocks, 8,323 positions; nodes as the original's Graph builds them
./build.sh ci                                                                 # green, without Docker
```
- The `oracle` workflow runs only for its paths, `workflow_dispatch` and the nightly schedule (check: a docs-only PR does
  not trigger it).
- CI is green on the last PR, including the `oracle` workflow (sample with no diff, full dump matching `FULL.sha256`,
  artifact published).
- Every class in `sample.tsv` has at least one example, and every anomaly class in section 10 is in the sample.
- `docs/original.md` covers the 10 sections with `file:line` references. `code-reviewer` (opus, core area) checks
  a sample of claims against the submodule and finds no discrepancies.
- `docs/architecture.md` and ADRs 0002–0006 exist and are linked from `CLAUDE.md`/`architecture.md`.
- The checklist of epic #3 is ticked, with links to the PRs.
