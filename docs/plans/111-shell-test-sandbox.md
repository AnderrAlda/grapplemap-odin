# Plan: #111 test: shell tests must not inherit the hook's GIT_* environment
Spec: n/a (infra; incident of 2026-11-21 described in the issue)
## Pasos
1. Read `build.sh` (`cmd_test`, `cmd_ci`), `.githooks/pre-push`, `.claude/hooks/stop-check.sh` and the four shell tests. Today `tests/hooks/guard-bash.test.sh:8-28` and `tests/worktree/worktree.test.sh:4-24` each carry their own isolation (unset `--local-env-vars`, `mktemp -d` + `trap`, `GIT_CEILING_DIRECTORIES`, common-dir / origin guards); `protect-paths.test.sh` and `changelog/fragments.test.sh` use `mktemp` but check whether they run any `git` that writes (grep shows none today).
2. `build.sh`: in `cmd_test`, before the shell tests, clear every variable printed by `git rev-parse --local-env-vars` (in the function, so the Odin tests also run clean). One short comment citing #111. `cmd_ci`, the `pre-push` hook and the Stop hook all go through `cmd_test`, so they are covered.
3. New `tests/lib/sandbox.sh` (sourced, not executed; no `set -e` side effects on the caller):
   - `sandbox_init`: unset `--local-env-vars` (defence in depth if a test is run by hand), `SANDBOX=$(mktemp -d)` resolved with `pwd -P`, `trap` that removes it on EXIT (compose with an existing trap: let the caller pass extra cleanup or document that the helper owns the EXIT trap), `export GIT_CEILING_DIRECTORIES="$SANDBOX"`.
   - `sandbox_assert_repo <dir>`: aborts (`exit 1`, message `FATAL: ...`) unless `git -C <dir> rev-parse --path-format=absolute --git-common-dir` is inside `$SANDBOX`, and, if the repo has an `origin`, its URL is a local path inside `$SANDBOX` (no `://`, no `user@host:`).
   - Optionally `sandbox_git` (= the `G` helper of the worktree test: fixed `user.name/email`, `protocol.file.allow=always`).
4. Migrate: `guard-bash.test.sh` and `worktree.test.sh` use the helper instead of their inline copies, keeping the extra checks that are test-specific (the real `.git/config` checksum in guard-bash stays: it is a second, independent tripwire). `protect-paths`/`fragments` only if they create repos (if not, leave them and say so in the PR).
5. Regression test `tests/lib/sandbox.test.sh`, added to `cmd_test`:
   - Builds a **victim** repo inside its own sandbox (commit, a branch, a bare `origin` in the sandbox), records `config` checksum, `git for-each-ref`, `git worktree list --porcelain`.
   - Runs the shell-test suite with `GIT_DIR=<victim>/.git GIT_WORK_TREE=<victim>` exported (and `GIT_INDEX_FILE` too) and asserts all three recorded states are unchanged and the run passed.
   - Recursion: running `./build.sh test` from inside a test of `./build.sh test` would loop. Use an env guard (e.g. `GM_IN_SANDBOX_REGRESSION=1`) that makes `cmd_test` skip only this regression test in the nested run; document it in the test header. The nested run may skip the Odin packages too if it keeps the test fast (say which in the PR).
   - Also a direct helper test: `sandbox_assert_repo` aborts on a repo outside `$SANDBOX` and on a remote origin URL (run in a subshell, check exit code).
6. `docs/ai-workflow.md`, Enforcement section: one line — shell tests never touch the real repo: they source `tests/lib/sandbox.sh` and run `sandbox_assert_repo` before any write; `./build.sh test` clears the repo env (#111).
7. Changelog fragment `changelog.d/111-shell-test-sandbox.md` (`### Fixed` or `### Changed`).
## Ficheros a tocar
`build.sh` (`cmd_test` only), `tests/lib/sandbox.sh` (new), `tests/lib/sandbox.test.sh` (new), `tests/hooks/guard-bash.test.sh`, `tests/worktree/worktree.test.sh`, `docs/ai-workflow.md` (one line), `changelog.d/111-shell-test-sandbox.md`. Not `tests/golden/`, not `reference/`.
## Tests a escribir primero
`tests/lib/sandbox.test.sh`: write it first and run it against the current `build.sh` with the env-clearing step removed or not yet added, to show it would catch a test that writes through an inherited `GIT_DIR` (e.g. a throwaway probe that runs `git config x.y z` without isolation; do not commit the probe). Then implement and show it green.
## Riesgos
- The regression test itself manipulates `GIT_DIR`: it must point only at its own sandbox victim, never at `$ROOT`. Assert that before exporting.
- Never run experiments with `GIT_DIR` pointing at the real repo or at another worktree (that is exactly the incident).
- The EXIT trap of the helper can clobber a test's own trap: pick one convention and apply it in both migrated tests.
- Do not weaken any existing assertion of the migrated tests (CLAUDE.md prohibition): behaviour must stay identical; diff the `ok/FAIL` output before and after.
- Concurrent workers share `.git/config` (#100): the guard-bash checksum tripwire can flake if another worker writes it; not in scope, do not "fix" it by removing the check.
## Criterio de hecho
All five checkboxes of #111 met, `./build.sh ci` green with the regression test running, evidence in the PR of the regression test failing without the env clearing, reviewer (sonnet) without blockers.
