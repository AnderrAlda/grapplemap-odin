# Plan: #55 MAIN orchestrates worktrees with Herdr
Spec: docs/ai-workflow.md (Worktrees)
## Pasos
1. `.claude/settings.json`: move the push, PR-create/ready and issue-create rules from `ask` to `allow`; add PR/issue edit and comment, `git worktree list` and `herdr *`. `deny` rules and hooks unchanged.
2. New skill `.claude/skills/orchestrate/SKILL.md` (inventory, launch worker, watch, close PR, closed escalation list).
3. Docs: `docs/ai-workflow.md` section "Orquestación (MAIN + Herdr)", one line in `CLAUDE.md`, `CHANGELOG.md`.
## Ficheros a tocar
`.claude/settings.json`, `.claude/skills/orchestrate/SKILL.md`, `docs/ai-workflow.md`, `CLAUDE.md`, `CHANGELOG.md`.
## Tests a escribir primero
n/a (configuration and docs). Checks: `jq . .claude/settings.json`; the guard hook still denies pushes to main and PR merges; `./build.sh ci`.
## Riesgos
- `herdr worktree create` does not run `./build.sh setup`, so git hooks are inactive until the worker runs it (the skill says so).
- A broader `allow` means workers push and open PRs unprompted; `deny` rules and hooks still block main, forced pushes and merges.
## Criterio de hecho
`./build.sh ci` green, guard dry-run denies the main push and the merge, and a real `/orchestrate` run on a small issue reaches a draft PR.
