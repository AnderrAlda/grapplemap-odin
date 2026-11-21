### Fixed
- `./build.sh worktree` resolves the target path from the main worktree, so it no longer nests `grapplemap-odin-wt` when run from another worktree, and no longer hides `git worktree add` errors (#31).
