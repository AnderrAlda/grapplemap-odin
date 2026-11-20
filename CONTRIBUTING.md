# Contributing

## Workflow
- Trunk-based. `main` is always green; never commit to it directly (a git hook and branch protection enforce this).
- Branches: `feat/…`, `fix/…`, `refactor/…`, `test/…`, `docs/…`, `chore/…`, `ci/…`.
- Small PRs (guideline: < 400 changed lines, excluding data). Open as **draft**; mark ready once CI is green
  and the `code-reviewer` review has no blockers. Squash merge; the PR title is a Conventional Commit.
- Commits: Conventional Commits (`feat(core): …`), small and atomic; each one compiles.

## Protección de `main`
No hay branch protection de GitHub (repo privado sin plan Pro): `main` está protegido solo por los hooks locales
(`pre-commit` y `pre-push` bloquean commits y pushes a `main`). Requieren `./build.sh setup`. Los merges se hacen solo desde GitHub.

## Setup
`./build.sh setup` activates hooks. Run `./build.sh ci` before declaring anything done.

## Definition of done
- Plan in `docs/plans/` linked in the PR (skip for one-sentence changes).
- `./build.sh ci` passes locally; CI green.
- Tests added/updated (TDD in `core`); zero leaks in debug.
- Docs, nested `CLAUDE.md`, CHANGELOG (Unreleased) and ADR updated where applicable.
- Reviewed with no blockers; screenshots/GIF for visual changes.

## Rules
- Never weaken or skip tests, raise tolerances, or disable `-vet`/`-strict-style` to get green.
- `reference/GrappleMap` (submodule pinned to the original) is read-only. Golden images change only via `./build.sh test-golden --update`, visible in the PR.
- No TODO without an issue: `// TODO(#12): …`.
- Architecture decisions get an ADR in `docs/adr/`.
