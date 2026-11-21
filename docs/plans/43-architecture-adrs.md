# Plan: #43 docs: architecture overview and ADRs 0002-0003 (oracle, numeric precision)
Spec: docs/specs/phase-1-original-research.md (deliverable n, "Decisions and trade-offs", "Edge cases")
## Pasos
1. Read `CLAUDE.md`, the spec (decisions table, edge cases on precision and Mesa), `docs/adr/0001-*.md` and `TEMPLATE.md` (new ADRs in English with the translated headings: Status, Context, Decision, Alternatives, Consequences), `tools/oracle/README.md`, and `docs/original.md` §1.3, §4, §5 (inputs for precision).
2. `docs/architecture.md`: packages (`src/core`, `src/render`, `src/ui`, `src/editor`) and dependency direction (`core` imports neither `render` nor `ui`); data flow (`GrappleMap.txt` → parser → graph in an arena → interpolation → render); memory strategy (graph arena, per-frame `context.temp_allocator`, tracking allocator, indices instead of pointers); test strategy (TDD in `core`, oracle sample committed and run locally, full dump only in CI, golden images in phase 3); links to ADRs 0001-0003 and to `docs/original.md`. Short: what exists or is decided, not speculation; future pieces marked "phase N".
3. ADR 0002 "Oracle: the original built in Docker as the source of truth": context (fidelity goal), decision (pinned submodule, Docker image linux/amd64, dumper linked to `common` objects, NDJSON with quantized input and `%.17g` results, sample in git + full dump hashes in CI, submodule never patched), alternatives (porting by reading only, running the original's web JS, patching the original), consequences (Docker needed to regenerate, Mesa/Boost drift caught by hashes, timebox rule).
4. ADR 0003 "Numeric precision": decision on `f64` in `core` for positions and transforms to match the original's doubles, `-ffp-contract=off` on the oracle side and the equivalent concern for Odin (FMA contraction, `-o:speed`), what is compared bit for bit vs. with a tolerance (and who may change a tolerance: only Ander, per `CLAUDE.md`), and where `f32` is allowed (render upload). Check Odin's behaviour on FMA/fp-contract in its docs or source (`odin-researcher`), do not assume it. Anything not verifiable now is an explicit open point.
5. Both ADRs with **Status: Proposed**; Ander accepts them by merging (say so in the PR). Link them from `CLAUDE.md` (Mapa: one line) and from `docs/architecture.md`. CHANGELOG (Unreleased).
## Ficheros a tocar
`docs/architecture.md` (new), `docs/adr/0002-*.md`, `docs/adr/0003-*.md` (new), `CLAUDE.md` (one line in Mapa), `CHANGELOG.md`.
## Tests a escribir primero
n/a (docs). Every claim about the oracle or the original is cited (`file:line` or repo path); every claim about Odin cites its docs or source.
## Riesgos
- `CLAUDE.md` is also touched by #98 in this batch (a different section: "Hecho"): keep the change to one line in Mapa; whoever opens second merges `main`.
- ADR 0003 is an architecture decision: if the evidence points somewhere other than `f64`, write it as an open question for Ander in the PR instead of deciding.
- Do not anticipate ADRs 0004-0006 (#44).
## Criterio de hecho
Done-when of #43 met (ADRs proposed for acceptance at merge), `./build.sh ci` green, reviewer (opus: architecture) without blockers.
