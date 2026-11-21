# Plan: #31 build: ./build.sh worktree nests worktrees when run from another worktree
Spec: issue #31
## Pasos
1. Read `build.sh` (`cmd_worktree`, `cmd_worktree_remove` for the style of resolving paths from git, not `$PWD`) and `tests/changelog/fragments.test.sh` / `tests/hooks/*.test.sh` for the shell test style.
2. Test first: `tests/build/worktree.test.sh`, run from `./build.sh check` next to the other shell tests. In a throwaway repo in a temp dir (a bare "origin" + a clone, so `origin/main` exists; no network, no submodule), run `build.sh worktree` from the main checkout and from inside a worktree and assert both give `<parent of main checkout>/grapplemap-odin-wt/<branch with / → ->`; assert a failing `git worktree add` prints git's error and exits non-zero. Show it red before the fix.
3. Fix `cmd_worktree`: base dir = parent of the main checkout, not `..`: `git rev-parse --path-format=absolute --git-common-dir` gives `<main>/.git`, so the base is `dirname` of `dirname` of it, plus `/grapplemap-odin-wt`. Replace `add -b ... 2>/dev/null || add ...` with an explicit check: if `refs/heads/<branch>` exists, `git worktree add "$dir" "$branch"`, else `git worktree add -b "$branch" "$dir" origin/main`; no stderr hidden. The folder name stays `grapplemap-odin-wt` (existing worktrees and `space-id` depend on it).
4. `docs/ai-workflow.md` (Worktrees, line "crea `../grapplemap-odin-wt/<rama>`"): check it still matches; only edit it if it does not (another PR in this batch edits a different section of that file).
5. Changelog fragment `changelog.d/31-worktree-path.md` (`### Fixed`); do not edit `CHANGELOG.md`.
## Ficheros a tocar
`build.sh` (`cmd_worktree` and the test line in `check`), `tests/build/worktree.test.sh` (new), `changelog.d/31-worktree-path.md` (new).
## Tests a escribir primero
`tests/build/worktree.test.sh` as in step 2 (red before the fix, green after; output of both in the PR).
## Riesgos
- The test must not touch the real repo or the network: everything under `mktemp -d`, cleaned with a `trap`.
- `cmd_worktree` runs `submodule update --init`: in the test repo there are no submodules, so it must stay quiet/harmless.
- Run from a worktree, `--git-common-dir` points to the main `.git`: verify, do not assume (print it in the test).
## Criterio de hecho
Done-when of #31 met, test red→green shown in the PR, `./build.sh ci` green, reviewer without blockers.
