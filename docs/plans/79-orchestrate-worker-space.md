# Plan: #79 each /orchestrate worker opens in its own Herdr space
Spec: docs/ai-workflow.md (Orquestación)
## Pasos
1. `./build.sh space-id <branch>`: prints `sp` + the first 32 hex of the git hash of the branch name (same format as the ids the app uses), so it is stable per branch and needs no extra permission (`./build.sh *` is already allowed).
2. `/orchestrate`: launch workers with `--label herdr.space=<space-id of the branch>` instead of MAIN's own space label; inventory by the `w-*` names.
3. Docs and CHANGELOG.
## Ficheros a tocar
`build.sh`, `.claude/skills/orchestrate/SKILL.md`, `docs/ai-workflow.md`, `CHANGELOG.md`.
## Tests a escribir primero
n/a (shell helper and docs). Checked by hand: same branch gives the same id, different branches differ, no argument prints the usage error. Verified on the server beforehand: a terminal started with `hc run --bg --on hetzner --cwd /home/ander/grapplemap-odin-wt --label herdr.space=sp<32 hex>` gets `where: "grapplemap-odin-wt / 1"`, a new space named after its folder.
## Riesgos
- That a new space also shows nested under the repo like the app's own worktree spaces is only confirmed visually by the user.
- A worker relaunched in the same space reuses it; spaces with no terminals left may disappear or linger, to be seen on the first cleanup.
## Criterio de hecho
`./build.sh ci` green, and a real `/orchestrate` run opens the worker in its own space and the cleanup closes it.
