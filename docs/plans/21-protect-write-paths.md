# Plan: #21 fix(claude): close write paths into reference/ and tests/golden/
Spec: issue #21 (origin: review of PR #10 and of the PR of #32)
## Pasos
1. `.claude/hooks/protect-paths.sh`: normalize the path before the `case` (absolute or relative, `./`, `..`, repeated `/`, symlinks): resolve with `realpath -m` against `$PWD` and compare against the repo's `reference/GrappleMap/` and `tests/golden/`. Check in `.claude/settings.json` which tools the hook matches (Edit/Write/NotebookEdit; `notebook_path` for NotebookEdit) and cover them all.
2. `.claude/hooks/guard-bash.sh`: in `check_segment`, block segments that **write** into those paths: output redirection (`>`, `>>`, `&>`, `tee [-a]`) and write commands whose operands name them (`sed -i`/`--in-place`, `perl -i`, `cp`/`mv`/`install`/`rsync` destination, `rm`, `truncate`, `touch`, `ln`, `chmod`/`chown`, `dd of=`, `patch`, `git apply`, `git -C reference/GrappleMap` with a writing subcommand). Same normalization as step 1 for the operands (`./`, `..`, `$PWD/`). Read-only use stays allowed (`cat`, `grep`, `sed -n`, `cd reference/GrappleMap/src && grep …`, `git submodule update`, `git -C reference/GrappleMap log/show`), and so does `./build.sh test-golden --update` (the sanctioned path).
3. Update the "Known limits" header (fail-open accepted: variable expansion, command substitution, interpreters writing from inside `python -c`/`node -e` scripts) and the hooks line of `docs/ai-workflow.md` (Permisos: "no las escrituras por Bash, ver #21" → what is now covered and what is not).
4. CHANGELOG (Unreleased).
## Ficheros a tocar
`.claude/hooks/protect-paths.sh`, `.claude/hooks/guard-bash.sh`, `tests/hooks/guard-bash.test.sh`, `tests/hooks/protect-paths.test.sh` (new), `build.sh` (one line: run the new test next to `tests/hooks/guard-bash.test.sh`), `docs/ai-workflow.md`, `CHANGELOG.md`.
## Tests a escribir primero
`tests/hooks/protect-paths.test.sh`: deny `reference/GrappleMap/x`, `./reference/GrappleMap/x`, `$PWD/./reference/GrappleMap/x`, `src/../tests/golden/a.png`, a symlink into `tests/golden/`; allow `src/x.odin`, `reference_notes.md`, `tests/goldenish/x`. In `guard-bash.test.sh`: deny `echo x > reference/GrappleMap/a`, `sed -i s/a/b/ ./reference/GrappleMap/a`, `cp a tests/golden/b.png`, `rm tests/golden/x.png`, `tee -a src/../reference/GrappleMap/a`; allow `cat reference/GrappleMap/src/a.cpp`, `grep -n x reference/GrappleMap/src/*.hpp`, `sed -n 1,5p reference/GrappleMap/a`, `cp reference/GrappleMap/a /tmp/x`, `./build.sh test-golden --update`. Red before, green after.
## Riesgos
- Over-blocking read-only commands breaks every session that inspects the original: the allow cases above are as important as the deny ones.
- The guard stays heuristic (quotes deleted, not parsed); `Edit(...)` deny rules in settings.json remain the second barrier. Do not touch the `deny` list without saying so in the PR.
- `CHANGELOG.md` shared with #34 and #40 in this batch: whoever opens second merges `main` (see #98).
## Criterio de hecho
Both items of #21 (and its comment) met, hook tests green in `./build.sh ci`, reviewer without blockers.
