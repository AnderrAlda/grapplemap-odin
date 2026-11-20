# Plan: #32 chore: add the original GrappleMap as a pinned read-only submodule
Spec: docs/specs/phase-1-original-research.md (Deliverable 1, L28; pin decision L264; bump risk L249; E2E L271)

## Context
Phase 1 needs the original C++ repo in-tree so `docs/original.md` can cite `file:line` and the oracle (deliverables 2–5)
can build from it. Both tracks are blocked on this. The pin `032c8f91809786b7b784852abd07cf3e10c0ea35` is verified to be
the current upstream `master` HEAD (2020-03-14, repo ≈ 8 MB).

Today `reference/` does not exist, but it is already write-protected as a whole (`.claude/hooks/protect-paths.sh:8`,
`.claude/settings.json:46` `Edit(./reference/**)`), which would block `reference/CLAUDE.md`.
**Decision (Ander):** narrow the protection to the submodule only, `reference/GrappleMap/**`.

## Pasos
1. Commit this plan as `docs/plans/32-reference-submodule.md`.
2. Add the submodule (Bash, not Edit):
   `git submodule add https://github.com/Eelis/GrappleMap.git reference/GrappleMap`
   `git -C reference/GrappleMap checkout 032c8f91809786b7b784852abd07cf3e10c0ea35`, then `git add reference/GrappleMap .gitmodules`.
   No `shallow`/`branch`/`ignore` options in `.gitmodules`: we want a dirty submodule to show up in `git status`.
3. Narrow the protection to the submodule:
   - `.claude/hooks/protect-paths.sh`: case `reference/GrappleMap/* | tests/golden/*`; update comment and deny message.
   - `.claude/settings.json`: `Edit(./reference/**)` → `Edit(./reference/GrappleMap/**)`.
4. Write `reference/CLAUDE.md` (style of `src/*/CLAUDE.md`: H1 + short bullets):
   - `GrappleMap/` is the original, pinned at `032c8f9`, READ-ONLY: never edit, build in place or leave files in it
     (the oracle builds out-of-tree; patches only in `tools/oracle/patches/` + ADR 0002). `git status` must show it clean.
   - Bash writes are not covered by the hooks; same rule applies.
   - Init: `git submodule update --init`; check: `git -C reference/GrappleMap rev-parse HEAD`.
   - Bump the pin: only in its own PR, which updates the gitlink and regenerates the oracle sample
     (`tests/fixtures/oracle/`), `FULL.sha256` and the inventory, and re-checks `file:line` citations in `docs/original.md`.
5. `build.sh`:
   - `cmd_setup`: `git submodule update --init || echo "WARN: …"` (idempotent; warns offline instead of failing).
   - `cmd_worktree`: `git -C "$dir" submodule update --init` so new worktrees (how docs-track sessions start) have the original.
   - `build.bat` setup: same one-liner for parity.
6. CI: **no workflow change**. None of the `ci.yml`/`release.yml` jobs read `reference/` (all walks are scoped to `src/`,
   `git ls-files` lists the gitlink as one entry), and default `actions/checkout` ignores submodules — which is what we want
   (faster, no network dependency). The only consumer, `oracle.yml`, comes with its own issue and uses `submodules: true`
   (spec L137–144). State this in the PR description so the "CI checks out submodules where needed" box is justified.
7. Docs:
   - `README.md` (Build section, L18): clone with `--recurse-submodules` or run `git submodule update --init`; note `setup` does it.
   - `CLAUDE.md`: Comandos/Mapa mention `git submodule update --init`; Prohibiciones L42 → "Tocar `reference/GrappleMap`…".
   - `docs/ai-workflow.md:28` and `CONTRIBUTING.md:26`: align wording with the narrowed protection.
   - `CHANGELOG.md` Unreleased: Added (submodule + `reference/CLAUDE.md`, #32); Changed (protection narrowed to the submodule; `setup`/`worktree` init it).
   - No ADR: the pin decision is already recorded in the spec (L264).

## Ficheros a tocar
`.gitmodules` (new) · `reference/GrappleMap` (gitlink) · `reference/CLAUDE.md` (new) · `.claude/hooks/protect-paths.sh` ·
`.claude/settings.json` · `build.sh` · `build.bat` · `README.md` · `CLAUDE.md` · `docs/ai-workflow.md` · `CONTRIBUTING.md` ·
`CHANGELOG.md` · `docs/plans/32-reference-submodule.md` (new). ≈ 60 lines of diff (gitlink excluded).

## Tests a escribir primero
No `core` code, so no Odin tests. Checks run before/after as evidence:
- Hook: before step 3, `echo '{"tool_input":{"file_path":"'$PWD'/reference/CLAUDE.md"}}' | .claude/hooks/protect-paths.sh` → denied;
  after → allowed; same with `reference/GrappleMap/README.md` → still denied; `tests/golden/x.png` → still denied.
- Pin: `git -C reference/GrappleMap rev-parse HEAD` = `032c8f9…`; `git submodule status` without `+`/`-` prefix; `git ls-tree HEAD reference/GrappleMap` mode `160000`.
- Fresh clone: `git clone <worktree> /scratch/x && cd x && ./build.sh setup` → submodule populated at the pin.
- `./build.sh worktree test/tmp-sub` → `reference/GrappleMap` populated; then remove the worktree and branch.

## Riesgos
- Editing the protection itself: keep `tests/golden/` intact; verify with the hook checks above.
- `settings.json` change only takes effect in new sessions; verify with the hook script directly, not by trying an Edit.
- Network needed for `setup`/`worktree`: handled with a warning, not a failure.
- Accidentally dirtying the submodule later (builds, `.index` files): covered by `reference/CLAUDE.md` + spec's out-of-tree rule.

## Criterio de hecho
- Issue boxes: submodule pinned at `032c8f9`; `reference/CLAUDE.md` with read-only + bump rules; CI justified unchanged
  (documented in PR) and green; README/CLAUDE.md mention `git submodule update --init`.
- Hook checks above pass (output pasted in the PR). `./build.sh ci` green locally, CI green.
- PR draft with labels `type:ci`, `area:infra`, `phase-1`, milestone "Fase 1: Investigación del original";
  `code-reviewer` without blockers; CHANGELOG updated. No merge without Ander's OK.
