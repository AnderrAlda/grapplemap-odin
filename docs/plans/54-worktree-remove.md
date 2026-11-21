# Plan: #54 ./build.sh worktree-remove <rama> with clean-state check
Spec: issue #54 and `/orchestrate` §4b
## Pasos
1. Read `build.sh` (`worktree` and `space-id` targets) and follow its style (errors to stderr, exit codes, no magic).
2. Add `worktree-remove <rama>`: find the worktree of `<rama>` in `git worktree list --porcelain` (clear error and exit 1 if the branch or its worktree does not exist; it must work from another worktree, see #31, so resolve paths from the porcelain output, not from `$PWD`).
3. Check clean state: `git -C <wt> status --short` and `git -C <wt> submodule foreach --recursive 'git status --short'` (ignored build outputs allowed as in §4b check 3). If anything is dirty: print it, delete nothing, exit non-zero.
4. If clean: `git worktree remove --force <wt>` (needed because of the submodule), `git worktree prune`, `git branch -D <rama>` (refuse `main*`).
5. Update `/orchestrate` §4b ("usa `./build.sh worktree-remove` cuando exista" → now exists), `CLAUDE.md` command list, `docs/ai-workflow.md` (the #54 sentence only), CHANGELOG.
## Ficheros a tocar
`build.sh`, `CLAUDE.md`, `.claude/skills/orchestrate/SKILL.md` (§4b only), `docs/ai-workflow.md`, `CHANGELOG.md`.
## Tests a escribir primero
Shell target, no Odin tests. Manual cases with output as evidence in the PR, using a throwaway branch: missing branch; branch without worktree; dirty worktree; dirty submodule; clean worktree (removed with its branch); run from another worktree.
## Riesgos
- Loses work if the dirty check misses something: check the submodule and untracked files (`--short` shows them).
- Touches `docs/ai-workflow.md` and `orchestrate/SKILL.md` like #83: merge after #83 and rebase if needed.
- `git branch -D` is allowed in `allow` but `git branch -D main*` is in `deny`: the script must also refuse `main`.
## Criterio de hecho
Acceptance criteria of #54 met, `./build.sh ci` green, manual evidence in the PR, reviewer without blockers.
