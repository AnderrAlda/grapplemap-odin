### Fixed
- Shell tests no longer inherit the git hooks' `GIT_*` environment: `./build.sh test` clears it and the tests share `tests/lib/sandbox.sh` (temp-dir sandbox plus `sandbox_assert_repo`), with a regression test (#111).
