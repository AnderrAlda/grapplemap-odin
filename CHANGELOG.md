# Changelog

All notable changes to this project are documented here.
Format: [Keep a Changelog](https://keepachangelog.com/en/1.1.0/); versioning: [SemVer](https://semver.org/).

## [Unreleased]

### Added
- MAIN must run on Opus: documented in the models table and «Sigue trabajando», and `/orchestrate` refuses to launch workers from a non-Opus session (`opusplan` drops to Sonnet after plan approval) (#90).
- `./build.sh worktree-remove <branch>`: removes a worktree and its branch only when the worktree and its submodules are clean; otherwise prints the status, deletes nothing and exits non-zero (#54).
- «Sigue trabajando» flow: MAIN proposes a batch of up to 3 issues with their plans in a single approval request and runs `/orchestrate` on it; `/orchestrate` is now model-invocable and picks the worker model per issue (`claude --model`); `/start-task` inherits it (#83).
- `docs/original.md` section 2: graph model and node matching (named positions vs. transitions, anonymous nodes, `is_reoriented`/`basicallySame` matching and its order, `.index` cache, `in`/`out`, `bidirectional`/`detailed`, lookup by description), cited to the pinned original (#38).
- `docs/original.md` section 1: data format and parser of `GrappleMap.txt` (structure, base62 position encoding,
  grammar, parser errors and edge cases, DB checks), each claim cited to the pinned original (#37).
- Phase 1 spec (`docs/specs/phase-1-original-research.md`): pinned original as a submodule, Docker oracle with a
  committed fixture sample and a full dump checked in CI, and the plan for `docs/original.md`, `docs/architecture.md`
  and the initial ADRs (#3).
- Original GrappleMap as a read-only submodule `reference/GrappleMap`, pinned at `032c8f9`, with `reference/CLAUDE.md`
  (read-only and pin-bump rules) (#32).
- `/orchestrate` skill: the MAIN session coordinates worktrees through Herdr (launch workers, watch them, take PRs to ready);
  merge and plan approval stay with the user (#55).
- `/orchestrate` cleans up finished work: after a merge it removes the worktree, deletes the local branch and prunes remote
  refs, only when the PR is merged, the local head equals the PR head and the tree is clean (#62).
- `tools/oracle`: Docker image (Ubuntu 18.04 pinned by digest, linux/amd64) that builds the original
  `grapplemap-indexer`, `-dbtojs` and `-mkpospages` out of tree, plus the object files for `--images` (#33).
- `./build.sh space-id <branch>`: stable Herdr space id (`sp` + 32 hex) derived from the branch name; `/orchestrate` uses it so each
  worker opens in its own Herdr space (named after the worktree folder) instead of a tab of MAIN's space (#79).
- `build.bat setup` warns when `git submodule update --init` fails (offline?) and says how to retry, like `build.sh setup` (#50).

### Changed
- `/pr` verifies every PR body edit by reading the body back and falls back to the REST API (`gh api -X PATCH`, with a narrow `allow` rule for `repos/{owner}/{repo}/pulls/*`) when `gh pr edit` fails, as it does with the old `gh` on the server; it marks ready only after seeing the CI box ticked, which the PR template now includes (#76).
- `/pr` review-round rule: a re-review after blocker fixes that returns only non-blockers counts as the single round; non-blockers go to the task's issue; `docs/ai-workflow.md` restates that blockers are always fixed (#48).
- Worker flow: `/orchestrate` launches each worker with `claude "/start-task N <plan path>"` as the initial prompt (a slash command sent with `hc send` arrives wrapped as text and is not executed). `/start-task` runs setup, copies and commits the approved plan, implements and invokes `/pr`; `/pr` is now invocable by workers and waits for CI before marking ready; `hc send|kill|rm` in `allow` are scoped to terminals named `w-*` (#71, #69).
- `/orchestrate` now drives Herdr through `hc` (herdr-core), which is what the Herdr app runs its terminals on; the old `herdr` CLI could not see them. Workers are launched with `hc run --bg --outlive-parent` labelled into MAIN's space (recommended on the server, so it keeps going while the laptop sleeps), and the allow rules use `hc ls|get|read|wait|send|run --bg` instead of `herdr ...`; `hc send --force` is denied, and the residual risk of `hc send`/`run --bg` is documented (#68).
- Agent autonomy rules (create issues/branches/PRs without asking, mark ready when CI is green, review has no blockers and the checklist is
  complete) now live in `CLAUDE.md`; `/pr` no longer asks for confirmation before opening the draft and `/orchestrate` no longer points to
  a Claude memory entry (#65).
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
