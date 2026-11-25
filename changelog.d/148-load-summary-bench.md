### Added
- `--load <file>` prints a one-line graph summary (blocks, positions, named, transitions, nodes, anonymous); with `--headless` no window opens. Distinct exit codes for invalid database (4), I/O error (5) and usage error (6) (#148).
- `./build.sh bench`: load benchmark over the full database (median/min/max of 9 runs) (#148).
