# Plan: #87 MAIN tells when to /clear and what to say afterwards
Spec: docs/ai-workflow.md (Orquestación)
## Pasos
1. `docs/ai-workflow.md` (Orquestación): add a section "Reanudar MAIN": (a) `/clear` is safe when the batch is closed (its PRs merged and cleaned per §4b, no plan waiting for approval, no worker `blocked`/`error`); it does not kill workers (`--outlive-parent`) and the state lives in issues, PRs and `docs/plans/`; (b) where: Ander's MAIN terminal, at the repo root, on `main`; (c) what to say: `/rename MAIN`, then "sigue trabajando".
2. `.claude/skills/orchestrate/SKILL.md`: when a batch is closed (after §4b) and whenever MAIN proposes the next batch, MAIN ends its message with a fixed block "Momento de /clear: sí|no" with the reason and, if yes, the two lines to type and where. If a worker is still alive, say which one (`hc ls`, `w-*`) so the new session finds it.
3. `CLAUDE.md` (Flujo Git, next to the «Sigue trabajando» paragraph): one line linking to the section.
4. Changelog fragment `changelog.d/87-main-clear-guidance.md` (format in `changelog.d/README.md`); do not edit `CHANGELOG.md`.
## Ficheros a tocar
`docs/ai-workflow.md` (Orquestación only), `.claude/skills/orchestrate/SKILL.md`, `CLAUDE.md`, `changelog.d/87-main-clear-guidance.md` (new).
## Tests a escribir primero
n/a (docs and skill text). Check by hand: `./build.sh ci` green; grep finds "Momento de /clear" in the skill and "Reanudar MAIN" in ai-workflow.md.
## Riesgos
- #31 in the same batch may touch `docs/ai-workflow.md` (Worktrees section, only if it no longer matches): different section; whoever opens second merges `main`.
- Keep it short: CLAUDE.md gets one line, the detail lives in ai-workflow.md.
## Criterio de hecho
Acceptance criteria of #87, `./build.sh ci` green, reviewer without blockers.
