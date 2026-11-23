### Added
- `core`: correctly rounded `cr_sin`/`cr_cos` (binary64, round to nearest), ported from CORE-MATH (MIT) and used on every target instead of the host libm, so trigonometry matches the oracle bit for bit (#162).
- `tools/cr_trig_ref.py`: standard-library-only generator of the correctly rounded reference values in `tests/fixtures/cr_sin_cos.txt` (#162).
