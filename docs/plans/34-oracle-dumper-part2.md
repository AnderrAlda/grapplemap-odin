# Plan: #34 ci: oracle dumper, PR 2 of 2 (`ops`, `between`, `playback`, `spring`)
Spec: docs/specs/phase-1-original-research.md (deliverable 3, "Dump format", "Full dump"). PR 1: #94 (`docs/plans/34-oracle-dumper.md`).
**This PR closes #34** (`Closes #34`); it ticks the two items still open in the issue.
## Pasos
1. `tools/oracle/dump/dump.cpp`, `ops.ndjson`: for every position in block/file order (named positions and every position of every sequence), `{block, pos, mirror, swap_players, orient_canonically_with_mirror, orient_canonically_without_mirror, heading, center}` with `%.17g` doubles (`positions.hpp:37,68,142-184`). `swap_players` works in place: copy first.
2. `between.ndjson`: for every consecutive pair of each sequence, `between(a, b, s)` (`positions.hpp:42`) with `s ∈ {0.25, 0.5, 0.75}`; key `{seq, pos, s}`.
3. `playback.ndjson`: per transition, the frames of `frames(g, path, 11)` (`paths.cpp:23`; `detailed` uses `frames_per_pos / 2` = 5 by **integer** division, `paths.cpp:42`), `raw` and after `smoothen` (`paths.cpp:8-21`) of that transition alone. Plus at least one **2-transition chain** smoothed in one call (`frames(g, script, 11)`, `paths.cpp:54`), because every caller in the original smooths a whole script (`makevideo.cpp:93,105`, `playback.cpp:77,89`, `paths.cpp:261`). Pick the chain deterministically (first pair `a → b → c` in index order) and record it in the record. `Playback::progress` is not dumped.
4. `spring.ndjson`: `spring(Position&)` (`positions.hpp:40`) on a copy of every named position.
5. Memory: the full dump is ~0.5 GB; do not hold every file as one string. Write each file to a temp name and rename at the end (keeps "a failure never leaves a partial dump") or stream per record; say which in the code comment.
6. `testdata/basic` expected output: regenerate with the new files and review the diff by hand (`ops` of the named position, `between` of one pair, `playback` of the short transition and the chain if `basic.txt` allows it; extend `make_basic.py` with a third block if needed for the chain).
7. Docs: `tools/oracle/README.md` (new files, per-transition smoothing is a dumper choice + the chain record, integer halving of `frames_per_pos`); correct the full-dump size in the spec (~0.45–0.55 GB, `playback` ~350–390 MB) with the real size measured by `--full`; CHANGELOG (Unreleased).
## Ficheros a tocar
`tools/oracle/dump/dump.cpp`, `tools/oracle/dump/testdata/*`, `tools/oracle/README.md`, `docs/specs/phase-1-original-research.md` (size figure only), `CHANGELOG.md`. Not `build.sh`, not `docs/original.md` (#40 edits it), not `.github/workflows` (#36).
## Tests a escribir primero
Expected output for `testdata/basic` with the new files written first (values of `mirror`/`swap_players`/`between(…,0.5)` checked by hand on one position); `./build.sh oracle --test` red, then green.
## Riesgos
- Size/time of `--full`: measure and paste in the PR (sizes per file, wall time, `sha256sum` of two consecutive runs equal).
- `frames()` drops the last frame of each transition (`paths.cpp:44`); dump exactly what it returns, do not "fix" it.
- PR > 400 lines: split `playback` into a third PR (`Refs #34`) and say so.
- `CHANGELOG.md` is shared with #40 and #21 in this batch: whoever opens second merges `main` (see #98).
## Criterio de hecho
The open items of #34 and the 3 points of its review comment met with evidence (`--test` and `--full` output, counts, sizes, hashes), `./build.sh ci` green, reviewer (opus) without blockers.
