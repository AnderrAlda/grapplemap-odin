### Added
- `core.cr_atan2`: correctly rounded binary64 `atan2`, ported from CORE-MATH (MIT). `core` uses it on every target instead of `math.atan2` or the libm; tests compare it bit for bit against `tools/cr_atan2_ref.py`, a Python `decimal` reference (#161).

### Changed
- ADR 0003 amendment: `core`'s `atan2`/`sin`/`cos` are its own correctly rounded functions (CORE-MATH); `./build.sh check` rejects `math.`/`libc.` `atan2`/`sin`/`cos` in `src/core` (#161).
