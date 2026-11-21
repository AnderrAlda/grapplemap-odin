# Plan: #98 chore(claude): stop CHANGELOG conflicts between PRs of the same batch
Spec: issue #98
## Diseño
One fragment per PR: `changelog.d/<issue>-<slug>.md`, containing the entries under their Keep a Changelog heading (`### Added`, `### Changed`, `### Fixed`, …) exactly as they would read in `CHANGELOG.md`. PRs never edit `CHANGELOG.md`. The `release` skill folds every fragment into the new version section (grouped by heading, in issue order) and deletes the fragments in the same `chore: release vX.Y.Z` PR, so `release.yml` keeps reading `CHANGELOG.md` unchanged. A `.gitattributes` `merge=union` on `CHANGELOG.md` is not used: GitHub's merge ignores it.
## Pasos
1. `changelog.d/README.md`: format, naming (`<issue>-<slug>.md`; a second PR for the same issue adds `-2`), one example. `CHANGELOG.md` `[Unreleased]` gets one line: "Unreleased changes live in `changelog.d/` until the next release."; existing Unreleased entries stay where they are.
2. `./build.sh` (`check`, so it runs in `ci`): fail if a fragment has no `### <Keep a Changelog type>` heading or an unknown one. Only the format check: detecting PRs that still edit `CHANGELOG.md` needs git history and is out of scope (the reviewer and the PR checklist cover it).
3. `.claude/skills/release/SKILL.md`: step 2 folds `changelog.d/*.md` (plus any entries already in Unreleased) into `## [X.Y.Z] - date` and removes the fragments.
4. Rules: `CLAUDE.md` ("Hecho": "CHANGELOG (Unreleased)" → "fragmento en `changelog.d/`"), `docs/ai-workflow.md`, `.claude/skills/pr/SKILL.md` (checklist line), `.claude/skills/start-task/SKILL.md` (where it mentions CHANGELOG), `.github/pull_request_template.md` (checklist line; not a workflow). `grep -rn -i changelog` afterwards to catch every mention.
5. Item 3 of the issue ("until it lands, MAIN asks the remaining workers to merge `main`"): add it to `.claude/skills/orchestrate/SKILL.md` step 4 as the rule for any shared-file conflict after a merge (merge `main`, no force-push, CI green on the new head; a merge that only resolves conflicts in fragments/CHANGELOG does not need a new review, any other conflict does).
6. This PR's own entry goes in `changelog.d/98-changelog-fragments.md`.
## Ficheros a tocar
`changelog.d/README.md`, `changelog.d/98-changelog-fragments.md` (new), `CHANGELOG.md` (one line), `build.sh`, `.claude/skills/{release,pr,start-task,orchestrate}/SKILL.md`, `CLAUDE.md` (Hecho line), `docs/ai-workflow.md`, `.github/pull_request_template.md`.
## Tests a escribir primero
The fragment check: a bad fragment (no heading, unknown heading) makes `./build.sh check` fail; the real fragment passes. Shown red/green in the PR.
## Riesgos
- `CLAUDE.md` is also touched by #43 in this batch (Mapa line): different section; whoever opens second merges `main`.
- The other two PRs of this batch still edit `CHANGELOG.md` (they are planned before this lands); that is expected. After merge, the next batches use fragments.
- Does not touch `.github/workflows/` (`release.yml` keeps working because the release skill folds before tagging).
## Criterio de hecho
The three items of #98 met, `./build.sh ci` green with the new check, reviewer without blockers.
