# grapplemap-odin

A modern viewer (and, later, editor) for graphs of grappling positions, reimplemented in
[Odin](https://odin-lang.org) with raylib. Based on the data and ideas of
[GrappleMap](https://github.com/Eelis/GrappleMap) by Eelis (public domain).

> Status: Phase 0 (repo and infrastructure). No viewer yet. See [docs/](docs/) and the GitHub issues.

## Requirements

- Odin **dev-2026-11a** (pinned in `.odin-version`). Install: <https://odin-lang.org/docs/install/>
  (macOS: `brew install odin`; Linux/Windows: release archive from <https://github.com/odin-lang/Odin/releases>).
- `odinfmt` and `ols` from <https://github.com/DanielGavin/ols> (formatting and language server).
- `jq` (used by the Claude Code hooks), `git`, `gh` (optional).

## Build, run, test

```sh
./build.sh setup        # activate git hooks (core.hooksPath=.githooks)
./build.sh debug        # debug build (+ AddressSanitizer on Linux/macOS)
./build.sh release      # optimized build
./build.sh run          # build debug and run
./build.sh test         # unit/property/round-trip/robustness/fidelity tests
./build.sh test-golden  # golden images (--update to regenerate, explicit only)
./build.sh bench        # benchmarks
./build.sh check        # odin check with -vet -strict-style -warnings-as-errors
./build.sh fmt          # format;  fmt-check: verify only
./build.sh ci           # everything CI runs, locally
./build.sh worktree <branch>   # git worktree in ../grapplemap-odin-wt/
```

Windows: `build.bat` offers the same targets.

## Contributing

Trunk-based: short branches (`feat/…`, `fix/…`), squash-merge PRs with a Conventional Commit title,
never commit to `main`. See [CONTRIBUTING.md](CONTRIBUTING.md) and [docs/ai-workflow.md](docs/ai-workflow.md).

## Credits

Data model and position database: [GrappleMap](https://github.com/Eelis/GrappleMap) by Eelis.
Third-party assets are listed in [docs/ASSETS.md](docs/ASSETS.md).

## License

[MIT](LICENSE) for the code. Original GrappleMap data is public domain.
