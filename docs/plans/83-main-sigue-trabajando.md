# Plan: #83 MAIN "sigue trabajando" flow and per-issue worker model
Spec: docs/ai-workflow.md (Orquestación)
## Pasos
1. `CLAUDE.md` (sección Flujo Git) y `docs/ai-workflow.md` (Orquestación): add the permanent rule. If the session is named MAIN, is at the repo root on `main` and Ander says "sigue trabajando" (or similar), MAIN takes the inventory, picks the next batch (≤3 issues of the current phase by priority, no overlapping files), writes their plans and presents them **together in one approval request**; once approved it runs `/orchestrate` on the batch until the PRs are ready, tells Ander to merge, cleans up and proposes the next batch. It only asks in the escalations of `/orchestrate` §5.
2. `.claude/skills/orchestrate/SKILL.md`: remove `disable-model-invocation: true` (MAIN must be able to invoke it), add step "0b. Proponer lote y planes" with the behaviour above, and in §2 choose the worker model per issue: `claude --model <m> --permission-mode auto ...` (sonnet by default; opus for the oracle C++, core fidelity and ADRs). Keep the `hc run --bg *` allow rule valid (the model flag goes after `claude`).
3. `.claude/skills/start-task/SKILL.md`: remove `model: sonnet` so the worker keeps the model it was launched with.
4. `docs/ai-workflow.md`: update the "Reparto de modelos" table with the per-issue worker model and note that `/start-task` inherits it.
5. CHANGELOG (Unreleased).
## Ficheros a tocar
`CLAUDE.md`, `docs/ai-workflow.md`, `.claude/skills/orchestrate/SKILL.md`, `.claude/skills/start-task/SKILL.md`, `CHANGELOG.md`.
## Tests a escribir primero
n/a (docs and skill text). Check by hand: `./build.sh ci` green; `grep -n 'disable-model-invocation' .claude/skills/orchestrate/SKILL.md` empty; `grep -n '^model:' .claude/skills/start-task/SKILL.md` empty.
## Riesgos
- Without `disable-model-invocation` any session could invoke `/orchestrate`; the skill already says "solo desde MAIN", keep that guard in the text.
- Whether `claude --model` is honoured when the skill itself had a `model:` is only confirmed by a real worker run (checked after merge by `hc read` on a worker).
- `docs/ai-workflow.md` is also touched by #54: this plan merges first.
## Criterio de hecho
`./build.sh ci` green, rule present in CLAUDE.md and ai-workflow.md, orchestrate/start-task changed as above, reviewer without blockers.
