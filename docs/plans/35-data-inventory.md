# Plan: #35 docs(original): data inventory (section 10) — PR 2 of 3
Spec: docs/specs/phase-1-original-research.md ("Sections of `docs/original.md`", item 10; "Database facts").
#35 PR 1 (#123 + #126) is merged: the dumper writes `inventory.ndjson` (classes per block) and the sample is committed.
This PR is `Refs #35`; PR 3 (`docs/plans/35-oracle-images.md`, `--images`, `Closes #35`) runs in the same batch and
does **not** touch `docs/original.md`.
## Pasos
1. Read `tools/oracle/README.md` ("Inventory and sample": class rules and counts), `tools/oracle/sample.tsv`, ADR 0002, and every place of `docs/original.md` that defers to section 10 (grep `section 10`, `§10`): counts in §1.8 (line ~223), anonymous nodes in §2.2 (~284), §6.1 (~991), self-loops and the `follow` direction rule in §6.8 (~1162), pillar-basis degeneracy in §7.7 (~1382). Style: English, `file:line` of the pinned submodule, `[unverified]` for what is not checked.
2. Run `./build.sh oracle --full` (Docker is available, amd64) and work from `build/oracle/full/`. Any analysis script (jq or `python3 -I`) lives in the session scratchpad and is **not** committed; the PR body pastes the exact commands so a reader can reproduce every number.
3. Write `## 10. Data inventory` (after §9):
   - 10.1 Counts at the pin: blocks, positions, named positions, transitions, nodes, anonymous nodes, length histogram (confirms or corrects the spec's `awk` figures), `bidirectional`/`detailed`, tag and family distribution.
   - 10.2 Anomaly classes: one row per class of the closed list (rule, count, and its cases). Small classes (`long`, `bidirectional`, `description_utf8`, `edge_coordinate` = 0, the 5 named positions with no transition, …) list **every** case by block index and first description line; large classes (`duplicate_description`, `description_newline`, `has_ref`, …) give the count, a breakdown where it helps (e.g. the 136 `...`), a few examples and the command that lists all of them from `inventory.ndjson`. Nothing is fixed: anomalies are documented only.
   - 10.3 Answers to the points other sections deferred here: anonymous node count; self-loop transitions (from = to) and whether any exists; whether a pillar basis degenerates on the DB (§7.1 rule, computed over every segment of every position); anything else the grep of step 1 finds. Each one: the answer, the evidence (command), and an edit of the deferring sentence to point at the subsection (only those sentences).
   - 10.4 How the sample was chosen: link `tools/oracle/sample.tsv` and the README; do not duplicate the table.
4. Update Contents. Changelog fragment `changelog.d/35-data-inventory.md` (`### Added`).
## Ficheros a tocar
`docs/original.md` (§10, Contents, the deferring sentences of step 3), `changelog.d/35-data-inventory.md` (new). Not `tools/oracle/`, `build.sh`, `tests/fixtures/` (PR 3 in this batch), not `docs/adr/`, not `reference/`.
## Tests a escribir primero
n/a (docs). Every count is reproducible from the full dump with a command in the PR body; every `file:line` is checked against the pinned submodule.
## Riesgos
- Size: <400 hand-written lines; listing every case of the big classes would blow it, hence the count + command rule above.
- If a number disagrees with the spec or the README, the dump wins: correct the README only if PR 3 is not touching it at the same time (it is): instead, note the discrepancy in the PR body for a follow-up.
- Do not reinterpret the class rules merged in #123/#126; if one looks wrong, say so in the PR (Ander decides).
## Criterio de hecho
Section 10 with counts and every anomaly class with its cases, deferred points answered or explicitly left open, `./build.sh ci` green, reviewer (opus: fidelity data) without blockers.
