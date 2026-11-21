# Plan: #71 workers run the whole flow themselves; hc permissions scoped to w-* workers
Spec: docs/ai-workflow.md (Orquestación)
## Pasos
1. `/orchestrate`: launch each worker with `claude "/start-task <N> <plan path>"` as the initial prompt (verified on the server: a slash command with arguments in the initial prompt is executed; the same text sent with `hc send` arrives as `<hc from=...>` text and is not). Workers are named `w-<slug>`.
2. `/start-task`: setup, copy and commit the approved plan, implement, `./build.sh ci`, then invoke `/pr`.
3. `/pr`: drop `disable-model-invocation` (a worker cannot invoke it otherwise; verified), add a step that waits for CI (`gh pr checks --watch`) and marks ready.
4. `.claude/settings.json`: `hc send|kill|rm` in `allow` only for `w-*`.
5. Docs: `docs/ai-workflow.md`, `CHANGELOG.md`.
## Ficheros a tocar
`.claude/skills/orchestrate/SKILL.md`, `.claude/skills/start-task/SKILL.md`, `.claude/skills/pr/SKILL.md`, `.claude/settings.json`, `docs/ai-workflow.md`, `CHANGELOG.md`.
## Tests a escribir primero
n/a (configuration and docs). Verified beforehand with toy skills on the server (removed afterwards): initial-prompt slash with args works; a worker invokes a model-invocable skill by name and chains another; `disable-model-invocation` blocks it. Checks: `jq . .claude/settings.json`, `./build.sh ci`.
## Riesgos
- Removing `disable-model-invocation` from `/pr` lets Claude invoke it on its own; consistent with the autonomy rule in `CLAUDE.md` (draft PRs and ready without asking; merge never).
- `hc run --bg` can still start any program (not analyzed by deny rules or the guard); accepted, mitigated by convention.
- A first real end-to-end run (a one-sentence issue, no plan) is still needed to prove worktree-per-worker Stop hooks, the worker reaching a ready PR, and cleanup.
## Criterio de hecho
`./build.sh ci` green, and one real `/orchestrate` run on a small issue reaches a ready PR with the worker visible in the app, then cleanup, asking the user only for the merge.
