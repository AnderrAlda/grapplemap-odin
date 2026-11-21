# Changelog

All notable changes to this project are documented here.
Format: [Keep a Changelog](https://keepachangelog.com/en/1.1.0/); versioning: [SemVer](https://semver.org/).

## [Unreleased]

### Added
- Phase 1 spec (`docs/specs/phase-1-original-research.md`): pinned original as a submodule, Docker oracle with a
  committed fixture sample and a full dump checked in CI, and the plan for `docs/original.md`, `docs/architecture.md`
  and the initial ADRs (#3).
- Original GrappleMap as a read-only submodule `reference/GrappleMap`, pinned at `032c8f9`, with `reference/CLAUDE.md`
  (read-only and pin-bump rules) (#32).
- `/orchestrate` skill: the MAIN session coordinates worktrees through Herdr (launch workers, watch them, take PRs to ready);
  merge and plan approval stay with the user (#55).
- `tools/oracle`: Docker image (Ubuntu 18.04 pinned by digest, linux/amd64) that builds the original
  `grapplemap-indexer`, `-dbtojs` and `-mkpospages` out of tree, plus the object files for `--images` (#33).

### Changed
- Claude Code permissions: `git push`, `gh pr create/ready/edit/comment`, `gh issue create/edit/comment` and the specific
  `herdr` subcommands the orchestrator uses move to `allow` so worktree workers do not stall; `herdr pane run/send-*`,
  `agent send-keys`, `worktree remove` and `update` stay out of `allow`. `deny` rules are unchanged; the push guard now also
  blocks `--mirror`, `--all` and `+refspec` pushes (#55).
- Write protection narrowed from `reference/` to the submodule `reference/GrappleMap/`; `./build.sh setup` and `worktree`
  (and `build.bat setup`) initialize the submodule (#32).
- `/pr` skill: at most one round of non-blocking review findings is applied per PR; the rest go to issues.
- `CLAUDE.md`: every issue and PR gets labels and its phase milestone when created (#29).
- `CLAUDE.md`: non-blocking review findings become issues labeled `tech-debt` in the `Backlog` milestone, unless `priority:high`.

### Fixed
- Claude Code permission rules: removed `Write(...)` path rules, which have no effect; the existing `Edit(...)` rules
  protect `reference/`, `tests/golden/` and `.github/workflows/` for every file-writing tool (#29).

## [0.1.0] - 2026-11-20

Phase 0: repository, infrastructure and AI-assisted workflow. No viewer yet.

### Added
- Minimal raylib window (`src/main.odin`) with `--headless --frames N` mode for smoke tests, and a
  tracking allocator that exits with code 3 on leaks or bad frees in debug builds.
- `build.sh` with targets for check, format, debug/release builds, tests, golden tests, benchmarks, CI and git worktrees;
  `build.bat` offers a subset for Windows (setup, check, fmt, debug, release, run, test, ci).
- Local git hooks (`.githooks/`): Conventional Commits validation, formatting and vet checks, tests on push,
  and blocking of commits and pushes to `main`. Activated with `./build.sh setup`.
- GitHub Actions: CI (lint, tests, golden, build matrix, bench) and tag-triggered release workflow.
- Issue and PR templates, CODEOWNERS, Dependabot for Actions, SECURITY, CONTRIBUTING.
- Claude Code configuration: project `CLAUDE.md` files, permissions, hooks, status line, skills
  (`/spec`, `/plan`, `/start-task`, `/pr`, `/fidelity-check`, `/adr`, `/release`) and subagents.
- ADR 0001, spec/plan/ADR templates and `docs/ai-workflow.md`.
- Documentation that `main` has no GitHub branch protection (private repository without a paid plan); protection
  relies on the local hooks and `./build.sh setup`. See `docs/ai-workflow.md`.

[Unreleased]: https://github.com/AnderrAlda/grapplemap-odin/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/AnderrAlda/grapplemap-odin/releases/tag/v0.1.0
