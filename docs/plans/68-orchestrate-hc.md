# Plan: #68 /orchestrate must drive Herdr through hc
Spec: docs/ai-workflow.md (Orquestación)
## Pasos
1. Rewrite `.claude/skills/orchestrate/SKILL.md` for `hc` (herdr-core): MAIN lives on the server, launches workers with `hc run --bg` labelled into its own space, watches them with `hc wait/read/send`, closes PRs and cleans up.
2. `.claude/settings.json`: replace the `herdr ...` allow rules with `hc ls|get|read|wait|send|run --bg`.
3. Docs: `docs/ai-workflow.md`, `CLAUDE.md`, `CHANGELOG.md`.
## Ficheros a tocar
`.claude/skills/orchestrate/SKILL.md`, `.claude/settings.json`, `docs/ai-workflow.md`, `CLAUDE.md`, `CHANGELOG.md`.
## Tests a escribir primero
n/a (configuration and docs). Checks: `jq . .claude/settings.json`; `./build.sh ci`; hc subcommands and flags match `hc <cmd> --help`.
## Riesgos
- `hc run --bg`, `hc send` can start programs or type into other terminals, so the skill limits them to the workers MAIN launched; the guard still scans the command text.
- Not verified in a real run: that `$HC_TERMINAL_ID` carries `herdr.space` in a server pane, that a worker labelled with it shows as a tab in the app, and that `hc send "/start-task N"` is interpreted as a slash command.
- The approved plan is uncommitted on `main`; the first worker message tells the worker to copy and commit it in its branch.
## Criterio de hecho
`./build.sh ci` green and one real `/orchestrate` run on a small issue reaches a draft PR with the worker visible in the app.
