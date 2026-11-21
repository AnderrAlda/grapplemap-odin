# Plan: #20 fix(claude): harden guard-bash against push and option variants
Spec: issue #20 (origin: code-reviewer on PR #10)
## Pasos
1. Test first: `tests/hooks/guard-bash.test.sh` creates a temporary git repo (branches `main` and `feat/x`), sets `CLAUDE_PROJECT_DIR` to it and feeds `.claude/hooks/guard-bash.sh` JSON on stdin; table of allowed/blocked cases; exits non-zero on any mismatch. Hooked into `cmd_test` of `build.sh` (CI runs it through `./build.sh test`; `ci.yml` is not touched).
2. Rewrite `guard-bash.sh` to evaluate **per segment** (split on `&&`, `||`, `;`, `|`, newline) and, per segment, skip git global options (`-C <dir>`, `-c k=v`, `--git-dir=…`, `--work-tree=…`, `--no-pager`) before the subcommand.
3. Block everything the current guard blocks, plus the variants: `push` with grouped short force flags (`-fu`, `-uf`), long force/delete/mirror/all flags, `-d`, `+…` or `:…` refspecs; push to `main` (arg, `x:main`, `refs/heads/main`); commit/push while on `main`; hard reset; forced clean; recursive+forced `rm` in any spelling (`-rf`, `-r -f`, `-R`, long options); privilege escalation; `gh pr merge`; the hook-skipping commit flag.
4. Explicitly allowed: `git push origin feat && git log main`, `git push -u origin feat/x`, `rm -r dir` without force.
5. Document the limit in the script: quotes are not parsed, a `;` inside a message may over-block (fail-closed, accepted). CHANGELOG.
## Ficheros a tocar
`.claude/hooks/guard-bash.sh`, `tests/hooks/guard-bash.test.sh`, `build.sh` (one line in `cmd_test`), `CHANGELOG.md`.
## Tests a escribir primero
The table in step 1, red against the current guard for the new cases, green after the rewrite.
## Riesgos
- A guard bug blocks every agent: the test covers every command workers use (`git push -u origin <branch>`, `gh pr create`, `hc …`).
- No existing block is relaxed: every currently blocked case stays in the table as blocked.
## Criterio de hecho
Checklist of #20 met, `./build.sh ci` green, reviewer without blockers.
