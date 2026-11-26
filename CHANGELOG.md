# Changelog

All notable changes to this project are documented here.
Format: [Keep a Changelog](https://keepachangelog.com/en/1.1.0/); versioning: [SemVer](https://semver.org/).

## [Unreleased]

Unreleased changes live in `changelog.d/` until the next release.

## [0.2.0] - 2026-11-26

Phases 1 and 2: research of the original and the data core (parser, graph, transforms, playback, lookups, export, JSON), verified against the oracle.

### Added
- `docs/original.md` section 6: interpolation and playback (`between` and its term order, frame-based `follow`/`frames` with integer-halved frames per position for `detailed`, repeated boundaries and dropped last frame, `smoothen` with state across a script, time-based `Playback::progress` in segments per second with leftover time and pauses, the per-frame 0.2 chaser, chained transitions, input for phases 2/3), cited to the pinned original and cross-checked against the oracle test data (#41).
- `docs/original.md` section 5: transforms (`mirror`, `swap_players`, `Reorientation`/`PositionReorientation` and their order of application, `compose`/`inverse` with derived formulas, canonical orientation with and without mirror, how the graph uses them, input for phase 2), cited to the pinned original (#40).
- Oracle dumper part 2: `ops.ndjson` (`mirror`, `swap_players`, both canonical orientations, `heading`, `center` of every position), `between.ndjson` (`s` = 0.25/0.5/0.75 for every consecutive pair), `playback.ndjson` (`frames()` with frames-per-pos 11, 5 for `detailed`, raw and smoothed per transition, plus one 2-transition chain smoothed in one call) and `spring.ndjson` (every named position); files are streamed to temporaries and renamed at the end; full dump ~0.54 GB (#34).
- Oracle dumper (`tools/oracle/dump`, linked against the original's `common` objects) and `./build.sh oracle --full|--test`: `meta.json`, `sequences.ndjson`, `graph.ndjson` (including anonymous nodes and the `.index`) and `body.json` of the whole DB to `build/oracle/full/`, plus a dumper test over `tools/oracle/dump/testdata/` (#34, part 1).
- `docs/original.md` sections 3-4: player model (23 joints and `jointDefs`, the 28 limbs with lengths, mid radii and visibility, players 0/1) and units and axes (meters, `y` up, right-handed derivation, `heading`, `normalRotation`, `center`, `cameraOffsetFor`, input for ADR 0004), cited to the pinned original (#39).
- MAIN must run on Opus: documented in the models table and «Sigue trabajando», and `/orchestrate` refuses to launch workers from a non-Opus session (`opusplan` drops to Sonnet after plan approval) (#90).
- `tests/hooks/guard-bash.test.sh` (run by `./build.sh test`): table of allowed/blocked commands for the `guard-bash` hook (#20).
- `./build.sh worktree-remove <branch>`: removes a worktree and its branch only when the worktree and its submodules are clean; otherwise prints the status, deletes nothing and exits non-zero (#54).
- «Sigue trabajando» flow: MAIN proposes a batch of up to 3 issues with their plans in a single approval request and runs `/orchestrate` on it; `/orchestrate` is now model-invocable and picks the worker model per issue (`claude --model`); `/start-task` inherits it (#83).
- `docs/original.md` section 2: graph model and node matching (named positions vs. transitions, anonymous nodes, `is_reoriented`/`basicallySame` matching and its order, `.index` cache, `in`/`out`, `bidirectional`/`detailed`, lookup by description), cited to the pinned original (#38).
- `docs/original.md` section 1: data format and parser of `GrappleMap.txt` (structure, base62 position encoding,
  grammar, parser errors and edge cases, DB checks), each claim cited to the pinned original (#37).
- Phase 1 spec (`docs/specs/phase-1-original-research.md`): pinned original as a submodule, Docker oracle with a
  committed fixture sample and a full dump checked in CI, and the plan for `docs/original.md`, `docs/architecture.md`
  and the initial ADRs (#3).
- Original GrappleMap as a read-only submodule `reference/GrappleMap`, pinned at `032c8f9`, with `reference/CLAUDE.md`
  (read-only and pin-bump rules) (#32).
- `/orchestrate` skill: the MAIN session coordinates worktrees through Herdr (launch workers, watch them, take PRs to ready);
  merge and plan approval stay with the user (#55).
- `/orchestrate` cleans up finished work: after a merge it removes the worktree, deletes the local branch and prunes remote
  refs, only when the PR is merged, the local head equals the PR head and the tree is clean (#62).
- `tools/oracle`: Docker image (Ubuntu 18.04 pinned by digest, linux/amd64) that builds the original
  `grapplemap-indexer`, `-dbtojs` and `-mkpospages` out of tree, plus the object files for `--images` (#33).
- `./build.sh space-id <branch>`: stable Herdr space id (`sp` + 32 hex) derived from the branch name; `/orchestrate` uses it so each
  worker opens in its own Herdr space (named after the worktree folder) instead of a tab of MAIN's space (#79).
- `build.bat setup` warns when `git submodule update --init` fails (offline?) and says how to retry, like `build.sh setup` (#50).
- Phase 2 spec (data core): `docs/specs/phase-2-core.md` (#4).
- `docs/original.md` section 10: data inventory at the pin (counts, every anomaly class (all cases of the small ones, count and command for the large ones), the one self-loop, 124 anonymous nodes, no pillar-basis degeneracy) (#35).
- `./build.sh oracle --images`: renders 6 named positions with the original's `ImageMaker::png` (as mkpospages'
  position pages) into `tests/fixtures/oracle/images/` plus `meta.json` with the Mesa version; Mesa's softpipe
  driver, byte-identical across runs (#35).
- Oracle fixture sample: the dumper takes `--sample` (same code path as the full dump, filtered by block index); `tools/oracle/sample.tsv` lists 69 rows over 62 blocks covering every class, and the dumper fails on an empty or wrong class; `./build.sh oracle [--sample]` (the default) writes `tests/fixtures/oracle/` (1.54 MB) with `MANIFEST.sha256`, `--update-full-hashes` writes `FULL.sha256` and `--full` checks against it; `.gitattributes` marks the fixtures as generated (#35).
- Oracle data inventory: the dumper (version 3) writes `inventory.ndjson`, one line per block with its tag family, length bucket and anomaly classes (the closed list of the phase-1 spec), the input for the oracle fixture sample of the next #35 PR (#35).
- `oracle` workflow: builds the original in Docker on oracle paths, manual dispatch and nightly, checks the sample and `FULL.sha256` and uploads the full dump as an artifact (#36).
- `docs/original.md` section 7, rendering and camera: body geometry (icosphere spheres, 10-face pillars, fat triangles), colors, fixed-function and shader lighting, floor grid, camera and per-program controls, the `ImageMaker` setup behind the oracle images, and the input for ADR 0006 (#42).
- `docs/architecture.md` (packages and dependency direction, data flow, memory and test strategy) and ADRs 0002 (oracle: the original built in Docker as the source of truth) and 0003 (numeric precision: `f64` in `core`, no FMA contraction, what is compared bit for bit and what may need a tolerance), proposed for acceptance (#43).
- ADRs 0004 (axes and units: the original's meters, `y` up, right-handed coordinates used as-is in raylib, camera matrices from the original's formulas), 0005 (own JSON format: schema version, stable IDs, positions in the original's quantization, byte-exact round trip with the original's writer) and 0006 (body rendering: the original's meshes rebuilt on the CPU with per-vertex fixed-function lighting for the reference path, a separate modern path, pixel tolerance left to Ander), linked from `docs/architecture.md`, proposed for acceptance (#44).
- `docs/original.md` section 8: the original's web tools (search, per-position pages, explorer, composer, web editor): data pipeline, UX, differences from the C++ viewer and input for phase 5 (#45).
- `docs/original.md` section 9: editor semantics of the original (state and undo, `spring` and limits, graph effects of edits, operations, save), input for phase 6 (#46).
- Docs: «Reanudar MAIN» in `docs/ai-workflow.md` and a fixed «Momento de /clear» block in the `orchestrate` skill, so MAIN says when to `/clear` and what to type afterwards (#87).
- Changelog fragments: PRs add `changelog.d/<issue>-<slug>.md` instead of editing `CHANGELOG.md`, so PRs of the same batch no longer conflict; `./build.sh changelog-check` (part of `check`) validates their headings, the `release` skill folds them into `CHANGELOG.md`, and `/orchestrate` documents how to resolve shared-file conflicts after a merge (#98).
- `core`: player model types (`V3`, `Joint`, `Player`, `Position`), the original's joint and segment tables, its
  constants copied verbatim, and the `Error` union of the package (#136).
- `core`: `GrappleMap.txt` parser `parse_db` (blocks, base62 decoding, `line_nr`, `tags:`/`properties:`, strict 4 × 69 position layout, first error with line and block) (#137).
- `tests/fidelity/`: the body tables of `core` vs the oracle's `body.json` (bit for bit), and a seeded mutation test
  over the real DB (truncation, byte flip, line swap) where `parse_db` must never panic or leak (#138).
- `tests/fidelity/`: fidelity tests of `core` against the oracle (#138): `parse_db` of the real DB vs
  `sequences.ndjson` and `meta.json` (strings exact, coordinates bit for bit), over a streaming NDJSON reader.
  `GM_ORACLE_DIR` points them at the full dump; the default is the committed sample. A missing
  `reference/GrappleMap` submodule fails them.
- `core`: `between` position interpolation `a + (b − a)·s` (bit-identical to the original; fidelity test against `between.ndjson`) (#139).
- `core`: trig-free position transforms `mirror`, `swap_players`, `heading` and `center` (bit-identical to the original; fidelity test against `ops.ndjson`) (#139).
- `core`: reorientations (`Reorientation`, `Position_Reorientation`, `rotate`, `apply`, `reorient`) and canonical orientation (`normal_rotation`, `normal_translation`, `canonical_reorientation_*`, `orient_canonically_*`), in the original's operation order, with the correctly rounded `cr_atan2`/`cr_sin`/`cr_cos` (#140).
- Fidelity: `orient_canonically_with_mirror`/`…_without_mirror` compared bit for bit against `ops.ndjson`: 0 mismatches on the sample (62 positions) and on the full dump (8,323) (#140).
- Oracle dumper v4: `compose.ndjson` (`inverse`/`compose` of the endpoint reorientations of every transition),
  `save.txt` (full dump only) and `save_md5`/`save_equals_db` in `meta.json`; `save(loadGraph(DB))` equals the DB
  byte for byte at the pin (#141).
- `core.load_graph`/`graph_destroy`: the graph of the original (named positions first, anonymous nodes for unmatched
  sequence ends, lowest-index match wins, edges in file order) in its own arena, with
  `Duplicate_Position_Description`; checked against the oracle's whole node numbering (#142).
- `core`: the original's lookups by name (`node_by_desc`, `step_by_desc`, `named_entity`), quirks included; an out-of-range index or a `p<N>` that overflows is "not found", and an overflowing `l<N>` is not an `l` name, instead of the original's undefined behaviour or crash (#143).
- `core`: `inverse`/`compose` of position reorientations and their building blocks `reorientation_inverse`/`reorientation_compose` (`compose(a, b)` = first `a`, then `b`; angle not wrapped), bit-identical to the original and checked against the oracle's `compose.ndjson` (#144).
- `core.export_txt`: writes a graph as `GrappleMap.txt` exactly like the original's `save` (named positions, then
  transitions; `round((x + 2) * 1000)` in base62, 4 × 69 layout), rejecting with `Export_Error` what could not load
  back (description line starting with a space or holding `'\n'`, empty description, duplicate position description,
  coordinate outside 0…3843 or NaN); `export_txt(load_graph(DB))` is the DB byte for byte (#145).
- Fidelity tests load the DB graph once per test binary (`shared_graph`) (#145).
- `core.export_json`: writes a graph as the project's own JSON (ADR 0005) with a fixed, hand-written layout and
  RFC 8259 string escaping; `Json_Error` for empty or duplicate descriptions, bad ids, invalid UTF-8 and coordinates
  outside 0…3843, all checked before allocating (#146).
- Stable ids: `Sequence.id` (1-based block number), `Node.id` (`NO_ID` for anonymous nodes) and `Graph.next_id` (#146).
- `fidelity` workflow: runs the fidelity tests over the full oracle dump on linux and macOS (PRs touching core,
  fidelity tests, fixtures or `build.sh`; nightly; manual) (#147).
- `--load <file>` prints a one-line graph summary (blocks, positions, named, transitions, nodes, anonymous); with `--headless` no window opens. Distinct exit codes for invalid database (4), I/O error (5) and usage error (6) (#148).
- `./build.sh bench`: load benchmark over the full database (median/min/max of 9 runs) (#148).
- `core`: test of `parse_db` failing each allocation through its `allocator` in turn, on a valid file and on one ending in a `Bad_Base62_Digit`: `Out_Of_Memory` (or the parse error), no leak, no bad free (#151).
- `core.cr_atan2`: correctly rounded binary64 `atan2`, ported from CORE-MATH (MIT). `core` uses it on every target instead of `math.atan2` or the libm; tests compare it bit for bit against `tools/cr_atan2_ref.py`, a Python `decimal` reference (#161).
- `core`: correctly rounded `cr_sin`/`cr_cos` (binary64, round to nearest), ported from CORE-MATH (MIT) and used on every target instead of the host libm, so trigonometry matches the oracle bit for bit (#162).
- `tools/cr_trig_ref.py`: standard-library-only generator of the correctly rounded reference values in `tests/fixtures/cr_sin_cos.txt` (#162).
- Literal-bit test of `orient_canonically_with_mirror`/`without_mirror` against values computed outside Odin (`tools/canonical_ref.py`, `tests/fixtures/canonical.txt`) (#168).
- `core`: node matching (`basically_same`, `head2head`, `is_reoriented` with the original's pre-filter and four attempts in order), bit-identical to the original's `reorientation_from`/`_to` on every transition of the DB (#169).
- Fidelity: `is_reoriented(node, sequence end)` compared bit for bit against `graph.ndjson`: 0 mismatches on the sample (49 transitions) and on the full dump (1,485 transitions, 2,970 ends) (#169).
- `core`: each graph node's `incoming`/`outgoing`/`in_out` step lists, in the original's order (`Graph::compute_in_out`) (#173).
- `tests/fidelity`: `load_graph` over seeded mutants of a 60-block sample of the DB (named positions + transitions):
  an error or a graph with every edge end and step in range, no panic, no leak (#173).
- `core`: playback (`follow`, `frames` with captions, `smoothen`), bit-identical to the original's `frames()`/`smoothen()` and checked against the oracle's `playback.ndjson`, including a chained path smoothed in one call (#181).
- `core`: JSON reader `load_graph_json` (ADR 0005): any RFC 8259 layout, strict schema, precise `Json_Error`s with line and block; round trips `txt → JSON → txt` and `JSON → JSON` checked against the DB (#182).

### Changed
- `/pr` verifies every PR body edit by reading the body back and falls back to the REST API (`gh api -X PATCH`, with a narrow `allow` rule for `repos/{owner}/{repo}/pulls/*`) when `gh pr edit` fails, as it does with the old `gh` on the server; it marks ready only after seeing the CI box ticked, which the PR template now includes (#76).
- `/pr` review-round rule: a re-review after blocker fixes that returns only non-blockers counts as the single round; non-blockers go to the task's issue; `docs/ai-workflow.md` restates that blockers are always fixed (#48).
- Worker flow: `/orchestrate` launches each worker with `claude "/start-task N <plan path>"` as the initial prompt (a slash command sent with `hc send` arrives wrapped as text and is not executed). `/start-task` runs setup, copies and commits the approved plan, implements and invokes `/pr`; `/pr` is now invocable by workers and waits for CI before marking ready; `hc send|kill|rm` in `allow` are scoped to terminals named `w-*` (#71, #69).
- `/orchestrate` now drives Herdr through `hc` (herdr-core), which is what the Herdr app runs its terminals on; the old `herdr` CLI could not see them. Workers are launched with `hc run --bg --outlive-parent` labelled into MAIN's space (recommended on the server, so it keeps going while the laptop sleeps), and the allow rules use `hc ls|get|read|wait|send|run --bg` instead of `herdr ...`; `hc send --force` is denied, and the residual risk of `hc send`/`run --bg` is documented (#68).
- Agent autonomy rules (create issues/branches/PRs without asking, mark ready when CI is green, review has no blockers and the checklist is
  complete) now live in `CLAUDE.md`; `/pr` no longer asks for confirmation before opening the draft and `/orchestrate` no longer points to
  a Claude memory entry (#65).
- Claude Code permissions: `git push`, `gh pr create/ready/edit/comment`, `gh issue create/edit/comment` and the specific
  `herdr` subcommands the orchestrator uses move to `allow` so worktree workers do not stall; `herdr pane run/send-*`,
  `agent send-keys`, `worktree remove` and `update` stay out of `allow`. `deny` rules are unchanged; the push guard now also
  blocks `--mirror`, `--all` and `+refspec` pushes (#55).
- Write protection narrowed from `reference/` to the submodule `reference/GrappleMap/`; `./build.sh setup` and `worktree`
  (and `build.bat setup`) initialize the submodule (#32).
- `/pr` skill: at most one round of non-blocking review findings is applied per PR; the rest go to issues.
- `CLAUDE.md`: every issue and PR gets labels and its phase milestone when created (#29).
- `CLAUDE.md`: non-blocking review findings become issues labeled `tech-debt` in the `Backlog` milestone, unless `priority:high`.
- `docs/original.md` §7.6 and §4.2: the oracle images settle the `OSMESA_RGB` channel order (the PNGs are BGR: player 0 shows blue, player 1 red), the heading-N on-screen camera (`+x` right, eye on `+z`) and the softpipe driver choice; the `[unverified]` marks are gone (#127).
- `./build.sh test` fails a test on leaks and bad frees (`ODIN_TEST_FAIL_ON_BAD_MEMORY`, #151); `check`, `fmt` and
  `fmt-check` also cover `tests/fidelity/`.
- CI checks out the submodule in the `test` and `bench` jobs.
- ADR 0003 amendment: `core`'s `atan2`/`sin`/`cos` are its own correctly rounded functions (CORE-MATH); `./build.sh check` rejects `math.`/`libc.` `atan2`/`sin`/`cos` in `src/core` (#161).

### Fixed
- `protect-paths` and `guard-bash` hooks close the write paths into `reference/GrappleMap/` and `tests/golden/`: paths are normalized (`./`, `..`, `$PWD`, symlinks), `NotebookEdit` is matched, and Bash writes (redirections, `tee`, `sed -i`, `cp`/`mv`/`rm`, `git checkout`/`restore`, `cd` + write…) are blocked while read-only use stays allowed; tests in `tests/hooks/` (#21).
- Claude Code permission rules: removed `Write(...)` path rules, which have no effect; the existing `Edit(...)` rules
  protect `reference/`, `tests/golden/` and `.github/workflows/` for every file-writing tool (#29).
- `guard-bash` hook: judges each command segment separately (no more false positives like `git push origin feat && git log main`) and skips git global options (`-C`, `-c`, `--git-dir`, ...); now also blocks `git push` with grouped force flags (`-fu`), `+`/`:` refspecs, `-d`, and `rm` with split or long recursive/force options (#20).
- `./build.sh worktree` resolves the target path from the main worktree, so it no longer nests `grapplemap-odin-wt` when run from another worktree, and no longer hides `git worktree add` errors (#31).
- Shell tests no longer inherit the git hooks' `GIT_*` environment: `./build.sh test` clears it and the tests share `tests/lib/sandbox.sh` (temp-dir sandbox plus `sandbox_assert_repo`), with a regression test (#111).

## [0.1.0] - 2026-11-20

Phase 0: repository, infrastructure and AI-assisted workflow. No viewer yet.

### Added
- Minimal raylib window (`src/main.odin`) with `--headless --frames N` mode for smoke tests, and a
  tracking allocator that exits with code 3 on leaks or bad frees in debug builds.
- `build.sh` with targets for check, format, debug/release builds, tests, golden tests, benchmarks, CI and git worktrees;
  `build.bat` offers a subset for Windows (setup, check, fmt, debug, release, run, test, ci).
- Local git hooks (`.githooks/`): Conventional Commits validation, formatting and vet checks, tests on push,
  and blocking of commits and pushes to `main`. Activated with `./build.sh setup`.
- GitHub Actions: CI (lint, tests, golden, build matrix, bench) and tag-triggered release workflow.
- Issue and PR templates, CODEOWNERS, Dependabot for Actions, SECURITY, CONTRIBUTING.
- Claude Code configuration: project `CLAUDE.md` files, permissions, hooks, status line, skills
  (`/spec`, `/plan`, `/start-task`, `/pr`, `/fidelity-check`, `/adr`, `/release`) and subagents.
- ADR 0001, spec/plan/ADR templates and `docs/ai-workflow.md`.
- Documentation that `main` has no GitHub branch protection (private repository without a paid plan); protection
  relies on the local hooks and `./build.sh setup`. See `docs/ai-workflow.md`.

[Unreleased]: https://github.com/AnderrAlda/grapplemap-odin/compare/v0.2.0...HEAD
[0.2.0]: https://github.com/AnderrAlda/grapplemap-odin/compare/v0.1.0...v0.2.0
[0.1.0]: https://github.com/AnderrAlda/grapplemap-odin/releases/tag/v0.1.0
