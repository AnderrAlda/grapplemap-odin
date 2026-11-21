# Plan: #38 docs(original): graph model and node matching (section 2)
Spec: docs/specs/phase-1-original-research.md (section 2 of `docs/original.md`)
## Pasos
1. Read section 1 of `docs/original.md` for style (citations `file:line` of the pinned submodule, anything unverified marked as such) and the Contents list.
2. Read the original, read-only: `reference/GrappleMap/src/graph.cpp` (`find_or_add` ~235, node creation), `graph.hpp`, `persistence.cpp:154-169` (`loadGraph`: named positions vs. transitions), `is_reoriented`/`basicallySame` (threshold `0.0016` m² per joint) and its callers, the `.index` cache keyed by md5 (`grapplemap-indexer`), `bidirectional`/`detailed` handling, lookup of nodes by description.
3. Write section 2 in `docs/original.md`: named positions vs. transitions; anonymous nodes; endpoint matching by reorientation (exact algorithm, order of candidates, tie-breaks, mirror/swap handling if involved); `.index` format and invalidation; `bidirectional`, `detailed`; lookup by description. Enough detail for phase 2 to reimplement and agree 100% with the oracle.
4. Cross-check the numbers against the spec's "Database facts" (601 named, 1,485 transitions); mark anything not verifiable without the oracle as such. Update the Contents list. CHANGELOG (Unreleased).
## Ficheros a tocar
`docs/original.md`, `CHANGELOG.md`. Nothing under `reference/` (read-only).
## Tests a escribir primero
n/a (docs). Every claim must cite `file:line`; the worker re-opens each cited line to verify it.
## Riesgos
- Sections 3-6 (#39-#41) edit the same file: they are chained after this PR, not parallel.
- Matching details that depend on runtime data (anonymous node count) can only be confirmed by the dumper (#34): mark them as pending.
- Keep the PR <400 lines.
## Criterio de hecho
Done-when list of #38 met, citations verified, `./build.sh ci` green, reviewer (opus: it is fidelity content) without blockers.
