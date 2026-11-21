### Added
- Changelog fragments: PRs add `changelog.d/<issue>-<slug>.md` instead of editing `CHANGELOG.md`, so PRs of the same batch no longer conflict; `./build.sh changelog-check` (part of `check`) validates their headings, the `release` skill folds them into `CHANGELOG.md`, and `/orchestrate` documents how to resolve shared-file conflicts after a merge (#98).
