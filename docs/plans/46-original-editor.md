# Plan: #46 docs(original): editor semantics (section 9)
Spec: docs/specs/phase-1-original-research.md (section 9 of `docs/original.md`; input for phase 6)
## Pasos
1. Read `docs/original.md` §1.5 (writer), §2.3 and §2.9 (mutations that touch matching), §3 (joints, segments, lengths), §5, §7.5 (editor camera), §8.6 (web editor UX, which links here) — style: `file:line` citations of the pinned submodule, `[unverified]` for anything not checked; link, do not repeat.
2. Read in `reference/GrappleMap/src/` (read-only): `editor.{hpp,cpp}` (the shared editor model: selection, undo, operations), `positions.cpp` (`spring`, `apply_limits`, bone-length constraint), `graph.cpp` (`set`, `replace` + `NodeModifyPolicy`, `erase`, `split_at`/insert, `set_description`), `persistence.cpp` (`save`, what is written and in which order, backups), `viables.cpp` (what "viable" joints/positions mean for dragging), `glfw_editor.cpp` (key/mouse bindings not covered by §7.5), `editor_canvas.cpp`/`cursor_canvas.cpp` and `editor.js` (web editor: `determineNextPos`, `closeCandidates`, how JS calls the C++ through emscripten).
3. Write `## 9. Editor semantics`:
   - Editor state (selection of sequence/segment/position/joint, edit mode, undo stack and what an undo entry holds).
   - Dragging a joint: what moves, `spring()` (exact algorithm, iterations, which joints are fixed), the bone-length constraint, `apply_limits` (box), mirror/symmetric editing if any.
   - Operations: insert/duplicate/delete a position, split/merge, create/delete a sequence, reverse, mirror/swap, change description/tags/properties; for each, the effect on the graph (link §2.9 for matching) and invariants kept or broken.
   - Persistence on save: file written, order (§1.5), `.index` refresh, backups, what is lost (e.g. comments, formatting).
   - C++ editor vs web editor: which operations exist in each.
   - "9.x Input for phase 6": what must be reproduced exactly (spring numerics, save format) vs. free UX; open points.
4. Fix the two stale pointers in §2.9 ("for phase 8" → phase 6; "full editor behaviour is section 8" → section 9) and the "section 9" mentions in §7.5/§8 only if they now point to a concrete subsection. Update Contents.
5. Changelog fragment `changelog.d/46-original-editor.md` (`### Added`).
## Ficheros a tocar
`docs/original.md` (§9, Contents, the §2.9 pointers), `changelog.d/46-original-editor.md` (new). Nothing under `reference/`; not `tools/oracle/`, `build.sh`, `tests/` (#35 in the same batch).
## Tests a escribir primero
n/a (docs). Check every `file:line` citation against the pinned submodule before the PR (grep/sed of each one).
## Riesgos
- Size: <400 hand-written lines. If it does not fit, keep the semantics (spring, operations, save) and move the full key-binding table to a follow-up phase-1 docs issue; say so in the PR.
- `spring()` numerics feed phase 6 fidelity: describe exactly (order of updates, constants), and note that `spring.ndjson` of the oracle checks it.
- Asserts disappear under `NDEBUG` (as in §2.9): say what the release build does, mark runtime effects not checked as `[unverified]`.
- Insert §9 after §8; leave §10 to #35 (its PR 2 writes it).
## Criterio de hecho
Done-when of #46 met, citations verified, `./build.sh ci` green, reviewer (opus: fidelity content for phase 6) without blockers.
