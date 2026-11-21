# Changelog fragments

PRs never edit `CHANGELOG.md`: that line was a shared conflict point between PRs of the same batch (#98).
Each PR adds one fragment here instead; the `release` skill folds them into `CHANGELOG.md` and deletes them.

- Name: `<issue>-<slug>.md`. A second PR for the same issue adds `-2` (`98-changelog-fragments-2.md`).
- Content: the entries exactly as they would read in `CHANGELOG.md`, under a Keep a Changelog heading
  (`### Added`, `### Changed`, `### Deprecated`, `### Removed`, `### Fixed`, `### Security`). One or more headings per file.
- `./build.sh check` (so `ci`) fails on an empty fragment, a missing first heading or an unknown heading.

Example (`changelog.d/123-foo.md`):

```markdown
### Added
- `./build.sh foo`: does the foo thing (#123).
```
