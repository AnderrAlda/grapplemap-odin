# Plan: #90 ci(claude): MAIN must run on Opus (opusplan drops it to Sonnet)
Spec: docs/ai-workflow.md (Reparto de modelos, Orquestación)
## Pasos
1. `docs/ai-workflow.md`: in "Reparto de modelos", a row "Sesión MAIN (inventario, lote, orquestación, verificación) | opus | arrancar con `claude --model opus` o `/model opus` antes de «sigue trabajando»". In Orquestación, one sentence on why: the project's `opusplan` is Opus only in plan mode, so MAIN would orchestrate on Sonnet after the batch is approved.
2. `CLAUDE.md`, «Sigue trabajando» paragraph: add "MAIN runs on Opus (`/model opus`; see `docs/ai-workflow.md`)". One clause, no more.
3. `.claude/skills/orchestrate/SKILL.md` §0, first bullet: "The session model must be Opus (you know your model ID). If it is not, stop and ask Ander to run `/model opus`; launch nothing before that." §0b: "With the OK, invoke the `orchestrate` skill with the batch's issues (do not follow its steps by hand) and go on with steps 2-4."
4. CHANGELOG (Unreleased).
## Ficheros a tocar
`docs/ai-workflow.md`, `CLAUDE.md`, `.claude/skills/orchestrate/SKILL.md`, `CHANGELOG.md`. Not `.claude/settings.json`: `opusplan` stays for manual sessions; workers already pass `--model`.
## Tests a escribir primero
n/a (docs and skill text). Check by hand: `./build.sh ci` green; grep finds "Opus" in §0 of the skill, in the «Sigue trabajando» paragraph and in the models table.
## Riesgos
- Overlaps #87 (same three files and CHANGELOG): this goes first; #87 rebases.
- Keep CLAUDE.md short: the detail lives in ai-workflow.md.
## Criterio de hecho
Done-when of #90, `./build.sh ci` green, reviewer without blockers.
